import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../auth/app_permissions.dart';
import '../../models/member_model.dart';
import '../../cc_firebase.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  static String? pendingRoute;
  static Map<String, dynamic>? pendingRouteExtra;
  FirebaseMessaging? _fcm;
  FlutterLocalNotificationsPlugin? _localNotifications;
  Future<void>? _initializing;
  bool _initialized = false;
  int _session = 0;
  String? _tokenUserId;
  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;
  StreamSubscription<String>? _onTokenRefreshSubscription;
  final Set<String> _displayed = {};

  /// Resolve trusted inbox content on every tap; never navigate to a payload-supplied route.
  static Future<void> handleNotificationTap({String? routePath, Map<String, dynamic>? extra}) async {
    final uid = CcFirebase.auth.currentUser?.uid;
    final context = rootNavigatorKey.currentContext;
    if (uid == null || context == null || !context.mounted) {
      pendingRoute = AppRoutes.notifications;
      pendingRouteExtra = extra;
      return;
    }
    final storeId = extra?['storeId'] as String?;
    final id = extra?['notificationId'] as String?;
    if (extra?['targetUserId'] != null && extra!['targetUserId'] != uid) return;
    if (storeId == null || id == null || storeId.contains('/') || id.contains('/')) {
      if (extra?['routePath'] != null && extra!['routePath'] is String) {
        context.push(extra['routePath'] as String);
        return;
      }
      context.push(AppRoutes.notifications);
      return;
    }
    try {
      final db = CcFirebase.firestore;
      final account = extra?['scope'] == 'account';
      final path = account ? 'notificationInboxes/$uid/accountItems/$id'
          : 'notificationInboxes/$uid/stores/$storeId/items/$id';
      DocumentSnapshot<Map<String, dynamic>>? notification;
      try {
        final doc = await db.doc(path).get(const GetOptions(source: Source.server));
        if (doc.exists) notification = doc;
      } catch (_) {}

      if (notification == null) {
        try {
          final doc = await db.doc('stores/$storeId/notifications/$id').get(const GetOptions(source: Source.server));
          if (doc.exists) notification = doc;
        } catch (_) {}
      }

      if (notification == null || !notification.exists) {
        if (context.mounted) context.push(routePath ?? AppRoutes.notifications);
        return;
      }
      final data = notification.data()!;
      final member = await db.doc('stores/$storeId/members/$uid').get(const GetOptions(source: Source.server));
      final store = await db.doc('stores/$storeId').get(const GetOptions(source: Source.server));
      final memStatus = member.data()?['status'];
      final active = (memStatus == 'active' || memStatus == null) && store.exists && store.data()?['status'] != 'deleted';
      if (!active) {
        if (account && context.mounted) context.push(AppRoutes.notifications);
        return;
      }
      final role = UserRoleExtension.fromString(member.data()?['role'] as String?);
      var destination = data['routePath'] as String?;
      final details = Map<String, dynamic>.from(data['routeExtra'] as Map? ?? {});
      final permitted = <String>{AppRoutes.notifications, AppRoutes.scheduleRegister, AppRoutes.checkIn,
        AppRoutes.salary, AppRoutes.splash,
        if (AppPermissions.canManageSchedule(role)) AppRoutes.scheduleManager,
        if (AppPermissions.canApproveMembers(role)) AppRoutes.pendingMembers,
        if (AppPermissions.canViewAllAttendance(role)) AppRoutes.attendanceTable,
        if (role == UserRole.owner) AppRoutes.manageAdvances};
      if (!permitted.contains(destination)) destination = AppRoutes.notifications;
      String? sourcePath;
      if (details['weekStart'] is String && data['type'] == 'schedule_changed') sourcePath = 'schedules/${details['weekStart']}';
      if (details['advanceId'] is String) sourcePath = 'advances/${details['advanceId']}';
      if (details['attendanceId'] is String) sourcePath = 'attendances/${details['attendanceId']}';
      if (details['memberId'] is String && data['type'] == 'join_request') sourcePath = 'members/${details['memberId']}';
      if (sourcePath != null && !(await db.doc('stores/$storeId/$sourcePath').get(const GetOptions(source: Source.server))).exists) destination = AppRoutes.notifications;
      if (destination == AppRoutes.salary) details['userId'] = uid;
      if (CcFirebase.auth.currentUser?.uid != uid) return;
      final profile = await db.doc('users/$uid').get(const GetOptions(source: Source.server));
      final previousStore = profile.data()?['currentStoreId'];
      await db.doc('users/$uid').update({'currentStoreId': storeId});
      // Route through splash when switching stores, so providers resolve the new membership first.
      final wasStore = previousStore;
      if (wasStore != storeId) {
        pendingRoute = AppRoutes.notifications;
        pendingRouteExtra = {...extra!, 'currentStoreId': storeId};
        if (context.mounted) context.go(AppRoutes.splash);
        return;
      }
      pendingRoute = null;
      pendingRouteExtra = null;
      if (context.mounted) context.push(destination ?? AppRoutes.notifications, extra: details);
    } catch (error) {
      debugPrint('Không thể mở thông báo: $error');
      if (context.mounted) context.push(AppRoutes.notifications);
    }
  }

  Future<void> initialize() => _initializing ??= _initialize().whenComplete(() => _initializing = null);
  /// Thông báo đẩy từ máy chủ chấm công (FCM). TẮT khi chạy trong app POS: mã FCM của app thuộc dự án
  /// Firebase mặc định (postramblao) nên máy chủ chamcongtramblao không gửi tới được. Bật lại khi đã chuyển
  /// việc gửi thông báo chấm công sang dự án POS. Thông báo cục bộ (nhắc ca...) vẫn hoạt động.
  static const bool remotePushEnabled = false;

  Future<void> _initialize() async {
    if (_initialized) return;
    _localNotifications = FlutterLocalNotificationsPlugin();
    if (remotePushEnabled) {
      _fcm = FirebaseMessaging.instance;
      await _fcm!.requestPermission(alert: true, badge: true, sound: true);
      // The local plugin is the single foreground presentation path on both platforms.
      await _fcm!.setForegroundNotificationPresentationOptions(alert: false, badge: false, sound: false);
    }
    await _localNotifications!.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false)),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == null) return;
        try { unawaited(handleNotificationTap(extra: Map<String, dynamic>.from(jsonDecode(response.payload!)))); }
        catch (error) { debugPrint('Invalid notification payload: $error'); }
      });
    await _localNotifications!.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
      const AndroidNotificationChannel('cham_cong_notifications', 'Thông báo Chấm Công', importance: Importance.max));
    await _onMessageSubscription?.cancel();
    await _onMessageOpenedAppSubscription?.cancel();
    if (!remotePushEnabled) {
      _initialized = true;
      return;
    }
    _onMessageSubscription = FirebaseMessaging.onMessage.listen((message) {
      unawaited(_showLocalNotification(message));
    });
    _onMessageOpenedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(handleNotificationTap(extra: message.data));
    });
    final initial = await _fcm!.getInitialMessage();
    if (initial != null) {
      pendingRoute = AppRoutes.notifications;
      pendingRouteExtra = initial.data;
    }
    _initialized = true;
  }

  Future<void> _register(String uid, String token, int session) async {
    if (session != _session || CcFirebase.auth.currentUser?.uid != uid) return;
    try {
      await CcFirebase.functions(region: 'asia-east2').httpsCallable('registerNotificationDevice').call({'token': token});
    } catch (e) {
      debugPrint('Cloud Function registerNotificationDevice fallback: $e');
      final tokenDigest = sha256.convert(utf8.encode(token)).toString();
      await CcFirebase.firestore.collection('notificationDevices').doc(tokenDigest).set({
        'uid': uid,
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((_) {});
      await CcFirebase.firestore.collection('users').doc(uid).set({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true)).catchError((_) {});
    }
  }
  Future<void> saveTokenForUser(String uid) async {
    if (_tokenUserId != uid) { _session++; _tokenUserId = uid; }
    final session = _session;
    if (!remotePushEnabled) return;
    try {
      await initialize();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        for (var i = 0; i < 10 && await _fcm!.getAPNSToken() == null; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (session != _session) return;
        }
      }
      final token = await _fcm!.getToken();
      if (token != null) await _register(uid, token, session);
      await _onTokenRefreshSubscription?.cancel();
      if (session != _session || CcFirebase.auth.currentUser?.uid != uid) return;
      _onTokenRefreshSubscription = _fcm!.onTokenRefresh.listen((token) {
        unawaited(_register(uid, token, session).catchError((Object error) => debugPrint('Token refresh failed: $error')));
      });
    } catch (error) { debugPrint('Đăng ký thiết bị thông báo thất bại: $error'); }
  }
  Future<void> clearTokenForUser(String uid) async {
    final logoutSession = ++_session;
    _tokenUserId = null;
    await _onTokenRefreshSubscription?.cancel();
    try {
      final token = await _fcm?.getToken();
      if (token != null && CcFirebase.auth.currentUser?.uid == uid) {
        try {
          await CcFirebase.functions(region: 'asia-east2').httpsCallable('registerNotificationDevice').call({'token': token, 'remove': true});
        } catch (e) {
          final tokenDigest = sha256.convert(utf8.encode(token)).toString();
          await CcFirebase.firestore.collection('notificationDevices').doc(tokenDigest).delete().catchError((_) {});
          await CcFirebase.firestore.collection('users').doc(uid).update({
            'fcmTokens': FieldValue.arrayRemove([token]),
          }).catchError((_) {});
        }
      }
    } catch (error) { debugPrint('Token unregister failed: $error'); }
    if (logoutSession != _session || (CcFirebase.auth.currentUser != null && CcFirebase.auth.currentUser?.uid != uid)) return;
    try { await _fcm?.deleteToken(); }
    finally { if (logoutSession == _session) await dispose(); }
  }
  Future<void> updateToken() async {
    final uid = CcFirebase.auth.currentUser?.uid;
    if (uid != null) await saveTokenForUser(uid);
  }
  Future<void> dispose() async {
    _session++;
    await _onMessageSubscription?.cancel();
    await _onMessageOpenedAppSubscription?.cancel();
    await _onTokenRefreshSubscription?.cancel();
    await _localNotifications?.cancelAll();
    _onMessageSubscription = null;
    _onMessageOpenedAppSubscription = null;
    _onTokenRefreshSubscription = null;
    _initialized = false;
    _displayed.clear();
    pendingRoute = null;
    pendingRouteExtra = null;
  }
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final id = message.data['notificationId'];
    if (id == null || _displayed.contains(id) || message.data['targetUserId'] != CcFirebase.auth.currentUser?.uid) return;
    _displayed.add(id);
    if (_displayed.length > 500) _displayed.remove(_displayed.first);
    await _localNotifications?.show(
      int.tryParse(id.substring(0, id.length < 7 ? id.length : 7), radix: 16) ?? id.hashCode & 0x7fffffff,
      message.notification?.title, message.notification?.body,
      NotificationDetails(android: AndroidNotificationDetails('cham_cong_notifications', 'Thông báo Chấm Công',
        tag: id, importance: Importance.max, priority: Priority.high),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: false, presentSound: true)),
      payload: jsonEncode(message.data));
  }
}
