# Báo Cáo Chuyển Dữ Liệu Chấm Công Sang Firebase POS (`2026-11-23`)

- **Nguồn:** `chamcongtramblao` (chỉ đọc)
- **Đích:** `postramblao` (Firestore vùng `asia-southeast1`)
- **Phương thức xác thực:** firebase-tools OAuth (fallback vì máy chưa có gcloud ADC)
- **Trạng thái ghi Storage:** 0 file ở nguồn, 0 file đã sao chép

## 1. Bảng Ghép Cửa Hàng & Nhân Sự

| Loại | ID Nguồn (`chamcongtramblao`) | ID Đích (`postramblao`) | Ghi chú |
|---|---|---|---|
| Store | `Fp6YTSWxcbPNzJ1k2asZ` (`TRẠM BLAO`, code `JG7LF7`) | `BLAO` | Ghép 1-1 cửa hàng thật |
| User | `4NQ9WEHfxePLl6UOkXMic9TreCG3` (`Đỗ Nguyễn Nguyên Quan`) | `TQySd97HN8gjuihaezL5HPdVsV63` (`nguyenquan`) | Giữ nguyên role `employee`, 20 công |
| User | `DiJPAB7sRvTunQHk9P7NbEjiGIr1` (`Lương Sỹ Minh Anh`) | `P4yks89qJdYkhSwva3NKYU4QPys1` (`minhanh`) | Giữ nguyên role `employee`, 13 công |
| User | `BJ3cboxox5MXqQ4ujQyFItBgwyv1` (`Nguyễn Thị Mỹ Duyên`) | `hfk73nw4QWPpegtsPTULCpcq4qb2` (`myduyen`) | Giữ nguyên role `owner`, 6 công |
| User | `PeDatFC1vlVeCyhgXKtTzFbQhiO2` (`Nguyễn Thị Huyền Trang`) | `1554VRHR20hHYbn5O0FIuHb9kP53` (`huyentrang`) | Giữ nguyên role `employee`, 0 công |
| User | `iiA3fxIbN5XkCmoRnEV1vUkq5to1` (`Nguyễn Thị Thương`) | `VkIc1KHWlHbz5e2hb9BBKL1gPAG2` (`thithuong`) | Giữ nguyên role `owner`, 0 công |

## 2. Thống Kê Chuyển Đổi & Đối Chiếu Theo Collection

| Collection | Đọc nguồn | Dự kiến ghi | Đã ghi | Bỏ qua | Tổng ở đích sau migration |
|---|---:|---:|---:|---:|---:|
| `users` | 18 | 5 | 5 | 13 | 5 |
| `stores` | 3 | 1 | 1 | 2 | 1 |
| `stores/BLAO/members` | 6 | 5 | 5 | 1 | 5 |
| `stores/BLAO/attendances` | 44 | 39 | 39 | 5 | 39 |
| `stores/BLAO/schedules` | 3 | 3 | 3 | 0 | 3 |
| `stores/BLAO/advances` | 0 | 0 | 0 | 0 | - |
| `stores/BLAO/production_tasks` | 0 | 0 | 0 | 0 | - |
| `stores/BLAO/production_reports` | 0 | 0 | 0 | 0 | - |
| `stores/BLAO/assigned_tasks` | 0 | 0 | 0 | 0 | - |
| `stores/BLAO/notifications` | 16 | 16 | 16 | 0 | 16 |
| `stores/BLAO/audit_logs` | 1 | 1 | 1 | 0 | 1 |
| `stores/BLAO/private` | 0 | 0 | 0 | 0 | - |
| `notificationInboxes/accountItems` | 2 | 2 | 2 | 0 | 2 |
| `notificationInboxes/storeItems` | 149 | 149 | 149 | 0 | 149 |

## 3. Các Mục Đã Bỏ Qua (Theo Quyết Định Chủ Dự Án)

- **Cửa hàng bỏ qua:** `1noouOSoiZIjLqzGHBu7` (`BLAODEMO`), `bX81rKaGTs3oAODiTVGr` (`app`).
- **Nhân viên bỏ qua:** `gjnlOcE99jbQWhPikTGLIBnBrRu2` (`gia hân`, `status: kicked`, 4 công), `XpxG6bKSXUdE9MkSi3tbc7JVavz1` (`Chủ Trạm BLAO (Demo)`, 1 công test 21/10).
- **Collection không chép:** `notificationDevices`, `notificationEvents`, `notificationDeliveries` và các trường `fcmToken`, `fcmTokens` (mã FCM cũ thuộc dự án cũ).

## 4. Danh Sách Chi Tiết Các Trường Được Chuyển Đổi UID / StoreId

- `users/{uid}`: docId=mapUid; uid=[id]; store=[currentStoreId]
- `stores/{storeId}`: docId=mapStoreId; uid=[ownerId, deletedBy, orphanedBy]; arrayUid=[coOwnerIds, memberOrder, hiddenScheduleUserIds]
- `stores/{storeId}/members/{uid}`: docId=mapUid; uid=[userId, approvedBy, kickedBy]
- `stores/{storeId}/private/{docId}`: docId=keep; uid=[updatedBy]; store=[storeId]
- `stores/{storeId}/attendances/{attendanceId}`: docId=replaceUidAndStoreInId; uid=[userId, approvedBy, createdBy, updatedBy, editedBy]; store=[storeId]
- `stores/{storeId}/schedules/{weekId}`: docId=keep; uid=[updatedBy]; arrayUid=[lockedUsers]; store=[storeId]; uidMap=[shifts, registrations]
- `stores/{storeId}/advances/{advanceId}`: docId=keep; uid=[userId, approvedBy, rejectedBy, requestedBy, createdBy, updatedBy]; store=[storeId]
- `stores/{storeId}/production_tasks/{taskId}`: docId=keep; uid=[createdBy, updatedBy]; store=[storeId]
- `stores/{storeId}/production_reports/{reportId}`: docId=replaceUidAndStoreInId; uid=[userId, reviewedBy, approvedBy, createdBy]; store=[storeId]
- `stores/{storeId}/assigned_tasks/{taskId}`: docId=keep; uid=[createdBy, updatedBy, assignedTo]; arrayUid=[assignedUserIds, assigneeIds, targetUserIds]; store=[storeId]
- `stores/{storeId}/assigned_tasks/{taskId}/submissions/{subId}`: docId=replaceUidAndStoreInId; uid=[userId, submittedBy, reviewedBy, approvedBy]; store=[storeId]
- `stores/{storeId}/notifications/{notifId}`: docId=keep; uid=[targetUserId, actorId, createdBy, userId]; arrayUid=[readBy, recipientIds]; store=[storeId]
- `stores/{storeId}/audit_logs/{logId}`: docId=keep; uid=[actorId, previousOwnerId, newOwnerId, targetUserId, userId]; store=[storeId]
- `notificationInboxes/{uid}/accountItems/{itemId}`: docId=keep; uid=[targetUserId, actorId, userId, recipientId]; store=[storeId]
- `notificationInboxes/{uid}/stores/{storeId}/items/{itemId}`: docId=keep; uid=[targetUserId, actorId, userId, recipientId]; store=[storeId]
- `performance_sessions/{sessionId}`: docId=keep; uid=[managerId, createdBy]; store=[storeId]
- `performance_sessions/{sessionId}/measurements/{measurementId}`: docId=keep; uid=[userId]; store=[storeId]
- `performance_reports/{reportId}`: docId=keep; uid=[managerId, managerOnDutyId, viewedBy]; store=[storeId]
