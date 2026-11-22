import '../../models/member_model.dart';
import '../../models/schedule_model.dart';
import '../../models/store_model.dart';

class DepartmentUtils {
  DepartmentUtils._();

  /// Normalize string by lowercasing, trimming, and stripping common Vietnamese diacritics
  static String normalize(String? text) {
    if (text == null) return '';
    var result = text.trim().toLowerCase();
    
    // Replace Vietnamese accents
    const withDia = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const noDia   = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    
    for (int i = 0; i < withDia.length; i++) {
      result = result.replaceAll(withDia[i], noDia[i]);
    }
    return result;
  }

  /// Calculates the Monday (YYYY-MM-DD) of the week for a given date
  static String getMondayOfWeek(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      final monday = dt.subtract(Duration(days: dt.weekday - 1));
      return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  /// Checks whether [candidate] matches the target department by ID or Name
  static bool isDepartmentMatch({
    required String? candidate,
    required String? targetDeptId,
    required String? targetDeptName,
    List<DepartmentDefinition>? storeDepartments,
  }) {
    if (candidate == null || candidate.trim().isEmpty) return false;
    final cleanCand = candidate.trim().toLowerCase();
    final normCand = normalize(candidate);

    final cleanTargetId = (targetDeptId ?? '').trim().toLowerCase();
    final normTargetId = normalize(targetDeptId);

    final cleanTargetName = (targetDeptName ?? '').trim().toLowerCase();
    final normTargetName = normalize(targetDeptName);

    // 1. Direct exact or accent-stripped match
    if (cleanTargetId.isNotEmpty && (cleanCand == cleanTargetId || normCand == normTargetId)) {
      return true;
    }
    if (cleanTargetName.isNotEmpty && (cleanCand == cleanTargetName || normCand == normTargetName)) {
      return true;
    }

    // 2. Production special check
    final isTargetProd = (targetDeptId != null && isProduction(deptId: targetDeptId)) ||
        (targetDeptName != null && isProduction(deptName: targetDeptName));
    if (isTargetProd && isProduction(deptId: candidate, deptName: candidate)) {
      return true;
    }

    // 3. Resolve candidate via storeDepartments
    if (storeDepartments != null && storeDepartments.isNotEmpty) {
      final matchedDept = storeDepartments.where((d) {
        final dId = d.id.trim().toLowerCase();
        final dName = d.name.trim().toLowerCase();
        final dShort = d.shortName.trim().toLowerCase();
        final normDName = normalize(d.name);
        return cleanCand == dId || cleanCand == dName || cleanCand == dShort || normCand == normDName;
      }).firstOrNull;

      if (matchedDept != null) {
        final mId = matchedDept.id.trim().toLowerCase();
        final mName = matchedDept.name.trim().toLowerCase();
        final normMName = normalize(matchedDept.name);

        if (cleanTargetId.isNotEmpty && (mId == cleanTargetId || normMName == normTargetId)) {
          return true;
        }
        if (cleanTargetName.isNotEmpty && (mName == cleanTargetName || normMName == normTargetName || mId == cleanTargetName)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Determines whether [userId] is scheduled or assigned to target departments on [dateStr].
  /// [dateStr] format: 'YYYY-MM-DD'
  static bool isUserInDepartmentOnDate({
    required String userId,
    required String dateStr,
    String? targetDeptId,
    String? targetDeptName,
    List<String>? targetDeptIds,
    List<String>? targetDeptNames,
    ScheduleModel? schedule,
    String? memberDepartment,
    List<DepartmentDefinition>? storeDepartments,
  }) {
    final allTargetIds = {
      if (targetDeptIds != null) ...targetDeptIds,
      if (targetDeptId != null && targetDeptId.isNotEmpty) targetDeptId,
    }.toList();

    final allTargetNames = {
      if (targetDeptNames != null) ...targetDeptNames,
      if (targetDeptName != null && targetDeptName.isNotEmpty) targetDeptName,
    }.toList();

    if (allTargetIds.isEmpty && allTargetNames.isEmpty) return false;

    bool matchesAny(String? candidate) {
      if (candidate == null || candidate.trim().isEmpty) return false;
      for (final tId in allTargetIds) {
        if (isDepartmentMatch(
          candidate: candidate,
          targetDeptId: tId,
          targetDeptName: null,
          storeDepartments: storeDepartments,
        )) {
          return true;
        }
      }
      for (final tName in allTargetNames) {
        if (isDepartmentMatch(
          candidate: candidate,
          targetDeptId: null,
          targetDeptName: tName,
          storeDepartments: storeDepartments,
        )) {
          return true;
        }
      }
      return false;
    }

    // 1. If schedule is available for this date's week:
    if (schedule != null) {
      final userSchedule = schedule.getScheduleForUser(userId);
      if (userSchedule != null) {
        DateTime? dt;
        try {
          dt = DateTime.parse(dateStr);
        } catch (_) {}

        if (dt != null) {
          final weekday = dt.weekday; // 1 = Monday ... 7 = Sunday
          final dayShifts = userSchedule.shiftForDay(weekday);

          // If user has shifts explicitly scheduled on this day:
          if (dayShifts.isNotEmpty) {
            // Check if explicitly off
            final isAllOff = dayShifts.every((s) => s.trim().toLowerCase() == 'off');
            if (isAllOff) {
              return false; // User is off on this workday
            }

            for (final entry in dayShifts) {
              final trimmed = entry.trim();
              if (trimmed == 'off' || trimmed == 'delivery' || trimmed == 'giaohang') {
                continue;
              }
              if (trimmed.contains('|')) {
                final shiftDeptId = trimmed.split('|')[1];
                if (matchesAny(shiftDeptId)) {
                  return true;
                }
              } else {
                // Shift has no explicit department override -> inherits member's default department
                if (memberDepartment != null && matchesAny(memberDepartment)) {
                  return true;
                }
              }
            }
            // User has scheduled shifts today, but none matched the department
            return false;
          } else {
            // dayShifts is empty.
            // If the user has other shifts in the week, they are not scheduled to work on this day
            if (userSchedule.workingDays > 0) {
              return false;
            }
          }
        }
      }
    }

    // 2. Fallback if no schedule or user not in schedule:
    // Check member's static department
    if (memberDepartment != null && memberDepartment.trim().isNotEmpty) {
      return matchesAny(memberDepartment);
    }

    return false;
  }

  /// Returns list of member IDs who belong or are scheduled in the department on [dateStr].
  static List<String> getUserIdsInDepartmentOnDate({
    required String dateStr,
    String? targetDeptId,
    String? targetDeptName,
    List<String>? targetDeptIds,
    List<String>? targetDeptNames,
    required List<MemberModel> allMembers,
    ScheduleModel? schedule,
    List<DepartmentDefinition>? storeDepartments,
  }) {
    final matchedUserIds = <String>[];
    for (final member in allMembers) {
      if (isUserInDepartmentOnDate(
        userId: member.userId,
        dateStr: dateStr,
        targetDeptId: targetDeptId,
        targetDeptName: targetDeptName,
        targetDeptIds: targetDeptIds,
        targetDeptNames: targetDeptNames,
        schedule: schedule,
        memberDepartment: member.department,
        storeDepartments: storeDepartments,
      )) {
        matchedUserIds.add(member.userId);
      }
    }
    return matchedUserIds;
  }

  /// Determines whether a department definition or ID/name represents Production (Sản xuất / SX)
  static bool isProduction({
    String? deptId,
    String? deptName,
    String? shortName,
    List<DepartmentDefinition>? storeDepartments,
  }) {
    // 1. Direct ID match
    final cleanId = normalize(deptId);
    if (cleanId == 'sx' || cleanId == 'dept_sx' || cleanId == 'san_xuat' || cleanId == 'sanxuat') {
      return true;
    }

    // 2. Direct ShortName match (e.g. "SX")
    final cleanShort = normalize(shortName).toUpperCase();
    if (cleanShort == 'SX') {
      return true;
    }

    // 3. Direct Name match (e.g. "Sản xuất", "Sản Xuất", "San xuat")
    final cleanName = normalize(deptName);
    if (cleanName.contains('san xuat') || cleanName == 'sx') {
      return true;
    }

    // 4. Lookup inside store departments if deptId provided
    if (deptId != null && storeDepartments != null && storeDepartments.isNotEmpty) {
      final dept = storeDepartments.where((d) => d.id == deptId).firstOrNull;
      if (dept != null) {
        return isProduction(
          deptId: dept.id,
          deptName: dept.name,
          shortName: dept.shortName,
        );
      }
    }

    return false;
  }

  /// Check if the user is in a Production (SX) department shift today
  static bool isUserInProductionShiftToday({
    required String userId,
    required StoreModel store,
    String? memberDepartmentId,
    List<String>? todayShiftEntries,
  }) {
    // 1. If today has specific shift assignments in the weekly schedule
    if (todayShiftEntries != null) {
      if (todayShiftEntries.isEmpty) {
        // Explicitly no shifts scheduled on this workday -> Not a scheduled SX shift
        return false;
      }
      for (final entry in todayShiftEntries) {
        if (entry.contains('|')) {
          final deptId = entry.split('|')[1];
          if (isProduction(deptId: deptId, storeDepartments: store.departments)) {
            return true;
          }
        } else {
          // Entry has no explicit department override -> inherits member's default department
          if (memberDepartmentId != null && isProduction(deptId: memberDepartmentId, storeDepartments: store.departments)) {
            return true;
          }
        }
      }
      // If shifts are scheduled today but none of them match SX -> Not an SX shift
      return false;
    }

    // 2. Fallback ONLY if todayShiftEntries is null (no schedule model available):
    if (memberDepartmentId != null && isProduction(deptId: memberDepartmentId, storeDepartments: store.departments)) {
      return true;
    }

    return false;
  }
}
