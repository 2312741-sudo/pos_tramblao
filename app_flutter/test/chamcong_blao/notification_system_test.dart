import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/chamcong_blao/models/app_notification_model.dart';
import 'package:tram_flutter/chamcong_blao/models/member_model.dart';

void main() {
  group('AppNotificationModel & Notification System Tests', () {
    test('AppNotificationType parsing from string and to string', () {
      expect(AppNotificationTypeExtension.fromString('join_request'), equals(AppNotificationType.joinRequest));
      expect(AppNotificationTypeExtension.fromString('join_approved'), equals(AppNotificationType.joinApproved));
      expect(AppNotificationTypeExtension.fromString('join_rejected'), equals(AppNotificationType.joinRejected));
      expect(AppNotificationTypeExtension.fromString('schedule_changed'), equals(AppNotificationType.scheduleChanged));
      expect(AppNotificationTypeExtension.fromString('schedule_registration_reminder'), equals(AppNotificationType.scheduleRegistrationReminder));
      expect(AppNotificationTypeExtension.fromString('checklist_reminder'), equals(AppNotificationType.checklistReminder));
      expect(AppNotificationTypeExtension.fromString('delivery_update'), equals(AppNotificationType.deliveryUpdate));
      expect(AppNotificationTypeExtension.fromString('birthday'), equals(AppNotificationType.birthday));
      expect(AppNotificationTypeExtension.fromString('general'), equals(AppNotificationType.general));
      expect(AppNotificationTypeExtension.fromString('unknown'), equals(AppNotificationType.general));

      expect(AppNotificationType.joinRequest.value, equals('join_request'));
      expect(AppNotificationType.joinApproved.value, equals('join_approved'));
      expect(AppNotificationType.joinRejected.value, equals('join_rejected'));
      expect(AppNotificationType.scheduleChanged.value, equals('schedule_changed'));
      expect(AppNotificationType.scheduleRegistrationReminder.value, equals('schedule_registration_reminder'));
      expect(AppNotificationType.checklistReminder.value, equals('checklist_reminder'));
      expect(AppNotificationType.deliveryUpdate.value, equals('delivery_update'));
      expect(AppNotificationType.birthday.value, equals('birthday'));
      expect(AppNotificationType.general.value, equals('general'));
    });

    test('isReadByUser checks readBy list correctly', () {
      final notif = AppNotificationModel(
        id: 'n1',
        storeId: 's1',
        title: 'Thông báo',
        body: 'Nội dung',
        type: AppNotificationType.general,
        createdAt: DateTime.now(),
        readBy: ['user_1', 'user_2'],
      );

      expect(notif.isReadByUser('user_1'), isTrue);
      expect(notif.isReadByUser('user_2'), isTrue);
      expect(notif.isReadByUser('user_3'), isFalse);
      expect(notif.isReadByUser(null), isFalse);
    });

    test('isRelevantFor respects targetUserId', () {
      final notif = AppNotificationModel(
        id: 'n1',
        storeId: 's1',
        title: 'Duyệt thành viên',
        body: 'Bạn đã được duyệt',
        type: AppNotificationType.joinApproved,
        createdAt: DateTime.now(),
        targetUserId: 'user_123',
      );

      expect(notif.isRelevantFor('user_123', UserRole.employee), isTrue);
      expect(notif.isRelevantFor('user_456', UserRole.employee), isFalse);
      expect(notif.isRelevantFor('user_456', UserRole.owner), isFalse);
    });

    test('isRelevantFor respects targetRoles (Owner & Manager 1 for join request)', () {
      final joinReqNotif = AppNotificationModel(
        id: 'n2',
        storeId: 's1',
        title: 'Yêu cầu gia nhập mới',
        body: 'Có nhân viên mới xin vào',
        type: AppNotificationType.joinRequest,
        createdAt: DateTime.now(),
        targetRoles: [UserRole.owner, UserRole.manager1, UserRole.legacyManager],
      );

      expect(joinReqNotif.isRelevantFor('u_owner', UserRole.owner), isTrue);
      expect(joinReqNotif.isRelevantFor('u_mgr1', UserRole.manager1), isTrue);
      expect(joinReqNotif.isRelevantFor('u_legacy', UserRole.legacyManager), isTrue);
      // Quản lý 2 & Nhân viên không có quyền duyệt, không được nhận thông báo này
      expect(joinReqNotif.isRelevantFor('u_mgr2', UserRole.manager2), isFalse);
      expect(joinReqNotif.isRelevantFor('u_emp', UserRole.employee), isFalse);
    });

    test('isRelevantFor broadcast to all when targetUserId and targetRoles are null', () {
      final broadcastNotif = AppNotificationModel(
        id: 'n3',
        storeId: 's1',
        title: 'Thông báo chung',
        body: 'Nghỉ lễ 2/9',
        type: AppNotificationType.general,
        createdAt: DateTime.now(),
      );

      expect(broadcastNotif.isRelevantFor('u_owner', UserRole.owner), isTrue);
      expect(broadcastNotif.isRelevantFor('u_mgr1', UserRole.manager1), isTrue);
      expect(broadcastNotif.isRelevantFor('u_mgr2', UserRole.manager2), isTrue);
      expect(broadcastNotif.isRelevantFor('u_emp', UserRole.employee), isTrue);
    });

    test('Schedule registration reminder targets managers and employees', () {
      final regReminder = AppNotificationModel(
        id: 'n4',
        storeId: 's1',
        title: 'Nhắc đăng ký lịch tuần tới',
        body: 'Hạn chót 23:59 thứ Sáu',
        type: AppNotificationType.scheduleRegistrationReminder,
        createdAt: DateTime.now(),
        targetRoles: [UserRole.manager1, UserRole.manager2, UserRole.legacyManager, UserRole.employee],
        routePath: '/schedule',
      );

      expect(regReminder.isRelevantFor('u_emp', UserRole.employee), isTrue);
      expect(regReminder.isRelevantFor('u_mgr1', UserRole.manager1), isTrue);
      expect(regReminder.isRelevantFor('u_mgr2', UserRole.manager2), isTrue);
      expect(regReminder.isRelevantFor('u_owner', UserRole.owner), isFalse);
    });

    test('Advance request notifications target owner and employee correctly', () {
      final advanceReq = AppNotificationModel(
        id: 'n5',
        storeId: 's1',
        title: 'Yêu cầu ứng lương mới',
        body: 'Nhân viên A xin ứng 500.000đ',
        type: AppNotificationType.advanceRequest,
        createdAt: DateTime.now(),
        targetRoles: [UserRole.owner],
        routePath: '/manage-advances',
      );

      // Chỉ Chủ nhận được thông báo yêu cầu ứng lương
      expect(advanceReq.isRelevantFor('u_owner', UserRole.owner), isTrue);
      expect(advanceReq.isRelevantFor('u_mgr1', UserRole.manager1), isFalse);
      expect(advanceReq.isRelevantFor('u_emp', UserRole.employee), isFalse);

      final advanceApprove = AppNotificationModel(
        id: 'n6',
        storeId: 's1',
        title: 'Yêu cầu ứng lương đã được duyệt',
        body: 'Chủ quán đã duyệt yêu cầu của bạn',
        type: AppNotificationType.advanceApproved,
        createdAt: DateTime.now(),
        targetUserId: 'user_emp_1',
        routePath: '/salary',
      );

      // Chỉ nhân viên xin ứng nhận được kết quả duyệt
      expect(advanceApprove.isRelevantFor('user_emp_1', UserRole.employee), isTrue);
      expect(advanceApprove.isRelevantFor('user_emp_2', UserRole.employee), isFalse);
    });

    test('Birthday notifications are broadcast to everyone in the store (Owner, Managers, Employees)', () {
      final birthdayNotif = AppNotificationModel(
        id: 'birthday_u1_2026_8_17',
        storeId: 'store_1',
        title: '🎂 Hôm nay là sinh nhật của Nguyễn Văn A!',
        body: 'Cả cửa hàng hãy cùng gửi những lời chúc mừng tốt đẹp nhất đến Nguyễn Văn A nhân ngày sinh nhật hôm nay nhé! 🎉🎈',
        type: AppNotificationType.birthday,
        createdAt: DateTime(2026, 8, 17),
        targetUserId: null,
        targetRoles: null, // Broadcast to all in store
      );

      // Verify that all roles in the store receive the birthday notification
      expect(birthdayNotif.isRelevantFor('u_owner', UserRole.owner), isTrue);
      expect(birthdayNotif.isRelevantFor('u_mgr1', UserRole.manager1), isTrue);
      expect(birthdayNotif.isRelevantFor('u_mgr2', UserRole.manager2), isTrue);
      expect(birthdayNotif.isRelevantFor('u_legacy', UserRole.legacyManager), isTrue);
      expect(birthdayNotif.isRelevantFor('u_emp1', UserRole.employee), isTrue);
      expect(birthdayNotif.isRelevantFor('u1', UserRole.employee), isTrue);
    });

    test('Check-in and Check-out notifications are delivered to Owner and Managers', () {
      final checkInNotif = AppNotificationModel(
        id: 'ci_1',
        storeId: 'store_1',
        title: 'Nhân viên vào ca',
        body: 'Nguyễn Văn A tại Trạm Chanh đã vào ca lúc 08:30.',
        type: AppNotificationType.checkIn,
        createdAt: DateTime.now(),
        targetRoles: [
          UserRole.owner,
          UserRole.manager1,
          UserRole.manager2,
          UserRole.legacyManager,
        ],
        routePath: '/active-staff',
        routeExtra: {'storeId': 'store_1', 'userId': 'u_emp', 'date': '2026-08-30'},
      );

      final checkOutNotif = AppNotificationModel(
        id: 'co_1',
        storeId: 'store_1',
        title: 'Nhân viên kết thúc ca',
        body: 'Nguyễn Văn A tại Trạm Chanh đã kết thúc ca lúc 17:30 (Tổng: 9.0h).',
        type: AppNotificationType.checkOut,
        createdAt: DateTime.now(),
        targetRoles: [
          UserRole.owner,
          UserRole.manager1,
          UserRole.manager2,
          UserRole.legacyManager,
        ],
        routePath: '/attendance-table',
        routeExtra: {'storeId': 'store_1', 'userId': 'u_emp', 'date': '2026-08-30'},
      );

      // Check-in & Check-out notifications are relevant for Owner and Managers
      expect(checkInNotif.isRelevantFor('u_owner', UserRole.owner), isTrue);
      expect(checkInNotif.isRelevantFor('u_mgr1', UserRole.manager1), isTrue);
      expect(checkInNotif.isRelevantFor('u_mgr2', UserRole.manager2), isFalse);
      expect(checkInNotif.isRelevantFor('u_emp', UserRole.employee), isFalse);

      expect(checkOutNotif.isRelevantFor('u_owner', UserRole.owner), isTrue);
      expect(checkOutNotif.isRelevantFor('u_mgr1', UserRole.manager1), isTrue);
      expect(checkOutNotif.isRelevantFor('u_emp', UserRole.employee), isFalse);

      expect(checkInNotif.routeExtra?['storeId'], equals('store_1'));
      expect(checkOutNotif.routeExtra?['storeId'], equals('store_1'));
    });
  });
}
