import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/auth/app_permissions.dart';
import '../../../models/store_model.dart';
import '../../../models/advance_request_model.dart';
import '../../../models/member_model.dart';
import '../services/store_inheritance_service.dart';
import '../../../cc_firebase.dart';

class StoreRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  StoreRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? CcFirebase.firestore,
        _auth = auth ?? CcFirebase.auth;

  CollectionReference<Map<String, dynamic>> get _stores =>
      _firestore.collection('stores');

  CollectionReference<Map<String, dynamic>> _members(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('members');

  // ---------- Helpers ----------

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String _getUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Người dùng chưa đăng nhập');
    return uid;
  }

  // ---------- Store CRUD ----------

  Future<StoreModel> createStore(
    String name,
    String address,
    String networkIP,
    double? lat,
    double? lng,
    int radiusMeters, {
    String? wifiName,
    String? wifiSsid,
    String? wifiBssid,
    List<StoreWifi> wifis = const [],
    String? locationName,
    List<StoreLocation> locations = const [],
  }) async {
    try {
      final uid = _getUid();
      final code = _generateCode();
      final now = DateTime.now().toUtc();

      final resolvedWifis = List<StoreWifi>.from(wifis);
      if (resolvedWifis.isEmpty &&
          (wifiBssid?.trim().isNotEmpty == true ||
              networkIP.trim().isNotEmpty)) {
        resolvedWifis.add(
          StoreWifi(
            name: wifiName?.trim().isNotEmpty == true
                ? wifiName!.trim()
                : (wifiSsid?.trim().isNotEmpty == true
                    ? wifiSsid!.trim()
                    : 'WiFi Chính'),
            ssid: wifiSsid?.trim() ?? '',
            bssid: wifiBssid?.trim() ?? '',
            ip: networkIP.trim().isEmpty ? null : networkIP.trim(),
            createdAt: now,
          ),
        );
      }

      final resolvedLocations = List<StoreLocation>.from(locations);
      if (resolvedLocations.isEmpty && lat != null && lng != null) {
        resolvedLocations.add(
          StoreLocation(
            id: 'loc_${DateTime.now().millisecondsSinceEpoch}',
            name: locationName?.trim().isNotEmpty == true
                ? locationName!.trim()
                : 'Cơ sở chính',
            latitude: lat,
            longitude: lng,
            radiusMeters: radiusMeters,
          ),
        );
      }

      final storeRef = _stores.doc();
      final storeData = {
        'name': name.trim(),
        'code': code,
        'ownerId': uid,
        'address': address.trim().isEmpty ? null : address.trim(),
        'networkIP': networkIP.trim().isEmpty ? null : networkIP.trim(),
        'wifis': resolvedWifis.map((w) => w.toJson()).toList(),
        'locations': resolvedLocations.map((l) => l.toJson()).toList(),
        'latitude': resolvedLocations.isNotEmpty
            ? resolvedLocations.first.latitude
            : lat,
        'longitude': resolvedLocations.isNotEmpty
            ? resolvedLocations.first.longitude
            : lng,
        'radiusMeters': resolvedLocations.isNotEmpty
            ? resolvedLocations.first.radiusMeters
            : radiusMeters,
        'createdAt': Timestamp.fromDate(now),
      };

      final batch = _firestore.batch();
      batch.set(storeRef, storeData);

      // Add owner as active member
      final user = _auth.currentUser;
      final memberRef = _members(storeRef.id).doc(uid);
      batch.set(memberRef, {
        'userId': uid,
        'name': user?.displayName ?? user?.email ?? 'Chủ cửa hàng',
        'phone': user?.phoneNumber,
        'avatarUrl': user?.photoURL,
        'role': 'owner',
        'status': 'active',
        'employeeType': 'fulltime',
        'baseMonthlySalary': 0,
        'baseHourlyRate': 0,
        'standardHoursPerMonth': 208,
        'joinedAt': Timestamp.fromDate(now),
      });

      final userRef = _firestore.collection('users').doc(uid);
      batch.set(userRef, {
        'storeIds': FieldValue.arrayUnion([storeRef.id]),
        'currentStoreId': storeRef.id,
      }, SetOptions(merge: true));

      await batch.commit();

      return StoreModel(
        id: storeRef.id,
        name: name.trim(),
        code: code,
        ownerId: uid,
        address: address.trim().isEmpty ? null : address.trim(),
        networkIP: networkIP.trim().isEmpty ? null : networkIP.trim(),
        latitude: resolvedLocations.isNotEmpty
            ? resolvedLocations.first.latitude
            : lat,
        longitude: resolvedLocations.isNotEmpty
            ? resolvedLocations.first.longitude
            : lng,
        radiusMeters: resolvedLocations.isNotEmpty
            ? resolvedLocations.first.radiusMeters
            : radiusMeters,
        locations: resolvedLocations,
        createdAt: now,
      );
    } catch (e) {
      throw Exception('Tạo cửa hàng thất bại: $e');
    }
  }

  Future<StoreModel?> findStoreByCode(String code) async {
    try {
      final query = await _stores.where('code', isEqualTo: code).limit(1).get();
      if (query.docs.isEmpty) return null;
      final store = StoreModel.fromFirestore(query.docs.first);
      if (store.isDeleted) return null;
      return store;
    } catch (e) {
      throw Exception('Tìm cửa hàng thất bại: $e');
    }
  }

  Future<List<StoreModel>> getUserStores(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() ?? {};
      final storeIds = List<String>.from(userData['storeIds'] ?? []);
      final currentStoreId = userData['currentStoreId'] as String?;

      if (currentStoreId != null &&
          currentStoreId.isNotEmpty &&
          !storeIds.contains(currentStoreId)) {
        storeIds.add(currentStoreId);
      }

      // Fallback discovery if storeIds is empty: check owned stores & membership
      if (storeIds.isEmpty) {
        try {
          final ownedStores =
              await _stores.where('ownerId', isEqualTo: userId).get();
          for (final doc in ownedStores.docs) {
            final data = doc.data();
            if (data['status'] != 'deleted' && !storeIds.contains(doc.id)) {
              storeIds.add(doc.id);
            }
          }
        } catch (_) {}

        try {
          final memberDocs = await _firestore
              .collectionGroup('members')
              .where('userId', isEqualTo: userId)
              .get();
          for (final doc in memberDocs.docs) {
            final storeRef = doc.reference.parent.parent;
            if (storeRef != null && !storeIds.contains(storeRef.id)) {
              final status = doc.data()['status'] as String?;
              if (status != 'kicked') {
                storeIds.add(storeRef.id);
              }
            }
          }
        } catch (_) {}
      }

      if (storeIds.isEmpty) return [];

      // Fetch all store models for these IDs
      final stores = <StoreModel>[];
      for (var i = 0; i < storeIds.length; i += 10) {
        final chunk = storeIds.sublist(
            i, i + 10 > storeIds.length ? storeIds.length : i + 10);
        final storesQuery =
            await _stores.where(FieldPath.documentId, whereIn: chunk).get();
        stores.addAll(storesQuery.docs
            .map((d) => StoreModel.fromFirestore(d))
            .where((s) => !s.isDeleted));
      }

      // Verify member status to handle legacy kicked users and deleted stores
      final validStores = <StoreModel>[];
      final invalidStoreIds = <String>[];

      for (final store in stores) {
        if (store.isDeleted) {
          invalidStoreIds.add(store.id);
          continue;
        }

        // Owner is always valid
        if (store.ownerId == userId) {
          validStores.add(store);
          continue;
        }

        final memberDoc = await _members(store.id).doc(userId).get();
        if (memberDoc.exists && memberDoc.data()?['status'] != 'kicked') {
          validStores.add(store);
        } else {
          invalidStoreIds.add(store.id);
        }
      }

      // Also mark storeIds that were not found in Firestore as invalid
      for (final id in storeIds) {
        if (!validStores.any((s) => s.id == id) &&
            !invalidStoreIds.contains(id)) {
          invalidStoreIds.add(id);
        }
      }

      // Self-heal: update valid storeIds in user's profile
      final validIds = validStores.map((s) => s.id).toList();
      if (validIds.isNotEmpty || invalidStoreIds.isNotEmpty) {
        try {
          final String? resolvedCurrentStoreId =
              (currentStoreId != null && validIds.contains(currentStoreId))
                  ? currentStoreId
                  : (validIds.isNotEmpty ? validIds.first : null);

          await _firestore.collection('users').doc(userId).set({
            'storeIds': validIds,
            'currentStoreId': resolvedCurrentStoreId,
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      return validStores;
    } catch (e) {
      throw Exception('Lỗi lấy danh sách cửa hàng: $e');
    }
  }

  Future<void> joinStore(String storeId, String userId) async {
    try {
      final user = _auth.currentUser;
      final now = DateTime.now().toUtc();

      // Check if already a member
      final existing = await _members(storeId).doc(userId).get();
      if (existing.exists) {
        final status = existing.data()?['status'] as String?;
        if (status == 'active') {
          throw Exception('Bạn đã là thành viên của cửa hàng này');
        }
        if (status == 'pending') {
          throw Exception('Yêu cầu của bạn đang chờ duyệt');
        }
        // Kicked → re-apply
      }

      final batch = _firestore.batch();

      batch.set(_members(storeId).doc(userId), {
        'userId': userId,
        'name': user?.displayName ?? user?.email ?? 'Nhân viên',
        'phone': user?.phoneNumber,
        'avatarUrl': user?.photoURL,
        'role': 'employee',
        'status': 'pending',
        'employeeType': 'fulltime',
        'baseMonthlySalary': 0,
        'baseHourlyRate': 0,
        'standardHoursPerMonth': 208,
        'joinedAt': Timestamp.fromDate(now),
      });

      final userRef = _firestore.collection('users').doc(userId);
      batch.set(userRef, {
        'storeIds': FieldValue.arrayUnion([storeId])
      }, SetOptions(merge: true));

      await batch.commit();

    } catch (e) {
      throw Exception('Tham gia cửa hàng thất bại: $e');
    }
  }

  /// Hủy yêu cầu tham gia cửa hàng (chính chủ tự hủy khi đang ở trạng thái pending)
  Future<void> cancelJoinRequest(String storeId, String userId) async {
    try {
      final caller = _auth.currentUser;
      if (caller == null) {
        throw Exception('401 Unauthorized: Chưa đăng nhập');
      }
      if (caller.uid != userId) {
        throw Exception('403 Forbidden: Bạn chỉ có thể hủy yêu cầu của chính mình');
      }

      final batch = _firestore.batch();

      // 1. Xóa bản ghi xin gia nhập đang chờ duyệt
      final memberRef = _members(storeId).doc(userId);
      batch.delete(memberRef);

      // 2. Gỡ storeId khỏi danh sách storeIds của người dùng và gỡ currentStoreId
      final userRef = _firestore.collection('users').doc(userId);
      batch.set(userRef, {
        'storeIds': FieldValue.arrayRemove([storeId]),
        'currentStoreId': null,
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      throw Exception('Hủy yêu cầu tham gia thất bại: $e');
    }
  }

  Future<void> approveOrRejectMember(
      String storeId, String userId, bool approve) async {
    try {
      final caller = _auth.currentUser;
      if (caller == null) {
        throw Exception('401 Unauthorized: Chưa đăng nhập');
      }

      // Check caller's permission
      final callerDoc = await _members(storeId).doc(caller.uid).get();
      if (!callerDoc.exists) {
        throw Exception('403 Forbidden: Bạn không thuộc cửa hàng này');
      }
      final callerRole =
          UserRoleExtension.fromString(callerDoc.data()?['role'] as String?);
      if (!AppPermissions.canApproveMembers(callerRole)) {
        throw Exception(
            '403 Forbidden: Bạn không có quyền duyệt thành viên mới (Chỉ Chủ và Quản lý 1 có quyền này)');
      }

      final now = DateTime.now().toUtc();
      await _members(storeId).doc(userId).update({
        'status': approve ? 'active' : 'kicked',
        'approvedBy': caller.uid,
        'approvedByName': caller.displayName ?? caller.email ?? 'Quản lý',
        'approvedByRole': callerRole.value,
        'approvedAt': Timestamp.fromDate(now),
      });

    } catch (e) {
      throw Exception('Cập nhật trạng thái thành viên thất bại: $e');
    }
  }

  Future<void> kickMember(String storeId, String userId) async {
    try {
      final caller = _auth.currentUser;
      if (caller == null) {
        throw Exception('401 Unauthorized: Chưa đăng nhập');
      }

      final callerDoc = await _members(storeId).doc(caller.uid).get();
      if (!callerDoc.exists) {
        throw Exception('403 Forbidden: Bạn không thuộc cửa hàng này');
      }
      final callerRole =
          UserRoleExtension.fromString(callerDoc.data()?['role'] as String?);
      if (!AppPermissions.canApproveMembers(callerRole)) {
        throw Exception(
            '403 Forbidden: Bạn không có quyền xóa thành viên (Chỉ Chủ và Quản lý 1 có quyền này)');
      }

      // Check if the target user's /users document still exists.
      // If the member has self-deleted their account, this document is gone.
      // We must NOT call batch.update() on a non-existent doc — that causes
      // [cloud_firestore/permission-denied] even when the caller is the store owner.
      final userRef = _firestore.collection('users').doc(userId);
      final userDocSnapshot = await userRef.get();
      final userDocExists = userDocSnapshot.exists;

      final batch = _firestore.batch();

      // 1. Mark member as kicked in store members subcollection
      batch.update(_members(storeId).doc(userId), {'status': 'kicked'});

      // 2. Clean userId from store's memberOrder and hiddenScheduleUserIds
      batch.update(_stores.doc(storeId), {
        'memberOrder': FieldValue.arrayRemove([userId]),
        'hiddenScheduleUserIds': FieldValue.arrayRemove([userId]),
      });

      await batch.commit();

      // 3. Best-effort soft cleanup of kicked user's profile
      // Note: Firestore Security Rules strictly forbid updating other users' docs (/users/{uid}).
      // If caller is not userId (normal manager kicking member), this will be blocked by rules,
      // which is expected. The user's storeIds will be cleanly self-healed by getUserStores()
      // when that user next opens the app, and by Cloud Functions.
      if (userDocExists) {
        try {
          await userRef.update({
            'storeIds': FieldValue.arrayRemove([storeId]),
          });
        } catch (_) {}

        try {
          final userDoc = await userRef.get();
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
        } catch (_) {}
      }

    } catch (e) {
      throw Exception('Xóa thành viên thất bại: $e');
    }
  }


  /// Tìm người kế nhiệm chức vụ Chủ cửa hàng:
  /// Sử dụng StoreInheritanceService để đảm bảo thứ tự ưu tiên chuẩn xác:
  /// QL1 -> QL2 -> NV thâm niên nhất (joinedAt sớm nhất -> userId).
  Future<String?> findNextOwnerId(String storeId, String currentOwnerId) async {
    try {
      final candidate = await StoreInheritanceService(firestore: _firestore)
          .findNextOwnerCandidate(storeId, currentOwnerId);
      return candidate?.userId;
    } catch (_) {
      return null;
    }
  }

  /// Chuyển giao quyền Chủ cửa hàng một cách nguyên tử (Atomic):
  /// - Cập nhật /stores/{storeId}: ownerId = newOwnerId
  /// - Cập nhật /stores/{storeId}/members/{newOwnerId}: role = 'owner'
  /// - Cập nhật cựu chủ (nếu có): role = oldOwnerNewRole (mặc định manager1)
  /// - Ghi vết kiểm toán (Audit Trail)
  Future<void> transferStoreOwnership(
    String storeId,
    String newOwnerId, {
    String? oldOwnerId,
    UserRole? oldOwnerNewRole,
  }) async {
    try {
      final storeDoc = await _stores.doc(storeId).get();
      if (!storeDoc.exists) throw Exception('Cửa hàng không tồn tại');
      final actualOldOwnerId = oldOwnerId ?? storeDoc.data()?['ownerId'] as String?;

      final batch = _firestore.batch();

      // 1. Cập nhật ownerId trên store document
      batch.update(_stores.doc(storeId), {
        'ownerId': newOwnerId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. Thăng cấp newOwner thành 'owner'
      batch.update(_members(storeId).doc(newOwnerId), {
        'role': 'owner',
        'promotedAt': FieldValue.serverTimestamp(),
        'promotedReason': 'manual_transfer',
      });

      // 3. Nếu cựu chủ vẫn còn trong cửa hàng, chuyển vai trò thành oldOwnerNewRole hoặc manager1
      if (actualOldOwnerId != null && actualOldOwnerId != newOwnerId) {
        final oldOwnerDoc = await _members(storeId).doc(actualOldOwnerId).get();
        if (oldOwnerDoc.exists) {
          final targetRole = oldOwnerNewRole ?? UserRole.manager1;
          batch.update(_members(storeId).doc(actualOldOwnerId), {
            'role': targetRole.value,
          });
        }
      }

      // 4. Ghi vết kiểm toán (Audit Trail)
      final auditRef = _firestore
          .collection('stores')
          .doc(storeId)
          .collection('audit_logs')
          .doc();
      batch.set(auditRef, {
        'action': 'manual_transfer',
        'storeId': storeId,
        'previousOwnerId': actualOldOwnerId,
        'newOwnerId': newOwnerId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await batch.commit();

    } catch (e) {
      throw Exception('Chuyển quyền Chủ cửa hàng thất bại: $e');
    }
  }

  /// Rời cửa hàng cho mọi thành viên (Nhân viên, Quản lý, Chủ):
  /// - Tự động ủy quyền kế thừa cho StoreInheritanceService xử lý nguyên tử.
  /// - Nếu là Chủ: Tự động chuyển giao quyền cho người kế vị hoặc chuyển trạng thái orphaned.
  /// - Nếu là Nhân viên / Quản lý: Đánh dấu status = 'kicked' (member_left).
  /// - Dọn dẹp storeIds và currentStoreId an toàn.
  Future<void> leaveStore(String storeId) async {
    try {
      final caller = _auth.currentUser;
      if (caller == null) {
        throw Exception('401 Unauthorized: Chưa đăng nhập');
      }

      await StoreInheritanceService(firestore: _firestore).executeInheritance(
        storeId: storeId,
        leavingUserId: caller.uid,
        reason: 'owner_left',
      );
    } catch (e) {
      throw Exception('Rời cửa hàng thất bại: $e');
    }
  }

  Future<void> updateMemberRole(
      String storeId, String userId, UserRole newRole) async {
    try {
      final caller = _auth.currentUser;
      if (caller == null) {
        throw Exception('401 Unauthorized: Chưa đăng nhập');
      }

      final callerDoc = await _members(storeId).doc(caller.uid).get();
      if (!callerDoc.exists) {
        throw Exception('403 Forbidden: Bạn không thuộc cửa hàng này');
      }
      final callerRole =
          UserRoleExtension.fromString(callerDoc.data()?['role'] as String?);
      if (!AppPermissions.canAssignRoles(callerRole)) {
        throw Exception(
            '403 Forbidden: Chỉ Chủ cửa hàng mới có quyền phân vai trò');
      }

      if (newRole == UserRole.owner) {
        // Chuyển giao quyền chủ sở hữu cửa hàng cho thành viên này một cách nguyên tử
        await transferStoreOwnership(
          storeId,
          userId,
          oldOwnerId: caller.uid,
          oldOwnerNewRole: UserRole.manager1,
        );
        return;
      }

      await _members(storeId).doc(userId).update({'role': newRole.value});
    } catch (e) {
      throw Exception('Cập nhật vai trò thất bại: $e');
    }
  }


  Future<void> updateMemberSalary(
    String storeId,
    String userId,
    EmployeeType type,
    double salary,
    double standardHours,
  ) async {
    try {
      await _members(storeId).doc(userId).update({
        'employeeType': type.value,
        if (type == EmployeeType.fulltime)
          'baseMonthlySalary': salary
        else
          'baseHourlyRate': salary,
        'standardHoursPerMonth': standardHours,
      });
    } catch (e) {
      throw Exception('Cập nhật lương thất bại: $e');
    }
  }

  Stream<StoreModel?> watchStore(String storeId) {
    return _stores.doc(storeId).snapshots().map((snap) {
      if (!snap.exists) return null;
      final store = StoreModel.fromFirestore(snap);
      if (store.isDeleted) return null;
      return store;
    });
  }

  Future<void> deleteStore(String storeId) async {
    try {
      final caller = _auth.currentUser;
      if (caller == null) {
        throw Exception('401 Unauthorized: Chưa đăng nhập');
      }

      final storeDoc = await _stores.doc(storeId).get();
      if (!storeDoc.exists) {
        throw Exception('Cửa hàng không tồn tại');
      }

      final storeData = storeDoc.data() ?? {};
      final ownerId = storeData['ownerId'] as String?;

      if (ownerId != caller.uid) {
        throw Exception(
            '403 Forbidden: Chỉ Chủ cửa hàng mới có quyền xóa cửa hàng');
      }

      final now = DateTime.now().toUtc();

      // 1. Soft-delete store document
      await _stores.doc(storeId).update({
        'status': 'deleted',
        'deletedAt': Timestamp.fromDate(now),
        'deletedBy': caller.uid,
      });

      // 2. Fetch all members in this store
      final membersSnap = await _members(storeId).get();
      final affectedUserIds = <String>{};

      for (final doc in membersSnap.docs) {
        affectedUserIds.add(doc.id);
      }
      affectedUserIds.add(caller.uid);

      // 3. Remove storeId from each user's storeIds and update currentStoreId if pointing to this store
      for (final uid in affectedUserIds) {
        try {
          final userRef = _firestore.collection('users').doc(uid);
          final uDoc = await userRef.get();
          if (!uDoc.exists) continue;

          final uData = uDoc.data() ?? {};
          final currentStoreId = uData['currentStoreId'] as String?;
          final userStoreIds = List<String>.from(uData['storeIds'] ?? []);

          userStoreIds.remove(storeId);

          final String? newCurrentStoreId = (currentStoreId == storeId)
              ? (userStoreIds.isNotEmpty ? userStoreIds.first : null)
              : currentStoreId;

          await userRef.set({
            'storeIds': userStoreIds,
            'currentStoreId': newCurrentStoreId,
          }, SetOptions(merge: true));
        } catch (_) {}
      }

    } catch (e) {
      throw Exception('Xóa cửa hàng thất bại: $e');
    }
  }

  Stream<List<MemberModel>> watchMembers(String storeId) {
    return _members(storeId)
        .where('status', whereIn: ['active', 'pending'])
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => MemberModel.fromFirestore(d)).toList());
  }

  Stream<List<MemberModel>> watchPendingMembers(String storeId) {
    return _members(storeId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => MemberModel.fromFirestore(d)).toList());
  }

  /// Phát hiện và dọn dẹp "ghost members" — nhân viên bị xóa khỏi Firebase
  /// Console (hoặc tự xóa tài khoản trước đây mà chưa cleanup) nhưng vẫn còn
  /// document trong /stores/{storeId}/members với status = 'active'.
  ///
  /// Cách hoạt động:
  /// 1. Lấy toàn bộ active members
  /// 2. Kiểm tra từng member: /users/{uid} có tồn tại không
  /// 3. Nếu không tồn tại → mark status = 'kicked', kickedReason = 'account_deleted'
  ///
  /// Hàm này chạy BACKGROUND (không throw, tự swallow lỗi).
  /// Trả về số lượng ghost members được dọn dẹp.
  Future<int> cleanupGhostMembers(String storeId) async {
    int cleanedCount = 0;
    try {
      // Chỉ lấy active members (pending không cần check — chưa được duyệt)
      final activeSnap = await _members(storeId)
          .where('status', isEqualTo: 'active')
          .get();

      if (activeSnap.docs.isEmpty) return 0;

      for (final memberDoc in activeSnap.docs) {
        final userId = memberDoc.id;
        try {
          // Kiểm tra /users/{userId} có tồn tại không
          final userDoc =
              await _firestore.collection('users').doc(userId).get();
          if (!userDoc.exists) {
            // Ghost member — xóa tài khoản Firebase mà không cleanup
            await _members(storeId).doc(userId).update({
              'status': 'kicked',
              'kickedAt': FieldValue.serverTimestamp(),
              'kickedReason': 'account_deleted',
            });
            // Dọn dẹp cả khỏi memberOrder và hiddenScheduleUserIds của store
            await _stores.doc(storeId).update({
              'memberOrder': FieldValue.arrayRemove([userId]),
              'hiddenScheduleUserIds': FieldValue.arrayRemove([userId]),
            });
            cleanedCount++;
          }

        } catch (_) {
          // Bỏ qua lỗi từng member, tiếp tục check các member còn lại
        }
      }
    } catch (_) {
      // Hàm này không được phép crash UI
    }
    return cleanedCount;
  }

  Future<void> updateStoreSettings(
      String storeId, Map<String, dynamic> updates) async {
    try {
      await _stores.doc(storeId).update(updates);
    } catch (e) {
      throw Exception('Cập nhật cài đặt cửa hàng thất bại: $e');
    }
  }

  Future<void> updateMemberOrder(
      String storeId, List<String> memberOrder) async {
    try {
      await _stores.doc(storeId).update({'memberOrder': memberOrder});
    } catch (e) {
      throw Exception('Cập nhật thứ tự nhân viên thất bại: $e');
    }
  }

  Future<void> toggleHideMemberSchedule(
      String storeId, String userId, bool hide) async {
    try {
      if (hide) {
        await _stores.doc(storeId).update({
          'hiddenScheduleUserIds': FieldValue.arrayUnion([userId])
        });
      } else {
        await _stores.doc(storeId).update({
          'hiddenScheduleUserIds': FieldValue.arrayRemove([userId])
        });
      }
    } catch (e) {
      throw Exception('Cập nhật trạng thái ẩn lịch thất bại: $e');
    }
  }

  Future<String> regenerateStoreCode(String storeId) async {
    try {
      final newCode = _generateCode();
      await _stores.doc(storeId).update({'code': newCode});
      return newCode;
    } catch (e) {
      throw Exception('Tạo mã mới thất bại: $e');
    }
  }

  Future<void> updateMemberDepartment(
      String storeId, String userId, String? departmentId) async {
    try {
      await _members(storeId).doc(userId).update({
        'department': departmentId,
      });
    } catch (e) {
      throw Exception('Cập nhật bộ phận thất bại: $e');
    }
  }

  Future<void> updateMemberInfo(String storeId, String userId,
      String? employeeCode, DateTime joinedAt) async {
    try {
      await _members(storeId).doc(userId).update({
        'employeeCode': employeeCode,
        'joinedAt': Timestamp.fromDate(joinedAt),
      });
    } catch (e) {
      throw Exception('Cập nhật thông tin thất bại: $e');
    }
  }

  // ---------- Advances ----------

  Stream<List<AdvanceRequestModel>> watchAdvances(String storeId, String month) async* {
    final uid = _auth.currentUser?.uid;
    if (uid == null) { yield []; return; }
    final store = await _stores.doc(storeId).get();
    Query<Map<String, dynamic>> query = _stores.doc(storeId).collection('advances').where('month', isEqualTo: month);
    if (store.data()?['ownerId'] != uid) query = query.where('userId', isEqualTo: uid);
    yield* query.snapshots().map((snap) {
      final list = snap.docs.map(AdvanceRequestModel.fromFirestore).toList();
      list.sort((a, b) => b.requestDate.compareTo(a.requestDate));
      return list;
    });
  }

  Future<void> createAdvanceRequest(AdvanceRequestModel request) async {
    try {
      await _stores
          .doc(request.storeId)
          .collection('advances')
          .add(request.toMap());

      // Create notification for Store Owner & Managers
      try {
        final memberDoc =
            await _members(request.storeId).doc(request.userId).get();
        final memberName = memberDoc.data()?['name'] as String? ?? 'Nhân viên';
        final formattedAmount =
            '${request.amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}đ';

        await _firestore
            .collection('stores')
            .doc(request.storeId)
            .collection('notifications')
            .add({
          'storeId': request.storeId,
          'title': 'Yêu cầu ứng lương mới',
          'body':
              '$memberName vừa gửi yêu cầu tạm ứng $formattedAmount. Nhấn để duyệt.',
          'type': 'advance_request',
          'createdAt': Timestamp.now(),
          'targetRoles': ['owner', 'manager_1', 'manager', 'legacyManager'],
          'readBy': [],
          'routePath': '/manage-advances',
          'routeExtra': {'storeId': request.storeId, 'advanceId': request.id},
        });
      } catch (_) {}
    } catch (e) {
      throw Exception('Failed to create advance request: $e');
    }
  }

  Future<void> updateAdvanceRequestStatus(
      String storeId, String advanceId, AdvanceStatus status,
      [DateTime? approvedDate]) async {
    try {
      final updateData = <String, dynamic>{
        'status': status.name,
      };
      if (approvedDate != null) {
        updateData['approvedDate'] = approvedDate.toIso8601String();
      }
      await _stores
          .doc(storeId)
          .collection('advances')
          .doc(advanceId)
          .update(updateData);

      // Create notification for Employee
      try {
        final advanceDoc = await _stores
            .doc(storeId)
            .collection('advances')
            .doc(advanceId)
            .get();
        final userId = advanceDoc.data()?['userId'] as String?;
        final amount = advanceDoc.data()?['amount'] as num? ?? 0;
        final formattedAmount =
            '${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}đ';

        if (userId != null && userId.isNotEmpty) {
          final isApproved = status == AdvanceStatus.approved;
          await _firestore
              .collection('stores')
              .doc(storeId)
              .collection('notifications')
              .add({
            'storeId': storeId,
            'title': isApproved
                ? 'Yêu cầu ứng lương đã được duyệt'
                : 'Yêu cầu ứng lương bị từ chối',
            'body': isApproved
                ? 'Chủ quán đã duyệt yêu cầu tạm ứng $formattedAmount của bạn.'
                : 'Yêu cầu tạm ứng $formattedAmount của bạn đã bị từ chối.',
            'type': isApproved ? 'advance_approved' : 'advance_rejected',
            'createdAt': Timestamp.now(),
            'targetUserId': userId,
            'readBy': [],
            'routePath': '/salary',
            'routeExtra': {'storeId': storeId, 'advanceId': advanceId},
          });
        }
      } catch (_) {}
    } catch (e) {
      throw Exception('Failed to update advance request: $e');
    }
  }
}
