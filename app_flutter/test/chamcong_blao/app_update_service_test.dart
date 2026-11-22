import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tram_flutter/chamcong_blao/core/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      },
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  group('AppVersionControlModel Tests', () {
    test('Correctly parses explicit apkUrl from map', () {
      final model = AppVersionControlModel.fromMap({
        'latestVersion': '1.0.5',
        'minimumRequiredVersion': '1.0.3',
        'updateMessage': 'Bản vá lỗi mới',
        'apkUrl': 'https://storage.googleapis.com/apk/chamcong-v1.0.5.apk',
        'updateUrlAndroid':
            'https://play.google.com/store/apps/details?id=com.tramblao.chamcong',
      });

      expect(model.latestVersion, '1.0.5');
      expect(model.minimumRequiredVersion, '1.0.3');
      expect(model.updateMessage, 'Bản vá lỗi mới');
      expect(model.apkUrl,
          'https://storage.googleapis.com/apk/chamcong-v1.0.5.apk');
      expect(model.updateUrlAndroid,
          'https://play.google.com/store/apps/details?id=com.tramblao.chamcong');
    });

    test('Falls back to updateUrlAndroid if it ends with .apk and apkUrl is null',
        () {
      final model = AppVersionControlModel.fromMap({
        'latestVersion': '1.0.5',
        'minimumRequiredVersion': '1.0.3',
        'updateMessage': 'Bản cập nhật',
        'updateUrlAndroid': 'https://example.com/downloads/chamcong.apk',
      });

      expect(model.apkUrl, 'https://example.com/downloads/chamcong.apk');
    });

    test('apkUrl is null if updateUrlAndroid does not end with .apk and apkUrl is absent',
        () {
      final model = AppVersionControlModel.fromMap({
        'latestVersion': '1.0.5',
        'minimumRequiredVersion': '1.0.3',
        'updateMessage': 'Bản cập nhật',
        'updateUrlAndroid':
            'https://play.google.com/store/apps/details?id=com.tramblao.chamcong',
      });

      expect(model.apkUrl, isNull);
      expect(model.updateUrlAndroid,
          'https://play.google.com/store/apps/details?id=com.tramblao.chamcong');
    });
  });

  group('AppUpdateService Download Tests', () {
    test('downloadApkFile streams bytes and reports progress', () async {
      final service = AppUpdateService();
      final dummyApkBytes = List<int>.generate(1024 * 10, (i) => i % 256);

      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          dummyApkBytes,
          200,
          headers: {'content-length': dummyApkBytes.length.toString()},
        );
      });

      service.setHttpClientForTest(mockClient);

      double lastProgress = 0.0;
      int lastReceived = 0;
      int totalReported = 0;
      final statuses = <String>[];

      final file = await service.downloadApkFile(
        'https://example.com/test.apk',
        onProgress: (progress, received, total) {
          lastProgress = progress;
          lastReceived = received;
          totalReported = total;
        },
        onStatusChange: (status) {
          statuses.add(status);
        },
      );

      expect(await file.exists(), isTrue);
      expect(await file.length(), dummyApkBytes.length);
      expect(lastProgress, 1.0);
      expect(lastReceived, dummyApkBytes.length);
      expect(totalReported, dummyApkBytes.length);
      expect(statuses, contains('Đang tải xuống...'));
      expect(statuses, contains('Tải xong, chuẩn bị cài đặt...'));

      // Clean up temp file
      if (await file.exists()) {
        await file.delete();
      }
    });

    test('downloadApkFile throws when HTTP status is not 200', () async {
      final service = AppUpdateService();
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      service.setHttpClientForTest(mockClient);

      expect(
        () => service.downloadApkFile(
          'https://example.com/missing.apk',
          onProgress: (_, __, ___) {},
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
