import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/core/services/app_update_service.dart';

void main() {
  group('AppUpdateDialog UI Tests', () {
    testWidgets('Optional update displays "Để sau" and "Cập nhật ngay"',
        (tester) async {
      const config = AppVersionControlModel(
        latestVersion: '1.0.5',
        minimumRequiredVersion: '1.0.0',
        updateMessage: 'Cải tiến hiệu năng chấm công',
        apkUrl: 'https://example.com/app.apk',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppUpdateDialog(
              config: config,
              isForce: false,
              currentVersion: '1.0.2',
            ),
          ),
        ),
      );

      expect(find.text('Đã có phiên bản mới'), findsOneWidget);
      expect(find.text('Phiên bản mới: v1.0.5 (Hiện tại: v1.0.2)'),
          findsOneWidget);
      expect(find.text('Cải tiến hiệu năng chấm công'), findsOneWidget);
      expect(find.text('Để sau'), findsOneWidget);
      expect(find.text('Cập nhật ngay'), findsOneWidget);
      expect(find.text('Bắt buộc cập nhật'), findsNothing);
    });

    testWidgets('Force update hides "Để sau" and displays warning banner',
        (tester) async {
      const config = AppVersionControlModel(
        latestVersion: '1.0.5',
        minimumRequiredVersion: '1.0.5',
        updateMessage: 'Bản cập nhật bắt buộc sửa lỗi hệ thống',
        apkUrl: 'https://example.com/app.apk',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppUpdateDialog(
              config: config,
              isForce: true,
              currentVersion: '1.0.2',
            ),
          ),
        ),
      );

      expect(find.text('Bắt buộc cập nhật ứng dụng'), findsOneWidget);
      expect(find.text('Bản cập nhật bắt buộc sửa lỗi hệ thống'), findsOneWidget);
      expect(find.text('Để sau'), findsNothing);
      expect(find.text('Cập nhật ngay'), findsOneWidget);
      expect(find.text('Bắt buộc cập nhật'), findsOneWidget);
      expect(
        find.text(
            'Phiên bản hiện tại không còn được hỗ trợ. Bạn cần cập nhật để tiếp tục sử dụng.'),
        findsOneWidget,
      );
    });
  });
}
