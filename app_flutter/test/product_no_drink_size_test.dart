import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/product_model.dart';

void main() {
  group('Đồ uống không chọn size', () {
    test('đồ uống đã cấu hình S/M/L → không còn size', () {
      final p = ProductModel.fromMap({'id': 1, 'name': 'Trà đào', 'price': 30000, 'category': 'Trà', 'sizes': {'S': 0, 'M': 5000, 'L': 10000}});
      expect(p.sizes, isEmpty);
      expect(p.hasIceSugarOptions, isTrue);
    });

    test('đồ uống chưa cấu hình size → không tự thêm S/M/L', () {
      final p = ProductModel.fromMap({'id': 2, 'name': 'Cà phê sữa', 'price': 25000, 'category': 'Cà phê'});
      expect(p.sizes, isEmpty);
    });

    test('món không phải đồ uống (bánh Nhỏ/Lớn) vẫn giữ size', () {
      final p = ProductModel.fromMap({'id': 3, 'name': 'Bánh Lăn Nướng', 'price': 15000, 'category': 'Bánh Lăn Nướng', 'sizes': {'Nhỏ': 0, 'Lớn': 5000}});
      expect(p.sizes, {'Nhỏ': 0, 'Lớn': 5000});
    });
  });
}
