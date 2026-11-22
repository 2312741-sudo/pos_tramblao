import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/features/notifications/repositories/notification_repository.dart';
import 'package:tram_flutter/chamcong_blao/models/member_model.dart';
import 'package:tram_flutter/chamcong_blao/models/app_notification_model.dart';
void main() {
  test('unresolved membership has no store inbox scope', () {
    expect(NotificationRepository.scopes(null), isEmpty);
  });
  test('manager2 cannot subscribe to attendance, approvals or salary requests', () {
    expect(NotificationRepository.scopes(UserRole.manager2), ['member']);
    expect(NotificationRepository.scopes(UserRole.manager1), ['member', 'approver', 'attendance']);
    expect(NotificationRepository.scopes(UserRole.owner), ['member', 'approver', 'attendance', 'owner']);
  });
  test('attendance preference changes both list and unread query scopes', () {
    expect(NotificationRepository.scopes(UserRole.owner, notifyShiftInOut: false), ['member', 'approver', 'owner']);
  });
  test('legacy notification metadata cannot grant manager2 attendance access', () {
    final item = AppNotificationModel(id: 'n', storeId: 's', title: '', body: '',
      type: AppNotificationType.checkIn, createdAt: DateTime(2026), targetUserId: 'm2');
    expect(item.isRelevantFor('m2', UserRole.manager2), isFalse);
    expect(item.isRelevantFor(null, null), isFalse);
  });
  test('anonymous identity cannot receive legacy broadcasts', () {
    final item = AppNotificationModel(id: 'n', storeId: 's', title: '', body: '',
      type: AppNotificationType.birthday, createdAt: DateTime(2026));
    expect(item.isRelevantFor(null, UserRole.employee), isFalse);
    expect(item.isRelevantFor('user', null), isFalse);
  });

  test('legacy member with null status resolves to active', () {
    expect(MemberStatusExtension.fromString(null), MemberStatus.active);
    expect(MemberStatusExtension.fromString('active'), MemberStatus.active);
    expect(MemberStatusExtension.fromString('kicked'), MemberStatus.kicked);
    expect(MemberStatusExtension.fromString('pending'), MemberStatus.pending);
  });

  test('watchNotifications with empty or null userId returns empty stream without error', () async {
    final repo = NotificationRepository();
    final streamNull = repo.watchNotifications('store_1', null, UserRole.employee);
    expect(await streamNull.first, isEmpty);

    final streamEmpty = repo.watchNotifications('store_1', '', UserRole.employee);
    expect(await streamEmpty.first, isEmpty);
  });
}
