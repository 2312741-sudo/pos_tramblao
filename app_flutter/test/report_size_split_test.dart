import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/data/models/bill_model.dart';
import 'package:tram_flutter/data/models/product_model.dart';

/// Báo cáo hàng hoá: bánh (món không phải đồ uống) tách theo size; đồ uống có size cũ vẫn gộp (khớp web reports.ts).
void main() {
  final pm = {
    9: ProductModel(id: 9, name: 'Bánh Lăn Nướng', code: 'BANH01', price: 15000, unit: 'Cái', category: 'Bánh Lăn Nướng', sizes: {'Nhỏ': 0, 'Lớn': 5000}),
    5: ProductModel(id: 5, name: 'Sinh tố bơ', code: 'ST01', price: 40000, unit: 'Ly', category: 'Sinh Tố', hasIceSugarOptions: true),
  };

  test('bánh mỗi size một dòng, đơn giá gồm phụ thu; đồ uống có size cũ gộp một dòng', () {
    final bills = [
      BillModel.fromMap({
        'billCode': 'HD-1', 'status': 'PAID', 'closedAt': 1000, 'finalAmount': 0, 'subTotal': 0,
        'items': [
          {'productId': 9, 'name': 'Bánh Lăn Nướng', 'price': 15000, 'quantity': 2, 'selectedSize': 'Nhỏ', 'sizeExtraPrice': 0},
          {'productId': 9, 'name': 'Bánh Lăn Nướng', 'price': 15000, 'quantity': 1, 'selectedSize': 'Lớn', 'sizeExtraPrice': 5000},
          {'productId': 5, 'name': 'Sinh tố bơ', 'price': 40000, 'quantity': 1, 'selectedSize': 'M', 'selectedSugar': '100% đường'},
        ],
      }, 'B1'),
      BillModel.fromMap({
        'billCode': 'HD-2', 'status': 'PAID', 'closedAt': 2000, 'finalAmount': 0, 'subTotal': 0,
        'items': [
          {'productId': 9, 'name': 'Bánh Lăn Nướng', 'price': 15000, 'quantity': 3, 'selectedSize': 'Lớn', 'sizeExtraPrice': 5000},
          {'productId': 5, 'name': 'Sinh tố bơ', 'price': 40000, 'quantity': 2, 'selectedSize': 'L', 'sizeExtraPrice': 5000},
        ],
      }, 'B2'),
    ];
    final rows = ReportCalculator.calculateProductReport(bills, productsMap: pm);
    final by = {for (final r in rows) r.productName: r};
    expect(by.keys.toSet(), {'Bánh Lăn Nướng (Nhỏ)', 'Bánh Lăn Nướng (Lớn)', 'Sinh tố bơ'});
    expect(by['Bánh Lăn Nướng (Nhỏ)']!.quantity, 2);
    expect(by['Bánh Lăn Nướng (Lớn)']!.quantity, 4);
    expect(by['Bánh Lăn Nướng (Lớn)']!.basePrice, 20000);
    expect(by['Sinh tố bơ']!.quantity, 3);
  });
}
