import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/auth_repository.dart';
import '../../../models/user_model.dart';
import '../../../cc_firebase.dart';

// ── Repository Provider ───────────────────────────────────────────────────────

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

// ── Auth State Stream Provider ────────────────────────────────────────────────

final authStateChangesProvider = StreamProvider<User?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges;
});

// ── Current Firebase User Provider ───────────────────────────────────────────

final currentFirebaseUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  return authState.whenOrNull(data: (user) => user) ?? CcFirebase.auth.currentUser;
});

// ── Current User ID Provider ──────────────────────────────────────────────────

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentFirebaseUserProvider)?.uid;
});

// ── Current UserModel Stream Provider ────────────────────────────────────────

final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(null);

  final repo = ref.watch(authRepositoryProvider);
  return repo.watchUserDocument(uid);
});

// ── Is Authenticated Provider ─────────────────────────────────────────────────

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentFirebaseUserProvider) != null;
});

// ── User Profile Completion Provider ─────────────────────────────────────────

final isProfileCompleteProvider = Provider<bool>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  return userAsync.whenOrNull(
        data: (user) => user != null && user.name.isNotEmpty,
      ) ??
      false;
});
