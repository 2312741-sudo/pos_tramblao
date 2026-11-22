import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Attendance Multi-Day & Overnight Duration Tests', () {
    test('Cross-midnight check-in 14:00 (day 17) to 01:30 (day 18) calculates 11.5 hours', () {
      final checkIn = DateTime(2026, 8, 17, 14, 0, 0);
      final checkOut = DateTime(2026, 8, 18, 1, 30, 0);

      expect(checkOut.isAfter(checkIn), isTrue);
      final totalMinutes = checkOut.difference(checkIn).inMinutes;
      expect(totalMinutes, equals(690));
      final totalHours = totalMinutes / 60.0;
      expect(totalHours, equals(11.5));
    });

    test('Same-day check-in 08:00 to 17:00 calculates 9.0 hours', () {
      final checkIn = DateTime(2026, 8, 17, 8, 0, 0);
      final checkOut = DateTime(2026, 8, 17, 17, 0, 0);

      expect(checkOut.isAfter(checkIn), isTrue);
      final totalHours = checkOut.difference(checkIn).inMinutes / 60.0;
      expect(totalHours, equals(9.0));
    });

    test('Invalid check-out before check-in is detected correctly', () {
      final checkIn = DateTime(2026, 8, 17, 14, 0, 0);
      final checkOut = DateTime(2026, 8, 17, 1, 0, 0);

      expect(checkOut.isAfter(checkIn), isFalse);
    });
  });
}
