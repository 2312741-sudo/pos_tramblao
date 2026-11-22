import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../app/router.dart';
import '../../store/providers/store_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/utils/version_utils.dart';
import '../../../models/member_model.dart';
import '../../../cc_firebase.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _hasNavigated = false;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    // Start navigation flow immediately without artificial delays
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndNavigate();
    });
  }

  /// Chạy luồng khởi động với giới hạn thời gian để không xoay vô hạn
  /// khi mạng yếu / Firestore không phản hồi.
  Future<void> _checkAuthAndNavigate() async {
    if (_hasNavigated || !mounted) return;
    if (_timedOut) setState(() => _timedOut = false);
    try {
      await _runStartupFlow().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      debugPrint('SplashScreen: startup flow timed out');
      if (mounted && !_hasNavigated) setState(() => _timedOut = true);
    }
  }

  Future<void> _runStartupFlow() async {
    if (_hasNavigated || !mounted) return;

    try {
      // 0. Version Control Check (Force Update)
      try {
        final updateConfig = await AppUpdateService().fetchVersionConfig();
        if (updateConfig != null) {
          final packageInfo = await PackageInfo.fromPlatform();
          if (VersionUtils.isBelow(packageInfo.version, updateConfig.minimumRequiredVersion)) {
            if (mounted) {
              await AppUpdateService().checkAppVersion(context);
            }
            return; // Block execution, do not navigate away
          }
        }
      } catch (e) {
        debugPrint('Version check error on splash: $e');
      }

      // 1. Check current auth state
      final authUser = CcFirebase.auth.currentUser;
      if (authUser == null) {
        _navigateTo(AppRoutes.login);
        return;
      }

      // 2. Initialize push notifications in background (non-blocking)
      unawaited(() async {
        try {
          await NotificationService().initialize();
          await NotificationService().saveTokenForUser(authUser.uid);
        } catch (_) {}
      }());

      // 3. Get user document from Firestore
      final userDoc = await CcFirebase.firestore
          .collection('users')
          .doc(authUser.uid)
          .get();

      if (!mounted || _hasNavigated) return;

      if (!userDoc.exists || userDoc.data() == null) {
        _navigateTo(AppRoutes.profileSetup);
        return;
      }

      final userData = userDoc.data()!;
      var currentStoreId = userData['currentStoreId'] as String?;

      // 4. If currentStoreId is missing or empty, discover user's stores
      if (currentStoreId == null || currentStoreId.isEmpty) {
        final storeRepo = ref.read(storeRepositoryProvider);
        final stores = await storeRepo.getUserStores(authUser.uid);
        if (stores.isNotEmpty) {
          currentStoreId = stores.first.id;
          await CcFirebase.firestore
              .collection('users')
              .doc(authUser.uid)
              .set({
            'currentStoreId': currentStoreId,
            'storeIds': stores.map((s) => s.id).toList(),
          }, SetOptions(merge: true));
        } else {
          _navigateTo(AppRoutes.welcome);
          return;
        }
      }

      if (!mounted || _hasNavigated) return;

      // 5. Check if currentStore exists and is not deleted
      final storeDoc = await CcFirebase.firestore
          .collection('stores')
          .doc(currentStoreId)
          .get();

      final storeData = storeDoc.data();
      final isStoreDeleted = !storeDoc.exists || storeData?['status'] == 'deleted';

      if (!isStoreDeleted) {
        // Resolve member role and status in current store
        final memberDoc = await CcFirebase.firestore
            .collection('stores')
            .doc(currentStoreId)
            .collection('members')
            .doc(authUser.uid)
            .get();

        if (!mounted || _hasNavigated) return;

        if (memberDoc.exists && memberDoc.data() != null) {
          final data = memberDoc.data()!;
          final role = data['role'] as String?;
          final status = data['status'] as String?;

          if (status == 'pending') {
            _navigateTo(AppRoutes.pendingApproval);
            return;
          }
          if (status == 'active' || status == null) {
            final isOwner = storeData?['ownerId'] == authUser.uid ||
                ((storeData?['coOwnerIds'] as List?)?.contains(authUser.uid) ?? false);
            UserRole parsedRole = UserRoleExtension.fromString(role);
            if (parsedRole == UserRole.owner && !isOwner) {
              parsedRole = UserRole.manager1;
            }

            if (parsedRole.isOwner) {
              _navigateTo(AppRoutes.ownerDashboard);
            } else if (parsedRole.isManager) {
              _navigateTo(AppRoutes.managerDashboard);
            } else {
              _navigateTo(AppRoutes.employeeDashboard);
            }
            return;
          }
          // If status is 'kicked', do not navigate to welcome; fall through to switch to other stores.
        } else if (storeData?['ownerId'] == authUser.uid ||
            ((storeData?['coOwnerIds'] as List?)?.contains(authUser.uid) ?? false)) {
          _navigateTo(AppRoutes.ownerDashboard);
          return;
        }
      }

      // If user is kicked, store is deleted, or not a valid member: discover remaining stores
      final storeRepo = ref.read(storeRepositoryProvider);
      final stores = await storeRepo.getUserStores(authUser.uid);
      final validOtherStores = stores.where((s) => s.id != currentStoreId && !s.isDeleted).toList();

      if (validOtherStores.isNotEmpty) {
        final newStoreId = validOtherStores.first.id;
        await CcFirebase.firestore
            .collection('users')
            .doc(authUser.uid)
            .set({
          'currentStoreId': newStoreId,
          'storeIds': validOtherStores.map((s) => s.id).toList(),
        }, SetOptions(merge: true));
        // Đang ở /splash nên context.go(splash) không dựng lại màn hình;
        // chạy lại luồng trực tiếp.
        await _runStartupFlow();
        return;
      }

      // Truly no valid stores left
      await CcFirebase.firestore
          .collection('users')
          .doc(authUser.uid)
          .set({
        'currentStoreId': null,
        'storeIds': [],
      }, SetOptions(merge: true));

      _navigateTo(AppRoutes.welcome);
    } catch (e) {
      debugPrint('SplashScreen auth error: $e');
      if (mounted && !_hasNavigated) {
        _navigateTo(AppRoutes.login);
      }
    }
  }

  void _navigateTo(String route) {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    context.go(route);

    // If user tapped a push notification on cold start, push the notification route
    final pending = NotificationService.pendingRoute;
    final extra = NotificationService.pendingRouteExtra;
    if (pending != null &&
        (route == AppRoutes.ownerDashboard ||
            route == AppRoutes.managerDashboard ||
            route == AppRoutes.employeeDashboard ||
            route == AppRoutes.welcome || route == AppRoutes.pendingApproval)) {
      NotificationService.pendingRoute = null;
      NotificationService.pendingRouteExtra = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService.handleNotificationTap(extra: extra);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  image: const DecorationImage(
                    image: AssetImage('assets/chamcong_blao/logo.jpg'),
                    fit: BoxFit.contain,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neutral.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // App Name
              const Text(
                AppStrings.appName,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF143A2F),
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 10),

              // Slogan thương hiệu
              const Text(
                AppStrings.appTagline,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF143A2F),
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 48),

              if (_timedOut) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Không kết nối được máy chủ. Vui lòng kiểm tra mạng và thử lại.',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _checkAuthAndNavigate,
                  child: const Text('Thử lại'),
                ),
              ] else
                // Loading Indicator
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2.5,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
