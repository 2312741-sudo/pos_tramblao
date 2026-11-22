import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../models/app_notification_model.dart';
import '../../../models/member_model.dart';
import '../../../core/auth/app_permissions.dart';
import '../../../cc_firebase.dart';

class NotificationRepository {
  final FirebaseFirestore? _customFirestore;
  FirebaseFirestore get _firestore => _customFirestore ?? CcFirebase.firestore;
  NotificationRepository({FirebaseFirestore? firestore})
      : _customFirestore = firestore;

  CollectionReference<Map<String, dynamic>> _notificationsRef(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('notifications');

  CollectionReference<Map<String, dynamic>> _items(String userId, String storeId) =>
      _firestore.collection('notificationInboxes').doc(userId)
          .collection('stores').doc(storeId).collection('items');

  CollectionReference<Map<String, dynamic>> _account(String userId) =>
      _firestore.collection('notificationInboxes').doc(userId).collection('accountItems');

  static List<String> scopes(UserRole? role, {bool notifyShiftInOut = true}) => [
    if (role != null) 'member',
    if (AppPermissions.canApproveMembers(role)) 'approver',
    if (AppPermissions.canViewAllAttendance(role) && notifyShiftInOut) 'attendance',
    if (role == UserRole.owner) 'owner',
  ];

  /// Stream of notifications filtered for the specific user & role.
  /// Combines store notifications collection (primary) and account inbox notifications.
  /// Never throws unhandled stream errors so the UI stays resilient.
  Stream<List<AppNotificationModel>> watchNotifications(
    String storeId,
    String? userId,
    UserRole? role, {
    bool notifyShiftInOut = true,
    int limit = 50,
    bool unreadOnly = false,
  }) {
    if (userId == null || userId.isEmpty) return Stream.value([]);

    final controller = StreamController<List<AppNotificationModel>>();
    List<AppNotificationModel> storeItems = [];
    List<AppNotificationModel> accountItems = [];
    StreamSubscription? storeSub;
    StreamSubscription? accountSub;
    StreamSubscription? inboxSub;

    void emitMerged() {
      if (controller.isClosed) return;
      final map = <String, AppNotificationModel>{};
      for (final item in storeItems) {
        map[item.id] = item;
      }
      for (final item in accountItems) {
        map[item.id] = item;
      }
      final merged = map.values.toList()
        ..sort((a, b) {
          final order = b.createdAt.compareTo(a.createdAt);
          return order != 0 ? order : a.id.compareTo(b.id);
        });

      final result = merged.take(limit).toList();
      controller.add(result);
    }

    controller.onListen = () {
      // 1. Primary source: stores/{storeId}/notifications
      if (storeId.isNotEmpty) {
        try {
          storeSub = _notificationsRef(storeId).snapshots().listen(
            (snapshot) {
              storeItems = snapshot.docs
                  .map(AppNotificationModel.fromFirestore)
                  .where((n) {
                    if (!notifyShiftInOut &&
                        (n.type == AppNotificationType.checkIn ||
                            n.type == AppNotificationType.checkOut)) {
                      return false;
                    }
                    if (unreadOnly && n.isReadByUser(userId)) {
                      return false;
                    }
                    return n.isRelevantFor(userId, role);
                  })
                  .toList();
              emitMerged();
            },
            onError: (error) {
              debugPrint('NotificationRepository: store notifications error: $error');
              storeItems = [];
              emitMerged();
            },
          );
        } catch (e) {
          debugPrint('NotificationRepository: failed to listen to store notifications: $e');
        }
      } else {
        storeItems = [];
        emitMerged();
      }

      // 2. Fallback / Account inbox source: notificationInboxes/{userId}/accountItems
      try {
        accountSub = _account(userId).snapshots().listen(
          (snapshot) {
            accountItems = snapshot.docs
                .map(AppNotificationModel.fromFirestore)
                .where((n) {
                  if (unreadOnly && n.isReadByUser(userId)) {
                    return false;
                  }
                  return true;
                })
                .toList();
            emitMerged();
          },
          onError: (error) {
            // Silently ignore if rules/collection do not exist
            debugPrint('NotificationRepository: accountItems error (safe to ignore): $error');
          },
        );
      } catch (_) {}
    };

    controller.onCancel = () async {
      await storeSub?.cancel();
      await accountSub?.cancel();
      await inboxSub?.cancel();
    };

    return controller.stream;
  }

  Stream<int> watchUnreadCount(
    String storeId,
    String? userId,
    UserRole? role, {
    bool notifyShiftInOut = true,
  }) =>
      watchNotifications(
        storeId,
        userId,
        role,
        notifyShiftInOut: notifyShiftInOut,
        unreadOnly: true,
        limit: 200,
      ).map((items) => items.length);

  Future<void> markAsRead(
    String storeId,
    String notificationId,
    String userId, {
    bool account = false,
  }) async {
    if (notificationId.isEmpty || userId.isEmpty) return;
    try {
      if (storeId.isNotEmpty) {
        await _notificationsRef(storeId).doc(notificationId).update({
          'readBy': FieldValue.arrayUnion([userId]),
        });
      }
    } catch (_) {}

    try {
      final collection = account ? _account(userId) : _items(userId, storeId);
      await collection.doc(notificationId).update({'readAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  Future<void> markAllAsRead(
    String storeId,
    String userId,
    UserRole? role, {
    bool notifyShiftInOut = true,
  }) async {
    if (userId.isEmpty) return;
    try {
      if (storeId.isNotEmpty) {
        final snap = await _notificationsRef(storeId).get();
        final batch = _firestore.batch();
        int count = 0;
        for (final doc in snap.docs) {
          final notif = AppNotificationModel.fromFirestore(doc);
          if (notif.isRelevantFor(userId, role) && !notif.isReadByUser(userId)) {
            batch.update(doc.reference, {
              'readBy': FieldValue.arrayUnion([userId]),
            });
            count++;
            if (count >= 400) {
              await batch.commit();
              count = 0;
            }
          }
        }
        if (count > 0) {
          await batch.commit();
        }
      }
    } catch (_) {}

    try {
      final allowed = scopes(role, notifyShiftInOut: notifyShiftInOut);
      final queries = <Query<Map<String, dynamic>>>[_account(userId)];
      if (storeId.isNotEmpty && allowed.isNotEmpty) {
        queries.add(_items(userId, storeId).where('scope', whereIn: allowed));
      }
      final snapshots = await Future.wait(
        queries.map((query) => query.where('readAt', isNull: true).get().catchError((_) => query.get())),
      );
      final docs = snapshots.expand((snapshot) => snapshot.docs).toList();
      for (var offset = 0; offset < docs.length; offset += 400) {
        final batch = _firestore.batch();
        for (final doc in docs.skip(offset).take(400)) {
          batch.update(doc.reference, {'readAt': FieldValue.serverTimestamp()});
        }
        await batch.commit();
      }
    } catch (_) {}
  }

  /// Send a notification to store's notifications collection
  Future<void> sendNotification(String storeId, AppNotificationModel notification) async {
    if (storeId.isEmpty) return;
    try {
      await _notificationsRef(storeId).add(notification.toJson());
    } catch (e) {
      debugPrint('sendNotification error: $e');
    }
  }

  /// Check and generate weekly schedule registration reminder
  Future<void> checkAndGenerateWeeklyScheduleReminder(String storeId) async {
    if (storeId.isEmpty) return;
    try {
      final now = DateTime.now();
      if (now.weekday != DateTime.thursday && now.weekday != DateTime.friday) return;

      final thisMonday = now.subtract(Duration(days: now.weekday - 1));
      final nextMonday = thisMonday.add(const Duration(days: 7));
      final nextWeekStr =
          '${nextMonday.year}-${nextMonday.month.toString().padLeft(2, '0')}-${nextMonday.day.toString().padLeft(2, '0')}';
      final reminderKey = 'schedule_reg_remind_$nextWeekStr';

      final existing = await _notificationsRef(storeId)
          .where('routeExtra.reminderKey', isEqualTo: reminderKey)
          .limit(1)
          .get();

      if (existing.docs.isEmpty) {
        await sendNotification(
          storeId,
          AppNotificationModel(
            id: '',
            storeId: storeId,
            title: 'Nhắc nhở: Đăng ký lịch làm tuần tới',
            body:
                'Hạn chót đăng ký ca làm việc cho tuần tới ($nextWeekStr) là 23:59 Thứ Sáu. Vui lòng hoàn tất đăng ký sớm!',
            type: AppNotificationType.scheduleRegistrationReminder,
            createdAt: DateTime.now(),
            targetRoles: [
              UserRole.owner,
              UserRole.manager1,
              UserRole.manager2,
              UserRole.legacyManager,
              UserRole.employee,
            ],
            routePath: '/schedule',
            routeExtra: {
              'storeId': storeId,
              'reminderKey': reminderKey,
              'weekStart': nextWeekStr,
            },
          ),
        );
      }
    } catch (_) {}
  }

  /// Check and generate birthday notifications for store members
  Future<void> checkAndGenerateBirthdayNotifications(String storeId) async {
    if (storeId.isEmpty) return;
    try {
      final now = DateTime.now();
      final membersSnap = await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('members')
          .where('status', isEqualTo: 'active')
          .get();

      final activeMembers = membersSnap.docs.map((d) => MemberModel.fromFirestore(d)).toList();

      for (final member in activeMembers) {
        DateTime? birthday = member.birthday;

        if (birthday == null) {
          try {
            final userDoc = await _firestore.collection('users').doc(member.userId).get();
            if (userDoc.exists && userDoc.data() != null) {
              final bStr = userDoc.data()!['birthday'];
              if (bStr != null) {
                birthday = DateTime.tryParse(bStr.toString());
              }
            }
          } catch (_) {}
        }

        if (birthday != null && birthday.day == now.day && birthday.month == now.month) {
          final birthdayKey = 'birthday_${member.userId}_${now.year}_${now.month}_${now.day}';

          final existing = await _notificationsRef(storeId)
              .where('routeExtra.birthdayKey', isEqualTo: birthdayKey)
              .limit(1)
              .get();

          if (existing.docs.isEmpty) {
            await sendNotification(
              storeId,
              AppNotificationModel(
                id: '',
                storeId: storeId,
                title: 'Hôm nay là sinh nhật của ${member.name}!',
                body:
                    'Cả cửa hàng hãy cùng gửi những lời chúc mừng tốt đẹp nhất đến ${member.name} (${member.role.label}) nhân ngày sinh nhật hôm nay nhé!',
                type: AppNotificationType.birthday,
                createdAt: DateTime.now(),
                targetRoles: null,
                targetUserId: null,
                routePath: null,
                routeExtra: {
                  'storeId': storeId,
                  'birthdayKey': birthdayKey,
                  'memberId': member.userId,
                  'memberName': member.name,
                  'memberRole': member.role.label,
                },
              ),
            );
          }
        }
      }
    } catch (_) {}
  }
}
