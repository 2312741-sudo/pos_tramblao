import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/features/schedule/repositories/schedule_repository.dart';

void main() {
  group('Schedule Date Utils Tests', () {
    final repo = ScheduleRepository();

    test('getWeekStart calculates correct Monday for Monday 2026-08-17 at 00:02', () {
      final mondayEarly = DateTime(2026, 8, 17, 0, 2, 0);
      expect(mondayEarly.weekday, equals(1));
      expect(repo.getWeekStart(mondayEarly), equals('2026-08-17'));
    });

    test('getWeekStart calculates correct Monday for Sunday 2026-08-16 at 23:59', () {
      final sundayLate = DateTime(2026, 8, 16, 23, 59, 0);
      expect(sundayLate.weekday, equals(7));
      expect(repo.getWeekStart(sundayLate), equals('2026-08-10'));
    });

    test('getWeekStart calculates correct Monday for Wednesday 2026-08-19', () {
      final wed = DateTime(2026, 8, 19, 14, 30, 0);
      expect(wed.weekday, equals(3));
      expect(repo.getWeekStart(wed), equals('2026-08-17'));
    });

    test('getNextWeeks generates correct sequence of week starts', () {
      final weeks = repo.getNextWeeks(3);
      expect(weeks.length, equals(3));
      // Each week must be 7 days apart
      final d0 = DateTime.parse(weeks[0]);
      final d1 = DateTime.parse(weeks[1]);
      final d2 = DateTime.parse(weeks[2]);
      expect(d1.difference(d0).inDays, equals(7));
      expect(d2.difference(d1).inDays, equals(7));
    });

    test('getWeeksRange generates correct past, current and future weeks', () {
      final range = repo.getWeeksRange(pastWeeks: 4, futureWeeks: 4);
      expect(range.length, equals(9)); // 4 past + 1 current + 4 future = 9
      final currentMonday = repo.getWeekStart(DateTime.now());
      expect(range[4], equals(currentMonday)); // Index 4 is the current week
      
      // Index 0 is 4 weeks before index 4
      final dPast = DateTime.parse(range[0]);
      final dCurr = DateTime.parse(range[4]);
      expect(dCurr.difference(dPast).inDays, equals(28));
    });
  });
}
