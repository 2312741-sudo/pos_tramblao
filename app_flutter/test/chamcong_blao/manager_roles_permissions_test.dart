import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/core/auth/app_permissions.dart';
import 'package:tram_flutter/chamcong_blao/models/member_model.dart';

void main() {
  group('UserRole & Permissions Tests', () {
    test('UserRole parsing from Firestore strings', () {
      expect(UserRoleExtension.fromString('owner'), equals(UserRole.owner));
      expect(UserRoleExtension.fromString('manager_1'), equals(UserRole.manager1));
      expect(UserRoleExtension.fromString('manager1'), equals(UserRole.manager1));
      expect(UserRoleExtension.fromString('manager_2'), equals(UserRole.manager2));
      expect(UserRoleExtension.fromString('manager2'), equals(UserRole.manager2));
      expect(UserRoleExtension.fromString('manager'), equals(UserRole.legacyManager));
      expect(UserRoleExtension.fromString('employee'), equals(UserRole.employee));
      expect(UserRoleExtension.fromString('unknown_role'), equals(UserRole.employee));
    });

    test('UserRole serialization to Firestore string', () {
      expect(UserRole.owner.value, equals('owner'));
      expect(UserRole.manager1.value, equals('manager_1'));
      expect(UserRole.manager2.value, equals('manager_2'));
      expect(UserRole.legacyManager.value, equals('manager'));
      expect(UserRole.employee.value, equals('employee'));
    });

    test('UserRole labels and short labels', () {
      expect(UserRole.owner.label, equals('Chủ'));
      expect(UserRole.manager1.label, equals('Quản lý 1'));
      expect(UserRole.manager2.label, equals('Quản lý 2'));
      expect(UserRole.legacyManager.label, equals('Quản lý (Chưa phân loại)'));
      expect(UserRole.employee.label, equals('Nhân viên'));

      expect(UserRole.manager1.shortLabel, equals('Quản lý 1'));
      expect(UserRole.manager2.shortLabel, equals('Quản lý 2'));
      expect(UserRole.legacyManager.shortLabel, equals('Quản lý'));
    });

    test('AppPermissions - canManageSchedule', () {
      expect(AppPermissions.canManageSchedule(UserRole.owner), isTrue);
      expect(AppPermissions.canManageSchedule(UserRole.manager1), isTrue);
      expect(AppPermissions.canManageSchedule(UserRole.legacyManager), isTrue);
      expect(AppPermissions.canManageSchedule(UserRole.manager2), isFalse);
      expect(AppPermissions.canManageSchedule(UserRole.employee), isFalse);
      expect(AppPermissions.canManageSchedule(null), isFalse);
    });

    test('AppPermissions - canViewStoreSchedule', () {
      expect(AppPermissions.canViewStoreSchedule(UserRole.owner), isTrue);
      expect(AppPermissions.canViewStoreSchedule(UserRole.manager1), isTrue);
      expect(AppPermissions.canViewStoreSchedule(UserRole.manager2), isTrue);
      expect(AppPermissions.canViewStoreSchedule(UserRole.legacyManager), isTrue);
      expect(AppPermissions.canViewStoreSchedule(UserRole.employee), isTrue);
    });

    test('AppPermissions - canTickDelivery and canTickGiaoHang', () {
      for (final role in [UserRole.owner, UserRole.manager1, UserRole.manager2, UserRole.legacyManager]) {
        expect(AppPermissions.canTickDelivery(role), isTrue);
        expect(AppPermissions.canTickGiaoHang(role), isTrue);
      }
      expect(AppPermissions.canTickDelivery(UserRole.employee), isFalse);
      expect(AppPermissions.canTickGiaoHang(UserRole.employee), isFalse);
    });

    test('AppPermissions - canApproveMembers (Quản lý 1 có quyền, Quản lý 2 không)', () {
      expect(AppPermissions.canApproveMembers(UserRole.owner), isTrue);
      expect(AppPermissions.canApproveMembers(UserRole.manager1), isTrue);
      expect(AppPermissions.canApproveMembers(UserRole.legacyManager), isTrue);
      expect(AppPermissions.canApproveMembers(UserRole.manager2), isFalse);
      expect(AppPermissions.canApproveMembers(UserRole.employee), isFalse);
      expect(AppPermissions.canApproveMembers(null), isFalse);
    });

    test('AppPermissions - canEditAttendance (Chủ, Quản lý 1, Legacy có quyền, Quản lý 2 & NV không)', () {
      expect(AppPermissions.canEditAttendance(UserRole.owner), isTrue);
      expect(AppPermissions.canEditAttendance(UserRole.manager1), isTrue);
      expect(AppPermissions.canEditAttendance(UserRole.legacyManager), isTrue);
      expect(AppPermissions.canEditAttendance(UserRole.manager2), isFalse);
      expect(AppPermissions.canEditAttendance(UserRole.employee), isFalse);
      expect(AppPermissions.canEditAttendance(null), isFalse);
    });

    test('AppPermissions - canViewAllAttendance (Chủ, Quản lý 1, Legacy có quyền, Quản lý 2 & NV không)', () {
      expect(AppPermissions.canViewAllAttendance(UserRole.owner), isTrue);
      expect(AppPermissions.canViewAllAttendance(UserRole.manager1), isTrue);
      expect(AppPermissions.canViewAllAttendance(UserRole.legacyManager), isTrue);
      expect(AppPermissions.canViewAllAttendance(UserRole.manager2), isFalse);
      expect(AppPermissions.canViewAllAttendance(UserRole.employee), isFalse);
      expect(AppPermissions.canViewAllAttendance(null), isFalse);
    });

    test('AppPermissions - canAssignRoles (Chỉ Chủ có quyền)', () {
      expect(AppPermissions.canAssignRoles(UserRole.owner), isTrue);
      expect(AppPermissions.canAssignRoles(UserRole.manager1), isFalse);
      expect(AppPermissions.canAssignRoles(UserRole.manager2), isFalse);
      expect(AppPermissions.canAssignRoles(UserRole.legacyManager), isFalse);
      expect(AppPermissions.canAssignRoles(UserRole.employee), isFalse);
    });

    test('AppPermissions - canManageStoreSettings (Chỉ Chủ có quyền)', () {
      expect(AppPermissions.canManageStoreSettings(UserRole.owner), isTrue);
      expect(AppPermissions.canManageStoreSettings(UserRole.manager1), isFalse);
      expect(AppPermissions.canManageStoreSettings(UserRole.manager2), isFalse);
      expect(AppPermissions.canManageStoreSettings(UserRole.legacyManager), isFalse);
      expect(AppPermissions.canManageStoreSettings(UserRole.employee), isFalse);
    });

    test('MemberModel convenience getters', () {
      final owner = MemberModel(
        userId: 'u1',
        name: 'Chủ quán',
        role: UserRole.owner,
        status: MemberStatus.active,
        employeeType: EmployeeType.fulltime,
        joinedAt: DateTime.now(),
      );
      expect(owner.isOwner, isTrue);
      expect(owner.isManager, isFalse);

      final mgr1 = MemberModel(
        userId: 'u2',
        name: 'Quản lý cấp 1',
        role: UserRole.manager1,
        status: MemberStatus.active,
        employeeType: EmployeeType.fulltime,
        joinedAt: DateTime.now(),
      );
      expect(mgr1.isManager1, isTrue);
      expect(mgr1.isManager2, isFalse);
      expect(mgr1.isManager, isTrue);

      final mgr2 = MemberModel(
        userId: 'u3',
        name: 'Quản lý cấp 2',
        role: UserRole.manager2,
        status: MemberStatus.active,
        employeeType: EmployeeType.fulltime,
        joinedAt: DateTime.now(),
      );
      expect(mgr2.isManager1, isFalse);
      expect(mgr2.isManager2, isTrue);
      expect(mgr2.isManager, isTrue);

      final legacyMgr = MemberModel(
        userId: 'u4',
        name: 'Quản lý cũ',
        role: UserRole.legacyManager,
        status: MemberStatus.active,
        employeeType: EmployeeType.fulltime,
        joinedAt: DateTime.now(),
      );
      expect(legacyMgr.isLegacyManager, isTrue);
      expect(legacyMgr.isManager1, isTrue); // Legacy retains Manager 1 powers temporarily
      expect(legacyMgr.isManager, isTrue);
      expect(AppPermissions.isUnclassifiedManager(legacyMgr.role), isTrue);
    });

    test('UserRoleExtension getters directly on enum', () {
      expect(UserRole.owner.isOwner, isTrue);
      expect(UserRole.owner.isManager, isFalse);
      expect(UserRole.owner.isEmployee, isFalse);

      expect(UserRole.manager1.isOwner, isFalse);
      expect(UserRole.manager1.isManager, isTrue);
      expect(UserRole.manager1.isManager1, isTrue);
      expect(UserRole.manager1.isManager2, isFalse);
      expect(UserRole.manager1.isEmployee, isFalse);

      expect(UserRole.manager2.isOwner, isFalse);
      expect(UserRole.manager2.isManager, isTrue);
      expect(UserRole.manager2.isManager1, isFalse);
      expect(UserRole.manager2.isManager2, isTrue);
      expect(UserRole.manager2.isEmployee, isFalse);

      expect(UserRole.legacyManager.isOwner, isFalse);
      expect(UserRole.legacyManager.isManager, isTrue);
      expect(UserRole.legacyManager.isLegacyManager, isTrue);
      expect(UserRole.legacyManager.isEmployee, isFalse);

      expect(UserRole.employee.isOwner, isFalse);
      expect(UserRole.employee.isManager, isFalse);
      expect(UserRole.employee.isEmployee, isTrue);
    });

    test('Schedule management permissions for current week vs other weeks', () {
      // Owner, Manager 1, and Legacy Manager can manage schedule in ANY week (current or future)
      expect(AppPermissions.canManageSchedule(UserRole.owner), isTrue);
      expect(AppPermissions.canManageSchedule(UserRole.manager1), isTrue);
      expect(AppPermissions.canManageSchedule(UserRole.legacyManager), isTrue);

      // Manager 2 cannot edit shifts in any week, only tick delivery/giaohang
      expect(AppPermissions.canManageSchedule(UserRole.manager2), isFalse);
      expect(AppPermissions.canTickDelivery(UserRole.manager2), isTrue);
      expect(AppPermissions.canTickGiaoHang(UserRole.manager2), isTrue);
    });
  });
}
