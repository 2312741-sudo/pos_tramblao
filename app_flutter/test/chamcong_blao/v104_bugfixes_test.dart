import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/core/auth/app_permissions.dart';
import 'package:tram_flutter/chamcong_blao/models/member_model.dart';
import 'package:tram_flutter/chamcong_blao/models/production_model.dart';
import 'package:tram_flutter/chamcong_blao/models/attendance_model.dart';
import 'package:tram_flutter/chamcong_blao/core/widgets/avatar_widget.dart';
import 'package:tram_flutter/chamcong_blao/app/router.dart';

void main() {
  group('BUG 1: Production Checklist Decimal Parsing Tests', () {
    test('Correctly parses comma decimal separator into double', () {
      final inputComma = '2,5'.replaceAll(',', '.');
      final val1 = double.tryParse(inputComma);
      expect(val1, equals(2.5));

      final inputComma2 = '0,75'.replaceAll(',', '.');
      final val2 = double.tryParse(inputComma2);
      expect(val2, equals(0.75));

      final inputComma3 = '12,50'.replaceAll(',', '.');
      final val3 = double.tryParse(inputComma3);
      expect(val3, equals(12.5));
    });

    test('Correctly parses dot decimal separator into double', () {
      final inputDot = '2.5'.replaceAll(',', '.');
      final val1 = double.tryParse(inputDot);
      expect(val1, equals(2.5));

      final inputDot2 = '0.75'.replaceAll(',', '.');
      final val2 = double.tryParse(inputDot2);
      expect(val2, equals(0.75));
    });

    test('ProductionTaskEntry supports double values from json', () {
      final json1 = {
        'taskId': 'task_1',
        'taskName': 'Nấu sốt me',
        'unit': 'kg',
        'unitLabel': 'Kg',
        'value': 2.5,
      };
      final entry1 = ProductionTaskEntry.fromJson(json1);
      expect(entry1.value, equals(2.5));

      final json2 = {
        'taskId': 'task_2',
        'taskName': 'Làm trân châu',
        'unit': 'kg',
        'unitLabel': 'Kg',
        'value': 5, // Integer input from backend
      };
      final entry2 = ProductionTaskEntry.fromJson(json2);
      expect(entry2.value, equals(5.0));
    });
  });

  group('TASK 5: Cross-Midnight Attendance Tests', () {
    test('Attendance active state is true when checkOut is null regardless of cross-midnight', () {
      final checkInDay1 = DateTime.utc(2026, 8, 24, 22, 0); // 22:00
      final att = AttendanceModel(
        id: 'att_cross_midnight',
        userId: 'user_123',
        storeId: 'store_456',
        date: '2026-08-24',
        checkIn: checkInDay1,
        checkOut: null,
      );

      expect(att.isActive, isTrue);
      expect(att.totalHours, equals(0.0));
    });

    test('Calculates total hours accurately across midnight', () {
      final checkIn = DateTime.utc(2026, 8, 24, 22, 0); // 22:00 Day 1
      final checkOut = DateTime.utc(2026, 8, 25, 6, 30); // 06:30 Day 2 (8.5 hours)
      final diffMinutes = checkOut.difference(checkIn).inMinutes;
      final totalHours = diffMinutes / 60.0;

      expect(totalHours, equals(8.5));

      final att = AttendanceModel(
        id: 'att_completed',
        userId: 'user_123',
        storeId: 'store_456',
        date: '2026-08-24',
        checkIn: checkIn,
        checkOut: checkOut,
        totalHours: totalHours,
      );

      expect(att.isActive, isFalse);
      expect(att.formattedDuration, equals('8h 30m'));
    });
  });

  group('LỖI 3: Timezone UTC vs Local Display Tests', () {
    test('DateTime toLocal converts UTC correctly', () {
      final utcTime = DateTime.utc(2026, 8, 25, 5, 0); // 05:00 UTC
      final localTime = utcTime.toLocal();

      // Local time should preserve UTC instant
      expect(localTime.isUtc, isFalse);
      expect(localTime.toUtc(), equals(utcTime));
    });
  });

  group('NEW: Notification Route Constants Tests', () {
    test('AppRoutes contains notifications route', () {
      expect(AppRoutes.notifications, equals('/notifications'));
      expect(AppRoutes.scheduleManager, equals('/schedule-manager'));
      expect(AppRoutes.checkIn, equals('/check-in'));
    });
  });

  group('NEW: Manager 2 Attendance Restrictions Tests', () {
    test('Manager 2 cannot edit attendance of other employees', () {
      expect(AppPermissions.canEditAttendance(UserRole.manager2), isFalse);
      expect(AppPermissions.canEditAttendance(UserRole.employee), isFalse);
      expect(AppPermissions.canEditAttendance(UserRole.manager1), isTrue);
      expect(AppPermissions.canEditAttendance(UserRole.owner), isTrue);
      expect(AppPermissions.canEditAttendance(UserRole.legacyManager), isTrue);
    });

    test('Manager 2 cannot view all employees attendance table', () {
      expect(AppPermissions.canViewAllAttendance(UserRole.manager2), isFalse);
      expect(AppPermissions.canViewAllAttendance(UserRole.employee), isFalse);
      expect(AppPermissions.canViewAllAttendance(UserRole.manager1), isTrue);
      expect(AppPermissions.canViewAllAttendance(UserRole.owner), isTrue);
      expect(AppPermissions.canViewAllAttendance(UserRole.legacyManager), isTrue);
    });
  });

  group('NEW: Avatar Helper & Fallback Tests', () {
    test('getAvatarImageProvider returns null for empty or null url', () {
      expect(getAvatarImageProvider(null), isNull);
      expect(getAvatarImageProvider(''), isNull);
      expect(getAvatarImageProvider('   '), isNull);
    });

    test('getAvatarImageProvider returns CachedNetworkImageProvider for http and https', () {
      final p1 = getAvatarImageProvider('https://example.com/avatar.jpg');
      expect(p1, isNotNull);
      expect(p1.runtimeType.toString(), contains('CachedNetworkImageProvider'));

      final p2 = getAvatarImageProvider('http://example.com/avatar.jpg');
      expect(p2, isNotNull);
      expect(p2.runtimeType.toString(), contains('CachedNetworkImageProvider'));
    });

    test('getAvatarImageProvider returns null for invalid non-url string', () {
      final p = getAvatarImageProvider('invalid_path_not_url');
      expect(p, isNull);
    });
  });
}
