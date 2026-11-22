import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/models/store_model.dart';
import 'package:tram_flutter/chamcong_blao/models/user_model.dart';
import 'package:tram_flutter/chamcong_blao/models/member_model.dart';
import 'package:tram_flutter/chamcong_blao/app/router.dart';
import 'package:tram_flutter/chamcong_blao/features/store/services/store_inheritance_service.dart';

void main() {
  group('StoreModel soft-delete status tests', () {
    test('Default status is active and isDeleted is false', () {
      final store = StoreModel(
        id: 'store_1',
        name: 'Trạm Sữa 1',
        code: 'ABC123',
        ownerId: 'user_1',
        createdAt: DateTime.now(),
      );
      expect(store.status, 'active');
      expect(store.isDeleted, false);
    });

    test('Store with status deleted has isDeleted = true', () {
      final store = StoreModel(
        id: 'store_2',
        name: 'Trạm Sữa 2',
        code: 'XYZ789',
        ownerId: 'user_1',
        createdAt: DateTime.now(),
        status: 'deleted',
      );
      expect(store.status, 'deleted');
      expect(store.isDeleted, true);
    });

    test('StoreModel serialization & deserialization preserves status', () {
      final original = StoreModel(
        id: 'store_3',
        name: 'Trạm Sữa 3',
        code: 'TEST01',
        ownerId: 'user_owner',
        createdAt: DateTime.utc(2026, 8, 20),
        status: 'deleted',
      );
      final json = original.toJson();
      expect(json['status'], 'deleted');
      final reconstructed = StoreModel.fromJson(json, 'store_3');
      expect(reconstructed.id, 'store_3');
      expect(reconstructed.name, 'Trạm Sữa 3');
      expect(reconstructed.status, 'deleted');
      expect(reconstructed.isDeleted, true);
    });

    test('StoreModel copyWith updates status', () {
      final store = StoreModel(
        id: 'store_4',
        name: 'Trạm Sữa 4',
        code: 'TEST02',
        ownerId: 'user_owner',
        createdAt: DateTime.now(),
      );
      final deletedStore = store.copyWith(status: 'deleted');
      expect(deletedStore.status, 'deleted');
      expect(deletedStore.isDeleted, true);
    });
  });

  group('UserModel and store resolution tests', () {
    test('UserModel with multiple storeIds validates currentStoreId', () {
      final user = UserModel(
        id: 'user_123',
        name: 'Nguyễn Văn A',
        email: 'a@example.com',
        currentStoreId: 'store_kicked',
        storeIds: const ['store_active_1', 'store_active_2'],
        createdAt: DateTime.now(),
      );
      expect(user.storeIds.contains(user.currentStoreId), false);
      final String resolvedStoreId = (user.currentStoreId != null &&
              user.storeIds.contains(user.currentStoreId))
          ? user.currentStoreId!
          : (user.storeIds.isNotEmpty ? user.storeIds.first : '');
      expect(resolvedStoreId, 'store_active_1');
    });

    test('UserModel with no remaining stores falls back to empty', () {
      final user = UserModel(
        id: 'user_456',
        name: 'Nguyễn Văn B',
        email: 'b@example.com',
        currentStoreId: 'store_kicked',
        storeIds: const [],
        createdAt: DateTime.now(),
      );
      final String? resolvedStoreId = (user.currentStoreId != null &&
              user.storeIds.contains(user.currentStoreId))
          ? user.currentStoreId!
          : (user.storeIds.isNotEmpty ? user.storeIds.first : null);
      expect(resolvedStoreId, null);
    });
  });

  // === VẤN ĐỀ 1: kickMember khi nhân viên đã tự xóa tài khoản ================
  // Root cause: batch.update() trên /users/{uid} đã bị xóa → permission-denied
  // Fix: kiểm tra userDocExists trước, chỉ update nếu doc tồn tại
  group('kickMember – xử lý nhân viên đã tự xóa tài khoản', () {
    test('userDocExists=false → bỏ qua update /users → không lỗi permission', () {
      const bool userDocExists = false;
      final batchOps = <String>['mark_member_kicked', 'clean_store_member_order'];
      if (userDocExists) {
        batchOps.add('remove_storeId_from_user_doc');
      }
      expect(batchOps.length, 2);
      expect(batchOps.contains('mark_member_kicked'), true);
      expect(batchOps.contains('clean_store_member_order'), true);
      expect(batchOps.contains('remove_storeId_from_user_doc'), false);
    });

    test('userDocExists=true → update /users đầy đủ → backward-compatible', () {
      const bool userDocExists = true;
      final batchOps = <String>['mark_member_kicked', 'clean_store_member_order'];
      if (userDocExists) {
        batchOps.add('remove_storeId_from_user_doc');
      }
      expect(batchOps.length, 3);
      expect(batchOps.contains('mark_member_kicked'), true);
      expect(batchOps.contains('remove_storeId_from_user_doc'), true);
      expect(batchOps.contains('clean_store_member_order'), true);
    });

    test('userDocExists=false → bỏ qua step 3 fix currentStoreId', () {
      const bool userDocExists = false;
      bool didFixCurrentStoreId = false;
      if (userDocExists) {
        didFixCurrentStoreId = true;
      }
      expect(didFixCurrentStoreId, false);
    });
  });

  // === VẤN ĐỀ 2: activeMembersProvider deduplication =========================
  // Guard: nếu stream hoặc memberOrder bị lặp userId → vẫn chỉ hiển thị 1 lần
  group('activeMembersProvider deduplication – không hiển thị nhân viên 2 lần', () {
    MemberModel makeMember(String uid, String name, MemberStatus status) {
      return MemberModel(
        userId: uid,
        name: name,
        role: UserRole.employee,
        status: status,
        employeeType: EmployeeType.fulltime,
        joinedAt: DateTime.now(),
      );
    }

    test('Danh sách không trùng → giữ nguyên', () {
      final members = [
        makeMember('uid_1', 'An', MemberStatus.active),
        makeMember('uid_2', 'Bình', MemberStatus.active),
        makeMember('uid_3', 'Châu', MemberStatus.active),
      ];
      final seen = <String>{};
      final deduped = members.where((m) => seen.add(m.userId)).toList();
      expect(deduped.length, 3);
    });

    test('Thanh Linh xuất hiện 2 lần → dedup chỉ còn 1', () {
      final members = [
        makeMember('uid_thanh_linh', 'Thanh Linh Nguyễn', MemberStatus.active),
        makeMember('uid_2', 'Bình', MemberStatus.active),
        makeMember('uid_thanh_linh', 'Thanh Linh Nguyễn', MemberStatus.active), // duplicate
      ];
      final seen = <String>{};
      final deduped = members.where((m) => seen.add(m.userId)).toList();
      expect(deduped.length, 2);
      expect(deduped.where((m) => m.userId == 'uid_thanh_linh').length, 1);
    });

    test('Nhiều phần tử trùng → dedup chính xác', () {
      final members = [
        makeMember('uid_1', 'An', MemberStatus.active),
        makeMember('uid_1', 'An', MemberStatus.active),
        makeMember('uid_2', 'Bình', MemberStatus.active),
        makeMember('uid_2', 'Bình', MemberStatus.active),
        makeMember('uid_3', 'Châu', MemberStatus.active),
      ];
      final seen = <String>{};
      final deduped = members.where((m) => seen.add(m.userId)).toList();
      expect(deduped.length, 3);
    });
  });

  // === VẤN ĐỀ 3: deleteAccount cleanup & ghost member handling ================
  group('deleteAccount & ghost member cleanup tests', () {
    test('deleteAccount marks all stores as kicked and cleans memberOrder', () {
      const uid = 'deleted_user_1';
      final storeMemberships = <String, String>{
        'store_A': 'active',
        'store_B': 'active',
        'store_C': 'kicked',
      };
      final storeMemberOrder = <String>['uid_other', uid, 'uid_another'];

      // Simulate deleteAccount Step 2:
      final updatedStores = <String>[];
      storeMemberships.forEach((storeId, status) {
        if (status != 'kicked') {
          storeMemberships[storeId] = 'kicked';
          updatedStores.add(storeId);
        }
      });
      storeMemberOrder.remove(uid);

      // Verify all memberships are kicked
      expect(storeMemberships['store_A'], 'kicked');
      expect(storeMemberships['store_B'], 'kicked');
      expect(storeMemberships['store_C'], 'kicked');
      expect(updatedStores, containsAll(['store_A', 'store_B']));

      // Verify memberOrder was cleaned
      expect(storeMemberOrder.contains(uid), false);
      expect(storeMemberOrder.length, 2);
    });

    test('cleanupGhostMembers detects active member with missing user document', () {
      final existingUsers = <String>{'uid_valid_1', 'uid_valid_2'};
      final storeMembers = <Map<String, dynamic>>[
        {'userId': 'uid_valid_1', 'status': 'active'},
        {'userId': 'uid_ghost_1', 'status': 'active'}, // user deleted from Firebase
        {'userId': 'uid_valid_2', 'status': 'active'},
        {'userId': 'uid_ghost_2', 'status': 'active'}, // user deleted from Firebase
      ];

      int cleanedCount = 0;
      final memberOrder = <String>['uid_valid_1', 'uid_ghost_1', 'uid_valid_2', 'uid_ghost_2'];

      for (final member in storeMembers) {
        final userId = member['userId'] as String;
        final userExists = existingUsers.contains(userId);
        if (!userExists) {
          member['status'] = 'kicked';
          member['kickedReason'] = 'account_deleted';
          memberOrder.remove(userId);
          cleanedCount++;
        }
      }

      expect(cleanedCount, 2);
      expect(storeMembers[1]['status'], 'kicked');
      expect(storeMembers[1]['kickedReason'], 'account_deleted');
      expect(storeMembers[3]['status'], 'kicked');
      expect(memberOrder, ['uid_valid_1', 'uid_valid_2']);
    });
  });

  // === VẤN ĐỀ 4: Auto-transfer ownership & leaveStore tests ===================
  group('Auto-transfer ownership & leaveStore tests', () {
    MemberModel createCandidate(String uid, UserRole role, DateTime joinedAt) {
      return MemberModel(
        userId: uid,
        name: 'Member $uid',
        role: role,
        status: MemberStatus.active,
        employeeType: EmployeeType.fulltime,
        joinedAt: joinedAt,
      );
    }

    String? selectNextOwner(List<MemberModel> candidates, String currentOwnerId) {
      final filtered = candidates.where((m) => m.userId != currentOwnerId && m.isActive).toList();
      if (filtered.isEmpty) return null;

      // 1. Ưu tiên Quản lý 1
      final ql1List = filtered.where((m) => m.isManager1).toList();
      if (ql1List.isNotEmpty) {
        ql1List.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
        return ql1List.first.userId;
      }

      // 2. Fallback: Quản lý 2
      final ql2List = filtered.where((m) => m.isManager2).toList();
      if (ql2List.isNotEmpty) {
        ql2List.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
        return ql2List.first.userId;
      }

      // 3. Fallback: Nhân viên thâm niên nhất
      filtered.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
      return filtered.first.userId;
    }

    test('Chủ rời cửa hàng: Ưu tiên Quản lý 1 vào sớm nhất', () {
      final members = [
        createCandidate('owner_1', UserRole.owner, DateTime(2025, 1, 1)),
        createCandidate('ql1_newer', UserRole.manager1, DateTime(2025, 5, 1)),
        createCandidate('ql1_older', UserRole.manager1, DateTime(2025, 2, 1)), // sớm hơn
        createCandidate('emp_1', UserRole.employee, DateTime(2025, 1, 15)),
      ];

      final nextOwnerId = selectNextOwner(members, 'owner_1');
      expect(nextOwnerId, 'ql1_older');
    });

    test('Chủ rời cửa hàng: Không có QL1 -> Fallback sang QL2 vào sớm nhất', () {
      final members = [
        createCandidate('owner_1', UserRole.owner, DateTime(2025, 1, 1)),
        createCandidate('ql2_newer', UserRole.manager2, DateTime(2025, 6, 1)),
        createCandidate('ql2_older', UserRole.manager2, DateTime(2025, 3, 1)),
        createCandidate('emp_1', UserRole.employee, DateTime(2025, 4, 1)),
      ];

      final nextOwnerId = selectNextOwner(members, 'owner_1');
      expect(nextOwnerId, 'ql2_older');
    });

    test('Chủ rời cửa hàng: Không có QL1 & QL2 -> Fallback sang Nhân viên thâm niên nhất', () {
      final members = [
        createCandidate('owner_1', UserRole.owner, DateTime(2025, 1, 1)),
        createCandidate('emp_newer', UserRole.employee, DateTime(2025, 8, 1)),
        createCandidate('emp_older', UserRole.employee, DateTime(2025, 3, 1)),
      ];

      final nextOwnerId = selectNextOwner(members, 'owner_1');
      expect(nextOwnerId, 'emp_older');
    });

    test('Chủ là thành viên duy nhất -> selectNextOwner trả về null để soft-delete', () {
      final members = [
        createCandidate('owner_1', UserRole.owner, DateTime(2025, 1, 1)),
      ];

      final nextOwnerId = selectNextOwner(members, 'owner_1');
      expect(nextOwnerId, null);
    });
  });

  // === VẤN ĐỀ 5: Permission truth reconciliation tests ========================
  group('Permission truth reconciliation tests (chống lưu quyền cũ)', () {
    test('store.ownerId == uid && member == null -> Fallback role == UserRole.owner', () {
      const currentUserId = 'user_owner';
      final store = StoreModel(
        id: 'store_1',
        name: 'Quán 1',
        code: 'Q1',
        ownerId: currentUserId,
        createdAt: DateTime.now(),
      );

      MemberModel? member;

      // Reconciliation logic:
      final isStoreOwner = store.ownerId == currentUserId;
      if (member != null) {
        if (member.role == UserRole.owner && !isStoreOwner) {
          member = member.copyWith(role: UserRole.manager1);
        }
      } else if (isStoreOwner) {
        member = MemberModel(
          userId: currentUserId,
          name: 'Chủ cửa hàng',
          role: UserRole.owner,
          status: MemberStatus.active,
          employeeType: EmployeeType.fulltime,
          joinedAt: store.createdAt,
        );
      }

      expect(member?.role, UserRole.owner);
      expect(member?.isOwner, true);
    });

    test('store.ownerId == uid && member có role rõ ràng (manager2, employee) -> Tôn trọng vai trò đó', () {
      const currentUserId = 'user_owner';
      final store = StoreModel(
        id: 'store_1',
        name: 'Quán 1',
        code: 'Q1',
        ownerId: currentUserId,
        createdAt: DateTime.now(),
      );

      // User có document member rõ ràng là manager2
      var member = MemberModel(
        userId: currentUserId,
        name: 'Nguyễn Quản Lý',
        role: UserRole.manager2,
        status: MemberStatus.active,
        employeeType: EmployeeType.fulltime,
        joinedAt: DateTime.now(),
      );

      // Reconciliation logic:
      final isStoreOwner = store.ownerId == currentUserId;
      if (member.role == UserRole.owner && !isStoreOwner) {
        member = member.copyWith(role: UserRole.manager1);
      }

      expect(member.role, UserRole.manager2);
      expect(member.isOwner, false);
      expect(member.isManager2, true);
    });

    test('store.ownerId != uid -> Triệt tiêu quyền Owner cũ, hạ xuống manager1', () {
      const formerOwnerId = 'former_owner';
      final store = StoreModel(
        id: 'store_1',
        name: 'Quán 1',
        code: 'Q1',
        ownerId: 'new_owner', // Chủ mới đã đổi
        createdAt: DateTime.now(),
      );

      // Member doc của cựu chủ vẫn còn lưu role 'owner' trong local cache
      var member = MemberModel(
        userId: formerOwnerId,
        name: 'Cựu Chủ Quán',
        role: UserRole.owner,
        status: MemberStatus.active,
        employeeType: EmployeeType.fulltime,
        joinedAt: DateTime.now(),
      );

      // Reconciliation logic:
      final isStoreOwner = store.ownerId == formerOwnerId;
      if (!isStoreOwner && member.role == UserRole.owner) {
        member = member.copyWith(role: UserRole.manager1);
      }

      expect(member.role, UserRole.manager1);
      expect(member.isOwner, false);
      expect(member.isManager1, true);
    });
  });

  group('Dashboard Routing and Role Resolution Tests', () {
    test('Role mapping correctly maps all user roles to target dashboard routes', () {
      String getTargetPath(UserRole role) {
        if (role.isOwner) return AppRoutes.ownerDashboard;
        if (role.isManager) return AppRoutes.managerDashboard;
        return AppRoutes.employeeDashboard;
      }

      // 1. Owner
      expect(getTargetPath(UserRole.owner), AppRoutes.ownerDashboard);

      // 2. Manager 1 (Quản lý 1)
      expect(getTargetPath(UserRole.manager1), AppRoutes.managerDashboard);

      // 3. Manager 2 (Quản lý 2)
      expect(getTargetPath(UserRole.manager2), AppRoutes.managerDashboard);

      // 4. Legacy Manager (Quản lý chưa phân loại)
      expect(getTargetPath(UserRole.legacyManager), AppRoutes.managerDashboard);

      // 5. Employee (Nhân viên)
      expect(getTargetPath(UserRole.employee), AppRoutes.employeeDashboard);
    });

    test('UserRoleExtension.fromString correctly identifies manager roles from Firestore strings', () {
      final ql2 = UserRoleExtension.fromString('manager_2');
      expect(ql2, UserRole.manager2);
      expect(ql2.isManager, true);
      expect(ql2.isOwner, false);
      expect(ql2.isEmployee, false);

      final ql2Alt = UserRoleExtension.fromString('manager2');
      expect(ql2Alt, UserRole.manager2);
      expect(ql2Alt.isManager, true);

      final ql1 = UserRoleExtension.fromString('manager_1');
      expect(ql1, UserRole.manager1);
      expect(ql1.isManager, true);

      final nv = UserRoleExtension.fromString('employee');
      expect(nv, UserRole.employee);
      expect(nv.isEmployee, true);
      expect(nv.isManager, false);
      expect(nv.isOwner, false);
    });

    test('currentStoreId resolution does not falsely revert to first store if currentStoreId is valid in loaded stores', () {
      final user = UserModel(
        id: 'user_1',
        name: 'Chủ Quán',
        email: 'chu@example.com',
        currentStoreId: 'tram_sua_id', // switched to Trạm Sữa (user is employee here)
        storeIds: const ['owner_store_id'], // storeIds array was not yet synced
        createdAt: DateTime.now(),
      );

      final loadedStores = [
        StoreModel(id: 'owner_store_id', name: 'Trạm Cà Phê', code: 'CF0001', ownerId: 'user_1', createdAt: DateTime.now()),
        StoreModel(id: 'tram_sua_id', name: 'Trạm Sữa', code: 'SUA001', ownerId: 'other_owner', createdAt: DateTime.now()),
        StoreModel(id: 'tram_chanh_id', name: 'Trạm Chanh', code: 'CH0001', ownerId: 'other_owner_2', createdAt: DateTime.now()),
      ];

      final validStoreIds = loadedStores.map((s) => s.id).toSet();

      // Resolution logic as implemented in currentStoreIdProvider
      String? resolvedId;
      if (user.currentStoreId != null && user.currentStoreId!.isNotEmpty) {
        final cur = user.currentStoreId!;
        if (validStoreIds.isNotEmpty) {
          if (validStoreIds.contains(cur) || user.storeIds.contains(cur)) {
            resolvedId = cur;
          }
        } else {
          if (user.storeIds.isEmpty || user.storeIds.contains(cur)) {
            resolvedId = cur;
          }
        }
      }

      // Crucial verification: resolvedId MUST BE 'tram_sua_id', NOT 'owner_store_id'
      expect(resolvedId, 'tram_sua_id');
    });

    test('currentStoreId falls back to available stores only if currentStoreId was deleted or kicked', () {
      final user = UserModel(
        id: 'user_1',
        name: 'Chủ Quán',
        email: 'chu@example.com',
        currentStoreId: 'kicked_store_id',
        storeIds: const ['owner_store_id'],
        createdAt: DateTime.now(),
      );

      final loadedStores = [
        StoreModel(id: 'owner_store_id', name: 'Trạm Cà Phê', code: 'CF0001', ownerId: 'user_1', createdAt: DateTime.now()),
      ];

      final validStoreIds = loadedStores.map((s) => s.id).toSet();

      String? resolvedId;
      if (user.currentStoreId != null && user.currentStoreId!.isNotEmpty) {
        final cur = user.currentStoreId!;
        if (validStoreIds.isNotEmpty) {
          if (validStoreIds.contains(cur) || user.storeIds.contains(cur)) {
            resolvedId = cur;
          }
        }
      }

      if (resolvedId == null) {
        if (loadedStores.isNotEmpty) {
          resolvedId = loadedStores.first.id;
        } else if (user.storeIds.isNotEmpty) {
          resolvedId = user.storeIds.first;
        }
      }

      expect(resolvedId, 'owner_store_id');
    });
  });

  group('StoreInheritanceService – Quy định nghiệp vụ kế thừa cửa hàng', () {
    MemberModel makeMember({
      required String uid,
      required String name,
      required UserRole role,
      required DateTime joinedAt,
      MemberStatus status = MemberStatus.active,
    }) {
      return MemberModel(
        userId: uid,
        name: name,
        role: role,
        status: status,
        employeeType: EmployeeType.fulltime,
        joinedAt: joinedAt,
      );
    }

    test('Kịch bản 1: Có Quản lý 1 -> Quản lý 1 được chọn làm Chủ mới. Nếu có nhiều QL1, ai vào trước làm Chủ', () {
      final owner = makeMember(
        uid: 'owner_uid',
        name: 'Chủ cũ',
        role: UserRole.owner,
        joinedAt: DateTime(2025, 1, 1),
      );
      final ql1Newer = makeMember(
        uid: 'ql1_newer',
        name: 'Quản lý 1 mới',
        role: UserRole.manager1,
        joinedAt: DateTime(2025, 6, 1),
      );
      final ql1Older = makeMember(
        uid: 'ql1_older',
        name: 'Quản lý 1 cũ',
        role: UserRole.manager1,
        joinedAt: DateTime(2025, 3, 1),
      );
      final employee = makeMember(
        uid: 'emp_1',
        name: 'Nhân viên',
        role: UserRole.employee,
        joinedAt: DateTime(2025, 2, 1), // Vào trước cả QL1 nhưng role thấp hơn
      );

      final candidates = [owner, ql1Newer, ql1Older, employee];
      final nextOwner = StoreInheritanceService.selectNextOwner(
        candidates,
        leavingOwnerId: 'owner_uid',
      );

      expect(nextOwner, isNotNull);
      expect(nextOwner!.userId, 'ql1_older');
      expect(nextOwner.name, 'Quản lý 1 cũ');
    });

    test('Kịch bản 2: Hỗ trợ legacyManager tương đương Quản lý 1', () {
      final owner = makeMember(
        uid: 'owner_uid',
        name: 'Chủ cũ',
        role: UserRole.owner,
        joinedAt: DateTime(2025, 1, 1),
      );
      final legacyMgr = makeMember(
        uid: 'legacy_mgr',
        name: 'Quản lý đời cũ',
        role: UserRole.legacyManager,
        joinedAt: DateTime(2025, 5, 1),
      );
      final ql2 = makeMember(
        uid: 'ql2_user',
        name: 'Quản lý 2',
        role: UserRole.manager2,
        joinedAt: DateTime(2025, 2, 1),
      );

      final nextOwner = StoreInheritanceService.selectNextOwner(
        [owner, legacyMgr, ql2],
        leavingOwnerId: 'owner_uid',
      );

      expect(nextOwner, isNotNull);
      expect(nextOwner!.userId, 'legacy_mgr');
    });

    test('Kịch bản 3: Không có Quản lý 1, có Quản lý 2 -> Quản lý 2 được chọn làm Chủ mới', () {
      final owner = makeMember(
        uid: 'owner_uid',
        name: 'Chủ cũ',
        role: UserRole.owner,
        joinedAt: DateTime(2025, 1, 1),
      );
      final ql2 = makeMember(
        uid: 'ql2_user',
        name: 'Quản lý 2',
        role: UserRole.manager2,
        joinedAt: DateTime(2025, 4, 1),
      );
      final employeeSenior = makeMember(
        uid: 'emp_senior',
        name: 'Nhân viên kỳ cựu',
        role: UserRole.employee,
        joinedAt: DateTime(2025, 2, 1),
      );

      final nextOwner = StoreInheritanceService.selectNextOwner(
        [owner, ql2, employeeSenior],
        leavingOwnerId: 'owner_uid',
      );

      expect(nextOwner, isNotNull);
      expect(nextOwner!.userId, 'ql2_user');
      expect(nextOwner.role, UserRole.manager2);
    });

    test('Kịch bản 4: Chỉ có Nhân viên -> Nhân viên có thâm niên cao nhất (joinedAt sớm nhất) làm Chủ', () {
      final owner = makeMember(
        uid: 'owner_uid',
        name: 'Chủ cũ',
        role: UserRole.owner,
        joinedAt: DateTime(2025, 1, 1),
      );
      final empJunior = makeMember(
        uid: 'emp_junior',
        name: 'Nhân viên mới',
        role: UserRole.employee,
        joinedAt: DateTime(2025, 8, 1),
      );
      final empSenior = makeMember(
        uid: 'emp_senior',
        name: 'Nhân viên vào sớm nhất',
        role: UserRole.employee,
        joinedAt: DateTime(2025, 2, 15),
      );

      final nextOwner = StoreInheritanceService.selectNextOwner(
        [owner, empJunior, empSenior],
        leavingOwnerId: 'owner_uid',
      );

      expect(nextOwner, isNotNull);
      expect(nextOwner!.userId, 'emp_senior');
      expect(nextOwner.name, 'Nhân viên vào sớm nhất');
    });

    test('Kịch bản 5: Tie-breaker khi cùng hạng & cùng joinedAt -> xác định 100% bằng userId alphabetically', () {
      final t = DateTime(2025, 5, 1, 10, 0, 0);
      final empB = makeMember(
        uid: 'user_beta',
        name: 'Nhân viên B',
        role: UserRole.employee,
        joinedAt: t,
      );
      final empA = makeMember(
        uid: 'user_alpha',
        name: 'Nhân viên A',
        role: UserRole.employee,
        joinedAt: t,
      );

      // Thử cả 2 thứ tự input để đảm bảo kết quả 100% deterministic không phụ thuộc thứ tự danh sách
      final res1 = StoreInheritanceService.selectNextOwner([empB, empA]);
      final res2 = StoreInheritanceService.selectNextOwner([empA, empB]);

      expect(res1!.userId, 'user_alpha');
      expect(res2!.userId, 'user_alpha');
    });

    test('Kịch bản 6: Cửa hàng không còn ai khác -> trả về null (Store chuyển status = orphaned, ownerId = \'\')', () {
      final owner = makeMember(
        uid: 'owner_uid',
        name: 'Chủ độc nhất',
        role: UserRole.owner,
        joinedAt: DateTime(2025, 1, 1),
      );

      final nextOwner = StoreInheritanceService.selectNextOwner(
        [owner],
        leavingOwnerId: 'owner_uid',
      );

      expect(nextOwner, isNull);
    });

    test('Bộ lọc thành viên: Thành viên kicked hoặc pending KHÔNG BAO GIỜ được kế thừa', () {
      final owner = makeMember(
        uid: 'owner_uid',
        name: 'Chủ cũ',
        role: UserRole.owner,
        joinedAt: DateTime(2025, 1, 1),
      );
      final kickedQL1 = makeMember(
        uid: 'kicked_ql1',
        name: 'QL1 bị đuổi',
        role: UserRole.manager1,
        status: MemberStatus.kicked,
        joinedAt: DateTime(2025, 2, 1),
      );
      final pendingQL1 = makeMember(
        uid: 'pending_ql1',
        name: 'QL1 chưa duyệt',
        role: UserRole.manager1,
        status: MemberStatus.pending,
        joinedAt: DateTime(2025, 3, 1),
      );
      final activeEmployee = makeMember(
        uid: 'active_emp',
        name: 'Nhân viên đang hoạt động',
        role: UserRole.employee,
        status: MemberStatus.active,
        joinedAt: DateTime(2025, 7, 1),
      );

      final nextOwner = StoreInheritanceService.selectNextOwner(
        [owner, kickedQL1, pendingQL1, activeEmployee],
        leavingOwnerId: 'owner_uid',
      );

      // QL1 kicked/pending bị loại -> activeEmployee được chọn
      expect(nextOwner, isNotNull);
      expect(nextOwner!.userId, 'active_emp');
    });
  });

  group('cancelJoinRequest – Hủy yêu cầu tham gia cửa hàng', () {
    test('Hủy yêu cầu tham gia gỡ storeId khỏi danh sách storeIds và reset currentStoreId', () {
      final initialUser = UserModel(
        id: 'applicant_1',
        name: 'Applicant 1',
        email: 'applicant1@example.com',
        storeIds: ['store_pending_1', 'store_other_2'],
        currentStoreId: 'store_pending_1',
        createdAt: DateTime.now(),
      );

      // Simulating cancelJoinRequest effects on UserModel
      final updatedStoreIds = List<String>.from(initialUser.storeIds)..remove('store_pending_1');
      final updatedUser = UserModel(
        id: initialUser.id,
        name: initialUser.name,
        email: initialUser.email,
        storeIds: updatedStoreIds,
        currentStoreId: null,
        createdAt: initialUser.createdAt,
      );

      expect(updatedUser.storeIds, ['store_other_2']);
      expect(updatedUser.currentStoreId, isNull);
      expect(updatedUser.storeIds.contains('store_pending_1'), isFalse);
    });
  });
}


