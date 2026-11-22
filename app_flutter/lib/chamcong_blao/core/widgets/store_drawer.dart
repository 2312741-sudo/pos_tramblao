import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../../features/store/providers/store_provider.dart';
import '../../features/store/providers/user_repository.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/providers/auth_notifier.dart';
import '../../models/member_model.dart';
import '../constants/app_colors.dart';

import 'avatar_widget.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../cc_firebase.dart';

class StoreDrawer extends ConsumerWidget {
  const StoreDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(userStoresProvider);
    final currentStoreId = ref.watch(currentStoreIdProvider);
    final user = ref.watch(currentUserProvider).value;

    return Drawer(
      backgroundColor: AppColors.background,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: AppColors.primary),
            accountName: Text(
              user?.name ?? 'Người dùng',
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'BeVietnamPro', color: Color(0xFF143A2F)),
            ),
            accountEmail: Text(
              user?.email ?? '',
              style: const TextStyle(fontFamily: 'BeVietnamPro', color: Color(0xFF143A2F)),
            ),
            currentAccountPicture: AvatarWidget(
              avatarUrl: user?.avatarUrl ?? ref.watch(currentFirebaseUserProvider)?.photoURL,
              name: user?.name ?? 'Người dùng',
              radius: 36,
            ),
          ),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            alignment: Alignment.centerLeft,
            child: const Text(
              'CÁC CỬA HÀNG CỦA BẠN',
              style: TextStyle(
                fontFamily: 'BeVietnamPro',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          
          Expanded(
            child: storesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (err, _) => Center(child: Text('Lỗi: $err')),
              data: (stores) {
                if (stores.isEmpty) {
                  return const Center(child: Text('Bạn chưa tham gia cửa hàng nào.'));
                }
                
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: stores.length,
                  itemBuilder: (context, index) {
                    final store = stores[index];
                    final isSelected = store.id == currentStoreId;
                    
                    return ListTile(
                      leading: Icon(
                        LucideIcons.store,
                        color: isSelected ? AppColors.primary : AppColors.textSecondary,
                      ),
                      title: Text(
                        store.name,
                        style: TextStyle(
                          fontFamily: 'BeVietnamPro',
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppColors.primary : AppColors.neutral,
                        ),
                      ),
                      subtitle: Text(
                        'Mã: ${store.code}',
                        style: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 12),
                      ),
                      trailing: isSelected 
                          ? const Icon(LucideIcons.circleCheck, color: AppColors.primary, size: 20)
                          : null,
                      onTap: () async {
                        if (isSelected) {
                          Navigator.of(context).pop();
                          return;
                        }

                        // Capture router, container, and currentPath before drawer widget can be disposed
                        final router = GoRouter.of(context);
                        final container = ProviderScope.containerOf(context);
                        final currentPath = router.routeInformationProvider.value.uri.toString();
                        final userRepo = ref.read(userRepositoryProvider);

                        Navigator.of(context).pop(); // Close drawer

                        try {
                          if (user == null) return;

                          await userRepo.updateCurrentStoreId(user.id, store.id);

                          // Invalidate session providers via container to prevent any permission/member caching from old store
                          container.invalidate(currentStoreProvider);
                          container.invalidate(currentMemberStreamProvider);
                          container.invalidate(currentMemberProvider);
                          container.invalidate(storeMembersProvider);
                          container.invalidate(activeMembersProvider);

                          // Fetch role in target store
                          UserRole targetRole = UserRole.employee;
                          final memberDoc = await CcFirebase.firestore
                              .collection('stores')
                              .doc(store.id)
                              .collection('members')
                              .doc(user.id)
                              .get();
                          if (memberDoc.exists && memberDoc.data() != null) {
                            final rawRole = memberDoc.data()?['role'] as String?;
                            final parsedRole = UserRoleExtension.fromString(rawRole);
                            if (parsedRole == UserRole.owner && !store.isOwnerUid(user.id)) {
                              targetRole = UserRole.manager1;
                            } else {
                              targetRole = parsedRole;
                            }
                          } else if (store.isOwnerUid(user.id)) {
                            targetRole = UserRole.owner;
                          }

                          String targetPath = AppRoutes.employeeDashboard;
                          if (targetRole.isOwner) {
                            targetPath = AppRoutes.ownerDashboard;
                          } else if (targetRole.isManager) {
                            targetPath = AppRoutes.managerDashboard;
                          }

                          if (currentPath == targetPath) {
                            final rootContext = rootNavigatorKey.currentContext;
                            if (rootContext != null && rootContext.mounted) {
                              ScaffoldMessenger.of(rootContext).showSnackBar(
                                SnackBar(content: Text('Đã chuyển sang: ${store.name}'), backgroundColor: AppColors.success),
                              );
                            }
                          } else {
                            router.go(targetPath);
                          }
                        } catch (e) {
                          debugPrint('Lỗi chuyển cửa hàng: $e');
                          final rootContext = rootNavigatorKey.currentContext;
                          if (rootContext != null && rootContext.mounted) {
                            ScaffoldMessenger.of(rootContext).showSnackBar(
                              SnackBar(content: Text('Lỗi chuyển cửa hàng: $e'), backgroundColor: AppColors.primary),
                            );
                          }
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(LucideIcons.store, color: AppColors.neutral),
            title: const Text('Tạo cửa hàng mới', style: TextStyle(fontFamily: 'BeVietnamPro')),
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.createStore);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.userPlus, color: AppColors.neutral),
            title: const Text('Tham gia cửa hàng', style: TextStyle(fontFamily: 'BeVietnamPro')),
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.joinStore);
            },
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(LucideIcons.flameKindling, color: AppColors.primaryDark),
            title: const Text(
              'Sổ tay & Hẹn giờ Quầy BLAO',
              style: TextStyle(fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w600),
            ),
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.blaoStationSop);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.info, color: AppColors.neutral),
            title: const Text('Thông tin ứng dụng', style: TextStyle(fontFamily: 'BeVietnamPro')),
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.aboutApp);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.logOut, color: AppColors.danger),
            title: const Text('Đăng xuất', style: TextStyle(color: AppColors.danger, fontFamily: 'BeVietnamPro')),
            onTap: () async {
              Navigator.of(context).pop(); // Close drawer
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) {
                context.go(AppRoutes.login);
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
