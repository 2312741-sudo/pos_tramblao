import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/schedule_model.dart';
import '../../../cc_firebase.dart';

class ScheduleRepository {
  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;

  ScheduleRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestoreOverride = firestore,
        _authOverride = auth;

  FirebaseFirestore get _firestore => _firestoreOverride ?? CcFirebase.firestore;
  FirebaseAuth get _auth => _authOverride ?? CcFirebase.auth;

  // ---------- Collection reference ----------

  CollectionReference<Map<String, dynamic>> _schedules(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('schedules');

  // ---------- Reads ----------

  Future<ScheduleModel?> getWeekSchedule(
      String storeId, String weekStart) async {
    try {
      final doc = await _schedules(storeId).doc(weekStart).get();
      if (!doc.exists) return null;
      return ScheduleModel.fromFirestore(doc);
    } catch (e) {
      throw Exception('Lấy lịch tuần thất bại: $e');
    }
  }

  Stream<ScheduleModel?> watchWeekSchedule(
      String storeId, String weekStart) {
    return _schedules(storeId).doc(weekStart).snapshots().map((snap) {
      if (!snap.exists) return null;
      return ScheduleModel.fromFirestore(snap);
    });
  }

  // ---------- Writes ----------

  /// Upserts a single user's DaySchedule for the given week.
  Future<void> saveUserSchedule(
    String storeId,
    String userId,
    String weekStart,
    DaySchedule schedule,
  ) async {
    try {
      final ref = _schedules(storeId).doc(weekStart);
      final now = Timestamp.now();
      await ref.set({
        'storeId': storeId,
        'weekStart': weekStart,
        'shifts': {userId: schedule.toJson()},
        'updatedAt': now,
      }, SetOptions(merge: true));

      // Trigger notification
      try {
        final caller = _auth.currentUser;
        final isSelf = caller?.uid == userId;

        if (isSelf) {
          final memberDoc = await _firestore.collection('stores').doc(storeId).collection('members').doc(userId).get();
          final memberName = memberDoc.data()?['name'] as String? ?? 'Nhân viên';

          await _firestore.collection('stores').doc(storeId).collection('notifications').add({
            'storeId': storeId,
            'title': 'Đăng ký lịch làm mới',
            'body': '$memberName vừa đăng ký lịch làm việc tuần ($weekStart).',
            'type': 'schedule_changed',
            'createdAt': now,
            'targetRoles': ['owner', 'manager_1', 'manager', 'legacyManager'],
            'readBy': caller?.uid != null ? [caller!.uid] : [],
            'routePath': '/schedule-manager',
            'routeExtra': {'storeId': storeId, 'weekStart': weekStart, 'userId': userId},
          });
        } else {
          await _firestore.collection('stores').doc(storeId).collection('notifications').add({
            'storeId': storeId,
            'title': 'Lịch làm việc đã cập nhật',
            'body': 'Lịch làm việc tuần ($weekStart) của bạn đã được cập nhật. Nhấn để xem chi tiết.',
            'type': 'schedule_changed',
            'createdAt': now,
            'targetUserId': userId,
            'readBy': caller?.uid != null ? [caller!.uid] : [],
            'routePath': '/schedule',
            'routeExtra': {'storeId': storeId, 'weekStart': weekStart},
          });
        }
      } catch (_) {}
    } catch (e) {
      throw Exception('Lưu lịch cá nhân thất bại: $e');
    }
  }

  Future<void> setFullSchedule(
    String storeId,
    String weekStart,
    Map<String, DaySchedule> allShifts,
  ) async {
    try {
      final caller = _auth.currentUser;
      final shiftsJson = allShifts.map((k, v) => MapEntry(k, v.toJson()));
      final now = Timestamp.now();
      await _schedules(storeId).doc(weekStart).set({
        'storeId': storeId,
        'weekStart': weekStart,
        'shifts': shiftsJson,
        'updatedAt': now,
        'updatedBy': caller?.uid,
      }, SetOptions(merge: true));

      try {
        await _firestore.collection('stores').doc(storeId).collection('notifications').add({
          'storeId': storeId,
          'title': 'Lịch làm việc đã cập nhật',
          'body': 'Lịch làm việc tuần ($weekStart) đã được cập nhật. Nhấn để xem chi tiết ca của bạn.',
          'type': 'schedule_changed',
          'createdAt': now,
          'targetRoles': ['employee', 'manager_1', 'manager_2', 'manager', 'legacyManager'],
          'readBy': caller?.uid != null ? [caller!.uid] : [],
          'routePath': '/schedule',
          'routeExtra': {'storeId': storeId, 'weekStart': weekStart},
        });
      } catch (_) {}
    } catch (e) {
      throw Exception('Lưu lịch toàn bộ thất bại: $e');
    }
  }

  // ---------- Date utilities ----------

  /// Returns the Monday of the week containing [date] as YYYY-MM-DD.
  String getWeekStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final y = monday.year.toString().padLeft(4, '0');
    final m = monday.month.toString().padLeft(2, '0');
    final day = monday.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Returns a list of week-start dates spanning [pastWeeks] before this week to [futureWeeks] after this week.
  List<String> getWeeksRange({int pastWeeks = 8, int futureWeeks = 6}) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day);
    final thisMonday = d.subtract(Duration(days: d.weekday - 1));
    final total = pastWeeks + 1 + futureWeeks;
    return List.generate(total, (i) {
      final offset = i - pastWeeks;
      final monday = thisMonday.add(Duration(days: offset * 7));
      final y = monday.year.toString().padLeft(4, '0');
      final m = monday.month.toString().padLeft(2, '0');
      final day = monday.day.toString().padLeft(2, '0');
      return '$y-$m-$day';
    });
  }

  /// Returns the next [count] week-start dates starting from this week's Monday.
  List<String> getNextWeeks(int count) {
    return getWeeksRange(pastWeeks: 0, futureWeeks: count > 0 ? count - 1 : 0);
  }
}
