import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tram_flutter/chamcong_blao/models/store_model.dart';

void main() {
  group('Multi-Location GPS Configuration & Custom Naming Tests', () {
    test('Auto-migrates legacy latitude & longitude into locations list with default name "Vị trí chính"', () {
      final json = {
        'name': 'Trạm Chanh Tràng Tiền',
        'code': 'TC0001',
        'ownerId': 'owner_1',
        'latitude': 21.028511,
        'longitude': 105.854444,
        'radiusMeters': 120,
        'locations': <dynamic>[],
        'createdAt': DateTime.now().toIso8601String(),
      };

      final store = StoreModel.fromJson(json, 'store_1');

      expect(store.locations.length, 1);
      expect(store.locations.first.name, 'Vị trí chính');
      expect(store.locations.first.latitude, 21.028511);
      expect(store.locations.first.longitude, 105.854444);
      expect(store.locations.first.radiusMeters, 120);
      expect(store.hasLocation, isTrue);
    });

    test('Preserves custom names and coordinates when locations list is provided', () {
      final json = {
        'name': 'Trạm Chanh Chuỗi 3 Điểm',
        'code': 'TC0002',
        'ownerId': 'owner_2',
        'locations': [
          {
            'id': 'loc_1',
            'name': 'Cơ sở chính (Tràng Tiền)',
            'latitude': 21.028511,
            'longitude': 105.854444,
            'radiusMeters': 100,
          },
          {
            'id': 'loc_2',
            'name': 'Kho sản xuất & Đóng gói',
            'latitude': 21.035000,
            'longitude': 105.860000,
            'radiusMeters': 150,
          },
        ],
        'createdAt': DateTime.now().toIso8601String(),
      };

      final store = StoreModel.fromJson(json, 'store_2');

      expect(store.locations.length, 2);
      expect(store.locations[0].name, 'Cơ sở chính (Tràng Tiền)');
      expect(store.locations[0].latitude, 21.028511);
      expect(store.locations[0].radiusMeters, 100);

      expect(store.locations[1].name, 'Kho sản xuất & Đóng gói');
      expect(store.locations[1].latitude, 21.035000);
      expect(store.locations[1].radiusMeters, 150);

      expect(store.hasLocation, isTrue);
      // Primary location synchronized
      expect(store.latitude, 21.028511);
      expect(store.longitude, 105.854444);
      expect(store.radiusMeters, 100);
    });

    test('StoreLocation serialization, deserialization, and renaming via copyWith', () {
      const loc = StoreLocation(
        id: 'loc_custom',
        name: 'Chi nhánh Cầu Giấy',
        latitude: 21.036237,
        longitude: 105.790583,
        radiusMeters: 80,
      );

      final json = loc.toJson();
      expect(json['id'], 'loc_custom');
      expect(json['name'], 'Chi nhánh Cầu Giấy');
      expect(json['latitude'], 21.036237);
      expect(json['longitude'], 105.790583);
      expect(json['radiusMeters'], 80);

      final deserialized = StoreLocation.fromJson(json);
      expect(deserialized.id, 'loc_custom');
      expect(deserialized.name, 'Chi nhánh Cầu Giấy');

      // Rename location
      final renamed = deserialized.copyWith(name: 'Chi nhánh Cầu Giấy (Tầng 1)');
      expect(renamed.name, 'Chi nhánh Cầu Giấy (Tầng 1)');
      expect(renamed.latitude, 21.036237);
      expect(renamed.radiusMeters, 80);
    });

    test('Can configure up to 5 distinct named GPS locations for a store', () {
      final locations = [
        const StoreLocation(id: '1', name: 'Cơ sở 1 - Hoàn Kiếm', latitude: 21.0285, longitude: 105.8544, radiusMeters: 100),
        const StoreLocation(id: '2', name: 'Cơ sở 2 - Cầu Giấy', latitude: 21.0362, longitude: 105.7905, radiusMeters: 100),
        const StoreLocation(id: '3', name: 'Kho Trung Tâm', latitude: 20.9980, longitude: 105.8200, radiusMeters: 200),
        const StoreLocation(id: '4', name: 'Điểm Bán Lưu Động A', latitude: 21.0100, longitude: 105.8300, radiusMeters: 50),
        const StoreLocation(id: '5', name: 'Bãi Xe & Kho Phụ', latitude: 21.0200, longitude: 105.8400, radiusMeters: 80),
      ];

      final store = StoreModel(
        id: 'store_5_locs',
        name: 'Trạm Chanh 5 Cơ Sở',
        code: 'TC5LOC',
        ownerId: 'owner_5',
        createdAt: DateTime.now(),
        locations: locations,
      );

      expect(store.locations.length, 5);
      expect(store.locations.map((l) => l.name).toList(), [
        'Cơ sở 1 - Hoàn Kiếm',
        'Cơ sở 2 - Cầu Giấy',
        'Kho Trung Tâm',
        'Điểm Bán Lưu Động A',
        'Bãi Xe & Kho Phụ',
      ]);

      // toJson maintains legacy fields from first location while serializing all 5
      final storeJson = store.toJson();
      expect(storeJson['latitude'], 21.0285);
      expect(storeJson['longitude'], 105.8544);
      expect((storeJson['locations'] as List).length, 5);
    });

    test('Multi-location distance check matches any location within range', () {
      final loc1 = const StoreLocation(
        id: '1',
        name: 'Quán Chính',
        latitude: 21.028511,
        longitude: 105.854444,
        radiusMeters: 100,
      );
      final loc2 = const StoreLocation(
        id: '2',
        name: 'Kho Ngoại Thành',
        latitude: 21.100000,
        longitude: 105.900000,
        radiusMeters: 150,
      );

      final locations = [loc1, loc2];

      // Simulated user standing 20m from Quán Chính
      // 0.00018 deg is ~20 meters
      final userNearLoc1Lat = 21.028511 + 0.00018;
      final userNearLoc1Lng = 105.854444;

      final distToLoc1 = Geolocator.distanceBetween(
        loc1.latitude,
        loc1.longitude,
        userNearLoc1Lat,
        userNearLoc1Lng,
      );
      expect(distToLoc1 <= loc1.radiusMeters, isTrue);

      // Verify that multi-location any() matches
      final matchesAny = locations.any((l) {
        final d = Geolocator.distanceBetween(l.latitude, l.longitude, userNearLoc1Lat, userNearLoc1Lng);
        return d <= l.radiusMeters;
      });
      expect(matchesAny, isTrue);

      // Simulated user standing at home (outside all locations)
      const userAtHomeLat = 21.050000;
      const userAtHomeLng = 105.800000;

      final matchesHome = locations.any((l) {
        final d = Geolocator.distanceBetween(l.latitude, l.longitude, userAtHomeLat, userAtHomeLng);
        return d <= l.radiusMeters;
      });
      expect(matchesHome, isFalse);

      // Find nearest location for the user at home
      StoreLocation? nearest;
      double? minDist;
      for (final l in locations) {
        final d = Geolocator.distanceBetween(l.latitude, l.longitude, userAtHomeLat, userAtHomeLng);
        if (minDist == null || d < minDist) {
          minDist = d;
          nearest = l;
        }
      }
      expect(nearest, isNotNull);
      expect(nearest!.name, 'Quán Chính');
    });

    test('hasLocation is false when no locations and no legacy coordinates', () {
      final store = StoreModel(
        id: 'store_empty',
        name: 'Cửa hàng chưa có vị trí',
        code: 'EMPTY1',
        ownerId: 'owner_e',
        createdAt: DateTime.now(),
        locations: const [],
      );

      expect(store.hasLocation, isFalse);
    });
  });
}
