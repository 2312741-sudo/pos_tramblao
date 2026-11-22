import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/models/user_model.dart';
import 'package:tram_flutter/chamcong_blao/models/member_model.dart';
import 'package:tram_flutter/chamcong_blao/features/auth/repositories/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() {
  group('UserModel with Birthday & Avatar Tests', () {
    test('UserModel serialize and deserialize with birthday', () {
      final birthday = DateTime(1998, 5, 20);
      final user = UserModel(
        id: 'user_123',
        name: 'Nguyen Van A',
        email: 'vana@example.com',
        phone: '0987654321',
        avatarUrl: 'https://example.com/avatar.jpg',
        birthday: birthday,
        currentStoreId: 'store_001',
        storeIds: const ['store_001', 'store_002'],
        createdAt: DateTime(2026, 1, 1),
      );

      final json = user.toJson();
      expect(json['id'], 'user_123');
      expect(json['name'], 'Nguyen Van A');
      expect(json['phone'], '0987654321');
      expect(json['avatarUrl'], 'https://example.com/avatar.jpg');
      expect(json['birthday'], birthday.toIso8601String());

      final fromJson = UserModel.fromJson(json, 'user_123');
      expect(fromJson.id, 'user_123');
      expect(fromJson.name, 'Nguyen Van A');
      expect(fromJson.phone, '0987654321');
      expect(fromJson.avatarUrl, 'https://example.com/avatar.jpg');
      expect(fromJson.birthday, birthday);
      expect(fromJson.hasStore, isTrue);
    });

    test('UserModel copyWith updates birthday and avatarUrl', () {
      final initialUser = UserModel(
        id: 'user_123',
        name: 'Nguyen Van A',
        email: 'vana@example.com',
        createdAt: DateTime(2026, 1, 1),
      );

      final updatedUser = initialUser.copyWith(
        name: 'Nguyen Van B',
        phone: '0901234567',
        birthday: DateTime(2000, 12, 25),
        avatarUrl: 'https://cdn.example.com/new_avatar.png',
      );

      expect(updatedUser.name, 'Nguyen Van B');
      expect(updatedUser.phone, '0901234567');
      expect(updatedUser.birthday, DateTime(2000, 12, 25));
      expect(updatedUser.avatarUrl, 'https://cdn.example.com/new_avatar.png');
      expect(updatedUser.email, initialUser.email);
    });

    test('MemberModel serialize and deserialize with birthday', () {
      final birthday = DateTime(1995, 10, 15);
      final member = MemberModel(
        userId: 'm1',
        name: 'Tran Thi B',
        role: UserRole.employee,
        status: MemberStatus.active,
        employeeType: EmployeeType.fulltime,
        joinedAt: DateTime(2026, 1, 1),
        birthday: birthday,
      );

      final json = member.toJson();
      expect(json['birthday'], birthday.toIso8601String());

      final fromJson = MemberModel.fromJson(json, 'm1');
      expect(fromJson.birthday, birthday);
      expect(fromJson.name, 'Tran Thi B');
    });
  });

  group('AuthRepository Error Parsing Tests', () {
    test('Correctly maps firebase auth error codes to Vietnamese messages', () {
      expect(
        AuthRepository.parseFirebaseAuthError(FirebaseAuthException(code: 'user-not-found')),
        'Tài khoản không tồn tại',
      );
      expect(
        AuthRepository.parseFirebaseAuthError(FirebaseAuthException(code: 'wrong-password')),
        'Mật khẩu không đúng',
      );
      expect(
        AuthRepository.parseFirebaseAuthError(FirebaseAuthException(code: 'email-already-in-use')),
        'Email này đã được sử dụng',
      );
      expect(
        AuthRepository.parseFirebaseAuthError(FirebaseAuthException(code: 'weak-password')),
        'Mật khẩu phải có ít nhất 6 ký tự',
      );
      expect(
        AuthRepository.parseFirebaseAuthError(FirebaseAuthException(code: 'invalid-email')),
        'Địa chỉ email không hợp lệ',
      );
      expect(
        AuthRepository.parseFirebaseAuthError(FirebaseAuthException(code: 'missing-email')),
        'Vui lòng nhập địa chỉ email',
      );
    });
  });
}
