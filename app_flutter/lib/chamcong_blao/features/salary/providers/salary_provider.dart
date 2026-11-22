import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/attendance_model.dart';
import '../../../models/member_model.dart';
import '../../store/providers/store_provider.dart';
import '../../../cc_firebase.dart';

// ---------- Repository-level salary logic ----------

class SalaryRepository {
  final FirebaseFirestore _firestore;
  SalaryRepository({
    FirebaseFirestore? firestore,
  })  : _firestore = firestore ?? CcFirebase.firestore;


  CollectionReference<Map<String, dynamic>> _attendances(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('attendances');

  CollectionReference<Map<String, dynamic>> _members(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('members');

  /// Returns list of AttendanceModel for [userId] in [month] (YYYY-MM).
  Future<List<AttendanceModel>> getMonthAttendances(
      String storeId, String userId, String month) async {
    final snap = await _attendances(storeId)
        .where('userId', isEqualTo: userId)
        .get();
    return snap.docs
        .map(AttendanceModel.fromFirestore)
        .where((a) => a.date.startsWith(month))
        .toList();
  }

  /// Returns all attendance records for all members in [month].
  Future<Map<String, List<AttendanceModel>>> getAllMonthAttendances(
      String storeId, String month) async {
    final snap = await _attendances(storeId)
        .where('date', isGreaterThanOrEqualTo: '$month-01')
        .where('date', isLessThanOrEqualTo: '$month-31')
        .get();
    final result = <String, List<AttendanceModel>>{};
    for (final doc in snap.docs) {
      final att = AttendanceModel.fromFirestore(doc);
      result.putIfAbsent(att.userId, () => []).add(att);
    }
    return result;
  }

  /// Fetches all active members of the store.
  Future<List<MemberModel>> getActiveMembers(String storeId) async {
    final snap = await _members(storeId)
        .where('status', isEqualTo: 'active')
        .get();
    return snap.docs.map(MemberModel.fromFirestore).toList();
  }

  /// Calculates number of delivery and giaoHang shifts for a user in a specific month
  Future<({int delivery, int giaoHang})> getMonthlySpecialCounts(String storeId, String userId, String month) async {
    final allCounts = await getAllMonthlySpecialCounts(storeId, month);
    return allCounts[userId] ?? (delivery: 0, giaoHang: 0);
  }

  /// Fetches all special counts for all users in a month efficiently
  Future<Map<String, ({int delivery, int giaoHang})>> getAllMonthlySpecialCounts(String storeId, String month) async {
    final snap = await _firestore.collection('stores').doc(storeId).collection('schedules').get();
    final result = <String, ({int delivery, int giaoHang})>{};
    
    for (final doc in snap.docs) {
      final data = doc.data();
      final shifts = data['shifts'] as Map<String, dynamic>? ?? {};
      final weekStartStr = data['weekStart'] as String? ?? doc.id;
      final weekStartDate = DateTime.tryParse(weekStartStr);
      if (weekStartDate == null) continue;
      
      for (final userId in shifts.keys) {
        final userShifts = shifts[userId] as Map<String, dynamic>?;
        if (userShifts == null) continue;

        final daysMap = {
          0: userShifts['monday'],
          1: userShifts['tuesday'],
          2: userShifts['wednesday'],
          3: userShifts['thursday'],
          4: userShifts['friday'],
          5: userShifts['saturday'],
          6: userShifts['sunday'],
        };
        
        for (int i = 0; i < 7; i++) {
          final dayDate = weekStartDate.add(Duration(days: i));
          final y = dayDate.year.toString().padLeft(4, '0');
          final m = dayDate.month.toString().padLeft(2, '0');
          final dateStr = '$y-$m';
          
          if (dateStr == month) {
            final shiftsForDay = daysMap[i];
            if (shiftsForDay is List) {
              int del = 0, giao = 0;
              if (shiftsForDay.contains('delivery')) del++;
              if (shiftsForDay.contains('giaohang')) giao++;
              
              if (del > 0 || giao > 0) {
                 final current = result[userId] ?? (delivery: 0, giaoHang: 0);
                 result[userId] = (delivery: current.delivery + del, giaoHang: current.giaoHang + giao);
              }
            }
          }
        }
      }
    }
    return result;
  }

  /// Calculates total worked hours for [attendances].
  double calculateTotalHours(List<AttendanceModel> attendances) {
    return attendances.fold(0.0, (sum, a) => sum + a.totalHours);
  }

  /// Calculates salary for given hours + member config.
  double calculateSalary(MemberModel member, double totalHours, {int deliveryCount = 0, double deliveryAllowance = 0, int giaoHangCount = 0, double giaoHangAllowance = 0}) {
    double base = 0.0;
    if (member.isFulltime) {
      final ratio = member.standardHoursPerMonth > 0
          ? (totalHours / member.standardHoursPerMonth).clamp(0.0, 1.5)
          : 0.0;
      base = member.baseMonthlySalary * ratio;
    } else {
      base = totalHours * member.baseHourlyRate;
    }
    return base + (deliveryCount * deliveryAllowance) + (giaoHangCount * giaoHangAllowance);
  }
}

// ---------- Providers ----------

final salaryRepositoryProvider = Provider<SalaryRepository>((ref) {
  return SalaryRepository();
});

// My monthly salary (for employee view)
final myMonthlySalaryProvider =
    FutureProvider.family<double, String>((ref, month) async {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return 0.0;
  final uid = CcFirebase.auth.currentUser?.uid;
  if (uid == null) return 0.0;
  final repo = ref.read(salaryRepositoryProvider);
  final members = await repo.getActiveMembers(storeId);
  final member = members.cast<MemberModel?>().firstWhere(
        (m) => m?.userId == uid,
        orElse: () => null,
      );
  if (member == null) return 0.0;
  final attendances = await repo.getMonthAttendances(storeId, uid, month);
  final totalHours = repo.calculateTotalHours(attendances);
  final specialCounts = await repo.getMonthlySpecialCounts(storeId, uid, month);
  
  final storeSnap = await CcFirebase.firestore.collection('stores').doc(storeId).get();
  final deliveryAllowance = (storeSnap.data()?['deliveryAllowance'] as num?)?.toDouble() ?? 0.0;
  final giaoHangAllowance = (storeSnap.data()?['giaoHangAllowance'] as num?)?.toDouble() ?? 0.0;

  return repo.calculateSalary(member, totalHours, deliveryCount: specialCounts.delivery, deliveryAllowance: deliveryAllowance, giaoHangCount: specialCounts.giaoHang, giaoHangAllowance: giaoHangAllowance);
});

// All salaries for owner view
final allSalariesProvider =
    FutureProvider.family<Map<String, Map<String, dynamic>>, String>((ref, month) async {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return {};
  final repo = ref.read(salaryRepositoryProvider);
  final members = await repo.getActiveMembers(storeId);
  final allAttendances = await repo.getAllMonthAttendances(storeId, month);
    final storeSnap = await CcFirebase.firestore.collection('stores').doc(storeId).get();
    final deliveryAllowance = (storeSnap.data()?['deliveryAllowance'] as num?)?.toDouble() ?? 0.0;
    final giaoHangAllowance = (storeSnap.data()?['giaoHangAllowance'] as num?)?.toDouble() ?? 0.0;
  
    final allSpecialCounts = await repo.getAllMonthlySpecialCounts(storeId, month);
    final result = <String, Map<String, dynamic>>{};
    for (final member in members) {
      final attendances = allAttendances[member.userId] ?? [];
      final totalHours = repo.calculateTotalHours(attendances);
      final specialCounts = allSpecialCounts[member.userId] ?? (delivery: 0, giaoHang: 0);
      final salary = repo.calculateSalary(member, totalHours, deliveryCount: specialCounts.delivery, deliveryAllowance: deliveryAllowance, giaoHangCount: specialCounts.giaoHang, giaoHangAllowance: giaoHangAllowance);
      result[member.userId] = {
        'totalHours': totalHours,
        'salary': salary,
      };
    }
  return result;
});

// Total hours for a specific user in a month
final monthTotalHoursProvider = FutureProvider.family<double,
    ({String userId, String month})>((ref, args) async {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return 0.0;
  final repo = ref.read(salaryRepositoryProvider);
  final attendances =
      await repo.getMonthAttendances(storeId, args.userId, args.month);
  return repo.calculateTotalHours(attendances);
});

// All attendance records for a specific user in a month (for detail screen)
final myMonthAttendancesProvider =
    FutureProvider.family<List<AttendanceModel>, String>((ref, month) async {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return [];
  final uid = CcFirebase.auth.currentUser?.uid;
  if (uid == null) return [];
  final repo = ref.read(salaryRepositoryProvider);
  return repo.getMonthAttendances(storeId, uid, month);
});

// Current user member data (from active members)
final myMemberDataProvider = FutureProvider<MemberModel?>((ref) async {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return null;
  final uid = CcFirebase.auth.currentUser?.uid;
  if (uid == null) return null;
  final repo = ref.read(salaryRepositoryProvider);
  final members = await repo.getActiveMembers(storeId);
  try {
    return members.firstWhere((m) => m.userId == uid);
  } catch (_) {
    return null;
  }
});

// All active members (for owner salary overview)
final allActiveMembersProvider =
    FutureProvider.family<List<MemberModel>, String>((ref, storeId) async {
  final repo = ref.read(salaryRepositoryProvider);
  final members = await repo.getActiveMembers(storeId);
  final store = ref.watch(currentStoreProvider).valueOrNull;
  if (store != null && store.memberOrder.isNotEmpty) {
    members.sort((a, b) {
      final idxA = store.memberOrder.indexOf(a.userId);
      final idxB = store.memberOrder.indexOf(b.userId);
      if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
      if (idxA != -1) return -1;
      if (idxB != -1) return 1;
      return a.name.compareTo(b.name);
    });
  }
  return members;
});

// Selected month for salary screens
final selectedSalaryMonthProvider = StateProvider<String>((ref) {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
});

// ----------// Total special counts for current user in a month
final myMonthSpecialCountsProvider = FutureProvider.family<({int delivery, int giaoHang}), String>((ref, month) async {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return (delivery: 0, giaoHang: 0);
  final uid = CcFirebase.auth.currentUser?.uid;
  if (uid == null) return (delivery: 0, giaoHang: 0);
  final repo = ref.read(salaryRepositoryProvider);
  return repo.getMonthlySpecialCounts(storeId, uid, month);
});

final allMonthlySpecialCountsProvider = FutureProvider.family<Map<String, ({int delivery, int giaoHang})>, String>((ref, month) async {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return {};
  final repo = ref.read(salaryRepositoryProvider);
  return repo.getAllMonthlySpecialCounts(storeId, month);
});

final memberMonthAttendancesProvider = FutureProvider.family<List<AttendanceModel>, ({String userId, String month})>((ref, args) async {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return [];
  final repo = ref.read(salaryRepositoryProvider);
  return repo.getMonthAttendances(storeId, args.userId, args.month);
});

final memberSalaryDataProvider = FutureProvider.family<Map<String, dynamic>, ({String userId, String month})>((ref, args) async {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return {};
  final repo = ref.read(salaryRepositoryProvider);
  final members = await repo.getActiveMembers(storeId);
  final member = members.cast<MemberModel?>().firstWhere(
    (m) => m?.userId == args.userId,
    orElse: () => null,
  );
  if (member == null) return {};
  final attendances = await repo.getMonthAttendances(storeId, args.userId, args.month);
  final totalHours = repo.calculateTotalHours(attendances);
  final specialCounts = await repo.getMonthlySpecialCounts(storeId, args.userId, args.month);
  
  final storeSnap = await CcFirebase.firestore.collection('stores').doc(storeId).get();
  final deliveryAllowance = (storeSnap.data()?['deliveryAllowance'] as num?)?.toDouble() ?? 0.0;
  final giaoHangAllowance = (storeSnap.data()?['giaoHangAllowance'] as num?)?.toDouble() ?? 0.0;

  final totalSalary = repo.calculateSalary(
    member,
    totalHours,
    deliveryCount: specialCounts.delivery,
    deliveryAllowance: deliveryAllowance,
    giaoHangCount: specialCounts.giaoHang,
    giaoHangAllowance: giaoHangAllowance,
  );

  return {
    'member': member,
    'attendances': attendances,
    'totalHours': totalHours,
    'specialCounts': specialCounts,
    'salary': totalSalary,
    'deliveryPay': specialCounts.delivery * deliveryAllowance,
    'giaoHangPay': specialCounts.giaoHang * giaoHangAllowance,
    'deliveryAllowance': deliveryAllowance,
    'giaoHangAllowance': giaoHangAllowance,
  };
});

