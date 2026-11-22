import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../../app/router.dart';
import '../../features/notifications/providers/notification_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class NotificationBellIcon extends ConsumerWidget {
  final Color iconColor;
  final Color? backgroundColor;
  final double size;

  const NotificationBellIcon({
    super.key,
    this.iconColor = Colors.white,
    this.backgroundColor,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCountAsync = ref.watch(unreadNotificationCountProvider);
    final unreadCount = unreadCountAsync.valueOrNull ?? 0;

    Widget bellWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          unreadCount > 0 ? LucideIcons.bell : LucideIcons.bell,
          color: iconColor,
          size: size,
        ),
        if (unreadCount > 0)
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Center(
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'BeVietnamPro',
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (backgroundColor != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(AppRoutes.notifications),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: bellWidget,
          ),
        ),
      );
    }

    return IconButton(
      icon: bellWidget,
      tooltip: 'Thông báo',
      onPressed: () => context.push(AppRoutes.notifications),
    );
  }
}
