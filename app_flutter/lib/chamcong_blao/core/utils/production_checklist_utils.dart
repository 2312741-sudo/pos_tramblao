import '../../models/store_model.dart';
import '../../models/schedule_model.dart';
import '../../features/store/screens/shift_settings_screen.dart';
import 'department_utils.dart';

class ChecklistEvaluationResult {
  /// Whether the user must complete the checklist before this checkout can proceed
  final bool isRequired;

  /// Workday date string in YYYY-MM-DD format (based on Vietnam Time UTC+7)
  final String workdayDate;

  /// Whether the employee has at least one scheduled shift in the Production (SX) department on this workday
  final bool hasProductionShiftOnWorkday;

  /// Whether the checkout attempt is within the validity window (before 03:00 AM of the day following the workday in VN Time)
  final bool isWithinValidWindow;

  /// Whether the employee has already completed a production checklist report for this workday
  final bool hasAlreadyReported;

  /// The shift definition resolved for this report (or fallback default shift)
  final ShiftDefinition resolvedShift;

  const ChecklistEvaluationResult({
    required this.isRequired,
    required this.workdayDate,
    required this.hasProductionShiftOnWorkday,
    required this.isWithinValidWindow,
    required this.hasAlreadyReported,
    required this.resolvedShift,
  });
}

class ProductionChecklistUtils {
  /// Evaluates whether a production checklist is required when checking out of a shift.
  ///
  /// Business Rules:
  /// 1. Workday Determination: Based on [checkInTime] in Vietnam Time (UTC+7).
  /// 2. Activation: Employee has at least 1 Production (SX) shift in [schedule] on that workday.
  /// 3. Frequency: Exactly 1 time per workday. If [hasAlreadyReportedForWorkday] is true, no checklist is needed.
  /// 4. Validity Window: Applies from check-in up to 03:00 AM of the day following the workday (Vietnam Time).
  /// 5. Expiration: After 03:00 AM next day, checklist is bypassed (checkout proceeds normally without blocking).
  static ChecklistEvaluationResult evaluateChecklistRequirement({
    required DateTime checkInTime,
    required DateTime now,
    required String userId,
    required StoreModel store,
    String? memberDepartmentId,
    ScheduleModel? schedule,
    bool hasAlreadyReportedForWorkday = false,
  }) {
    // 1. Calculate workday in Vietnam Time (UTC+7)
    final vnCheckIn = checkInTime.toUtc().add(const Duration(hours: 7));
    final workdayDate =
        '${vnCheckIn.year}-${vnCheckIn.month.toString().padLeft(2, '0')}-${vnCheckIn.day.toString().padLeft(2, '0')}';
    final weekday = vnCheckIn.weekday; // 1 = Mon ... 7 = Sun

    // 2. Check if the user has an SX shift scheduled on this workday
    List<String> workdayShiftEntries = [];
    if (schedule != null) {
      final userSchedule = schedule.getScheduleForUser(userId);
      if (userSchedule != null) {
        workdayShiftEntries = userSchedule.shiftForDay(weekday);
      }
    }

    final hasProductionShiftOnWorkday =
        DepartmentUtils.isUserInProductionShiftToday(
      userId: userId,
      store: store,
      memberDepartmentId: memberDepartmentId,
      todayShiftEntries: workdayShiftEntries,
    );

    // 3. Check validity window: up to 03:00:00 AM of the day following the workday (Vietnam Time)
    final vnNow = now.toUtc().add(const Duration(hours: 7));
    // Deadline: Year, Month, Day + 1 at 03:00:00 (in VN Time)
    final deadline = DateTime.utc(
      vnCheckIn.year,
      vnCheckIn.month,
      vnCheckIn.day + 1,
      3,
      0,
      0,
    );
    final isWithinValidWindow = vnNow.isBefore(deadline);

    // 4. Determine if checklist is required
    final isRequired = hasProductionShiftOnWorkday &&
        !hasAlreadyReportedForWorkday &&
        isWithinValidWindow;

    // 5. Resolve ShiftDefinition for report metadata
    final shifts = store.customShifts.isNotEmpty
        ? store.customShifts
        : [
            const ShiftDefinition(
              id: 'morning',
              name: 'Ca Sáng',
              startHour: 6,
              startMinute: 0,
              endHour: 12,
              endMinute: 0,
            ),
            const ShiftDefinition(
              id: 'afternoon',
              name: 'Ca Chiều',
              startHour: 12,
              startMinute: 0,
              endHour: 18,
              endMinute: 0,
            ),
            const ShiftDefinition(
              id: 'evening',
              name: 'Ca Tối',
              startHour: 18,
              startMinute: 0,
              endHour: 23,
              endMinute: 0,
            ),
          ];

    ShiftDefinition? matchedShift;
    if (workdayShiftEntries.isNotEmpty) {
      for (final entry in workdayShiftEntries) {
        final shiftId = entry.contains('|') ? entry.split('|')[0] : entry;
        final s = shifts.where((item) => item.id == shiftId).firstOrNull;
        if (s != null) {
          matchedShift = s;
          break;
        }
      }
    }

    matchedShift ??= shifts.firstOrNull ??
        const ShiftDefinition(
          id: 'default',
          name: 'Ca sản xuất',
          startHour: 8,
          startMinute: 0,
          endHour: 17,
          endMinute: 0,
        );

    return ChecklistEvaluationResult(
      isRequired: isRequired,
      workdayDate: workdayDate,
      hasProductionShiftOnWorkday: hasProductionShiftOnWorkday,
      isWithinValidWindow: isWithinValidWindow,
      hasAlreadyReported: hasAlreadyReportedForWorkday,
      resolvedShift: matchedShift,
    );
  }
}
