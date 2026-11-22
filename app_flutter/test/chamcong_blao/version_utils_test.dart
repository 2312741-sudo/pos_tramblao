import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/core/utils/version_utils.dart';

void main() {
  group('VersionUtils SemVer Tests', () {
    test('compare versions with equal values', () {
      expect(VersionUtils.compare('1.0.0', '1.0.0'), equals(0));
      expect(VersionUtils.compare('1.0.5', '1.0.5'), equals(0));
      expect(VersionUtils.compare('v1.0.5', '1.0.5'), equals(0));
      expect(VersionUtils.compare('1.0.5+7', '1.0.5'), equals(0));
      expect(VersionUtils.compare('1.0.5+7', '1.0.5+8'), equals(0));
    });

    test('compare versions with different patch versions', () {
      expect(VersionUtils.compare('1.0.4', '1.0.5'), isNegative);
      expect(VersionUtils.compare('1.0.5', '1.0.4'), isPositive);
    });

    test('compare versions with different minor and major versions', () {
      expect(VersionUtils.compare('1.0.9', '1.1.0'), isNegative);
      expect(VersionUtils.compare('1.9.9', '2.0.0'), isNegative);
      expect(VersionUtils.compare('2.0.0', '1.9.9'), isPositive);
    });

    test('isBelow tests', () {
      expect(VersionUtils.isBelow('1.0.4', '1.0.5'), isTrue);
      expect(VersionUtils.isBelow('1.0.5', '1.0.5'), isFalse);
      expect(VersionUtils.isBelow('1.0.6', '1.0.5'), isFalse);
      expect(VersionUtils.isBelow('1.0.5+7', '1.0.6'), isTrue);
    });

    test('isAtLeast tests', () {
      expect(VersionUtils.isAtLeast('1.0.5', '1.0.4'), isTrue);
      expect(VersionUtils.isAtLeast('1.0.5', '1.0.5'), isTrue);
      expect(VersionUtils.isAtLeast('1.0.4', '1.0.5'), isFalse);
    });

    test('handles 2-part and multi-part versions', () {
      expect(VersionUtils.compare('1.0', '1.0.0'), equals(0));
      expect(VersionUtils.compare('1.0', '1.0.1'), isNegative);
      expect(VersionUtils.compare('1.0.0.1', '1.0.0'), isPositive);
    });
  });
}
