import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/app_notification_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../store/providers/store_provider.dart';
import '../../../core/services/notification_service.dart';
import '../providers/notification_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsStreamProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    final storeId = ref.watch(currentStoreIdProvider) ?? '';
    final userId = ref.watch(currentUserIdProvider) ?? '';

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.info,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(
            LucideIcons.chevronLeft,
            color: AppColors.info,
            size: 20,
          ),
          onPressed: () => context.pop(),
        ),
        iconTheme: const IconThemeData(color: AppColors.info),
        title: Text(
          'Thông báo',
          style: GoogleFonts.merriweather(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.info,
          ),
        ),
        actions: [
          notificationsAsync.maybeWhen(
            data: (list) {
              if (unreadCount == 0) return const SizedBox();
              return TextButton.icon(
                onPressed: () async {
                  try {
                  await ref.read(notificationRepositoryProvider).markAllAsRead(
                        storeId,
                        userId,
                        ref.read(notificationRoleProvider),
                        notifyShiftInOut: ref.read(currentUserProvider).valueOrNull?.notifyShiftInOut ?? true,
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã đánh dấu đọc tất cả thông báo'),
                        backgroundColor: AppColors.success,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                  } catch (_) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể cập nhật trạng thái đã đọc. Vui lòng thử lại.')));
                  }
                },
                icon: const Icon(LucideIcons.checkCheck, size: 18, color: AppColors.primary),
                label: Text(
                  'Đã đọc tất cả',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              );
            },
            orElse: () => const SizedBox(),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, stack) {
          debugPrint('Lỗi tải thông báo: $e\n$stack');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.circleAlert, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    'Không thể tải thông báo',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.neutral,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Vui lòng kiểm tra kết nối mạng và thử lại.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => ref.refresh(notificationsStreamProvider),
                    icon: const Icon(LucideIcons.refreshCw, size: 18),
                    label: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          );
        },
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.bellOff,
                        size: 44,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Không có thông báo nào',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.neutral,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Các thông báo về lịch làm việc, duyệt thành viên và nhắc nhở ca làm sẽ xuất hiện tại đây.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: notifications.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == notifications.length) {
                final pageLimit = ref.watch(notificationPageLimitProvider);
                if (notifications.length < pageLimit) return const SizedBox.shrink();
                return TextButton(onPressed: () => ref.read(notificationPageLimitProvider.notifier).state += 50,
                  child: const Text('Xem thông báo cũ hơn'));
              }
              final notif = notifications[index];
              final isRead = notif.isReadByUser(userId);
              final notifStoreId = notif.storeId.isNotEmpty ? notif.storeId : storeId;

              return _NotificationCard(
                notification: notif,
                isRead: isRead,
                onTap: () async {
                  try {
                    if (!isRead) {
                      await ref.read(notificationRepositoryProvider).markAsRead(
                        notifStoreId, notif.id, userId, account: notif.scope == 'account');
                    }
                    await NotificationService.handleNotificationTap(extra: {
                      'storeId': notifStoreId, 'notificationId': notif.id,
                      'scope': notif.scope, 'targetUserId': userId,
                    });
                  } catch (_) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Không thể mở thông báo. Vui lòng thử lại.')));
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotificationModel notification;
  final bool isRead;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.isRead,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final typeConfig = _getTypeConfig(notification.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRead ? AppColors.border : AppColors.primary,
              width: isRead ? 1 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isRead ? AppColors.shadow.withOpacity(0.15) : AppColors.primary.withOpacity(0.10),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: typeConfig.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(typeConfig.icon, color: typeConfig.color, size: 22),
              ),
              const SizedBox(width: 14),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14.5,
                              fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                              color: isRead ? const Color(0xFF2C3E50) : AppColors.neutral,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: isRead ? Colors.grey.shade600 : const Color(0xFF333333),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(LucideIcons.clock, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Flexible(child: Text(
                          _formatTime(notification.createdAt),
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11.5,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )),
                        if (notification.routePath != null && notification.routePath!.isNotEmpty) ...[
                          const Spacer(),
                          Row(
                            children: [
                              Text(
                                'Xem chi tiết',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11.5,
                                  color: typeConfig.color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(LucideIcons.chevronRight, size: 14, color: typeConfig.color),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return 'Vừa xong';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} phút trước';
    } else if (diff.inHours < 24 && now.day == time.day) {
      return 'Hôm nay ${DateFormat('HH:mm').format(time)}';
    } else if (diff.inDays < 2) {
      return 'Hôm qua ${DateFormat('HH:mm').format(time)}';
    } else {
      return DateFormat('dd/MM/yyyy HH:mm').format(time);
    }
  }

  _TypeConfig _getTypeConfig(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.joinRequest:
        return const _TypeConfig(LucideIcons.userPlus, AppColors.primary);
      case AppNotificationType.joinApproved:
        return const _TypeConfig(LucideIcons.circleCheck, AppColors.success);
      case AppNotificationType.joinRejected:
        return const _TypeConfig(LucideIcons.circleX, AppColors.primary);
      case AppNotificationType.advanceRequest:
        return const _TypeConfig(LucideIcons.wallet, AppColors.accentInk);
      case AppNotificationType.advanceApproved:
        return const _TypeConfig(LucideIcons.banknote, AppColors.success);
      case AppNotificationType.advanceRejected:
        return const _TypeConfig(LucideIcons.circleOff, AppColors.primary);
      case AppNotificationType.scheduleChanged:
        return const _TypeConfig(LucideIcons.calendarDays, AppColors.info);
      case AppNotificationType.scheduleRegistrationReminder:
        return const _TypeConfig(LucideIcons.alarmClock, Color(0xFFD97706));
      case AppNotificationType.checklistReminder:
        return const _TypeConfig(LucideIcons.clipboardX, Color(0xFFEA580C));
      case AppNotificationType.deliveryUpdate:
        return const _TypeConfig(LucideIcons.truck, Color(0xFF7B1FA2));
      case AppNotificationType.birthday:
        return const _TypeConfig(LucideIcons.cake, Color(0xFFE91E63));
      case AppNotificationType.checkIn:
        return const _TypeConfig(LucideIcons.logIn, AppColors.success);
      case AppNotificationType.checkOut:
        return const _TypeConfig(LucideIcons.logOut, AppColors.primary);
      case AppNotificationType.general:
        return const _TypeConfig(LucideIcons.bell, Color(0xFF475569));
    }
  }
}

class _TypeConfig {
  final IconData icon;
  final Color color;
  const _TypeConfig(this.icon, this.color);
}
