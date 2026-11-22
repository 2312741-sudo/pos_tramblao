import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/core/utils/attendance_utils.dart';
import 'package:tram_flutter/chamcong_blao/models/schedule_model.dart';
import 'package:tram_flutter/chamcong_blao/models/store_model.dart';
import 'package:tram_flutter/chamcong_blao/features/store/screens/shift_settings_screen.dart';

void main() {
  group('Late Check-In Warning Calculation Tests (Cảnh báo đi muộn)', () {
    final defaultStore = StoreModel(
      id: 'store_test',
      name: 'Trạm Chanh Q1',
      code: 'TCQ1',
      ownerId: 'owner_1',
      createdAt: DateTime(2026, 1, 1),
      customShifts: const [
        ShiftDefinition(
          id: 'shift_11',
          name: 'Ca trưa 11h',
          startHour: 11,
          startMinute: 0,
          endHour: 17,
          endMinute: 0,
        ),
        ShiftDefinition(
          id: 'shift_morning',
          name: 'Ca sáng 8h',
          startHour: 8,
          startMinute: 0,
          endHour: 12,
          endMinute: 0,
        ),
        ShiftDefinition(
          id: 'shift_evening',
          name: 'Ca tối 17h',
          startHour: 17,
          startMinute: 0,
          endHour: 21,
          endMinute: 0,
        ),
        ShiftDefinition(
          id: 'shift_overnight',
          name: 'Ca đêm',
          startHour: 22,
          startMinute: 0,
          endHour: 6,
          endMinute: 0,
        ),
      ],
    );

    // Tuesday (2026-08-25 is Tuesday, weekday = 2)
    test('1. Shift start 11:00, check-in 11:15 -> "Đi muộn 15 phút"', () {
      final schedule = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_test',
        weekStart: '2026-08-24',
        shifts: {
          'user_1': const DaySchedule(
            tuesday: ['shift_11'],
          ),
        },
      );

      final checkInTime = DateTime(2026, 8, 25, 11, 15);
      final warning = AttendanceUtils.calculateLateString(
        checkIn: checkInTime,
        userId: 'user_1',
        store: defaultStore,
        schedule: schedule,
      );

      expect(warning, equals('Đi muộn 15 phút'));
    });

    test('2. Shift start 11:00, check-in 10:55 (early) -> null (no warning)', () {
      final schedule = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_test',
        weekStart: '2026-08-24',
        shifts: {
          'user_1': const DaySchedule(
            tuesday: ['shift_11'],
          ),
        },
      );

      final checkInTime = DateTime(2026, 8, 25, 10, 55);
      final warning = AttendanceUtils.calculateLateString(
        checkIn: checkInTime,
        userId: 'user_1',
        store: defaultStore,
        schedule: schedule,
      );

      expect(warning, isNull);
    });

    test('3. Shift start 11:00, check-in 11:00 (on-time) -> null (no warning)', () {
      final schedule = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_test',
        weekStart: '2026-08-24',
        shifts: {
          'user_1': const DaySchedule(
            tuesday: ['shift_11'],
          ),
        },
      );

      final checkInTime = DateTime(2026, 8, 25, 11, 0);
      final warning = AttendanceUtils.calculateLateString(
        checkIn: checkInTime,
        userId: 'user_1',
        store: defaultStore,
        schedule: schedule,
      );

      expect(warning, isNull);
    });

    test('4. Employee has NO scheduled shift on that day -> null (no warning)', () {
      final schedule = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_test',
        weekStart: '2026-08-24',
        shifts: {
          'user_1': const DaySchedule(
            tuesday: [], // No shifts on Tuesday
          ),
        },
      );

      final checkInTime = DateTime(2026, 8, 25, 11, 15);
      final warning = AttendanceUtils.calculateLateString(
        checkIn: checkInTime,
        userId: 'user_1',
        store: defaultStore,
        schedule: schedule,
      );

      expect(warning, isNull);
    });

    test('5. Shift start 08:00, check-in 09:20 (1h20m late) -> "Đi muộn 1h20p"', () {
      final schedule = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_test',
        weekStart: '2026-08-24',
        shifts: {
          'user_1': const DaySchedule(
            tuesday: ['shift_morning'],
          ),
        },
      );

      final checkInTime = DateTime(2026, 8, 25, 9, 20);
      final warning = AttendanceUtils.calculateLateString(
        checkIn: checkInTime,
        userId: 'user_1',
        store: defaultStore,
        schedule: schedule,
      );

      expect(warning, equals('Đi muộn 1h20p'));
    });

    test('6. Shift start 08:00, check-in 10:00 (exact 2 hours late) -> "Đi muộn 2h"', () {
      final schedule = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_test',
        weekStart: '2026-08-24',
        shifts: {
          'user_1': const DaySchedule(
            tuesday: ['shift_morning'],
          ),
        },
      );

      final checkInTime = DateTime(2026, 8, 25, 10, 0);
      final warning = AttendanceUtils.calculateLateString(
        checkIn: checkInTime,
        userId: 'user_1',
        store: defaultStore,
        schedule: schedule,
      );

      expect(warning, equals('Đi muộn 2h'));
    });

    test('7. Multiple shifts in day: matches current shift (17:00 vs 08:00), check-in 17:10 -> "Đi muộn 10 phút"', () {
      final schedule = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_test',
        weekStart: '2026-08-24',
        shifts: {
          'user_1': const DaySchedule(
            tuesday: ['shift_morning', 'shift_evening'],
          ),
        },
      );

      final checkInTime = DateTime(2026, 8, 25, 17, 10);
      final warning = AttendanceUtils.calculateLateString(
        checkIn: checkInTime,
        userId: 'user_1',
        store: defaultStore,
        schedule: schedule,
      );

      expect(warning, equals('Đi muộn 10 phút'));
    });

    test('8. Shift with department suffix (e.g. "shift_11|bar") parses and calculates late correctly', () {
      final schedule = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_test',
        weekStart: '2026-08-24',
        shifts: {
          'user_1': const DaySchedule(
            tuesday: ['shift_11|bar', 'delivery'],
          ),
        },
      );

      final checkInTime = DateTime(2026, 8, 25, 11, 45);
      final warning = AttendanceUtils.calculateLateString(
        checkIn: checkInTime,
        userId: 'user_1',
        store: defaultStore,
        schedule: schedule,
      );

      expect(warning, equals('Đi muộn 45 phút'));
    });

    test('9. Default shifts fallback (morning, afternoon, evening) when customShifts is empty', () {
      final storeWithoutCustomShifts = StoreModel(
        id: 'store_default',
        name: 'Trạm Default',
        code: 'TCDF',
        ownerId: 'owner_2',
        createdAt: DateTime(2026, 1, 1),
        customShifts: const [],
      );

      // Default morning shift starts at 06:00
      final schedule = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_default',
        weekStart: '2026-08-24',
        shifts: {
          'user_2': const DaySchedule(
            tuesday: ['morning'],
          ),
        },
      );

      final checkInTime = DateTime(2026, 8, 25, 6, 25);
      final warning = AttendanceUtils.calculateLateString(
        checkIn: checkInTime,
        userId: 'user_2',
        store: storeWithoutCustomShifts,
        schedule: schedule,
      );

      expect(warning, equals('Đi muộn 25 phút'));
    });
  });
}
