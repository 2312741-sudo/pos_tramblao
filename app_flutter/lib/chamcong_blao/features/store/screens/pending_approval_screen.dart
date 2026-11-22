import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/member_model.dart';
import '../../../app/router.dart';
import '../../../core/widgets/notification_bell_icon.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/providers/auth_notifier.dart';
import '../providers/store_provider.dart';
import '../providers/user_repository.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState
    extends ConsumerState<PendingApprovalScreen> {
  bool _isCancelling = false;

  @override
  Widget build(BuildContext context) {
    final memberAsync = ref.watch(currentMemberStreamProvider);

    memberAsync.whenData((member) {
      if (member == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (member.status == MemberStatus.active) {
          context.go(AppRoutes.splash);
        } else if (member.status == MemberStatus.kicked) {
          ref.invalidate(userStoresProvider);
          ref.invalidate(currentUserProvider);
          context.go(AppRoutes.splash);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Yêu cầu tham gia đã bị từ chối hoặc bạn đã bị xóa.'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      });
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        automaticallyImplyLeading: false,
        actions: [
          const NotificationBellIcon(iconColor: AppColors.primary),
          IconButton(
            icon: const Icon(LucideIcons.logOut, color: AppColors.primary),
            tooltip: 'Đăng xuất',
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Animated hourglass icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.hourglass,
                    color: AppColors.accent,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                const Text(
                  'Chờ xét duyệt',
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.neutral,
                  ),
                ),
                const SizedBox(height: 12),

                // Subtitle
                const Text(
                  'Yêu cầu của bạn đã được gửi.\nVui lòng chờ chủ cửa hàng duyệt.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 15,
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),

                // Status indicator
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.accent.withOpacity(0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Đang chờ phê duyệt...',
                        style: TextStyle(
                          fontFamily: 'BeVietnamPro',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB8952A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // Info card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Column(
                    children: [
                      _InfoRow(
                        icon: LucideIcons.bell,
                        text:
                            'Bạn sẽ nhận được thông báo khi được duyệt',
                      ),
                      Divider(height: 20),
                      _InfoRow(
                        icon: LucideIcons.clock,
                        text: 'Quá trình xét duyệt thường mất vài phút',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Cancel button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isCancelling ? null : _cancelRequest,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isCancelling
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Text(
                            'Hủy yêu cầu',
                            style: TextStyle(
                              fontFamily: 'BeVietnamPro',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Hủy yêu cầu',
          style: TextStyle(
              fontFamily: 'BeVietnamPro', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Bạn có chắc muốn hủy yêu cầu tham gia cửa hàng không?',
          style: TextStyle(fontFamily: 'BeVietnamPro'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không',
                style: TextStyle(fontFamily: 'BeVietnamPro')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Hủy yêu cầu',
                style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      final user = ref.read(userProvider).value;
      final storeId = ref.read(currentStoreIdProvider);
      if (user != null && storeId != null) {
        final repo = ref.read(storeRepositoryProvider);
        await repo.cancelJoinRequest(storeId, user.id);
      }
      ref.invalidate(userStoresProvider);
      ref.invalidate(currentStoreIdProvider);
      if (mounted) context.go(AppRoutes.welcome);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.info, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'BeVietnamPro',
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
