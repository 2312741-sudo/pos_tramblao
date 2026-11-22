import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/core/utils/department_utils.dart';
import 'package:tram_flutter/chamcong_blao/models/store_model.dart';

void main() {
  group('DepartmentUtils Tests', () {
    const sxDept = DepartmentDefinition(
      id: 'dept_sx_123',
      name: 'Sản xuất & Chế biến',
      shortName: 'SX',
    );

    const salesDept = DepartmentDefinition(
      id: 'dept_sales_456',
      name: 'Bán hàng',
      shortName: 'BH',
    );

    final store = StoreModel(
      id: 'store_1',
      name: 'Cửa hàng mẫu',
      code: 'STORE1',
      ownerId: 'owner_1',
      createdAt: DateTime.now(),
      departments: const [sxDept, salesDept],
    );

    test('isProduction matches exact shortName "SX" with case-insensitivity', () {
      expect(DepartmentUtils.isProduction(shortName: 'SX'), isTrue);
      expect(DepartmentUtils.isProduction(shortName: 'sx'), isTrue);
      expect(DepartmentUtils.isProduction(shortName: 'Sx'), isTrue);
      expect(DepartmentUtils.isProduction(shortName: 'BH'), isFalse);
    });

    test('isProduction matches name variants (Sản xuất, San xuat, etc.)', () {
      expect(DepartmentUtils.isProduction(deptName: 'Sản xuất'), isTrue);
      expect(DepartmentUtils.isProduction(deptName: 'SẢN XUẤT'), isTrue);
      expect(DepartmentUtils.isProduction(deptName: 'San xuat'), isTrue);
      expect(DepartmentUtils.isProduction(deptName: 'Khu vực Sản xuất bánh'), isTrue);
      expect(DepartmentUtils.isProduction(deptName: 'Bán hàng'), isFalse);
    });

    test('isProduction matches deptId inside storeDepartments list', () {
      expect(
        DepartmentUtils.isProduction(
          deptId: 'dept_sx_123',
          storeDepartments: store.departments,
        ),
        isTrue,
      );

      expect(
        DepartmentUtils.isProduction(
          deptId: 'dept_sales_456',
          storeDepartments: store.departments,
        ),
        isFalse,
      );
    });

    test('isUserInProductionShiftToday detects explicit shift department override (shiftId|deptId)', () {
      final isSX = DepartmentUtils.isUserInProductionShiftToday(
        userId: 'user_1',
        store: store,
        memberDepartmentId: 'dept_sales_456', // Member is default Sales
        todayShiftEntries: ['shift_morning|dept_sx_123'], // But shift is assigned SX
      );
      expect(isSX, isTrue);
    });

    test('isUserInProductionShiftToday detects member department when shift entry has no explicit department', () {
      final isSX = DepartmentUtils.isUserInProductionShiftToday(
        userId: 'user_1',
        store: store,
        memberDepartmentId: 'dept_sx_123', // Member is SX
        todayShiftEntries: ['shift_morning'], // Shift entry is plain shiftId
      );
      expect(isSX, isTrue);
    });

    test('isUserInProductionShiftToday returns false for non-SX member and non-SX shift', () {
      final isSX = DepartmentUtils.isUserInProductionShiftToday(
        userId: 'user_1',
        store: store,
        memberDepartmentId: 'dept_sales_456',
        todayShiftEntries: ['shift_morning|dept_sales_456'],
      );
      expect(isSX, isFalse);
    });
  });
}
