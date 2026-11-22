import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/core/services/shift_reminder_service.dart';
import 'package:tram_flutter/chamcong_blao/models/schedule_model.dart';
import 'package:tram_flutter/chamcong_blao/features/store/screens/shift_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShiftReminderService Tests', () {
    late ShiftReminderService service;

    setUp(() {
      service = ShiftReminderService();
    });

    test('initialize runs idempotently without throwing', () async {
      await service.initialize();
      await service.initialize();
      expect(true, isTrue);
    });

    test('calculateUpcomingReminders handles empty/off schedules', () {
      final emptySchedule = DaySchedule.allOff();
      final items = service.calculateUpcomingReminders(
        storeId: 'store_1',
        storeName: 'Trạm Chanh 1',
        schedule: emptySchedule,
        weekStart: '2026-09-28',
      );
      expect(items, isEmpty);
    });

    test('calculateUpcomingReminders handles invalid weekStart gracefully', () {
      const schedule = DaySchedule(monday: ['morning']);
      final items = service.calculateUpcomingReminders(
        storeId: 'store_1',
        storeName: 'Trạm Chanh 1',
        schedule: schedule,
        weekStart: 'invalid-date-string',
      );
      expect(items, isEmpty);
    });

    test('calculateUpcomingReminders calculates correct reminder time (15 mins prior)', () {
      final weekStart = '2030-01-07'; // Monday
      const schedule = DaySchedule(
        monday: ['morning'], // 06:00
      );

      final items = service.calculateUpcomingReminders(
        storeId: 'store_1',
        storeName: 'Trạm Chanh 1',
        schedule: schedule,
        weekStart: weekStart,
        minutesBefore: 15,
        fromTime: DateTime(2030, 1, 1),
      );

      expect(items.length, 1);
      final item = items.first;
      expect(item.shiftStart, DateTime(2030, 1, 7, 6, 0));
      expect(item.reminderTime, DateTime(2030, 1, 7, 5, 45));
      expect(item.title, 'Nhắc nhở ca làm việc');
      expect(item.body, contains('Trạm Chanh 1'));
      expect(item.body, contains('06:00'));
      expect(item.body, contains('15 phút'));
      expect(item.payload, contains('/check-in'));
    });

    test('calculateUpcomingReminders correctly matches custom shifts', () {
      final weekStart = '2030-01-07'; // Monday
      const customShifts = [
        ShiftDefinition(
          id: 'custom_lunch',
          name: 'Ca trưa tăng cường',
          startHour: 11,
          startMinute: 30,
          endHour: 15,
          endMinute: 30,
        ),
      ];

      final schedule = DaySchedule(
        monday: ['morning', 'custom_lunch|bar'],
        tuesday: ['afternoon'],
        wednesday: ['off'],
        thursday: ['evening'],
        friday: [],
        saturday: ['morning'],
        sunday: ['off'],
      );

      final items = service.calculateUpcomingReminders(
        storeId: 'store_test',
        storeName: 'Trạm Test',
        schedule: schedule,
        weekStart: weekStart,
        customShifts: customShifts,
        minutesBefore: 15,
        fromTime: DateTime(2030, 1, 1),
      );

      expect(items.length, 5);

      final lunchReminder = items.firstWhere((i) => i.body.contains('Ca trưa tăng cường'));
      expect(lunchReminder.shiftStart, DateTime(2030, 1, 7, 11, 30));
      expect(lunchReminder.reminderTime, DateTime(2030, 1, 7, 11, 15));
      expect(lunchReminder.body, contains('11:30'));
    });

    test('calculateUpcomingReminders excludes shifts that have already passed', () {
      final weekStart = '2026-01-05'; // Far in the past
      const schedule = DaySchedule(
        monday: ['morning'],
      );

      final items = service.calculateUpcomingReminders(
        storeId: 'store_1',
        storeName: 'Trạm Chanh 1',
        schedule: schedule,
        weekStart: weekStart,
        fromTime: DateTime(2026, 6, 1), // Later than January 2026
      );

      expect(items, isEmpty);
    });

    test('cancelAllShiftReminders runs safely without throwing', () async {
      await expectLater(service.cancelAllShiftReminders(), completes);
    });
  });
}
