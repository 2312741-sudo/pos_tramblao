import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/services/app_update_service.dart';
import 'package:tram_flutter/core/utils/version_utils.dart';

void main() {
  group('VersionUtils Tests', () {
    test('compare versions accurately', () {
      expect(VersionUtils.compare('1.0.0', '1.0.0'), 0);
      expect(VersionUtils.compare('1.0.0', '1.0.1'), lessThan(0));
      expect(VersionUtils.compare('1.0.2', '1.0.1'), greaterThan(0));
      expect(VersionUtils.compare('1.1.0', '1.0.9'), greaterThan(0));
      expect(VersionUtils.compare('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('handles build numbers and prefixes correctly', () {
      expect(VersionUtils.compare('1.0.0+1', '1.0.0+2'), 0);
      expect(VersionUtils.compare('v1.0.0', '1.0.0'), 0);
      expect(VersionUtils.compare('v1.0.0-beta', '1.0.0'), 0);
      expect(VersionUtils.compare('1.0.0+5', '1.0.1'), lessThan(0));
    });

    test('isBelow and isAtLeast', () {
      expect(VersionUtils.isBelow('1.0.0', '1.0.1'), isTrue);
      expect(VersionUtils.isBelow('1.0.1', '1.0.0'), isFalse);
      expect(VersionUtils.isBelow('1.0.0', '1.0.0'), isFalse);

      expect(VersionUtils.isAtLeast('1.0.1', '1.0.0'), isTrue);
      expect(VersionUtils.isAtLeast('1.0.0', '1.0.0'), isTrue);
      expect(VersionUtils.isAtLeast('0.9.9', '1.0.0'), isFalse);
    });
  });

  group('AppVersionControlModel Tests', () {
    test('parses from map correctly', () {
      final map = {
        'latestVersion': '1.0.5',
        'minimumRequiredVersion': '1.0.2',
        'updateMessage': 'Bản nâng cấp ổn định hệ thống',
        'updateUrlIos': 'https://apps.apple.com/app/id123456',
        'updateUrlAndroid': 'https://play.google.com/store/apps/details?id=com.tramblao.pos',
        'updateUrl': 'https://pos-tramblao.vercel.app',
      };

      final model = AppVersionControlModel.fromMap(map);
      expect(model.latestVersion, '1.0.5');
      expect(model.minimumRequiredVersion, '1.0.2');
      expect(model.updateMessage, 'Bản nâng cấp ổn định hệ thống');
      expect(model.updateUrlIos, 'https://apps.apple.com/app/id123456');
    });

    test('uses sensible defaults when map is empty', () {
      final model = AppVersionControlModel.fromMap({});
      expect(model.latestVersion, '1.0.0');
      expect(model.minimumRequiredVersion, '1.0.0');
      expect(model.updateMessage, isNotEmpty);
      expect(model.updateUrl, 'https://pos-tramblao.vercel.app');
    });
  });
}
