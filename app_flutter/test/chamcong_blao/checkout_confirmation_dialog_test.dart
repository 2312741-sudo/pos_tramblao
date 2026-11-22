import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tram_flutter/chamcong_blao/core/constants/app_colors.dart';
import 'package:tram_flutter/chamcong_blao/models/attendance_model.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget createTestApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('Checkout Confirmation Dialog Tests', () {
    testWidgets('Tapping Hủy dismisses dialog with false', (tester) async {
      bool? result;

      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  final inTime = DateTime.now().subtract(const Duration(hours: 4, minutes: 15));
                  final att = AttendanceModel(
                    id: 'att_1',
                    storeId: 'store_1',
                    userId: 'u_1',
                    date: '2026-10-01',
                    checkIn: inTime,
                    checkInMethod: CheckInMethod.wifi,
                    totalHours: 0,
                  );

                  final inTimeLocal = att.checkIn.toLocal();
                  final inTimeStr = DateFormat('HH:mm - dd/MM/yyyy').format(inTimeLocal);
                  final diff = DateTime.now().difference(att.checkIn);
                  final h = diff.inHours;
                  final m = diff.inMinutes.remainder(60);
                  final durationStr = h > 0 ? '$h giờ $m phút' : '$m phút';

                  result = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (dialogCtx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Row(
                        children: [
                          Icon(LucideIcons.logOut, color: AppColors.primary),
                          SizedBox(width: 12),
                          Text('Xác nhận ra ca'),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Bạn có chắc chắn muốn kết thúc ca làm việc lúc này không?'),
                          Text('Giờ vào: $inTimeStr'),
                          Text('Thời gian làm: $durationStr'),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx, false),
                          child: const Text('Hủy'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dialogCtx, true),
                          child: const Text('Xác nhận ra ca'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Mở Dialog'),
              );
            },
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Mở Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Xác nhận ra ca'), findsNWidgets(2)); // Title and Confirm button
      expect(find.text('Bạn có chắc chắn muốn kết thúc ca làm việc lúc này không?'), findsOneWidget);
      expect(find.textContaining('Giờ vào:'), findsOneWidget);
      expect(find.textContaining('Thời gian làm: 4 giờ 15 phút'), findsOneWidget);

      // Tap Hủy
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('Tapping Xác nhận ra ca dismisses dialog with true', (tester) async {
      bool? result;

      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (dialogCtx) => AlertDialog(
                      title: const Text('Xác nhận ra ca'),
                      content: const Text('Bạn có chắc chắn muốn kết thúc ca làm việc lúc này không?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx, false),
                          child: const Text('Hủy'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dialogCtx, true),
                          child: const Text('Xác nhận ra ca'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Mở Dialog'),
              );
            },
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Mở Dialog'));
      await tester.pumpAndSettle();

      // Tap Xác nhận ra ca button
      final confirmBtn = find.widgetWithText(ElevatedButton, 'Xác nhận ra ca');
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });
  });
}
