import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/member_model.dart';
import '../../models/schedule_model.dart';
import '../../models/store_model.dart';
import '../../features/salary/providers/salary_provider.dart';
import '../../features/store/screens/shift_settings_screen.dart';
import 'department_utils.dart';
import 'excel_export_service.dart';
import 'share_utils.dart';

class ExportUtils {
  static Future<void> exportMonthlyAttendanceToExcel(
    String storeId,
    DateTime dateInMonth,
    List<MemberModel> members,
    SalaryRepository repo, {
    String storeName = '',
    BuildContext? context,
  }) async {
    try {
      final monthStr = '${dateInMonth.year}-${dateInMonth.month.toString().padLeft(2, '0')}';
      final allAttendances = await repo.getAllMonthAttendances(storeId, monthStr);
      final daysInMonth = DateUtils.getDaysInMonth(dateInMonth.year, dateInMonth.month);

      final excel = Excel.createExcel();
      final sheetName = 'BangCong';
      excel.rename('Sheet1', sheetName);
      final sheet = excel[sheetName];

      // Build Headers: Tên nhân viên, Vai trò, Ngày 1..31, Tổng giờ
      final headers = [
        TextCellValue('Tên nhân viên'),
        TextCellValue('Vai trò'),
      ];
      for (int i = 1; i <= daysInMonth; i++) {
        headers.add(TextCellValue('Ngày $i'));
      }
      headers.add(TextCellValue('Tổng giờ'));
      sheet.appendRow(headers);

      // Add Data for each member
      for (final member in members) {
        final attendances = allAttendances[member.userId] ?? [];
        
        final row = <CellValue>[
          TextCellValue(member.name),
          TextCellValue(member.role.label),
        ];

        double totalMonthHours = 0.0;

        for (int day = 1; day <= daysInMonth; day++) {
          final dayStr = '$monthStr-${day.toString().padLeft(2, '0')}';
          final dayAttendances = attendances.where((a) => a.date == dayStr);
          final dayHours = dayAttendances.fold(0.0, (sum, a) => sum + a.totalHours);
          
          totalMonthHours += dayHours;
          
          if (dayHours > 0) {
            row.add(DoubleCellValue(dayHours));
          } else {
            row.add(IntCellValue(0));
          }
        }

        row.add(DoubleCellValue(totalMonthHours));
        sheet.appendRow(row);
      }

      // Save file
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final dir = await getApplicationDocumentsDirectory();
        final storePart = ExcelExportService.sanitize(storeName);
        final timePart = 'T${dateInMonth.month.toString().padLeft(2, '0')}-${dateInMonth.year}';
        final storePrefix = storePart.isNotEmpty ? '${storePart}_' : '';
        final fileName = 'BangCong_$storePrefix$timePart.xlsx';
        final file = File('${dir.path}/$fileName');
        
        await file.writeAsBytes(fileBytes);
        await ShareUtils.shareFiles(
          [file.path],
          context: context,
          text: 'Bảng công tháng $monthStr',
          subject: 'Bảng công $storeName $monthStr',
        );
      }
    } catch (e) {
      debugPrint('exportMonthlyAttendanceToExcel error: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi xuất file: $e'),
            backgroundColor: const Color(0xFFC8102E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      throw Exception('Lỗi xuất file: $e');
    }
  }

  static Future<void> exportWeeklyScheduleToExcel({
    required String weekStart,
    required List<MemberModel> members,
    required ScheduleModel? schedule,
    String storeName = '',
    List<ShiftDefinition> customShifts = const [],
    List<DepartmentDefinition> departments = const [],
    StoreModel? store,
    BuildContext? context,
  }) async {
    try {
      final monday = DateTime.parse(weekStart);
      final days = List.generate(7, (i) => monday.add(Duration(days: i)));
      final dayNamesEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

      final resolvedStoreName = (store != null && store.name.isNotEmpty) ? store.name : storeName;
      final resolvedShifts = (store != null && store.customShifts.isNotEmpty) ? store.customShifts : customShifts;
      final resolvedDepartments = (store != null && store.departments.isNotEmpty) ? store.departments : departments;

      final excel = Excel.createExcel();
      final sheetName = 'LichLam';
      excel.rename('Sheet1', sheetName);
      excel.setDefaultSheet(sheetName);
      final sheet = excel[sheetName];

      // Cell Styles
      final titleStyle = CellStyle(
        fontColorHex: ExcelColor.fromHexString('#FF0099FF'),
        bold: true,
        fontSize: 12,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final headerStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#FFEFEFEF'),
        bold: true,
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final nameStyle = CellStyle(
        bold: true,
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Left,
        verticalAlign: VerticalAlign.Center,
      );

      final centerStyle = CellStyle(
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final boldCenterStyle = CellStyle(
        bold: true,
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      // ── Row 0: Title Banner ──────────────────────────────────────────────
      final titleText = 'CÔNG VIỆC THÁNG ${monday.month} NĂM ${monday.year} ${resolvedStoreName.toUpperCase()}';
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(columnIndex: 29, rowIndex: 0),
        customValue: TextCellValue(titleText),
      );
      var titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      titleCell.cellStyle = titleStyle;

      // ── Row 1 & 2: Header Rows ───────────────────────────────────────────
      // Col 0: TÍNH CHẤT
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2),
        customValue: TextCellValue('TÍNH CHẤT'),
      );
      var tcCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1));
      tcCell.cellStyle = headerStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).cellStyle = headerStyle;

      // Days: Monday -> Sunday (Cols 1..28)
      for (int i = 0; i < 7; i++) {
        final startCol = 1 + i * 4;
        final endCol = startCol + 3;
        final dayDate = days[i];
        final dateStr = '${dayDate.day.toString().padLeft(2, '0')}/${dayDate.month.toString().padLeft(2, '0')}';

        // Row 1: Day Name (e.g. Monday)
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: 1),
          CellIndex.indexByColumnRow(columnIndex: endCol, rowIndex: 1),
          customValue: TextCellValue(dayNamesEn[i]),
        );
        for (int c = startCol; c <= endCol; c++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1)).cellStyle = headerStyle;
        }

        // Row 2: Date (e.g. 10/08)
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: 2),
          CellIndex.indexByColumnRow(columnIndex: endCol, rowIndex: 2),
          customValue: TextCellValue(dateStr),
        );
        for (int c = startCol; c <= endCol; c++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2)).cellStyle = headerStyle;
        }
      }

      // Col 29: TỔNG SỐ GIỜ TRONG TUẦN
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 29, rowIndex: 1),
        CellIndex.indexByColumnRow(columnIndex: 29, rowIndex: 2),
        customValue: TextCellValue('TỔNG SỐ GIỜ\nTRONG TUẦN'),
      );
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 29, rowIndex: 1)).cellStyle = headerStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 29, rowIndex: 2)).cellStyle = headerStyle;

      // ── Row 3+: Data Rows (Sorted by Owner's Custom Order) ──────────────
      final sortedMembers = List<MemberModel>.from(members);
      if (store != null && store.memberOrder.isNotEmpty) {
        sortedMembers.sort((a, b) {
          final idxA = store.memberOrder.indexOf(a.userId);
          final idxB = store.memberOrder.indexOf(b.userId);
          if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
          if (idxA != -1) return -1;
          if (idxB != -1) return 1;
          return a.name.compareTo(b.name);
        });
      }

      for (int r = 0; r < sortedMembers.length; r++) {
        final member = sortedMembers[r];
        final rowIdx = 3 + r;
        final daySchedule = schedule?.getScheduleForUser(member.userId);

        // Col 0: Member Name
        var mCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx));
        mCell.value = TextCellValue(member.name.toUpperCase());
        mCell.cellStyle = nameStyle;

        double memberTotalWeekHours = 0.0;

        for (int i = 0; i < 7; i++) {
          final startCol = 1 + i * 4;
          final shifts = daySchedule?.shiftForDay(i + 1) ?? [];
          final actualShifts = shifts.where((s) => s != 'delivery' && s != 'giaohang').toList();

          if (actualShifts.isEmpty) {
            // Off: - | - | - | 0,0
            var c1 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: startCol + 0, rowIndex: rowIdx));
            c1.value = TextCellValue('-');
            c1.cellStyle = centerStyle;

            var c2 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: startCol + 1, rowIndex: rowIdx));
            c2.value = TextCellValue('-');
            c2.cellStyle = centerStyle;

            var c3 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: startCol + 2, rowIndex: rowIdx));
            c3.value = TextCellValue('-');
            c3.cellStyle = centerStyle;

            var c4 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: startCol + 3, rowIndex: rowIdx));
            c4.value = DoubleCellValue(0.0);
            c4.cellStyle = centerStyle;
          } else {
            // Parse shifts
            String shiftId = actualShifts.first;
            String? deptId;
            if (shiftId.contains('|')) {
              final parts = shiftId.split('|');
              shiftId = parts[0];
              deptId = parts[1];
            }

            final shiftDef = resolvedShifts.where((s) => s.id == shiftId).firstOrNull;
            final deptDef = resolvedDepartments.where((d) => d.id == deptId).firstOrNull;

            String startTimeStr = '-';
            String endTimeStr = '-';
            String shiftLabel = '-';
            double dayHours = 0.0;

            if (shiftDef != null) {
              startTimeStr = shiftDef.startTimeStr;
              endTimeStr = shiftDef.endTimeStr;
              dayHours = shiftDef.totalHours;

              if (deptDef != null && deptDef.shortName.isNotEmpty) {
                shiftLabel = deptDef.shortName;
              } else if (deptDef != null && deptDef.name.isNotEmpty) {
                shiftLabel = deptDef.name;
              } else {
                shiftLabel = shiftDef.name;
              }
            } else {
              final defaultType = ShiftTypeExtension.fromString(shiftId);
              if (defaultType != ShiftType.off) {
                if (defaultType == ShiftType.morning) {
                  startTimeStr = '06:00';
                  endTimeStr = '14:00';
                  dayHours = 8.0;
                } else if (defaultType == ShiftType.afternoon) {
                  startTimeStr = '14:00';
                  endTimeStr = '22:00';
                  dayHours = 8.0;
                } else if (defaultType == ShiftType.evening) {
                  startTimeStr = '22:00';
                  endTimeStr = '06:00';
                  dayHours = 8.0;
                }
                if (deptDef != null && deptDef.shortName.isNotEmpty) {
                  shiftLabel = deptDef.shortName;
                } else {
                  shiftLabel = defaultType.label;
                }
              } else {
                shiftLabel = shiftId;
              }
            }

            final isHighlight = (shiftDef?.isProduction == true) ||
                DepartmentUtils.isProduction(
                  deptId: deptDef?.id,
                  deptName: deptDef?.name,
                  shortName: deptDef?.shortName,
                ) ||
                shiftLabel.toUpperCase() == 'DR' ||
                shiftLabel.toUpperCase() == 'SX';

            var c1 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: startCol + 0, rowIndex: rowIdx));
            c1.value = TextCellValue(startTimeStr);
            c1.cellStyle = centerStyle;

            var c2 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: startCol + 1, rowIndex: rowIdx));
            c2.value = TextCellValue(endTimeStr);
            c2.cellStyle = centerStyle;

            var c3 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: startCol + 2, rowIndex: rowIdx));
            c3.value = TextCellValue(shiftLabel);
            c3.cellStyle = isHighlight ? boldCenterStyle : centerStyle;

            var c4 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: startCol + 3, rowIndex: rowIdx));
            c4.value = DoubleCellValue(dayHours);
            c4.cellStyle = centerStyle;

            memberTotalWeekHours += dayHours;
          }
        }

        // Col 29: Total Week Hours
        var totCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 29, rowIndex: rowIdx));
        totCell.value = DoubleCellValue(memberTotalWeekHours);
        totCell.cellStyle = boldCenterStyle;
      }

      // Column widths
      sheet.setColumnWidth(0, 24);
      for (int i = 0; i < 7; i++) {
        sheet.setColumnWidth(1 + i * 4 + 0, 8);
        sheet.setColumnWidth(1 + i * 4 + 1, 8);
        sheet.setColumnWidth(1 + i * 4 + 2, 9);
        sheet.setColumnWidth(1 + i * 4 + 3, 7);
      }
      sheet.setColumnWidth(29, 18);

      // Save and share
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final dir = await getApplicationDocumentsDirectory();
        final storePart = ExcelExportService.sanitize(resolvedStoreName);
        final sundayStr = '${days.last.day.toString().padLeft(2, '0')}.${days.last.month.toString().padLeft(2, '0')}.${days.last.year}';
        final mondayStr = '${monday.day.toString().padLeft(2, '0')}.${monday.month.toString().padLeft(2, '0')}';
        final storePrefix = storePart.isNotEmpty ? '${storePart}_' : '';
        final fileName = 'LichLam_${storePrefix}Tuan_$mondayStr-$sundayStr.xlsx';
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(fileBytes);
        await ShareUtils.shareFiles(
          [file.path],
          context: context,
          text: 'Lịch làm tuần: $titleText',
          subject: 'Lịch làm việc $resolvedStoreName',
        );
      }
    } catch (e) {
      debugPrint('exportWeeklyScheduleToExcel error: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi xuất lịch: $e'),
            backgroundColor: const Color(0xFFC8102E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      throw Exception('Lỗi xuất lịch: $e');
    }
  }
}
