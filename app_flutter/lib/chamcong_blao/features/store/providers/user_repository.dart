import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/user_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../cc_firebase.dart';

class UserRepository {
  final FirebaseFirestore _firestore;

  UserRepository({
    FirebaseFirestore? firestore,
  })  : _firestore = firestore ?? CcFirebase.firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Future<UserModel?> getUser(String userId) async {
    try {
      final doc = await _users.doc(userId).get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
    } catch (e) {
      throw Exception('Lấy thông tin người dùng thất bại: $e');
    }
  }

  Stream<UserModel?> watchUser(String userId) {
    return _users.doc(userId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return UserModel.fromFirestore(snap);
    });
  }

  Future<void> createOrUpdateUser(UserModel user) async {
    try {
      await _users.doc(user.id).set(user.toJson(), SetOptions(merge: true));
    } catch (e) {
      throw Exception('Lưu thông tin người dùng thất bại: $e');
    }
  }

  Future<void> updateCurrentStoreId(String userId, String? storeId) async {
    try {
      final updateData = <String, dynamic>{'currentStoreId': storeId};
      if (storeId != null && storeId.isNotEmpty) {
        updateData['storeIds'] = FieldValue.arrayUnion([storeId]);
      }
      await _users.doc(userId).update(updateData);
    } catch (e) {
      throw Exception('Cập nhật cửa hàng thất bại: $e');
    }
  }

  Future<void> updateNotifyShiftInOut(String userId, bool enabled) async {
    try {
      await _users.doc(userId).update({'notifyShiftInOut': enabled});
    } catch (e) {
      throw Exception('Cập nhật cài đặt thông báo thất bại: $e');
    }
  }
}

// ---------- Providers ----------

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});

/// Re-export / unified user stream provider
final userProvider = currentUserProvider;

/// Re-export / unified auth state stream provider
final authStateProvider = authStateChangesProvider;

