import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/shift_reminder_service.dart';
import '../../../models/schedule_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../store/providers/store_provider.dart';
import '../repositories/schedule_repository.dart';

// ---------- Repository ----------

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ScheduleRepository();
});

// ---------- Current week start ----------

final currentWeekStartProvider = Provider<String>((ref) {
  final repo = ref.watch(scheduleRepositoryProvider);
  return repo.getWeekStart(DateTime.now());
});

// ---------- Week schedule (stream by weekStart) ----------

final weekScheduleProvider =
    StreamProvider.family<ScheduleModel?, String>((ref, weekStart) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return Stream.value(null);
  final repo = ref.watch(scheduleRepositoryProvider);
  return repo.watchWeekSchedule(storeId, weekStart);
});

// ---------- My schedule for the current week ----------

final myScheduleProvider = Provider<DaySchedule?>((ref) {
  final weekStart = ref.watch(currentWeekStartProvider);
  final scheduleAsync = ref.watch(weekScheduleProvider(weekStart));
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return scheduleAsync.whenOrNull(
    data: (schedule) => schedule?.getScheduleForUser(uid),
  );
});

// ---------- Available weeks (current + next 2) ----------

final availableWeeksProvider = Provider<List<String>>((ref) {
  final repo = ref.read(scheduleRepositoryProvider);
  return repo.getNextWeeks(3);
});

// Alias cho employee dashboard
final currentWeekScheduleProvider = Provider<AsyncValue<ScheduleModel?>>((ref) {
  final weekStart = ref.watch(currentWeekStartProvider);
  return ref.watch(weekScheduleProvider(weekStart));
});

/// Provider tự động lập lịch nhắc nhở ca làm tại máy (Local Notification)
/// cho nhân viên khi lịch tuần hoặc cửa hàng được tải / thay đổi.
/// Hoạt động 100% offline, 0 Firestore reads, nổ chuông trước 15 phút.
final shiftReminderSchedulerProvider = Provider.autoDispose<void>((ref) {
  final schedule = ref.watch(myScheduleProvider);
  final store = ref.watch(currentStoreProvider).valueOrNull;
  final weekStart = ref.watch(currentWeekStartProvider);
  final user = ref.watch(currentUserProvider).valueOrNull;

  // Nếu người dùng tắt thông báo ca làm thì hủy toàn bộ nhắc nhở
  if (user != null && user.notifyShiftInOut == false) {
    ShiftReminderService().cancelAllShiftReminders();
    return;
  }

  if (schedule != null && store != null && store.name.isNotEmpty) {
    ShiftReminderService().scheduleWeekShifts(
      storeId: store.id,
      storeName: store.name,
      schedule: schedule,
      weekStart: weekStart,
      customShifts: store.customShifts,
      minutesBefore: 15,
    );
  }
});
