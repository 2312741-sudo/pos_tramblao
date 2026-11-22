import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/core/utils/share_utils.dart';
import 'package:tram_flutter/chamcong_blao/app/router.dart';

void main() {
  group('ShareUtils Tests', () {
    test('getSharePositionOrigin returns non-zero default when context is null', () {
      final origin = ShareUtils.getSharePositionOrigin(null);
      expect(origin, isNotNull);
      expect(origin.width, greaterThan(0));
      expect(origin.height, greaterThan(0));
      expect(origin.size, isNot(Size.zero));
    });

    testWidgets('getSharePositionOrigin returns valid non-zero Rect from RenderBox', (tester) async {
      late BuildContext testContext;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) {
                  testContext = context;
                  return Container(
                    width: 200,
                    height: 50,
                    color: Colors.blue,
                  );
                },
              ),
            ),
          ),
        ),
      );

      final origin = ShareUtils.getSharePositionOrigin(testContext);
      expect(origin.width, greaterThan(0));
      expect(origin.height, greaterThan(0));
      expect(origin.size, isNot(Size.zero));
    });
  });

  group('Router AppRoutes Tests', () {
    test('AppRoutes contains qrDisplay constant matching /qr-display', () {
      expect(AppRoutes.qrDisplay, '/qr-display');
    });
  });
}
