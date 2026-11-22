import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/store_model.dart';
import '../../../models/member_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../repositories/store_repository.dart';
import '../../../models/advance_request_model.dart';
import '../../../cc_firebase.dart';

// ---------- Repository Provider ----------

final storeRepositoryProvider = Provider<StoreRepository>((ref) {
  return StoreRepository();
});

// ---------- Current Store ----------

final currentStoreIdProvider = Provider<String?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return null;

  final stores = ref.watch(userStoresProvider).valueOrNull;
  final validStoreIds = stores?.map((s) => s.id).toSet();

  // 1. If currentStoreId is set, verify it is not explicitly revoked/kicked
  if (user.currentStoreId != null && user.currentStoreId!.isNotEmpty) {
    final cur = user.currentStoreId!;
    // If stores list has loaded and has items, check if cur is in either storeIds or stores list
    if (validStoreIds != null && validStoreIds.isNotEmpty) {
      if (validStoreIds.contains(cur) || user.storeIds.contains(cur)) {
        return cur;
      }
      // If store was deleted or kicked, cur is invalid -> will fallback below
    } else {
      // Stores list not loaded yet: trust currentStoreId immediately
      return cur;
    }
  }

  // 2. Fallback to first available store in loaded stores list
  if (stores != null && stores.isNotEmpty) {
    return stores.first.id;
  }

  // 3. Fallback to user.storeIds if available
  if (user.storeIds.isNotEmpty) {
    return user.storeIds.first;
  }

  return null;
});

final currentStoreProvider = StreamProvider<StoreModel?>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return Stream.value(null);
  final repo = ref.watch(storeRepositoryProvider);
  return repo.watchStore(storeId);
});

final userStoresProvider = StreamProvider<List<StoreModel>>((ref) async* {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    yield [];
    return;
  }
  // Re-evaluate automatically when user document changes
  ref.watch(currentUserProvider);
  final repo = ref.watch(storeRepositoryProvider);
  final stores = await repo.getUserStores(uid);
  yield stores;
});

// ---------- Members ----------

final storeMembersProvider = StreamProvider<List<MemberModel>>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return Stream.value([]);
  final repo = ref.watch(storeRepositoryProvider);
  return repo.watchMembers(storeId);
});

final pendingMembersProvider = StreamProvider<List<MemberModel>>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return Stream.value([]);
  final repo = ref.watch(storeRepositoryProvider);
  return repo.watchPendingMembers(storeId);
});

final activeMembersProvider = Provider<List<MemberModel>>((ref) {
  final membersAsync = ref.watch(storeMembersProvider);
  final store = ref.watch(currentStoreProvider).valueOrNull;
  final rawList = membersAsync.whenOrNull(
        data: (members) =>
            members.where((m) => m.status == MemberStatus.active).toList(),
      ) ??
      [];

  // Deduplicate by userId (guard against stream race conditions or corrupt memberOrder)
  final seen = <String>{};
  final list = rawList.where((m) => seen.add(m.userId)).toList();

  if (store != null && store.memberOrder.isNotEmpty) {
    list.sort((a, b) {
      final idxA = store.memberOrder.indexOf(a.userId);
      final idxB = store.memberOrder.indexOf(b.userId);
      if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
      if (idxA != -1) return -1;
      if (idxB != -1) return 1;
      return a.name.compareTo(b.name);
    });
  }
  return list;
});

/// Background ghost-member cleanup provider.
/// Chạy tự động mỗi khi storeId thay đổi (= mỗi khi mở cửa hàng khác
/// hoặc mở màn hình nhân viên lần đầu).
/// Phát hiện và kick bất kỳ member nào có status='active' nhưng
/// /users/{uid} đã bị xóa (bị xóa từ Firebase Console hoặc tự xóa TK cũ).
/// Widget chỉ cần `ref.watch(ghostMemberCleanupProvider)` — không cần xử lý kết quả.
final ghostMemberCleanupProvider = FutureProvider.autoDispose<int>((ref) async {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return 0;
  final repo = ref.read(storeRepositoryProvider);
  // Chạy background, không block UI — lỗi đã được swallow bên trong hàm
  return repo.cleanupGhostMembers(storeId);
});


final currentMemberStreamProvider = StreamProvider<MemberModel?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  final storeId = ref.watch(currentStoreIdProvider);
  if (uid == null || storeId == null || storeId.isEmpty) {
    return Stream.value(null);
  }
  return CcFirebase.firestore
      .collection('stores')
      .doc(storeId)
      .collection('members')
      .doc(uid)
      .snapshots()
      .map((snap) {
    if (!snap.exists || snap.data() == null) return null;
    return MemberModel.fromFirestore(snap);
  });
});

/// Provider cung cấp thông tin thành viên hiện tại của cửa hàng đang chọn.
/// ÁP DỤNG TRUTH RECONCILIATION:
/// - Đối chiếu trực tiếp với `store.ownerId` để chống lỗi lưu quyền cũ.
/// - Nếu `store.ownerId == uid` -> luôn đảm bảo role = owner (kể cả khi subcollection chậm cập nhật).
/// - Nếu `store.ownerId != uid` mà role trong cache còn là owner -> lập tức hạ xuống manager1,
///   triệt tiêu hoàn toàn lỗ hổng giữ quyền Chủ cũ.
final currentMemberProvider = Provider<MemberModel?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  final storeId = ref.watch(currentStoreIdProvider);
  if (uid == null || storeId == null || storeId.isEmpty) return null;

  final currentStore = ref.watch(currentStoreProvider).valueOrNull;

  // Lấy member từ stream trực tiếp
  final directMemberAsync = ref.watch(currentMemberStreamProvider);
  MemberModel? member = directMemberAsync.valueOrNull;

  // Fallback sang storeMembersProvider nếu stream trực tiếp chưa kịp phát
  if (member == null) {
    final members = ref.watch(storeMembersProvider).valueOrNull;
    if (members != null) {
      try {
        member = members.firstWhere((m) => m.userId == uid);
      } catch (_) {
        member = null;
      }
    }
  }

  // ── TRUTH RECONCILIATION ──────────────────────────────────────────────
  if (currentStore != null) {
    final isStoreOwner = currentStore.isOwnerUid(uid);
    if (member != null) {
      if (member.role == UserRole.owner) {
        // User không còn là chủ trong store doc nhưng member doc còn lưu 'owner'
        // -> Triệt tiêu quyền Owner cũ ngay lập tức, hạ xuống manager1
        if (!isStoreOwner) {
          member = member.copyWith(role: UserRole.manager1);
        }
      }
      // Nếu member.role rõ ràng là manager1, manager2, employee -> TÔN TRỌNG VAI TRÒ ĐÓ
    } else if (isStoreOwner) {
      // Document member chưa tải xong nhưng chắc chắn là chủ cửa hàng tạo store
      final user = ref.watch(currentUserProvider).valueOrNull;
      member = MemberModel(
        userId: uid,
        name: user?.name ?? 'Chủ cửa hàng',
        role: UserRole.owner,
        status: MemberStatus.active,
        employeeType: EmployeeType.fulltime,
        joinedAt: currentStore.createdAt,
      );
    }
  }

  return member;
});


// ---------- Advances ----------

final storeAdvancesProvider = StreamProvider.family<List<AdvanceRequestModel>, String>((ref, month) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null || storeId.isEmpty) return Stream.value([]);
  final repo = ref.watch(storeRepositoryProvider);
  return repo.watchAdvances(storeId, month);
});

final myAdvancesProvider = Provider.family<List<AdvanceRequestModel>, String>((ref, month) {
  final advancesAsync = ref.watch(storeAdvancesProvider(month));
  final uid = CcFirebase.auth.currentUser?.uid;
  if (uid == null) return [];
  return advancesAsync.whenOrNull(
    data: (list) => list.where((a) => a.userId == uid).toList(),
  ) ?? [];
});

final userAdvancesProvider = Provider.family<List<AdvanceRequestModel>, ({String userId, String month})>((ref, args) {
  final advancesAsync = ref.watch(storeAdvancesProvider(args.month));
  return advancesAsync.whenOrNull(
    data: (list) => list.where((a) => a.userId == args.userId).toList(),
  ) ?? [];
});

