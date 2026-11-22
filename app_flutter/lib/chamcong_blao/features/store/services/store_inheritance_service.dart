import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/member_model.dart';
import '../../../cc_firebase.dart';

class StoreInheritanceResult {
  final bool isOwnerLeaving;
  final bool isInherited;
  final String? newOwnerId;
  final String? newOwnerName;
  final UserRole? promotedFromRole;
  final bool isOrphaned;

  const StoreInheritanceResult({
    required this.isOwnerLeaving,
    required this.isInherited,
    this.newOwnerId,
    this.newOwnerName,
    this.promotedFromRole,
    this.isOrphaned = false,
  });
}

class StoreInheritanceService {
  final FirebaseFirestore _firestore;

  StoreInheritanceService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? CcFirebase.firestore;

  CollectionReference<Map<String, dynamic>> _stores() =>
      _firestore.collection('stores');

  CollectionReference<Map<String, dynamic>> _members(String storeId) =>
      _stores().doc(storeId).collection('members');

  CollectionReference<Map<String, dynamic>> _auditLogs(String storeId) =>
      _stores().doc(storeId).collection('audit_logs');

  /// Logic chọn ứng viên kế nhiệm thuần túy (dễ dàng unit test độc lập):
  /// - Ứng viên phải có status == active và userId != leavingOwnerId
  /// - Ưu tiên 1: Quản lý 1 (manager1 / manager_1 / legacyManager)
  /// - Ưu tiên 2: Quản lý 2 (manager2 / manager_2)
  /// - Ưu tiên 3: Nhân viên (employee)
  /// - Tiêu chí giải quyết đồng hạng: joinedAt sớm nhất -> userId (100% deterministic, không ngẫu nhiên)
  static MemberModel? selectNextOwner(
    List<MemberModel> candidates, {
    String? leavingOwnerId,
  }) {
    final eligible = candidates
        .where((m) => m.status == MemberStatus.active)
        .where((m) => leavingOwnerId == null || m.userId != leavingOwnerId)
        .toList();

    if (eligible.isEmpty) return null;

    int compareCandidates(MemberModel a, MemberModel b) {
      final compTime = a.joinedAt.compareTo(b.joinedAt);
      if (compTime != 0) return compTime;
      return a.userId.compareTo(b.userId);
    }

    // Tầng 1: Quản lý 1
    final ql1List =
        eligible.where((m) => m.isManager1 || m.isLegacyManager).toList();
    if (ql1List.isNotEmpty) {
      ql1List.sort(compareCandidates);
      return ql1List.first;
    }

    // Tầng 2: Quản lý 2
    final ql2List = eligible.where((m) => m.isManager2).toList();
    if (ql2List.isNotEmpty) {
      ql2List.sort(compareCandidates);
      return ql2List.first;
    }

    // Tầng 3: Nhân viên vào sớm nhất
    eligible.sort(compareCandidates);
    return eligible.first;
  }

  /// Tìm ứng viên kế nhiệm chức vụ Chủ cửa hàng từ Firestore
  Future<MemberModel?> findNextOwnerCandidate(
    String storeId,
    String leavingOwnerId,
  ) async {
    final membersSnap = await _members(storeId)
        .where('status', isEqualTo: 'active')
        .get();

    final candidates = membersSnap.docs
        .map((d) => MemberModel.fromFirestore(d))
        .toList();

    return selectNextOwner(candidates, leavingOwnerId: leavingOwnerId);
  }

  /// Thực thi toàn bộ cơ chế rời cửa hàng / kế thừa cửa hàng:
  /// - Được dùng chung cho CẢ 2 TRƯỜNG HỢP:
  ///   1. reason: 'owner_left' (Chủ chủ động bấm Rời cửa hàng)
  ///   2. reason: 'account_deleted' (Chủ bị xóa tài khoản)
  /// - Cập nhật đồng bộ trong 1 Atomic WriteBatch:
  ///   + stores/{storeId}.ownerId
  ///   + stores/{storeId}/members/{newOwnerId}.role = 'owner'
  ///   + stores/{storeId}/members/{leavingUserId}.status = 'kicked'
  ///   + memberOrder và hiddenScheduleUserIds
  ///   + users/{leavingUserId}.storeIds
  ///   + Ghi vết kiểm toán (Audit Trail)
  Future<StoreInheritanceResult> executeInheritance({
    required String storeId,
    required String leavingUserId,
    required String reason, // 'owner_left' | 'account_deleted' | 'member_left'
  }) async {
    final storeDoc = await _stores().doc(storeId).get();
    if (!storeDoc.exists) {
      throw Exception('Cửa hàng $storeId không tồn tại');
    }

    final storeData = storeDoc.data() ?? {};
    final isOwner = storeData['ownerId'] == leavingUserId;
    final now = DateTime.now().toUtc();
    final batch = _firestore.batch();

    MemberModel? nextOwner;
    bool isOrphaned = false;

    if (isOwner) {
      // 1. Tìm người kế vị thích hợp
      nextOwner = await findNextOwnerCandidate(storeId, leavingUserId);

      if (nextOwner != null) {
        // Có người kế vị -> Thăng cấp thành Chủ mới
        batch.update(_stores().doc(storeId), {
          'ownerId': nextOwner.userId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        batch.update(_members(storeId).doc(nextOwner.userId), {
          'role': UserRole.owner.value,
          'promotedAt': FieldValue.serverTimestamp(),
          'promotedFrom': nextOwner.role.value,
          'promotedReason': reason,
        });

        // Ghi vết kiểm toán (Audit Trail)
        final auditRef = _auditLogs(storeId).doc();
        batch.set(auditRef, {
          'action': 'ownership_inheritance',
          'storeId': storeId,
          'previousOwnerId': leavingUserId,
          'newOwnerId': nextOwner.userId,
          'newOwnerName': nextOwner.name,
          'promotedFromRole': nextOwner.role.value,
          'reason': reason,
          'timestamp': FieldValue.serverTimestamp(),
          'candidateSelection': {
            'tier': nextOwner.isManager1
                ? 'manager1'
                : nextOwner.isManager2
                    ? 'manager2'
                    : 'employee',
            'joinedAt': nextOwner.joinedAt.toIso8601String(),
          },
          'isOrphaned': false,
        });
      } else {
        // Cửa hàng không còn ai -> Chuyển sang trạng thái không có chủ (Orphaned)
        isOrphaned = true;
        batch.update(_stores().doc(storeId), {
          'status': 'orphaned',
          'ownerId': '',
          'orphanedAt': FieldValue.serverTimestamp(),
          'orphanedReason': 'no_successor_available',
          'orphanedBy': leavingUserId,
        });

        // Ghi vết kiểm toán (Audit Trail)
        final auditRef = _auditLogs(storeId).doc();
        batch.set(auditRef, {
          'action': 'store_orphaned',
          'storeId': storeId,
          'previousOwnerId': leavingUserId,
          'reason': reason,
          'timestamp': FieldValue.serverTimestamp(),
          'isOrphaned': true,
        });
      }
    }

    // 2. Đánh dấu người rời đi là kicked (rời cửa hàng / xóa TK)
    final memberRef = _members(storeId).doc(leavingUserId);
    final memberDoc = await memberRef.get();
    if (memberDoc.exists) {
      batch.update(memberRef, {
        'status': 'kicked',
        'kickedAt': Timestamp.fromDate(now),
        'kickedReason': isOwner ? reason : 'member_left',
        if (isOwner) 'role': UserRole.manager1.value,
      });
    }

    // 3. Dọn dẹp memberOrder và hiddenScheduleUserIds
    batch.update(_stores().doc(storeId), {
      'memberOrder': FieldValue.arrayRemove([leavingUserId]),
      'hiddenScheduleUserIds': FieldValue.arrayRemove([leavingUserId]),
    });

    // 4. Gỡ storeId khỏi users/{leavingUserId}.storeIds
    final userRef = _firestore.collection('users').doc(leavingUserId);
    batch.update(userRef, {
      'storeIds': FieldValue.arrayRemove([storeId]),
    });

    // 5. Commit nguyên tử toàn bộ thay đổi
    await batch.commit();

    // 6. Cập nhật currentStoreId nếu user đang trỏ tới store vừa rời
    try {
      final userDoc = await userRef.get();
      if (userDoc.exists) {
        final userData = userDoc.data() ?? {};
        final currentStoreId = userData['currentStoreId'] as String?;
        final remainingStoreIds =
            List<String>.from(userData['storeIds'] ?? []);

        if (currentStoreId == storeId ||
            !remainingStoreIds.contains(currentStoreId)) {
          final newCurrentStoreId =
              remainingStoreIds.isNotEmpty ? remainingStoreIds.first : null;
          await userRef.update({'currentStoreId': newCurrentStoreId});
        }
      }
    } catch (_) {}

    return StoreInheritanceResult(
      isOwnerLeaving: isOwner,
      isInherited: isOwner && nextOwner != null,
      newOwnerId: nextOwner?.userId,
      newOwnerName: nextOwner?.name,
      promotedFromRole: nextOwner?.role,
      isOrphaned: isOrphaned,
    );
  }
}
