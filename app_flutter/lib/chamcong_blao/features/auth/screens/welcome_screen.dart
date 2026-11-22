import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router.dart';
import '../../../core/widgets/notification_bell_icon.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_notifier.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../cc_firebase.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: CcFirebase.auth.currentUser == null ? null : AppBar(
        backgroundColor: AppColors.surface, automaticallyImplyLeading: false,
        actions: const [NotificationBellIcon(iconColor: AppColors.primary)]),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.surfaceGradient,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // ── Hero Section ────────────────────────────────────────────
                  Expanded(
                    flex: 5,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 40,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Logo
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.white.withOpacity(0.4),
                                width: 2,
                              ),
                              image: const DecorationImage(
                                image: AssetImage('assets/chamcong_blao/logo.jpg'),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // App Name
                          const Text(
                            AppStrings.appName,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: AppColors.white,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 10),

                          // Tagline
                          const Text(
                            AppStrings.appTagline,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: AppColors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Bottom Card ─────────────────────────────────────────────
                  Expanded(
                    flex: 4,
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bắt đầu ngay',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.neutral,
                                  ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              AppStrings.welcomeSubtitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),

                            const SizedBox(height: 28),

                            // Create Store Button
                            ElevatedButton.icon(
                              onPressed: () {
                                final user = CcFirebase.auth.currentUser;
                                if (user != null) {
                                  context.push(AppRoutes.createStore);
                                } else {
                                  context.push(AppRoutes.login);
                                }
                              },
                              icon: const Icon(LucideIcons.store,
                                  size: 20),
                              label: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    AppStrings.createStore,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    AppStrings.createStoreSubtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: AppColors.white.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                              style: ElevatedButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Join Store Button
                            OutlinedButton.icon(
                              onPressed: () {
                                final user = CcFirebase.auth.currentUser;
                                if (user != null) {
                                  context.push(AppRoutes.joinStore);
                                } else {
                                  context.push(AppRoutes.login);
                                }
                              },
                              icon:
                                  const Icon(LucideIcons.userPlus, size: 20),
                              label: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    AppStrings.joinStore,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    AppStrings.joinStoreSubtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: AppColors.primary.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                              style: OutlinedButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Logout / Switch Account Button
                            Center(
                              child: TextButton.icon(
                                onPressed: () async {
                                  await ref.read(authNotifierProvider.notifier).signOut();
                                  if (context.mounted) context.go(AppRoutes.login);
                                },
                                icon: const Icon(LucideIcons.logOut, size: 18, color: AppColors.textSecondary),
                                label: const Text(
                                  'Đăng xuất / Đăng nhập tài khoản khác',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                    fontFamily: 'BeVietnamPro',
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  onPressed: () async {
                    await ref.read(authNotifierProvider.notifier).signOut();
                    await Future.delayed(const Duration(milliseconds: 300));
                    if (context.mounted) context.go(AppRoutes.login);
                  },
                  icon:
                      const Icon(LucideIcons.logOut, color: AppColors.white),
                  tooltip: 'Đăng xuất',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
