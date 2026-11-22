import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/core/utils/production_checklist_utils.dart';
import 'package:tram_flutter/chamcong_blao/models/store_model.dart';
import 'package:tram_flutter/chamcong_blao/models/schedule_model.dart';
import 'package:tram_flutter/chamcong_blao/models/attendance_model.dart';
import 'package:tram_flutter/chamcong_blao/features/store/screens/shift_settings_screen.dart';

void main() {
  group('Production Checklist Workday Logic Tests (Vấn đề 2)', () {
    final testStore = StoreModel(
      id: 'store_1',
      name: 'Trạm Chanh Store',
      code: 'TCS1',
      ownerId: 'owner_1',
      createdAt: DateTime(2026, 1, 1),
      departments: const [
        DepartmentDefinition(id: 'sx', name: 'Sản xuất', shortName: 'SX'),
        DepartmentDefinition(id: 'bar', name: 'Pha chế', shortName: 'BAR'),
        DepartmentDefinition(id: 'pv', name: 'Phục vụ', shortName: 'PV'),
      ],
      customShifts: const [
        ShiftDefinition(
          id: 'shift_morning',
          name: 'Ca Sáng',
          startHour: 8,
          startMinute: 0,
          endHour: 12,
          endMinute: 0,
        ),
        ShiftDefinition(
          id: 'shift_afternoon',
          name: 'Ca Chiều',
          startHour: 12,
          startMinute: 0,
          endHour: 18,
          endMinute: 0,
        ),
        ShiftDefinition(
          id: 'shift_evening',
          name: 'Ca Tối',
          startHour: 18,
          startMinute: 0,
          endHour: 23,
          endMinute: 0,
        ),
        ShiftDefinition(
          id: 'shift_overnight',
          name: 'Ca Đêm',
          startHour: 22,
          startMinute: 0,
          endHour: 2,
          endMinute: 0,
        ),
      ],
    );

    // Schedule for user on Wednesday (weekday 3, e.g. 2026-08-26)
    const scheduleWednesdaySX = ScheduleModel(
      id: '2026-08-24',
      storeId: 'store_1',
      weekStart: '2026-08-24',
      shifts: {
        'emp_1': DaySchedule(
          wednesday: ['shift_afternoon|sx'], // Wednesday: Ca Chiều SX (12h-18h)
        ),
      },
    );

    const scheduleWednesday2SXShifts = ScheduleModel(
      id: '2026-08-24',
      storeId: 'store_1',
      weekStart: '2026-08-24',
      shifts: {
        'emp_1': DaySchedule(
          wednesday: ['shift_morning|sx', 'shift_afternoon|sx'], // 2 SX shifts on Wednesday
        ),
      },
    );

    const scheduleWednesdayNonSX = ScheduleModel(
      id: '2026-08-24',
      storeId: 'store_1',
      weekStart: '2026-08-24',
      shifts: {
        'emp_2': DaySchedule(
          wednesday: ['shift_afternoon|bar'], // Wednesday: Ca Chiều Bar
        ),
      },
    );

    const scheduleOvernightSX = ScheduleModel(
      id: '2026-08-24',
      storeId: 'store_1',
      weekStart: '2026-08-24',
      shifts: {
        'emp_1': DaySchedule(
          wednesday: ['shift_overnight|sx'], // Wednesday night 22:00 to Thursday 02:00
        ),
      },
    );

    test('1. Nhân viên có 1 ca SX/ngày (12h-18h), out ca đúng 18h -> phải checklist', () {
      // CheckIn: 2026-08-26 12:00 VN (05:00 UTC)
      final checkIn = DateTime.utc(2026, 8, 26, 5, 0);
      // Checkout now: 2026-08-26 18:00 VN (11:00 UTC)
      final now = DateTime.utc(2026, 8, 26, 11, 0);

      final result = ProductionChecklistUtils.evaluateChecklistRequirement(
        checkInTime: checkIn,
        now: now,
        userId: 'emp_1',
        store: testStore,
        schedule: scheduleWednesdaySX,
        hasAlreadyReportedForWorkday: false,
      );

      expect(result.workdayDate, equals('2026-08-26'));
      expect(result.hasProductionShiftOnWorkday, isTrue);
      expect(result.isWithinValidWindow, isTrue);
      expect(result.hasAlreadyReported, isFalse);
      expect(result.isRequired, isTrue);
    });

    test('2. Nhân viên có 1 ca SX/ngày (12h-18h), out ca TRỄ lúc 22h cùng ngày -> VẪN PHẢI CHECKLIST (fix bug cũ)', () {
      // CheckIn: 2026-08-26 12:00 VN (05:00 UTC)
      final checkIn = DateTime.utc(2026, 8, 26, 5, 0);
      // Checkout now: 2026-08-26 22:00 VN (15:00 UTC)
      final now = DateTime.utc(2026, 8, 26, 15, 0);

      final result = ProductionChecklistUtils.evaluateChecklistRequirement(
        checkInTime: checkIn,
        now: now,
        userId: 'emp_1',
        store: testStore,
        schedule: scheduleWednesdaySX,
        hasAlreadyReportedForWorkday: false,
      );

      expect(result.workdayDate, equals('2026-08-26'));
      expect(result.hasProductionShiftOnWorkday, isTrue);
      expect(result.isWithinValidWindow, isTrue);
      expect(result.hasAlreadyReported, isFalse);
      expect(result.isRequired, isTrue);
    });

    test('3. Nhân viên có 2 ca SX trong CÙNG NGÀY (sáng + chiều): out ca lần 1 phải checklist, lần 2 KHÔNG hỏi lại', () {
      // CheckIn ca 1: 2026-08-26 08:00 VN (01:00 UTC)
      final checkIn1 = DateTime.utc(2026, 8, 26, 1, 0);
      // Checkout ca 1: 2026-08-26 12:00 VN (05:00 UTC)
      final now1 = DateTime.utc(2026, 8, 26, 5, 0);

      final result1 = ProductionChecklistUtils.evaluateChecklistRequirement(
        checkInTime: checkIn1,
        now: now1,
        userId: 'emp_1',
        store: testStore,
        schedule: scheduleWednesday2SXShifts,
        hasAlreadyReportedForWorkday: false,
      );

      expect(result1.isRequired, isTrue, reason: 'Lần out ca đầu tiên trong ngày bắt buộc phải làm checklist');

      // CheckIn ca 2: 2026-08-26 13:00 VN (06:00 UTC)
      final checkIn2 = DateTime.utc(2026, 8, 26, 6, 0);
      // Checkout ca 2: 2026-08-26 17:00 VN (10:00 UTC), đã hoàn thành checklist ở ca 1
      final now2 = DateTime.utc(2026, 8, 26, 10, 0);

      final result2 = ProductionChecklistUtils.evaluateChecklistRequirement(
        checkInTime: checkIn2,
        now: now2,
        userId: 'emp_1',
        store: testStore,
        schedule: scheduleWednesday2SXShifts,
        hasAlreadyReportedForWorkday: true, // Đã hoàn thành 1 lần trong ngày
      );

      expect(result2.isRequired, isFalse, reason: 'Đã nộp 1 lần trong ngày thì các lần out sau KHÔNG hỏi lại');
      expect(result2.hasAlreadyReported, isTrue);
    });

    test('4. Nhân viên có ca SX 12h-18h, tới 3h30 sáng hôm sau mới out -> KHÔNG còn yêu cầu checklist, cho out bình thường', () {
      // CheckIn: 2026-08-26 12:00 VN (05:00 UTC)
      final checkIn = DateTime.utc(2026, 8, 26, 5, 0);
      // Checkout now: 2026-08-27 03:30 VN (2026-08-26 20:30 UTC) -> Quá hạn 3h00 sáng ngày 27/08
      final now = DateTime.utc(2026, 8, 26, 20, 30);

      final result = ProductionChecklistUtils.evaluateChecklistRequirement(
        checkInTime: checkIn,
        now: now,
        userId: 'emp_1',
        store: testStore,
        schedule: scheduleWednesdaySX,
        hasAlreadyReportedForWorkday: false,
      );

      expect(result.workdayDate, equals('2026-08-26'));
      expect(result.isWithinValidWindow, isFalse, reason: 'Đã qua mốc 3h sáng hôm sau');
      expect(result.isRequired, isFalse, reason: 'Quá hạn 3h sáng tự động bỏ qua checklist');
    });

    test('5. Ngày không có ca SX nào (ca Bar/Phục vụ) -> out ca bình thường, không yêu cầu checklist', () {
      // CheckIn: 2026-08-26 12:00 VN
      final checkIn = DateTime.utc(2026, 8, 26, 5, 0);
      final now = DateTime.utc(2026, 8, 26, 11, 0);

      final result = ProductionChecklistUtils.evaluateChecklistRequirement(
        checkInTime: checkIn,
        now: now,
        userId: 'emp_2',
        store: testStore,
        schedule: scheduleWednesdayNonSX,
        hasAlreadyReportedForWorkday: false,
      );

      expect(result.hasProductionShiftOnWorkday, isFalse);
      expect(result.isRequired, isFalse);
    });

    test('6. Ca SX xuyên đêm (22h ngày 26/08 đến 2h sáng ngày 27/08): Tính đúng ngày làm việc là 26/08 và trong hạn 3h sáng', () {
      // CheckIn: 2026-08-26 22:00 VN (15:00 UTC ngày 26/08)
      final checkIn = DateTime.utc(2026, 8, 26, 15, 0);
      // Checkout now: 2026-08-27 02:00 VN (19:00 UTC ngày 26/08)
      final now = DateTime.utc(2026, 8, 26, 19, 0);

      final result = ProductionChecklistUtils.evaluateChecklistRequirement(
        checkInTime: checkIn,
        now: now,
        userId: 'emp_1',
        store: testStore,
        schedule: scheduleOvernightSX,
        hasAlreadyReportedForWorkday: false,
      );

      expect(result.workdayDate, equals('2026-08-26'));
      expect(result.isWithinValidWindow, isTrue, reason: '02:00 AM ngày 27/08 vẫn trước 03:00 AM ngày 27/08');
      expect(result.isRequired, isTrue);
    });

    test('7. Ngày 25 KHÔNG có ca SX, ngày 26 CÓ ca SX: In 18h ngày 25, Out 00h20 ngày 26 -> KHÔNG BỊ BẮT CHECKLIST', () {
      // Schedule: Tuesday 25/08 = Ca Tối Bar (không có SX), Wednesday 26/08 = Ca Sáng SX
      const scheduleTuesdayNonSXWedSX = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_1',
        weekStart: '2026-08-24',
        shifts: {
          'emp_1': DaySchedule(
            tuesday: ['shift_evening|bar'], // 25/08: Ca tối không phải SX
            wednesday: ['shift_morning|sx'], // 26/08: Ca sáng SX
          ),
        },
      );

      // CheckIn: 2026-08-25 18:00 VN (11:00 UTC)
      final checkIn = DateTime.utc(2026, 8, 25, 11, 0);
      // Checkout: 2026-08-26 00:20 VN (17:20 UTC ngày 25/08)
      final now = DateTime.utc(2026, 8, 25, 17, 20);

      final result = ProductionChecklistUtils.evaluateChecklistRequirement(
        checkInTime: checkIn,
        now: now,
        userId: 'emp_1',
        store: testStore,
        memberDepartmentId: 'sx', // Dù nhân viên có bộ phận gốc là SX
        schedule: scheduleTuesdayNonSXWedSX,
        hasAlreadyReportedForWorkday: false,
      );

      expect(result.workdayDate, equals('2026-08-25'), reason: 'Ngày làm việc cố định theo ngày In ca (25/08)');
      expect(result.hasProductionShiftOnWorkday, isFalse, reason: 'Ngày 25/08 không có ca SX nên không được xem là ca SX');
      expect(result.isRequired, isFalse, reason: 'Tuyệt đối không bắt checklist khi ngày 25/08 không có ca SX');
    });

    test('8. Ngày 25 CÓ ca SX: In 18h ngày 25, Out 00h20 ngày 26 (sau 24h) -> VẪN BẮT BUỘC CHECKLIST vì trước 3h sáng', () {
      // Schedule: Tuesday 25/08 = Ca Tối SX (18h-23h)
      const scheduleTuesdaySX = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_1',
        weekStart: '2026-08-24',
        shifts: {
          'emp_1': DaySchedule(
            tuesday: ['shift_evening|sx'],
          ),
        },
      );

      // CheckIn: 2026-08-25 18:00 VN (11:00 UTC)
      final checkIn = DateTime.utc(2026, 8, 25, 11, 0);
      // Checkout: 2026-08-26 00:20 VN (17:20 UTC ngày 25/08)
      final now = DateTime.utc(2026, 8, 25, 17, 20);

      final result = ProductionChecklistUtils.evaluateChecklistRequirement(
        checkInTime: checkIn,
        now: now,
        userId: 'emp_1',
        store: testStore,
        schedule: scheduleTuesdaySX,
        hasAlreadyReportedForWorkday: false,
      );

      expect(result.workdayDate, equals('2026-08-25'));
      expect(result.hasProductionShiftOnWorkday, isTrue);
      expect(result.isWithinValidWindow, isTrue, reason: '00h20 ngày 26/08 vẫn nằm trong hạn đến 03h00 sáng ngày 26/08');
      expect(result.isRequired, isTrue, reason: 'Bắt buộc phải nộp checklist');
    });

    test('9. Ngày 25 CÓ ca SX: In 18h ngày 25, Out 03h15 ngày 26 (quá 3h sáng) -> TỰ ĐỘNG THÔNG QUA, không chặn ra ca', () {
      const scheduleTuesdaySX = ScheduleModel(
        id: '2026-08-24',
        storeId: 'store_1',
        weekStart: '2026-08-24',
        shifts: {
          'emp_1': DaySchedule(
            tuesday: ['shift_evening|sx'],
          ),
        },
      );

      // CheckIn: 2026-08-25 18:00 VN (11:00 UTC)
      final checkIn = DateTime.utc(2026, 8, 25, 11, 0);
      // Checkout: 2026-08-26 03:15 VN (20:15 UTC ngày 25/08)
      final now = DateTime.utc(2026, 8, 25, 20, 15);

      final result = ProductionChecklistUtils.evaluateChecklistRequirement(
        checkInTime: checkIn,
        now: now,
        userId: 'emp_1',
        store: testStore,
        schedule: scheduleTuesdaySX,
        hasAlreadyReportedForWorkday: false,
      );

      expect(result.workdayDate, equals('2026-08-25'));
      expect(result.hasProductionShiftOnWorkday, isTrue);
      expect(result.isWithinValidWindow, isFalse, reason: 'Đã quá mốc 03h00 sáng ngày 26/08');
      expect(result.isRequired, isFalse, reason: 'Quá 3h sáng tự động thông qua checklist');
    });
  });

  group('Active Attendance Across Midnight Tests (Vấn đề 1)', () {
    test('AttendanceModel retains isActive = true across midnight as long as checkOut is null', () {
      // CheckIn at 22:00 on Day 1
      final checkIn = DateTime.utc(2026, 8, 26, 15, 0);
      final activeAtt = AttendanceModel(
        id: 'att_1',
        userId: 'user_1',
        storeId: 'store_1',
        date: '2026-08-26',
        checkIn: checkIn,
        checkOut: null,
      );

      expect(activeAtt.isActive, isTrue);
      expect(activeAtt.checkOut, isNull);

      // When checked out at 02:00 next day
      final checkOut = DateTime.utc(2026, 8, 26, 19, 0);
      final finishedAtt = activeAtt.copyWith(
        checkOut: checkOut,
        totalHours: 4.0,
      );

      expect(finishedAtt.isActive, isFalse);
      expect(finishedAtt.checkOut, isNotNull);
    });
  });
}
