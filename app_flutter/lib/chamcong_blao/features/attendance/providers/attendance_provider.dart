import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/attendance_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../repositories/attendance_repository.dart';
import '../../store/providers/store_provider.dart';

// ---------- Today's attendance ----------

// Uses watchActiveAttendance to handle cross-midnight shifts correctly:
// if a user checked in at 22:00 and it's now 01:00 next day, this still shows active.
final todayAttendanceProvider = StreamProvider<AttendanceModel?>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (storeId == null || uid == null) return Stream.value(null);
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.watchActiveAttendance(storeId, uid);
});

// ---------- Month attendance (family) ----------

final monthAttendanceProvider =
    StreamProvider.family<List<AttendanceModel>, String>((ref, month) {
  final storeId = ref.watch(currentStoreIdProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (storeId == null || uid == null) return Stream.value([]);
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.watchMonthAttendance(storeId, uid, month);
});

// ---------- All today attendances (owner/manager view) ----------

final allTodayAttendancesProvider =
    StreamProvider<List<AttendanceModel>>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null) return Stream.value([]);

  final now = DateTime.now().toUtc().add(const Duration(hours: 7));
  final date =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.watchAllAttendances(storeId, date);
});

// ---------- All currently active attendances across shifts (checkOut == null) ----------

final activeAttendancesProvider =
    StreamProvider<List<AttendanceModel>>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null) return Stream.value([]);
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.watchActiveAttendances(storeId);
});

// ---------- All attendances on a specific date (family) ----------

final dateAttendancesProvider =
    StreamProvider.family<List<AttendanceModel>, String>((ref, date) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null) return Stream.value([]);
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.watchAllAttendances(storeId, date);
});

// Alias cho employee dashboard
final myTodayAttendanceProvider = todayAttendanceProvider;
