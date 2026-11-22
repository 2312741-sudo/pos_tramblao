import '../../models/schedule_model.dart';
import '../../models/store_model.dart';
import '../../features/store/screens/shift_settings_screen.dart';

class AttendanceUtils {
  /// Calculates late check-in warning text for an active attendance.
  /// 
  /// Returns:
  /// - 'Đi muộn X phút' if late < 60 minutes (e.g. 'Đi muộn 15 phút')
  /// - 'Đi muộn XhYp' or 'Đi muộn Xh' if late >= 60 minutes (e.g. 'Đi muộn 1h15p', 'Đi muộn 2h')
  /// - null if user checked in early, on-time, without a scheduled shift, or late < 1 minute.
  static String? calculateLateString({
    required DateTime checkIn,
    required String userId,
    required StoreModel? store,
    required ScheduleModel? schedule,
  }) {
    if (store == null || schedule == null) return null;

    final localCheckIn = checkIn.toLocal();
    final weekday = localCheckIn.weekday; // 1 = Mon, 7 = Sun

    // 1. Get scheduled shifts for this user on this weekday
    final userDaySchedule = schedule.getScheduleForUser(userId);
    if (userDaySchedule == null) return null;

    final rawEntries = userDaySchedule.shiftForDay(weekday);
    if (rawEntries.isEmpty) return null;

    // Filter out delivery flags and extract shift IDs
    final assignedShiftIds = rawEntries
        .where((s) => s != 'delivery' && s != 'giaohang' && s != 'off' && s.isNotEmpty)
        .map((s) => s.split('|')[0])
        .toSet()
        .toList();

    if (assignedShiftIds.isEmpty) return null;

    // 2. Resolve ShiftDefinitions from store
    final allShifts = store.customShifts.isNotEmpty ? store.customShifts : kDefaultShifts;
    final scheduledShifts = <ShiftDefinition>[];
    for (final sId in assignedShiftIds) {
      final found = allShifts.where((s) => s.id == sId).firstOrNull;
      if (found != null) {
        scheduledShifts.add(found);
      }
    }

    if (scheduledShifts.isEmpty) return null;

    // 3. Find the best matching shift (in case user has multiple shifts in a day)
    final checkInMinutes = localCheckIn.hour * 60 + localCheckIn.minute;

    ShiftDefinition bestShift = scheduledShifts.first;
    if (scheduledShifts.length > 1) {
      int minDiff = 999999;
      for (final s in scheduledShifts) {
        final startM = s.startHour * 60 + s.startMinute;
        var endM = s.endHour * 60 + s.endMinute;
        if (endM < startM) endM += 24 * 60; // cross-midnight shift

        // If checkIn falls within reasonable window of this shift [start - 60, end]
        if (checkInMinutes >= startM - 60 && checkInMinutes <= endM) {
          bestShift = s;
          break;
        }

        final diff = (checkInMinutes - startM).abs();
        if (diff < minDiff) {
          minDiff = diff;
          bestShift = s;
        }
      }
    }

    // 4. Calculate minutes late
    final shiftStartMinutes = bestShift.startHour * 60 + bestShift.startMinute;
    int lateMinutes = checkInMinutes - shiftStartMinutes;

    // If shift is overnight (e.g. 22:00 to 06:00) and checkIn is in the morning after midnight (e.g. 00:30)
    if (bestShift.endHour < bestShift.startHour &&
        checkInMinutes < bestShift.startHour * 60 &&
        checkInMinutes <= bestShift.endHour * 60) {
      lateMinutes = (checkInMinutes + 24 * 60) - shiftStartMinutes;
    }

    // 5. If on time, early, or less than 1 minute late
    if (lateMinutes < 1) {
      return null;
    }

    // 6. Format late string
    if (lateMinutes < 60) {
      return 'Đi muộn $lateMinutes phút';
    } else {
      final hours = lateMinutes ~/ 60;
      final mins = lateMinutes % 60;
      if (mins == 0) {
        return 'Đi muộn ${hours}h';
      }
      return 'Đi muộn ${hours}h${mins}p';
    }
  }
}
