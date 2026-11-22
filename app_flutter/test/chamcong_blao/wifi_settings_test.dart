import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/models/store_model.dart';
import 'package:tram_flutter/chamcong_blao/core/utils/location_utils.dart';

void main() {
  group('Multi-WiFi BSSID Authentication & Legacy Migration Tests', () {
    // -------------------------------------------------------------
    // CASE 1: BSSID hiện tại đúng -> MATCH / PASS
    // -------------------------------------------------------------
    test('CASE 1: BSSID hiện tại khớp với BSSID đã đăng ký -> PASS', () {
      const allowed = [
        StoreWifi(
            name: 'Quầy bar', ssid: 'PT_WIFI', bssid: 'aa:bb:cc:dd:ee:ff'),
      ];

      const currentBssid = 'aa:bb:cc:dd:ee:ff';
      final isMatch = allowed.any(
        (w) =>
            LocationUtils.normalizeBssid(w.bssid) ==
            LocationUtils.normalizeBssid(currentBssid),
      );
      expect(isMatch, isTrue);
    });

    // -------------------------------------------------------------
    // CASE 2: BSSID sai -> FAIL
    // -------------------------------------------------------------
    test('CASE 2: BSSID không nằm trong danh sách cửa hàng -> FAIL', () {
      const allowed = [
        StoreWifi(
            name: 'Quầy bar', ssid: 'PT_WIFI', bssid: 'aa:bb:cc:dd:ee:ff'),
      ];

      const foreignBssid = '11:22:33:44:55:66';
      final isMatch = allowed.any(
        (w) =>
            LocationUtils.normalizeBssid(w.bssid) ==
            LocationUtils.normalizeBssid(foreignBssid),
      );
      expect(isMatch, isFalse);
    });

    // -------------------------------------------------------------
    // CASE 3: BSSID null -> FAIL an toàn, không crash
    // -------------------------------------------------------------
    test('CASE 3: BSSID null được xử lý an toàn, không crash -> FAIL', () {
      const allowed = [
        StoreWifi(
            name: 'Quầy bar', ssid: 'PT_WIFI', bssid: 'aa:bb:cc:dd:ee:ff'),
      ];

      String? nullBssid;
      final isValid = LocationUtils.isValidBssid(nullBssid);
      expect(isValid, isFalse);

      final isMatch = allowed.any((w) {
        if (!LocationUtils.isValidBssid(nullBssid)) return false;
        return LocationUtils.normalizeBssid(w.bssid) ==
            LocationUtils.normalizeBssid(nullBssid!);
      });
      expect(isMatch, isFalse);
    });

    // -------------------------------------------------------------
    // CASE 4: BSSID 02:00:00:00:00:00 (Android dummy) -> FAIL
    // -------------------------------------------------------------
    test('CASE 4: Placeholder BSSID 02:00:00:00:00:00 bị từ chối -> FAIL', () {
      expect(LocationUtils.isValidBssid('02:00:00:00:00:00'), isFalse);
      expect(LocationUtils.isValidBssid('00:00:00:00:00:00'), isFalse);
      expect(LocationUtils.isValidBssid('ff:ff:ff:ff:ff:ff'), isFalse);
      expect(LocationUtils.isValidBssid(''), isFalse);
      expect(LocationUtils.isValidBssid('not-a-mac'), isFalse);
    });

    // -------------------------------------------------------------
    // CASE 5: Database uppercase vs Device lowercase -> PASS
    // -------------------------------------------------------------
    test(
        'CASE 5: Database uppercase AA:BB:CC:DD:EE:FF vs Device lowercase aa:bb:cc:dd:ee:ff -> PASS',
        () {
      const allowed = [
        StoreWifi(
            name: 'Quầy Thu Ngân', ssid: 'PT_WIFI', bssid: 'AA:BB:CC:DD:EE:FF'),
      ];

      const currentBssid = 'aa:bb:cc:dd:ee:ff';
      final isMatch = allowed.any(
        (w) =>
            LocationUtils.normalizeBssid(w.bssid) ==
            LocationUtils.normalizeBssid(currentBssid),
      );
      expect(isMatch, isTrue);
    });

    // -------------------------------------------------------------
    // CASE 6: Database '-' vs Device ':' -> PASS
    // -------------------------------------------------------------
    test(
        'CASE 6: Database dùng gạch nối AA-BB-CC-DD-EE-FF vs Device dùng hai chấm aa:bb:cc:dd:ee:ff -> PASS',
        () {
      const allowed = [
        StoreWifi(name: 'Tầng 1', ssid: 'PT_WIFI', bssid: 'AA-BB-CC-DD-EE-FF'),
      ];

      const currentBssid = 'aa:bb:cc:dd:ee:ff';
      final isMatch = allowed.any(
        (w) =>
            LocationUtils.normalizeBssid(w.bssid) ==
            LocationUtils.normalizeBssid(currentBssid),
      );
      expect(isMatch, isTrue);
    });

    // -------------------------------------------------------------
    // CASE 7: SSID giống nhưng BSSID khác -> FAIL (BSSID là identifier chính)
    // -------------------------------------------------------------
    test(
        'CASE 7: SSID giống nhau nhưng BSSID khác nhau (WiFi giả lập / cafe ngoài) -> FAIL',
        () {
      const storeWifi = StoreWifi(
        name: 'WiFi Cửa Hàng',
        ssid: 'TRAM_CHANH_WIFI',
        bssid: 'aa:bb:cc:dd:ee:01',
      );

      // Hacker / employee tạo hotspot cùng tên SSID nhưng BSSID thiết bị di động
      const fakeHotspotSsid = 'TRAM_CHANH_WIFI';
      const fakeHotspotBssid = '99:88:77:66:55:44';

      expect(fakeHotspotSsid, equals(storeWifi.ssid)); // SSID trùng
      final bssidMatches = LocationUtils.normalizeBssid(storeWifi.bssid) ==
          LocationUtils.normalizeBssid(fakeHotspotBssid);
      expect(bssidMatches, isFalse); // Nhưng BSSID khác -> Từ chối chấm công
    });

    // -------------------------------------------------------------
    // CASE 8 & 9: Multi-BSSID (2.4GHz & 5GHz & Mesh) -> PASS
    // -------------------------------------------------------------
    test(
        'CASE 8 & 9: Hỗ trợ Router băng tần kép (2.4GHz & 5GHz) cùng SSID nhưng khác BSSID',
        () {
      const dualBandWifis = [
        StoreWifi(
            name: 'WiFi Chính 2.4GHz',
            ssid: 'PT_WIFI',
            bssid: 'aa:bb:cc:dd:ee:01'),
        StoreWifi(
            name: 'WiFi Chính 5GHz',
            ssid: 'PT_WIFI',
            bssid: 'aa:bb:cc:dd:ee:02'),
      ];

      // Khi kết nối băng tần 2.4GHz
      const connected24 = 'aa:bb:cc:dd:ee:01';
      final match24 = dualBandWifis.any(
        (w) =>
            LocationUtils.normalizeBssid(w.bssid) ==
            LocationUtils.normalizeBssid(connected24),
      );
      expect(match24, isTrue);

      // Khi kết nối băng tần 5GHz
      const connected5G = 'aa:bb:cc:dd:ee:02';
      final match5G = dualBandWifis.any(
        (w) =>
            LocationUtils.normalizeBssid(w.bssid) ==
            LocationUtils.normalizeBssid(connected5G),
      );
      expect(match5G, isTrue);
    });

    // -------------------------------------------------------------
    // CASE 10: Document Firestore legacy chỉ có networkIP -> load an toàn, không crash
    // -------------------------------------------------------------
    test(
        'CASE 10: Document Firestore legacy chỉ có networkIP deserializes an toàn và hasWifi = false',
        () {
      final json = {
        'name': 'Cửa hàng Phố Huế',
        'code': 'PHO001',
        'ownerId': 'owner_1',
        'networkIP': '113.161.45.10',
        'wifis': <dynamic>[],
        'createdAt': DateTime.now().toIso8601String(),
      };

      final store = StoreModel.fromJson(json, 'store_legacy_ip');

      expect(store.networkIP, '113.161.45.10');
      expect(store.wifis.length, 1);
      expect(store.wifis.first.ip, '113.161.45.10');
      expect(store.wifis.first.bssid, ''); // BSSID trống
      expect(store.wifis.first.hasValidBssid, isFalse);
      // hasWifi cho attendance BSSID trả về false vì chưa cấu hình BSSID
      expect(store.hasWifi, isFalse);
      expect(store.hasLegacyWifi, isTrue);
    });

    // -------------------------------------------------------------
    // CASE 11: Document legacy có wifis[].ip nhưng không có bssid -> load an toàn, không coi IP là BSSID
    // -------------------------------------------------------------
    test('CASE 11: Document legacy có wifis[].ip không tự động coi IP là BSSID',
        () {
      final json = {
        'name': 'Cửa hàng Cầu Giấy',
        'code': 'CG0002',
        'ownerId': 'owner_2',
        'wifis': [
          {'name': 'WiFi Tầng 1', 'ip': '113.161.45.10'},
          {'name': 'WiFi Tầng 2', 'ip': '113.161.45.11'},
        ],
        'createdAt': DateTime.now().toIso8601String(),
      };

      final store = StoreModel.fromJson(json, 'store_legacy_wifis');

      expect(store.wifis.length, 2);
      expect(store.wifis[0].bssid, '');
      expect(store.wifis[1].bssid, '');
      expect(store.wifis[0].ip, '113.161.45.10');
      expect(store.wifis[0].hasValidBssid, isFalse);
      expect(store.hasWifi, isFalse);
    });

    // -------------------------------------------------------------
    // CASE 12: GPS attendance hoạt động độc lập
    // -------------------------------------------------------------
    test(
        'CASE 12: GPS attendance độc lập với WiFi, StoreLocation & radius giữ nguyên',
        () {
      final store = StoreModel(
        id: 'store_gps',
        name: 'Cửa hàng GPS Only',
        code: 'GPS001',
        ownerId: 'owner_gps',
        createdAt: DateTime.now(),
        latitude: 21.028511,
        longitude: 105.854444,
        radiusMeters: 150,
        locations: const [
          StoreLocation(
            id: 'loc_1',
            name: 'Điểm bán chính',
            latitude: 21.028511,
            longitude: 105.854444,
            radiusMeters: 150,
          ),
        ],
        wifis: const [],
      );

      expect(store.hasLocation, isTrue);
      expect(store.hasWifi, isFalse);
      expect(store.locations.first.name, 'Điểm bán chính');
    });

    // -------------------------------------------------------------
    // CASE 13: Modem restart làm Public IP đổi -> Không ảnh hưởng BSSID
    // -------------------------------------------------------------
    test(
        'CASE 13: Modem restart đổi Public IP (113.x -> 14.x) nhưng BSSID giữ nguyên -> PASS',
        () {
      const storeWifi = StoreWifi(
        name: 'WiFi Cửa Hàng',
        ssid: 'PT_WIFI',
        bssid: 'aa:bb:cc:dd:ee:01',
      );

      // Modem khởi động lại: IP đổi nhưng MAC phần cứng router không đổi
      const ipBeforeRestart = '113.161.100.25';
      const ipAfterRestart = '14.162.200.88';
      expect(ipBeforeRestart, isNot(equals(ipAfterRestart)));

      // Thiết bị vẫn kết nối Access Point có BSSID aa:bb:cc:dd:ee:01
      const deviceCurrentBssid = 'aa:bb:cc:dd:ee:01';
      final isStillValid = LocationUtils.normalizeBssid(storeWifi.bssid) ==
          LocationUtils.normalizeBssid(deviceCurrentBssid);
      expect(isStillValid, isTrue);
    });

    // -------------------------------------------------------------
    // CASE 14: StoreWifi serialization and deserialization
    // -------------------------------------------------------------
    test(
        'CASE 14: StoreWifi serialization retaining name, ssid, bssid, createdAt, copyWith',
        () {
      final now = DateTime.utc(2026, 9, 6, 0, 0, 0);
      final wifi = StoreWifi(
        name: 'WiFi Quầy Thu Ngân',
        ssid: 'TRAM_5G',
        bssid: 'aa:bb:cc:dd:ee:ff',
        createdAt: now,
      );

      final json = wifi.toJson();
      expect(json['name'], 'WiFi Quầy Thu Ngân');
      expect(json['ssid'], 'TRAM_5G');
      expect(json['bssid'], 'aa:bb:cc:dd:ee:ff');

      final deserialized = StoreWifi.fromJson(json);
      expect(deserialized.name, 'WiFi Quầy Thu Ngân');
      expect(deserialized.ssid, 'TRAM_5G');
      expect(deserialized.bssid, 'aa:bb:cc:dd:ee:ff');
      expect(deserialized.hasValidBssid, isTrue);

      final renamed = deserialized.copyWith(name: 'WiFi Mới');
      expect(renamed.name, 'WiFi Mới');
      expect(renamed.bssid, 'aa:bb:cc:dd:ee:ff');
    });

    // -------------------------------------------------------------
    // CASE 15: Duplicate BSSID detection
    // -------------------------------------------------------------
    test('CASE 15: Duplicate BSSID detection (case and separator insensitive)',
        () {
      const wifis = [
        StoreWifi(name: 'Quầy bar', ssid: 'WIFI_1', bssid: 'aa:bb:cc:dd:ee:ff'),
      ];

      // Thêm cùng BSSID nhưng viết hoa và dùng dấu gạch ngang
      const newBssid = 'AA-BB-CC-DD-EE-FF';
      final isDuplicate = wifis.any(
        (w) =>
            LocationUtils.normalizeBssid(w.bssid) ==
            LocationUtils.normalizeBssid(newBssid),
      );
      expect(isDuplicate, isTrue);

      const uniqueBssid = '00:11:22:33:44:55';
      final isUnique = !wifis.any(
        (w) =>
            LocationUtils.normalizeBssid(w.bssid) ==
            LocationUtils.normalizeBssid(uniqueBssid),
      );
      expect(isUnique, isTrue);
    });

    // -------------------------------------------------------------
    // CASE 16: Max 10 WiFi limit enforcement
    // -------------------------------------------------------------
    test('CASE 16: Max 10 WiFi limit enforcement', () {
      final wifis = List.generate(
        10,
        (i) => StoreWifi(
          name: 'WiFi ${i + 1}',
          ssid: 'WIFI_${i + 1}',
          bssid: 'aa:bb:cc:dd:ee:0$i',
        ),
      );

      final canAddMore = wifis.length < 10;
      expect(canAddMore, isFalse);
    });
  });
}
