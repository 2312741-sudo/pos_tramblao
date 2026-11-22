import 'package:cloud_firestore/cloud_firestore.dart';
import 'member_model.dart';
import '../core/auth/app_permissions.dart';

enum AppNotificationType {
  joinRequest,
  joinApproved,
  joinRejected,
  advanceRequest,
  advanceApproved,
  advanceRejected,
  scheduleChanged,
  scheduleRegistrationReminder,
  checklistReminder,
  deliveryUpdate,
  birthday,
  checkIn,
  checkOut,
  general,
}

extension AppNotificationTypeExtension on AppNotificationType {
  String get value {
    switch (this) {
      case AppNotificationType.joinRequest:
        return 'join_request';
      case AppNotificationType.joinApproved:
        return 'join_approved';
      case AppNotificationType.joinRejected:
        return 'join_rejected';
      case AppNotificationType.advanceRequest:
        return 'advance_request';
      case AppNotificationType.advanceApproved:
        return 'advance_approved';
      case AppNotificationType.advanceRejected:
        return 'advance_rejected';
      case AppNotificationType.scheduleChanged:
        return 'schedule_changed';
      case AppNotificationType.scheduleRegistrationReminder:
        return 'schedule_registration_reminder';
      case AppNotificationType.checklistReminder:
        return 'checklist_reminder';
      case AppNotificationType.deliveryUpdate:
        return 'delivery_update';
      case AppNotificationType.birthday:
        return 'birthday';
      case AppNotificationType.checkIn:
        return 'check_in';
      case AppNotificationType.checkOut:
        return 'check_out';
      case AppNotificationType.general:
        return 'general';
    }
  }

  static AppNotificationType fromString(String? value) {
    switch (value) {
      case 'join_request':
        return AppNotificationType.joinRequest;
      case 'join_approved':
        return AppNotificationType.joinApproved;
      case 'join_rejected':
        return AppNotificationType.joinRejected;
      case 'advance_request':
        return AppNotificationType.advanceRequest;
      case 'advance_approved':
        return AppNotificationType.advanceApproved;
      case 'advance_rejected':
        return AppNotificationType.advanceRejected;
      case 'schedule_changed':
        return AppNotificationType.scheduleChanged;
      case 'schedule_registration_reminder':
        return AppNotificationType.scheduleRegistrationReminder;
      case 'checklist_reminder':
        return AppNotificationType.checklistReminder;
      case 'delivery_update':
        return AppNotificationType.deliveryUpdate;
      case 'birthday':
        return AppNotificationType.birthday;
      case 'check_in':
        return AppNotificationType.checkIn;
      case 'check_out':
        return AppNotificationType.checkOut;
      case 'general':
      default:
        return AppNotificationType.general;
    }
  }

  String get label {
    switch (this) {
      case AppNotificationType.joinRequest:
        return 'Yêu cầu gia nhập';
      case AppNotificationType.joinApproved:
        return 'Được duyệt thành viên';
      case AppNotificationType.joinRejected:
        return 'Từ chối tham gia';
      case AppNotificationType.advanceRequest:
        return 'Yêu cầu ứng lương';
      case AppNotificationType.advanceApproved:
        return 'Duyệt tạm ứng';
      case AppNotificationType.advanceRejected:
        return 'Từ chối tạm ứng';
      case AppNotificationType.scheduleChanged:
        return 'Lịch làm việc';
      case AppNotificationType.scheduleRegistrationReminder:
        return 'Nhắc đăng ký lịch';
      case AppNotificationType.checklistReminder:
        return 'Nhắc nhở sản xuất';
      case AppNotificationType.deliveryUpdate:
        return 'Chở hàng / Giao hàng';
      case AppNotificationType.birthday:
        return 'Sinh nhật';
      case AppNotificationType.checkIn:
        return 'Nhân viên vào ca';
      case AppNotificationType.checkOut:
        return 'Nhân viên kết thúc ca';
      case AppNotificationType.general:
        return 'Thông báo';
    }
  }
}

class AppNotificationModel {
  final String? scope;
  final String id;
  final String storeId;
  final String title;
  final String body;
  final AppNotificationType type;
  final DateTime createdAt;
  final String? targetUserId;
  final List<UserRole>? targetRoles;
  final List<String> readBy;
  final String? routePath;
  final Map<String, dynamic>? routeExtra;

  const AppNotificationModel({
    this.scope,
    required this.id,
    required this.storeId,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.targetUserId,
    this.targetRoles,
    this.readBy = const [],
    this.routePath,
    this.routeExtra,
  });

  bool isReadByUser(String? userId) {
    if (userId == null) return false;
    return readBy.contains(userId);
  }

  bool isRelevantFor(String? userId, UserRole? role) {
    if (userId == null || userId.isEmpty) return false;
    if ((type == AppNotificationType.checkIn || type == AppNotificationType.checkOut) &&
        !AppPermissions.canViewAllAttendance(role)) return false;
    if (type == AppNotificationType.advanceRequest && role != UserRole.owner) return false;
    if (type == AppNotificationType.joinRequest && !AppPermissions.canApproveMembers(role)) return false;
    // Legacy relevance is retained only for imported models; inbox queries enforce authorization.
    // 1. If targetUserId is set, check if it matches
    if (targetUserId != null) {
      return targetUserId == userId;
    }

    // 2. If targetRoles is set, check if user's role is in targetRoles
    if (targetRoles != null && targetRoles!.isNotEmpty) {
      final effectiveRole = role ?? UserRole.employee;
      return targetRoles!.contains(effectiveRole);
    }

    // An unresolved role never receives a legacy broadcast.
    return role != null;
  }

  factory AppNotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    DateTime parsedCreatedAt = DateTime.now();
    if (data['createdAt'] is Timestamp) {
      parsedCreatedAt = (data['createdAt'] as Timestamp).toDate();
    } else if (data['createdAt'] is String) {
      parsedCreatedAt = DateTime.tryParse(data['createdAt'] as String) ?? DateTime.now();
    }

    List<UserRole>? parsedRoles;
    if (data['targetRoles'] is List) {
      parsedRoles = (data['targetRoles'] as List)
          .map((r) => UserRoleExtension.fromString(r.toString()))
          .toList();
    }

    List<String> parsedReadBy = [];
    if (data['readBy'] is List) {
      parsedReadBy = (data['readBy'] as List).map((e) => e.toString()).toList();
    }

    return AppNotificationModel(
      scope: data['scope'] as String?,
      id: doc.id,
      storeId: data['storeId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      type: AppNotificationTypeExtension.fromString(data['type'] as String?),
      createdAt: parsedCreatedAt,
      targetUserId: data['targetUserId'] as String?,
      targetRoles: parsedRoles,
      readBy: data['readAt'] != null && data['targetUserId'] is String
          ? [data['targetUserId'] as String] : parsedReadBy,
      routePath: data['routePath'] as String?,
      routeExtra: data['routeExtra'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scope': scope,
      'storeId': storeId,
      'title': title,
      'body': body,
      'type': type.value,
      'createdAt': Timestamp.fromDate(createdAt),
      'targetUserId': targetUserId,
      'targetRoles': targetRoles?.map((r) => r.value).toList(),
      'readBy': readBy,
      'routePath': routePath,
      'routeExtra': routeExtra,
    };
  }

  AppNotificationModel copyWith({
    String? id,
    String? storeId,
    String? title,
    String? body,
    AppNotificationType? type,
    DateTime? createdAt,
    String? targetUserId,
    List<UserRole>? targetRoles,
    List<String>? readBy,
    String? routePath,
    Map<String, dynamic>? routeExtra,
  }) {
    return AppNotificationModel(
      scope: scope,
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      targetUserId: targetUserId ?? this.targetUserId,
      targetRoles: targetRoles ?? this.targetRoles,
      readBy: readBy ?? this.readBy,
      routePath: routePath ?? this.routePath,
      routeExtra: routeExtra ?? this.routeExtra,
    );
  }
}
