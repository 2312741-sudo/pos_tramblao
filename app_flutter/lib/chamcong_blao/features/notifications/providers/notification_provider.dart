import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/app_notification_model.dart';
import '../../../models/member_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../store/providers/store_provider.dart';
import '../repositories/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository();
});

/// Stream of notifications for current user in current store.
/// Đợi store load xong trước khi subscribe để tránh race condition:
/// role=null khi store đang loading → mọi thông báo bị lọc sạch.
final notificationsStreamProvider = StreamProvider.autoDispose<List<AppNotificationModel>>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  final userId = ref.watch(currentUserIdProvider);
  final user = ref.watch(currentUserProvider).valueOrNull;
  final storeAsync = ref.watch(currentStoreProvider);

  if (userId == null) {
    return Stream.value([]);
  }

  // Nếu storeId đã có nhưng store doc chưa load xong → giữ trạng thái
  // loading (stream chưa emit gì) để tránh subscribe với role=null.
  // Riverpod sẽ tự rebuild khi storeAsync resolve xong.
  if (storeId != null && storeId.isNotEmpty && storeAsync.isLoading) {
    final pending = StreamController<List<AppNotificationModel>>();
    ref.onDispose(pending.close);
    return pending.stream;
  }

  final role = ref.watch(notificationRoleProvider);
  final repo = ref.watch(notificationRepositoryProvider);

  return repo.watchNotifications(
    storeId ?? '',
    userId,
    role,
    notifyShiftInOut: user?.notifyShiftInOut ?? true,
    limit: ref.watch(notificationPageLimitProvider),
  );
});

/// Stream of unread notification count for current user in current store.
/// Không dùng autoDispose để badge count không bị reset khi navigate vào
/// NotificationsScreen (tránh flicker badge về 0 rồi lại về số cũ).
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  final userId = ref.watch(currentUserIdProvider);
  final role = ref.watch(notificationRoleProvider);
  final user = ref.watch(currentUserProvider).valueOrNull;

  if (userId == null) {
    return Stream.value(0);
  }

  final repo = ref.watch(notificationRepositoryProvider);
  return repo.watchUnreadCount(
    storeId ?? '',
    userId,
    role,
    notifyShiftInOut: user?.notifyShiftInOut ?? true,
  );
});

final notificationPageLimitProvider = StateProvider.autoDispose<int>((ref) => 50);

/// Xác định role của user trong store hiện tại cho mục đích thông báo.
/// Trả null nếu store đang load, bị xóa, bị kick, hoặc đang pending.
final notificationRoleProvider = Provider<UserRole?>((ref) {
  final store = ref.watch(currentStoreProvider).valueOrNull;
  final member = ref.watch(currentMemberProvider);
  if (store == null || store.isDeleted || store.id != ref.watch(currentStoreIdProvider)) return null;
  if (member != null && member.status == MemberStatus.kicked) return null;
  if (member != null && member.status == MemberStatus.pending) return null;
  return member?.role;
});
