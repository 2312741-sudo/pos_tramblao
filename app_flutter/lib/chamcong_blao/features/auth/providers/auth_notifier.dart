import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/auth_repository.dart';
import '../../../models/user_model.dart';
import '../../../core/services/notification_service.dart';
import 'auth_provider.dart';
import '../../store/providers/store_provider.dart';
import '../../../cc_firebase.dart';

// ── Auth Action State ─────────────────────────────────────────────────────────

class AuthState {
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const AuthState({
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  AuthState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }

  bool get hasError => errorMessage != null;
  bool get hasSuccess => successMessage != null;
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final Ref _ref;

  AuthNotifier(this._repository, this._ref) : super(const AuthState());

  void _invalidateAllUserData() {
    _ref.invalidate(currentUserProvider);
    _ref.invalidate(currentFirebaseUserProvider);
    _ref.invalidate(currentUserIdProvider);
    _ref.invalidate(userStoresProvider);
    _ref.invalidate(currentStoreProvider);
    _ref.invalidate(storeMembersProvider);
    _ref.invalidate(currentMemberStreamProvider);
  }

  // ── Sign In ─────────────────────────────────────────────────────────────

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      await _repository.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      _invalidateAllUserData();
      
      // Update FCM token in background without blocking login
      final user = CcFirebase.auth.currentUser;
      if (user != null) {
        unawaited(NotificationService().saveTokenForUser(user.uid).catchError((_) {}));
      }

      state = state.copyWith(
        isLoading: false,
        successMessage: 'Đăng nhập thành công',
      );
      return true;
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: AuthRepository.parseFirebaseAuthError(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Có lỗi xảy ra, vui lòng thử lại',
      );
      return false;
    }
  }

  // ── Google Sign In ────────────────────────────────────────────────────────

  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      await _repository.signInWithGoogle();

      _invalidateAllUserData();

      final user = CcFirebase.auth.currentUser;
      if (user != null) {
        unawaited(NotificationService().saveTokenForUser(user.uid).catchError((_) {}));
      }

      state = state.copyWith(
        isLoading: false,
        successMessage: 'Đăng nhập Google thành công',
      );
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'cancelled') {
        state = state.copyWith(isLoading: false);
        return false;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: AuthRepository.parseFirebaseAuthError(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể đăng nhập Google: $e',
      );
      return false;
    }
  }

  // ── Apple Sign In ─────────────────────────────────────────────────────────

  Future<bool> signInWithApple() async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      await _repository.signInWithApple();

      _invalidateAllUserData();

      final user = CcFirebase.auth.currentUser;
      if (user != null) {
        unawaited(NotificationService().saveTokenForUser(user.uid).catchError((_) {}));
      }

      state = state.copyWith(
        isLoading: false,
        successMessage: 'Đăng nhập Apple thành công',
      );
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'cancelled') {
        state = state.copyWith(isLoading: false);
        return false;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: AuthRepository.parseFirebaseAuthError(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể đăng nhập Apple: $e',
      );
      return false;
    }
  }

  // ── Register ────────────────────────────────────────────────────────────

  Future<bool> register({
    required String email,
    required String password,
    required String name,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      final credential = await _repository.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Không thể tạo tài khoản, vui lòng thử lại',
        );
        return false;
      }

      // Update Firebase display name
      await _repository.updateFirebaseProfile(displayName: name);

      // Create Firestore user document
      final userModel = UserModel(
        id: credential.user!.uid,
        name: name,
        email: email,
        createdAt: DateTime.now().toUtc(),
      );
      await _repository.createUserDocument(userModel);

      _invalidateAllUserData();

      // Update FCM token in background
      final currentUser = CcFirebase.auth.currentUser;
      if (currentUser != null) {
        unawaited(NotificationService().saveTokenForUser(currentUser.uid).catchError((_) {}));
      }

      state = state.copyWith(
        isLoading: false,
        successMessage: 'Đăng ký thành công',
      );
      return true;
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: AuthRepository.parseFirebaseAuthError(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Có lỗi xảy ra, vui lòng thử lại',
      );
      return false;
    }
  }

  // ── Đóng mô-đun (quay về POS, KHÔNG đăng xuất tài khoản POS) ──────────

  Future<void> signOut() async {
    _invalidateAllUserData();
    state = const AuthState();
    CcFirebase.exitModule();
  }

  // ── Update Profile ──────────────────────────────────────────────────────

  Future<bool> updateProfile({
    required String uid,
    required String name,
    String? phone,
    String? avatarUrl,
    DateTime? birthday,
    String? currentStoreId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      await _repository.updateUserProfile(
        uid: uid,
        name: name,
        phone: phone,
        avatarUrl: avatarUrl,
        birthday: birthday,
        currentStoreId: currentStoreId,
      );

      _invalidateAllUserData();

      state = state.copyWith(
        isLoading: false,
        successMessage: 'Cập nhật hồ sơ thành công',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Có lỗi khi cập nhật hồ sơ: $e',
      );
      return false;
    }
  }

  // ── Upload Avatar ───────────────────────────────────────────────────────

  Future<String?> uploadAvatar({
    required String uid,
    required Uint8List imageBytes,
    String? currentStoreId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      final downloadUrl = await _repository.uploadAvatar(
        uid: uid,
        imageBytes: imageBytes,
        currentStoreId: currentStoreId,
      );

      _invalidateAllUserData();

      state = state.copyWith(
        isLoading: false,
        successMessage: 'Cập nhật ảnh đại diện thành công',
      );
      return downloadUrl;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể tải lên ảnh đại diện: $e',
      );
      return null;
    }
  }

  // ── Send Password Reset ─────────────────────────────────────────────────

  Future<bool> sendPasswordResetEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Vui lòng nhập địa chỉ email',
      );
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      await _repository.sendPasswordResetEmail(cleanEmail);
      state = state.copyWith(
        isLoading: false,
        successMessage: 'Email đặt lại mật khẩu đã được gửi',
      );
      return true;
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: AuthRepository.parseFirebaseAuthError(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Có lỗi xảy ra, vui lòng thử lại',
      );
      return false;
    }
  }

  // ── Delete Account ──────────────────────────────────────────────────────

  Future<bool> deleteAccount({String? password}) async {
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);
    try {
      await _repository.deleteAccount(password: password);
      state = state.copyWith(
        isLoading: false,
        successMessage: 'Tài khoản đã được xóa thành công',
      );
      return true;
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: AuthRepository.parseFirebaseAuthError(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Có lỗi khi xóa tài khoản: $e',
      );
      return false;
    }
  }

  // ── Clear Error/Success ─────────────────────────────────────────────────

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void clearSuccess() {
    state = state.copyWith(clearSuccess: true);
  }
}

// ── Auth Notifier Provider ────────────────────────────────────────────────────

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthNotifier(repo, ref);
});
