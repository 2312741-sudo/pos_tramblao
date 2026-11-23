import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../models/user_model.dart';
import '../../../cc_firebase.dart';

class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  AuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _auth = auth ?? CcFirebase.auth,
        _firestore = firestore ?? CcFirebase.firestore,
        _storage = storage ?? CcFirebase.storage;

  // ── Auth State ────────────────────────────────────────────────────────────

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  String? get currentUserId => _auth.currentUser?.uid;

  // ── Sign In ───────────────────────────────────────────────────────────────

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  // ── Google Sign In ────────────────────────────────────────────────────────

  Future<UserCredential> signInWithGoogle() async {
    try {
      UserCredential userCredential;
      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        userCredential = await _auth.signInWithPopup(googleProvider);
      } else {
        final googleSignIn = GoogleSignIn();
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          throw FirebaseAuthException(
            code: 'cancelled',
            message: 'Người dùng đã hủy đăng nhập Google',
          );
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        userCredential = await _auth.signInWithCredential(credential);
      }
      await _ensureFirestoreUserExists(userCredential.user);
      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'web-context-cancelled' ||
          e.code == 'cancelled' ||
          e.code == 'user-cancelled' ||
          e.code == 'canceled') {
        throw FirebaseAuthException(
          code: 'cancelled',
          message: 'Người dùng đã hủy đăng nhập Google',
        );
      }
      rethrow;
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('sign_in_canceled') ||
          errorStr.contains('canceled') ||
          errorStr.contains('cancelled') ||
          errorStr.contains('user-cancelled')) {
        throw FirebaseAuthException(
          code: 'cancelled',
          message: 'Người dùng đã hủy đăng nhập Google',
        );
      }
      throw FirebaseAuthException(
        code: 'google-sign-in-failed',
        message: 'Lỗi đăng nhập Google: $e',
      );
    }
  }

  // ── Apple Sign In ─────────────────────────────────────────────────────────

  Future<UserCredential> signInWithApple() async {
    try {
      final appleProvider = AppleAuthProvider();
      appleProvider.addScope('email');
      appleProvider.addScope('name');

      UserCredential userCredential;
      if (kIsWeb) {
        userCredential = await _auth.signInWithPopup(appleProvider);
      } else {
        userCredential = await _auth.signInWithProvider(appleProvider);
      }
      await _ensureFirestoreUserExists(userCredential.user);
      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'web-context-cancelled' ||
          e.code == 'cancelled' ||
          e.code == 'user-cancelled' ||
          e.code == 'canceled') {
        throw FirebaseAuthException(
          code: 'cancelled',
          message: 'Người dùng đã hủy đăng nhập Apple',
        );
      }
      rethrow;
    } catch (e) {
      throw FirebaseAuthException(
        code: 'apple-sign-in-failed',
        message: 'Lỗi đăng nhập Apple: $e',
      );
    }
  }

  Future<void> _ensureFirestoreUserExists(User? user, {String? fallbackName}) async {
    if (user == null) return;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      final name = fallbackName ?? (user.displayName != null && user.displayName!.isNotEmpty ? user.displayName! : 'Người dùng');
      if (user.displayName == null && fallbackName != null) {
        try {
          await user.updateDisplayName(fallbackName);
        } catch (_) {}
      }
      final userModel = UserModel(
        id: user.uid,
        name: name,
        email: user.email ?? '',
        avatarUrl: user.photoURL,
        createdAt: DateTime.now().toUtc(),
      );
      await createUserDocument(userModel);
    } else {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final existingAvatar = data['avatarUrl'] as String?;
      if ((existingAvatar == null || existingAvatar.trim().isEmpty) &&
          user.photoURL != null &&
          user.photoURL!.trim().isNotEmpty) {
        try {
          await _firestore.collection('users').doc(user.uid).update({
            'avatarUrl': user.photoURL,
          });
        } catch (_) {}
      }
    }
  }

  // ── Register ──────────────────────────────────────────────────────────────

  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  // ── Sign Out (chỉ đóng mô-đun về POS, KHÔNG đăng xuất Firebase Auth của POS) ─

  Future<void> signOut() async {
    CcFirebase.exitModule();
  }

  // ── Profile Update ────────────────────────────────────────────────────────

  Future<void> updateFirebaseProfile({
    String? displayName,
    String? photoURL,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        if (displayName != null && displayName.isNotEmpty) {
          await user.updateDisplayName(displayName);
        }
        if (photoURL != null && photoURL.isNotEmpty) {
          await user.updatePhotoURL(photoURL);
        }
      }
    } catch (_) {
      // Ignored: Non-fatal Firebase Auth profile cache error
    }
  }

  /// Uploads user avatar image bytes to Firebase Storage and syncs URL to user & members docs
  Future<String> uploadAvatar({
    required String uid,
    required Uint8List imageBytes,
    String? currentStoreId,
  }) async {
    try {
      final ref = _storage.ref().child('avatars').child('$uid.jpg');
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'uploadedBy': uid, 'updatedAt': DateTime.now().toIso8601String()},
      );
      
      final uploadTask = await ref.putData(imageBytes, metadata);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      // 1. Update Firestore /users/{uid}
      await updateUserDocument(uid: uid, data: {'avatarUrl': downloadUrl});

      // 2. Update Firebase Auth photoURL
      await updateFirebaseProfile(photoURL: downloadUrl);

      // 3. Real-time sync to all store members subcollections
      try {
        final userDoc = await getUserDocument(uid);
        final storeIds = <String>{};
        if (currentStoreId != null && currentStoreId.isNotEmpty) {
          storeIds.add(currentStoreId);
        }
        if (userDoc != null) {
          if (userDoc.currentStoreId != null && userDoc.currentStoreId!.isNotEmpty) {
            storeIds.add(userDoc.currentStoreId!);
          }
          storeIds.addAll(userDoc.storeIds);
        }

        // Fallback discovery: tìm thêm stores qua collectionGroup
        try {
          final mDocs = await _firestore
              .collectionGroup('members')
              .where('userId', isEqualTo: uid)
              .get();
          for (final doc in mDocs.docs) {
            final storeRef = doc.reference.parent.parent;
            if (storeRef != null && storeRef.id.isNotEmpty) {
              storeIds.add(storeRef.id);
            }
          }
        } catch (_) {}

        for (final sId in storeIds) {

          final memberRef = _firestore.collection('stores').doc(sId).collection('members').doc(uid);
          final mDoc = await memberRef.get();
          if (mDoc.exists) {
            await memberRef.update({'avatarUrl': downloadUrl});
          }
        }
      } catch (_) {}

      return downloadUrl;
    } catch (e) {
      throw Exception('Tải lên ảnh đại diện thất bại: $e');
    }
  }

  Future<void> updateUserProfile({
    required String uid,
    required String name,
    String? phone,
    String? avatarUrl,
    DateTime? birthday,
    String? currentStoreId,
  }) async {
    final updateData = <String, dynamic>{
      'name': name.trim(),
    };
    if (phone != null) updateData['phone'] = phone.trim();
    if (avatarUrl != null) updateData['avatarUrl'] = avatarUrl.trim();
    if (birthday != null) {
      updateData['birthday'] = birthday.toIso8601String();
    }

    // 1. Update main Firestore user doc
    await updateUserDocument(uid: uid, data: updateData);

    // 2. Best-effort update Firebase Auth display name & photoURL (never throws)
    await updateFirebaseProfile(
      displayName: name.trim(),
      photoURL: avatarUrl?.trim(),
    );

    // 3. Sync name, phone, avatarUrl, birthday to store members subcollections
    try {
      final userDoc = await getUserDocument(uid);
      final storeIds = <String>{};
      if (currentStoreId != null && currentStoreId.isNotEmpty) {
        storeIds.add(currentStoreId);
      }
      if (userDoc != null) {
        if (userDoc.currentStoreId != null && userDoc.currentStoreId!.isNotEmpty) {
          storeIds.add(userDoc.currentStoreId!);
        }
        storeIds.addAll(userDoc.storeIds);
      }

      // Fallback discovery: tìm thêm stores qua collectionGroup
      try {
        final mDocs = await _firestore
            .collectionGroup('members')
            .where('userId', isEqualTo: uid)
            .get();
        for (final doc in mDocs.docs) {
          final storeRef = doc.reference.parent.parent;
          if (storeRef != null && storeRef.id.isNotEmpty) {
            storeIds.add(storeRef.id);
          }
        }
      } catch (_) {}

      for (final sId in storeIds) {
        final memberRef = _firestore.collection('stores').doc(sId).collection('members').doc(uid);
        final mDoc = await memberRef.get();
        if (mDoc.exists) {
          final memberUpdate = <String, dynamic>{'name': name.trim()};
          if (phone != null) memberUpdate['phone'] = phone.trim();
          if (avatarUrl != null) memberUpdate['avatarUrl'] = avatarUrl.trim();
          if (birthday != null) memberUpdate['birthday'] = birthday.toIso8601String();
          await memberRef.update(memberUpdate);
        }
      }
    } catch (_) {}
  }

  // ── Firestore User Doc ────────────────────────────────────────────────────

  Future<void> createUserDocument(UserModel user) async {
    await _firestore.collection('users').doc(user.id).set(user.toJson());
  }

  Future<void> updateUserDocument({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    await _firestore.collection('users').doc(uid).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<UserModel?> getUserDocument(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromJson(doc.data()!, doc.id);
  }

  Stream<UserModel?> watchUserDocument(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return UserModel.fromJson(doc.data()!, doc.id);
    });
  }

  // ── Password Reset / Change Password / Delete Account (quản lý qua POS) ───

  Future<void> sendPasswordResetEmail(String email) async {
    throw Exception('Tài khoản dùng chung với hệ thống POS. Liên hệ Chủ quán để đặt lại mật khẩu trên POS.');
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    throw Exception('Tài khoản dùng chung với hệ thống POS. Vui lòng đổi mật khẩu tại màn hình POS.');
  }

  Future<void> deleteAccount({String? password}) async {
    throw Exception('Tài khoản dùng chung với hệ thống POS. Vui lòng quản lý tài khoản tại màn hình POS.');
  }

  // ── Error Handling Helper ─────────────────────────────────────────────────

  static String parseFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Tài khoản không tồn tại';
      case 'wrong-password':
        return 'Mật khẩu không đúng';
      case 'invalid-credential':
        return 'Email hoặc mật khẩu không đúng';
      case 'email-already-in-use':
        return 'Email này đã được sử dụng';
      case 'weak-password':
        return 'Mật khẩu phải có ít nhất 6 ký tự';
      case 'missing-email':
        return 'Vui lòng nhập địa chỉ email';
      case 'invalid-email':
        return 'Địa chỉ email không hợp lệ';
      case 'network-request-failed':
        return 'Lỗi kết nối mạng, vui lòng thử lại';
      case 'too-many-requests':
        return 'Quá nhiều lần thử. Vui lòng thử lại sau';
      case 'user-disabled':
        return 'Tài khoản đã bị vô hiệu hóa';
      case 'requires-recent-login':
        return 'Vui lòng đăng nhập lại để thực hiện thao tác này';
      case 'google-sign-in-failed':
        return 'Đăng nhập bằng Google không thành công. Vui lòng kiểm tra lại kết nối mạng hoặc thử lại sau.';
      default:
        return 'Có lỗi xảy ra: ${e.message}';
    }
  }
}
