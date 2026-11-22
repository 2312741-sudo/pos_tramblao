import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/attendance_model.dart';
import '../../../cc_firebase.dart';

class AttendanceRepository {
  final FirebaseFirestore _firestore;

  AttendanceRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? CcFirebase.firestore;

  CollectionReference<Map<String, dynamic>> _attendances(String storeId) =>
      _firestore
          .collection('stores')
          .doc(storeId)
          .collection('attendances');

  String _todayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> checkIn(
    String storeId,
    String userId,
    CheckInMethod method,
  ) async {
    try {
      final now = DateTime.now().toUtc();
      final date = _todayDate();

      // Check for existing active record today
      final existing = await _attendances(storeId)
          .where('userId', isEqualTo: userId)
          .where('date', isEqualTo: date)
          .where('checkOut', isNull: true)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        throw Exception('Bạn đang trong ca làm việc hôm nay');
      }

      await _attendances(storeId).add({
        'userId': userId,
        'storeId': storeId,
        'date': date,
        'checkIn': Timestamp.fromDate(now),
        'checkOut': null,
        'checkInMethod': method.value,
        'totalHours': 0.0,
        'isEdited': false,
        'editedBy': null,
        'editNote': null,
        'isOffline': false,
      });

      // Send notification for Owner & Managers
      try {
        final memberDoc = await _firestore
            .collection('stores')
            .doc(storeId)
            .collection('members')
            .doc(userId)
            .get();
        final storeDoc = await _firestore.collection('stores').doc(storeId).get();
        final memberName = memberDoc.data()?['name'] as String? ?? 'Nhân viên';
        final storeName = storeDoc.data()?['name'] as String? ?? 'Cửa hàng';
        final vnTime = now.add(const Duration(hours: 7));
        final timeStr =
            '${vnTime.hour.toString().padLeft(2, '0')}:${vnTime.minute.toString().padLeft(2, '0')}';

        await _firestore
            .collection('stores')
            .doc(storeId)
            .collection('notifications')
            .add({
          'storeId': storeId,
          'title': 'Nhân viên vào ca',
          'body': '$memberName tại $storeName đã vào ca lúc $timeStr.',
          'type': 'check_in',
          'createdAt': Timestamp.fromDate(now),
          'targetRoles': [
            'owner',
            'manager_1',
            'manager_2',
            'manager',
            'legacyManager'
          ],
          'readBy': [userId],
          'routePath': '/active-staff',
          'routeExtra': {'storeId': storeId, 'userId': userId, 'date': date},
        });
      } catch (_) {}
    } catch (e) {
      throw Exception('Chấm vào thất bại: $e');
    }
  }

  Future<void> checkOut(
    String storeId,
    String userId, {
    bool isProductionShift = false,
  }) async {
    try {
      final now = DateTime.now().toUtc();

      // Find active attendance record first (no date filter — handles cross-midnight shifts)
      final query = await _attendances(storeId)
          .where('userId', isEqualTo: userId)
          .where('checkOut', isNull: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        throw Exception('Không tìm thấy ca làm việc nào đang hoạt động');
      }

      final doc = query.docs.first;
      final checkIn = (doc.data()['checkIn'] as Timestamp).toDate().toUtc();
      final vnCheckIn = checkIn.add(const Duration(hours: 7));
      final workdayDate =
          '${vnCheckIn.year}-${vnCheckIn.month.toString().padLeft(2, '0')}-${vnCheckIn.day.toString().padLeft(2, '0')}';

      // If user is in a production shift, verify that a production report was submitted for this workday
      // (only within the valid window up to 03:00 AM the next day VN Time)
      if (isProductionShift) {
        final vnNow = now.add(const Duration(hours: 7));
        final deadline = DateTime.utc(
          vnCheckIn.year,
          vnCheckIn.month,
          vnCheckIn.day + 1,
          3,
          0,
          0,
        );
        final isWithinValidWindow = vnNow.isBefore(deadline);

        if (isWithinValidWindow) {
          final reportsQuery = await _firestore
              .collection('stores')
              .doc(storeId)
              .collection('production_reports')
              .where('userId', isEqualTo: userId)
              .where('date', isEqualTo: workdayDate)
              .limit(1)
              .get();

          if (reportsQuery.docs.isEmpty) {
            try {
              await CcFirebase.functions(region: 'asia-east2').httpsCallable('requestChecklistNotification').call({
                'storeId': storeId, 'attendanceId': doc.id,
              });
            } catch (_) {}
            try {
              await _firestore
                  .collection('stores')
                  .doc(storeId)
                  .collection('notifications')
                  .add({
                'storeId': storeId,
                'title': 'Nhắc nhở: Chưa nộp báo cáo sản xuất',
                'body':
                    'Bạn đang trong ca sản xuất ngày $workdayDate nhưng chưa nộp báo cáo checklist. Vui lòng hoàn thành để chấm ra.',
                'type': 'checklist_reminder',
                'createdAt': Timestamp.now(),
                'targetUserId': userId,
                'readBy': [],
                'routePath': '/production/report',
              });
            } catch (_) {}
            throw Exception(
                'Bắt buộc phải hoàn thành và gửi báo cáo sản xuất trước khi ra ca.');
          }
        }
      }

      final totalHours = now.difference(checkIn).inMinutes / 60.0;

      await doc.reference.update({
        'checkOut': Timestamp.fromDate(now),
        'totalHours': double.parse(totalHours.toStringAsFixed(2)),
      });

      // Send notification for Owner & Managers
      try {
        final memberDoc = await _firestore
            .collection('stores')
            .doc(storeId)
            .collection('members')
            .doc(userId)
            .get();
        final storeDoc = await _firestore.collection('stores').doc(storeId).get();
        final memberName = memberDoc.data()?['name'] as String? ?? 'Nhân viên';
        final storeName = storeDoc.data()?['name'] as String? ?? 'Cửa hàng';
        final vnTime = now.add(const Duration(hours: 7));
        final timeStr =
            '${vnTime.hour.toString().padLeft(2, '0')}:${vnTime.minute.toString().padLeft(2, '0')}';

        await _firestore
            .collection('stores')
            .doc(storeId)
            .collection('notifications')
            .add({
          'storeId': storeId,
          'title': 'Nhân viên kết thúc ca',
          'body':
              '$memberName tại $storeName đã kết thúc ca lúc $timeStr (Tổng: ${totalHours.toStringAsFixed(1)}h).',
          'type': 'check_out',
          'createdAt': Timestamp.fromDate(now),
          'targetRoles': [
            'owner',
            'manager_1',
            'manager_2',
            'manager',
            'legacyManager'
          ],
          'readBy': [userId],
          'routePath': '/attendance-table',
          'routeExtra': {
            'storeId': storeId,
            'userId': userId,
            'date': workdayDate
          },
        });
      } catch (_) {}
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Chấm ra thất bại: $e');
    }
  }

  Stream<AttendanceModel?> watchTodayAttendance(
      String storeId, String userId) {
    final date = _todayDate();
    return _attendances(storeId)
        .where('userId', isEqualTo: userId)
        .where('date', isEqualTo: date)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      
      // Look for active shift first
      final activeDoc = snap.docs.where((d) => d.data()['checkOut'] == null).firstOrNull;
      if (activeDoc != null) {
        return AttendanceModel.fromFirestore(activeDoc);
      }
      
      // Otherwise, return the latest shift
      final list = snap.docs.map((d) => AttendanceModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.checkIn.compareTo(a.checkIn));
      return list.first;
    });
  }

  /// Watches for any ACTIVE attendance (checkOut == null) for this user,
  /// regardless of which date the check-in started on.
  /// This handles cross-midnight shifts: e.g. check-in at 22:00 Day 1,
  /// still active at 01:00 Day 2.
  /// Falls back to today's latest completed attendance if no active shift.
  Stream<AttendanceModel?> watchActiveAttendance(
      String storeId, String userId) {
    // Primary: watch for any unclosed attendance record
    return _attendances(storeId)
        .where('userId', isEqualTo: userId)
        .where('checkOut', isNull: true)
        .limit(1)
        .snapshots()
        .asyncMap((activeSnap) async {
      if (activeSnap.docs.isNotEmpty) {
        return AttendanceModel.fromFirestore(activeSnap.docs.first);
      }
      // No active shift → fall back to today's latest completed record
      final date = _todayDate();
      final todaySnap = await _attendances(storeId)
          .where('userId', isEqualTo: userId)
          .where('date', isEqualTo: date)
          .get();
      if (todaySnap.docs.isEmpty) return null;
      final list = todaySnap.docs
          .map((d) => AttendanceModel.fromFirestore(d))
          .toList();
      list.sort((a, b) => b.checkIn.compareTo(a.checkIn));
      return list.first;
    });
  }

  /// Retrieves the currently open attendance record (checkOut == null) without a date filter.
  Future<AttendanceModel?> getActiveAttendance(String storeId, String userId) async {
    try {
      final snap = await _attendances(storeId)
          .where('userId', isEqualTo: userId)
          .where('checkOut', isNull: true)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return AttendanceModel.fromFirestore(snap.docs.first);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Stream<List<AttendanceModel>> watchMonthAttendance(
    String storeId,
    String userId,
    String month, // YYYY-MM
  ) {
    return _attendances(storeId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => AttendanceModel.fromFirestore(d))
              .where((a) => a.date.startsWith(month))
              .toList();
          list.sort((a, b) => b.date.compareTo(a.date));
          return list;
        });
  }

  Stream<List<AttendanceModel>> watchAllAttendances(
      String storeId, String date) {
    return _attendances(storeId)
        .where('date', isEqualTo: date)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => AttendanceModel.fromFirestore(d))
              .toList();
          list.sort((a, b) => a.checkIn.compareTo(b.checkIn));
          return list;
        });
  }

  /// Watches for all currently ACTIVE attendances (checkOut == null) across all users in the store.
  /// Used for the real-time "Nhân viên đang làm" (Working Employees) dashboard box.
  Stream<List<AttendanceModel>> watchActiveAttendances(String storeId) {
    return _attendances(storeId)
        .where('checkOut', isNull: true)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => AttendanceModel.fromFirestore(d))
              .toList();
          list.sort((a, b) => a.checkIn.compareTo(b.checkIn));
          return list;
        });
  }

  Future<void> editAttendance(
    String storeId,
    String attendanceId,
    DateTime newCheckIn,
    DateTime newCheckOut,
    String editNote,
    String editedBy,
  ) async {
    try {
      final totalHours =
          newCheckOut.difference(newCheckIn).inMinutes / 60.0;
      await _attendances(storeId).doc(attendanceId).update({
        'checkIn': Timestamp.fromDate(newCheckIn.toUtc()),
        'checkOut': Timestamp.fromDate(newCheckOut.toUtc()),
        'totalHours': double.parse(totalHours.toStringAsFixed(2)),
        'isEdited': true,
        'editedBy': editedBy,
        'editNote': editNote,
      });
    } catch (e) {
      throw Exception('Chỉnh sửa chấm công thất bại: $e');
    }
  }

  Future<List<AttendanceModel>> getMonthAttendances(
    String storeId,
    String month,
  ) async {
    try {
      final snap = await _attendances(storeId)
          .where('date', isGreaterThanOrEqualTo: '$month-01')
          .where('date', isLessThanOrEqualTo: '$month-31')
          .orderBy('date')
          .get();
      return snap.docs
          .map((d) => AttendanceModel.fromFirestore(d))
          .toList();
    } catch (e) {
      print('Lỗi getMonthAttendances: $e');
      return [];
    }
  }

  Future<List<AttendanceModel>> getAttendancesInRange(
    String storeId,
    String startDate,
    String endDate,
  ) async {
    try {
      final snap = await _attendances(storeId)
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .orderBy('date')
          .get();
      return snap.docs
          .map((d) => AttendanceModel.fromFirestore(d))
          .toList();
    } catch (e) {
      print('Lỗi getAttendancesInRange: $e');
      return [];
    }
  }

  Future<void> createManualAttendance(
    String storeId,
    String userId,
    String date,
    DateTime checkIn,
    DateTime checkOut,
    String editNote,
    String editedBy,
  ) async {
    try {
      final totalHours = checkOut.difference(checkIn).inMinutes / 60.0;
      await _attendances(storeId).add({
        'userId': userId,
        'storeId': storeId,
        'date': date,
        'checkIn': Timestamp.fromDate(checkIn.toUtc()),
        'checkOut': Timestamp.fromDate(checkOut.toUtc()),
        'checkInMethod': CheckInMethod.manual.value,
        'totalHours': double.parse(totalHours.toStringAsFixed(2)),
        'isEdited': true,
        'editedBy': editedBy,
        'editNote': editNote.isNotEmpty ? editNote : 'Thêm thủ công',
        'isOffline': false,
      });
    } catch (e) {
      throw Exception('Tạo chấm công thất bại: $e');
    }
  }
}

// ---------- Provider ----------

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository();
});
