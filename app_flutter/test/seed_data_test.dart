import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/repositories/seed_data.dart';

void main() {
  group('Trạm BLAO SeedData Menu Tests', () {
    test('Categories contain exactly 5 expected groups with correct order (no fake Topping category)', () {
      final categories = SeedData.defaultCategories;
      expect(categories.length, 5);

      final names = categories.map((c) => c.name).toList();
      expect(names, [
        'Trà Ô Long',
        'Bánh Lăn Nướng',
        'Món Đặc Biệt',
        'Combo Trà + Bánh',
        'Đồ Ăn Vặt',
      ]);

      // Category 1: Trà Ô Long allows Thạch dừa
      final traCat = categories.firstWhere((c) => c.name == 'Trà Ô Long');
      expect(traCat.allowedToppingIds, contains('Thạch dừa'));
    });

    test('Products contain exactly 18 items across the 5 categories', () {
      final products = SeedData.defaultProducts;
      expect(products.length, 18);

      // Verify no item has old Tram image assets, tea items have official BLAO images
      for (final p in products) {
        if (p.category == 'Trà Ô Long') {
          expect(p.imageResourceName, startsWith('tra_olong_'));
        } else {
          expect(p.imageResourceName, isNull);
        }
        expect(p.name, isNotEmpty);
        expect(p.code, isNotEmpty);
        expect(p.price, greaterThan(0));
      }

      // Check Trà Ô Long (8 items)
      final traItems = products.where((p) => p.category == 'Trà Ô Long').toList();
      expect(traItems.length, 8);
      expect(traItems.any((p) => p.name == 'Trà Ô Long Chanh Tươi' && p.price == 15000), isTrue);
      expect(traItems.any((p) => p.name == 'Trà Ô Long Chanh Đào' && p.price == 20000), isTrue);
      expect(traItems.any((p) => p.name == 'Trà Ô Long Bưởi Hồng' && p.price == 20000), isTrue);
      expect(traItems.any((p) => p.name == 'Trà Ô Long Xoài Đào' && p.price == 20000), isTrue);
      expect(traItems.any((p) => p.name == 'Trà Ô Long Cam Đào' && p.price == 20000), isTrue);
      expect(traItems.any((p) => (p.name == 'Trà Ô Long Xoài Chanh Dây' || p.name == 'Trà Xoài Chanh Dây') && p.price == 20000), isTrue);
      expect(traItems.any((p) => p.name == 'Trà Ô Long Quýt Đào' && p.price == 20000), isTrue);
      expect(traItems.any((p) => p.name == 'Trà Ô Long Quýt Hoàng Kim' && p.price == 20000), isTrue);

      // Check Bánh Lăn Nướng (3 items with sizes)
      final banhItems = products.where((p) => p.category == 'Bánh Lăn Nướng').toList();
      expect(banhItems.length, 3);
      for (final b in banhItems) {
        expect(b.sizes.containsKey('Nhỏ'), isTrue);
        expect(b.sizes.containsKey('Lớn'), isTrue);
        expect(b.sizes['Lớn'], 5000);
        // Size nhỏ nhất luôn là "Nhỏ"
        expect(b.defaultSmallestSize, 'Nhỏ');
        expect(b.sortedSizes.first.key, 'Nhỏ');
      }

      // Check Món Đặc Biệt (2 items)
      final dacBiet = products.where((p) => p.category == 'Món Đặc Biệt').toList();
      expect(dacBiet.length, 2);
      expect(dacBiet.any((p) => p.name == 'Bánh Flan Vỏ Chanh' && p.price == 29000), isTrue);
      expect(dacBiet.any((p) => p.name == 'Set Marshmallow Nướng' && p.price == 49000), isTrue);

      // Check Combo (3 items)
      final combos = products.where((p) => p.category == 'Combo Trà + Bánh').toList();
      expect(combos.length, 3);
      expect(combos.any((p) => p.name == 'Combo Truyền Thống' && p.price == 29000), isTrue);
      expect(combos.any((p) => p.name == 'Combo Phô Mai' && p.price == 39000), isTrue);
      expect(combos.any((p) => p.name == 'Combo Choco Chip' && p.price == 39000), isTrue);

      // Check Đồ Ăn Vặt (2 items)
      final anVat = products.where((p) => p.category == 'Đồ Ăn Vặt').toList();
      expect(anVat.length, 2);
      expect(anVat.any((p) => p.name == 'Bánh tráng'), isTrue);
      expect(anVat.any((p) => p.name == 'Hạt hướng dương'), isTrue);

      // No fake Topping category or standalone product
      final toppings = products.where((p) => p.category == 'Topping').toList();
      expect(toppings, isEmpty);
    });

    test('Product size sorting and default smallest size selection', () {
      final p1 = SeedData.defaultProducts.firstWhere((p) => p.sizes.isNotEmpty);
      expect(p1.defaultSmallestSize, 'Nhỏ');
      expect(p1.sortedSizes.map((e) => e.key).toList(), ['Nhỏ', 'Lớn']);

      // Reverse map check
      final pReversed = SeedData.defaultProducts.first.copyWith(
        sizes: {'L': 10000, 'M': 5000, 'S': 0},
      );
      expect(pReversed.defaultSmallestSize, 'S');
      expect(pReversed.sortedSizes.map((e) => e.key).toList(), ['S', 'M', 'L']);
    });
  });
}
