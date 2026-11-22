import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/member_model.dart';
import '../../models/attendance_model.dart';
import '../../models/store_model.dart';
import 'share_utils.dart';

class ExcelExportService {
  /// Sanitize tên file: bỏ dấu tiếng Việt, thay khoảng trắng bằng _, bỏ ký tự đặc biệt
  static String sanitize(String input) {
    const vietMap = {
      'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
      'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
      'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
      'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
      'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
      'đ': 'd',
      'À': 'A', 'Á': 'A', 'Ả': 'A', 'Ã': 'A', 'Ạ': 'A',
      'Ă': 'A', 'Ằ': 'A', 'Ắ': 'A', 'Ẳ': 'A', 'Ẵ': 'A', 'Ặ': 'A',
      'Â': 'A', 'Ầ': 'A', 'Ấ': 'A', 'Ẩ': 'A', 'Ẫ': 'A', 'Ậ': 'A',
      'È': 'E', 'É': 'E', 'Ẻ': 'E', 'Ẽ': 'E', 'Ẹ': 'E',
      'Ê': 'E', 'Ề': 'E', 'Ế': 'E', 'Ể': 'E', 'Ễ': 'E', 'Ệ': 'E',
      'Ì': 'I', 'Í': 'I', 'Ỉ': 'I', 'Ĩ': 'I', 'Ị': 'I',
      'Ò': 'O', 'Ó': 'O', 'Ỏ': 'O', 'Õ': 'O', 'Ọ': 'O',
      'Ô': 'O', 'Ồ': 'O', 'Ố': 'O', 'Ổ': 'O', 'Ỗ': 'O', 'Ộ': 'O',
      'Ơ': 'O', 'Ờ': 'O', 'Ớ': 'O', 'Ở': 'O', 'Ỡ': 'O', 'Ợ': 'O',
      'Ù': 'U', 'Ú': 'U', 'Ủ': 'U', 'Ũ': 'U', 'Ụ': 'U',
      'Ư': 'U', 'Ừ': 'U', 'Ứ': 'U', 'Ử': 'U', 'Ữ': 'U', 'Ự': 'U',
      'Ỳ': 'Y', 'Ý': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y', 'Ỵ': 'Y',
      'Đ': 'D',
    };
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      buffer.write(vietMap[char] ?? char);
    }
    return buffer.toString()
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s_\-]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  static Future<void> exportMonthlyAttendance({
    required List<MemberModel> members,
    required List<AttendanceModel> attendances,
    required String month,
    required StoreModel store,
    DateTime? startDate,
    DateTime? endDate,
    String? memberName,
    BuildContext? context,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Bảng Công'];
      excel.setDefaultSheet('Bảng Công');

      List<DateTime> dates = [];
      if (startDate != null && endDate != null) {
        DateTime current = startDate;
        while (!current.isAfter(endDate)) {
          dates.add(current);
          current = current.add(const Duration(days: 1));
        }
      } else {
        final parts = month.split('-');
        final year = int.parse(parts[0]);
        final mon = int.parse(parts[1]);
        final daysInMonth = DateTime(year, mon + 1, 0).day;
        for (int i = 1; i <= daysInMonth; i++) {
          dates.add(DateTime(year, mon, i));
        }
      }

      final themeColorHex = (store.themeColor ?? '#C8102E').replaceAll('#', '');
      final headerStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#FF$themeColorHex'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final r = int.parse(themeColorHex.substring(0, 2), radix: 16);
      final g = int.parse(themeColorHex.substring(2, 4), radix: 16);
      final b = int.parse(themeColorHex.substring(4, 6), radix: 16);
      final lr = (r + (255 - r) * 0.85).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
      final lg = (g + (255 - g) * 0.85).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
      final lb = (b + (255 - b) * 0.85).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
      final lightColorHex = '#FF${lr.toUpperCase()}${lg.toUpperCase()}${lb.toUpperCase()}';

      final dataStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(lightColorHex),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
      final normalStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final headers = ['NHÂN VIÊN', 'VAI TRÒ', 'TỔNG GIỜ', ...dates.map((d) => '${d.day}/${d.month}')];
      for (int c = 0; c < headers.length; c++) {
        var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
        cell.value = TextCellValue(headers[c]);
        cell.cellStyle = headerStyle;
      }

      final sortedMembers = List<MemberModel>.from(members);
      if (store.memberOrder.isNotEmpty) {
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
        final memberAtts = attendances.where((a) => a.userId == member.userId).toList();
        double totalHours = 0;
        
        final rowIdx = r + 1;
        
        var nameCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx));
        nameCell.value = TextCellValue(member.name);
        
        var roleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx));
        roleCell.value = TextCellValue(member.role == 'owner' ? 'Chủ' : member.role == 'manager' ? 'Quản lý' : 'Nhân viên');
        
        List<double> dayValues = [];
        for (var d in dates) {
          final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          final att = memberAtts.where((a) => a.date == dateStr || a.date == '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}').firstOrNull;
          
          if (att != null && att.totalHours > 0) {
            totalHours += att.totalHours;
            dayValues.add(att.totalHours);
          } else {
            dayValues.add(0.0);
          }
        }

        var totalCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx));
        totalCell.value = DoubleCellValue(totalHours);
        totalCell.cellStyle = normalStyle;

        for (int i = 0; i < dates.length; i++) {
          var c = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i + 3, rowIndex: rowIdx));
          final hours = dayValues[i];
          c.value = DoubleCellValue(hours);
          if (hours > 0) {
            c.cellStyle = dataStyle;
          } else {
            c.cellStyle = normalStyle;
          }
        }
      }

      sheet.setColumnWidth(0, 25);
      sheet.setColumnWidth(1, 15);
      sheet.setColumnWidth(2, 12);
      for (int i = 0; i < dates.length; i++) {
        sheet.setColumnWidth(i + 3, 10);
      }

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final directory = await getTemporaryDirectory();
        final storePart = sanitize(store.name);
        String timePart;
        if (startDate != null && endDate != null) {
          timePart = '${startDate.day.toString().padLeft(2, '0')}.${startDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}.${endDate.month.toString().padLeft(2, '0')}.${endDate.year}';
        } else {
          final parts = month.split('-');
          timePart = 'T${parts[1]}-${parts[0]}';
        }
        final memberPart = memberName != null ? '_${sanitize(memberName)}' : '';
        final fileName = 'BangCong_${storePart}_$timePart$memberPart.xlsx';
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(fileBytes);
        await ShareUtils.shareFiles(
          [file.path],
          context: context,
          text: 'Bảng Công',
          subject: 'Bảng Công ${store.name} $timePart',
        );
      }
    } catch (e) {
      debugPrint('exportMonthlyAttendance error: $e');
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

  static Future<void> exportMonthlySalary({
    required String storeName,
    required String themeColorHex,
    required List<Map<String, dynamic>> computedSalaries,
    required String suffix,
    List<String> memberOrder = const [],
    String? memberName,
    BuildContext? context,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Lương Tháng'];
      excel.setDefaultSheet('Lương Tháng');

      final headerStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#FF${themeColorHex.replaceAll('#', '')}'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final r = int.parse(themeColorHex.substring(0, 2), radix: 16);
      final g = int.parse(themeColorHex.substring(2, 4), radix: 16);
      final b = int.parse(themeColorHex.substring(4, 6), radix: 16);
      final lr = (r + (255 - r) * 0.85).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
      final lg = (g + (255 - g) * 0.85).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
      final lb = (b + (255 - b) * 0.85).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
      final lightColorHex = '#FF${lr.toUpperCase()}${lg.toUpperCase()}${lb.toUpperCase()}';

      final dataStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(lightColorHex),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final headers = [
        'TÊN NHÂN VIÊN', 'VAI TRÒ', 'LOẠI HĐ',
        'TỔNG GIỜ', 'GIỜ CHUẨN', 'LƯƠNG CƠ BẢN', 'SỐ CA CHỞ HÀNG', 'PHỤ CẤP CHỞ', 'SỐ CA GIAO', 'PHỤ CẤP GIAO', 'ĐÃ TẠM ỨNG', 'LƯƠNG THỰC NHẬN'
      ];
      
      for (int c = 0; c < headers.length; c++) {
        var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
        cell.value = TextCellValue(headers[c]);
        cell.cellStyle = headerStyle;
      }

      final sortedSalaries = List<Map<String, dynamic>>.from(computedSalaries);
      if (memberOrder.isNotEmpty) {
        sortedSalaries.sort((a, b) {
          final uidA = a['userId']?.toString() ?? '';
          final uidB = b['userId']?.toString() ?? '';
          final idxA = memberOrder.indexOf(uidA);
          final idxB = memberOrder.indexOf(uidB);
          if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
          if (idxA != -1) return -1;
          if (idxB != -1) return 1;
          return (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
        });
      }

      for (int r = 0; r < sortedSalaries.length; r++) {
        final data = sortedSalaries[r];
        final rowIdx = r + 1;
        
        // Text columns
        var nameCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx));
        nameCell.value = TextCellValue(data['name'].toString());
        var roleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx));
        roleCell.value = TextCellValue(data['role'].toString());
        var typeCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx));
        typeCell.value = TextCellValue(data['type'].toString());

        // Numeric columns
        final numericData = [
          (data['totalHours'] as num).toDouble(),   // col 3: TỔNG GIỜ
          208.0,                                     // col 4: GIỜ CHUẨN
          (data['baseSalary'] as num).toDouble(),     // col 5: LƯƠNG CƠ BẢN
          (data['deliveryCount'] as num).toDouble(),  // col 6: SỐ CA CHỞ
          (data['deliveryPay'] as num).toDouble(),    // col 7: PHỤ CẤP CHỞ
          ((data['giaoHangCount'] ?? 0) as num).toDouble(), // col 8: SỐ CA GIAO
          ((data['giaoHangPay'] ?? 0) as num).toDouble(),   // col 9: PHỤ CẤP GIAO
          (data['advance'] as num).toDouble(),        // col 10: ĐÃ TẠM ỨNG
          (data['netSalary'] as num).toDouble(),      // col 11: LƯƠNG THỰC NHẬN
        ];

        for (int c = 0; c < numericData.length; c++) {
          var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c + 3, rowIndex: rowIdx));
          cell.value = DoubleCellValue(numericData[c]);
          cell.cellStyle = dataStyle;
        }
      }

      sheet.setColumnWidth(0, 22);
      sheet.setColumnWidth(1, 12);
      sheet.setColumnWidth(2, 16);
      sheet.setColumnWidth(3, 10);
      sheet.setColumnWidth(4, 10);
      sheet.setColumnWidth(5, 16);
      sheet.setColumnWidth(6, 16);
      sheet.setColumnWidth(7, 16);
      sheet.setColumnWidth(8, 16);
      sheet.setColumnWidth(9, 16);
      sheet.setColumnWidth(10, 16);
      sheet.setColumnWidth(11, 20);

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final directory = await getTemporaryDirectory();
        final storePart = sanitize(storeName);
        final parts = suffix.split('-');
        final timePart = parts.length == 2 ? 'T${parts[1]}-${parts[0]}' : suffix;
        final memberPart = memberName != null ? '_${sanitize(memberName)}' : '';
        final fileName = 'BaoCaoLuong_${storePart}_$timePart$memberPart.xlsx';
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(fileBytes);
        await ShareUtils.shareFiles(
          [file.path],
          context: context,
          text: 'Báo cáo lương',
          subject: 'Báo cáo lương $storeName $timePart',
        );
      }
    } catch (e) {
      debugPrint('exportMonthlySalary error: $e');
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
}
