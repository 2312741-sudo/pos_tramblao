/**
 * Bảng cấu hình ánh xạ chuyển dữ liệu Chấm Công Trạm BLAO (`chamcongtramblao` -> `postramblao`).
 * Đã rà soát toàn bộ schema trên `cham_cong_tram/lib`, `cham_cong_web/lib`, `functions_chamcong`.
 */

module.exports = {
  SOURCE_PROJECT_ID: "chamcongtramblao",
  TARGET_PROJECT_ID: "postramblao",
  SOURCE_STORAGE_BUCKET: "chamcongtramblao.firebasestorage.app",
  TARGET_STORAGE_BUCKET: "postramblao.firebasestorage.app",

  // Chỉ chuyển duy nhất cửa hàng thật TRẠM BLAO -> POS BLAO (theo quyết định đã chốt)
  STORE_MAP: {
    Fp6YTSWxcbPNzJ1k2asZ: "BLAO",
  },
  SKIPPED_STORES: {
    "1noouOSoiZIjLqzGHBu7": "TRẠM BLAO - BẢO LỘC (DEMO) — bỏ qua theo yêu cầu Chủ dự án",
    bX81rKaGTs3oAODiTVGr: "Cửa hàng rác 'app' của Apple Reviewer — bỏ qua",
  },

  // Bảng ghép 5 thành viên thật đã khớp 1-1 trên POS BLAO (uid chấm công -> uid POS)
  UID_MAP: {
    "4NQ9WEHfxePLl6UOkXMic9TreCG3": "TQySd97HN8gjuihaezL5HPdVsV63", // Đỗ Nguyễn Nguyên Quân (20 công)
    DiJPAB7sRvTunQHk9P7NbEjiGIr1: "P4yks89qJdYkhSwva3NKYU4QPys1", // Lương Sỹ Minh Anh (13 công)
    BJ3cboxox5MXqQ4ujQyFItBgwyv1: "hfk73nw4QWPpegtsPTULCpcq4qb2", // Nguyễn Thị Mỹ Duyên (6 công)
    PeDatFC1vlVeCyhgXKtTzFbQhiO2: "1554VRHR20hHYbn5O0FIuHb9kP53", // Nguyễn Thị Huyền Trang (0 công)
    iiA3fxIbN5XkCmoRnEV1vUkq5to1: "VkIc1KHWlHbz5e2hb9BBKL1gPAG2", // Nguyễn Thị Thương (0 công)
  },

  SKIPPED_UIDS: {
    gjnlOcE99jbQWhPikTGLIBnBrRu2: "gia hân (status: kicked, 4 bản ghi) — bỏ qua theo quyết định Chủ dự án",
    XpxG6bKSXUdE9MkSi3tbc7JVavz1: "Chủ Trạm BLAO (Demo test ngày 21/10, 1 bản ghi) — bỏ qua theo quyết định Chủ dự án",
  },

  // UID chủ gốc thay thế nếu một bản ghi hệ thống cũ (audit_logs / updatedBy) từng trỏ về tài khoản Demo đã bỏ
  FALLBACK_OWNER_UID: "hfk73nw4QWPpegtsPTULCpcq4qb2",

  // Bảng liệt kê MỌI trường chứa UID / storeId theo từng collection (rà từ app_flutter, cham_cong_web, functions_chamcong)
  FIELD_SCHEMA: {
    "users/{uid}": {
      docId: "mapUid",
      scalarUidFields: ["id"],
      scalarStoreFields: ["currentStoreId"],
      arrayStoreFields: ["storeIds"],
      stripFields: ["fcmToken", "fcmTokens", "posLink"],
      urlFields: ["avatarUrl"],
    },
    "stores/{storeId}": {
      docId: "mapStoreId",
      scalarUidFields: ["ownerId", "deletedBy", "orphanedBy"],
      arrayUidFields: ["coOwnerIds", "memberOrder", "hiddenScheduleUserIds"],
      extraSet: { code: "BLAO", posStoreCode: "BLAO" },
    },
    "stores/{storeId}/members/{uid}": {
      docId: "mapUid",
      scalarUidFields: ["userId", "approvedBy", "kickedBy"],
      urlFields: ["avatarUrl"],
    },
    "stores/{storeId}/private/{docId}": {
      docId: "keep",
      scalarUidFields: ["updatedBy"],
      scalarStoreFields: ["storeId"],
    },
    "stores/{storeId}/attendances/{attendanceId}": {
      docId: "replaceUidAndStoreInId",
      ownerUidField: "userId",
      scalarUidFields: ["userId", "approvedBy", "createdBy", "updatedBy", "editedBy"],
      scalarStoreFields: ["storeId"],
    },
    "stores/{storeId}/schedules/{weekId}": {
      docId: "keep",
      scalarUidFields: ["updatedBy"],
      scalarStoreFields: ["storeId"],
      uidKeyedMaps: ["shifts", "registrations"],
      arrayUidFields: ["lockedUsers"],
    },
    "stores/{storeId}/advances/{advanceId}": {
      docId: "keep",
      ownerUidField: "userId",
      scalarUidFields: ["userId", "approvedBy", "rejectedBy", "requestedBy", "createdBy", "updatedBy"],
      scalarStoreFields: ["storeId"],
    },
    "stores/{storeId}/production_tasks/{taskId}": {
      docId: "keep",
      scalarUidFields: ["createdBy", "updatedBy"],
      scalarStoreFields: ["storeId"],
    },
    "stores/{storeId}/production_reports/{reportId}": {
      docId: "replaceUidAndStoreInId",
      ownerUidField: "userId",
      scalarUidFields: ["userId", "reviewedBy", "approvedBy", "createdBy"],
      scalarStoreFields: ["storeId"],
      urlFields: ["photoUrl", "imageUrl"],
    },
    "stores/{storeId}/assigned_tasks/{taskId}": {
      docId: "keep",
      scalarUidFields: ["createdBy", "updatedBy", "assignedTo"],
      arrayUidFields: ["assignedUserIds", "assigneeIds", "targetUserIds"],
      scalarStoreFields: ["storeId"],
    },
    "stores/{storeId}/assigned_tasks/{taskId}/submissions/{subId}": {
      docId: "replaceUidAndStoreInId",
      ownerUidField: "userId",
      scalarUidFields: ["userId", "submittedBy", "reviewedBy", "approvedBy"],
      scalarStoreFields: ["storeId"],
      urlFields: ["photoUrl", "imageUrl", "attachmentUrl"],
    },
    "stores/{storeId}/notifications/{notifId}": {
      docId: "keep",
      scalarUidFields: ["targetUserId", "actorId", "createdBy", "userId"],
      arrayUidFields: ["readBy", "recipientIds"],
      scalarStoreFields: ["storeId"],
      nestedRouteExtra: ["storeId", "userId", "memberId"],
    },
    "stores/{storeId}/audit_logs/{logId}": {
      docId: "keep",
      scalarUidFields: ["actorId", "previousOwnerId", "newOwnerId", "targetUserId", "userId"],
      scalarStoreFields: ["storeId"],
    },
    "notificationInboxes/{uid}/accountItems/{itemId}": {
      docId: "keep",
      scalarUidFields: ["targetUserId", "actorId", "userId", "recipientId"],
      scalarStoreFields: ["storeId"],
      nestedRouteExtra: ["storeId", "userId", "memberId"],
    },
    "notificationInboxes/{uid}/stores/{storeId}/items/{itemId}": {
      docId: "keep",
      scalarUidFields: ["targetUserId", "actorId", "userId", "recipientId"],
      scalarStoreFields: ["storeId"],
      nestedRouteExtra: ["storeId", "userId", "memberId"],
    },
    "performance_sessions/{sessionId}": {
      docId: "keep",
      scalarUidFields: ["managerId", "createdBy"],
      scalarStoreFields: ["storeId"],
    },
    "performance_sessions/{sessionId}/measurements/{measurementId}": {
      docId: "keep",
      scalarUidFields: ["userId"],
      scalarStoreFields: ["storeId"],
      urlFields: ["incidentImageUrl", "imageUrl"],
    },
    "performance_reports/{reportId}": {
      docId: "keep",
      scalarUidFields: ["managerId", "managerOnDutyId", "viewedBy"],
      scalarStoreFields: ["storeId"],
    },
  },
};
