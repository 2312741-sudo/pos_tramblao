# Chấm Công Trạm BLAO trên Firebase POS (`postramblao`)

Từ bản hợp nhất này, phân hệ **Chấm Công Trạm BLAO** (cả module nhúng trong app POS Flutter tại `app_flutter/lib/chamcong_blao/` lẫn cổng quản lý Web `chamcong_blao/cham_cong_web/`) chạy **trực tiếp trên cùng dự án Firebase `postramblao`** với POS Trạm BLAO — không còn dự án Firebase trung gian hay SSO 2 bước.

## 1. Kiến trúc tài khoản & xác thực

- **Một tài khoản duy nhất:** `uid POS = uid chấm công`. Nhân sự chỉ cần đăng nhập một lần bằng **Mã cửa hàng (`storeCode`) + Tên đăng nhập / Mã nhân viên + Mật khẩu** qua Cloud Function `staffSignIn` (vùng `asia-southeast1`).
- **App POS Flutter (`app_flutter`):** Module Chấm Công dùng thẳng Firebase app mặc định (`Firebase.app()`, `FirebaseAuth.instance`, `FirebaseFirestore.instance`, `FirebaseStorage.instance`, Functions region `asia-southeast1`). Mọi nút đăng xuất / đổi mật khẩu / xóa tài khoản trong UI standalone đã bị vô hiệu hóa khi nhúng trong POS; nút **Về POS** đưa người dùng quay lại màn hình POS nguyên vẹn.
- **Web Chấm Công (`chamcong_blao/cham_cong_web`):** Cấu hình trỏ thẳng về `postramblao` (`asia-southeast1`). Form `/login` chỉ nhận **Mã cửa hàng + Tên đăng nhập / Mã nhân viên + Mật khẩu** (gọi `staffSignIn` -> `signInWithCustomToken` -> `chamCongEnsureMember`). Đã bổ sung domain `chamcong-tramblao.vercel.app` vào `authorizedDomains` của Firebase Auth `postramblao`.

## 2. Cloud Functions trên `postramblao` (`asia-southeast1`)

File `firebase.json` quản lý 2 codebase song song trên `postramblao`:

1. **`codebase: "pos"` (`functions/`):**
   - Chứa các hàm nghiệp vụ POS (`staffSignIn`, `createStaffAccount`, `assignStaffToStore`, v.v.) và hàm **`chamCongEnsureMember({ storeCode })`**.
   - Khi mở module Chấm Công (App hoặc Web), `chamCongEnsureMember` kiểm tra tư cách POS trong RTDB (`stores/{storeCode}/users/{uid}` và `userIndex/{uid}/{storeCode} == true`):
     - Nếu Firestore `stores/{storeCode}` chưa tồn tại: tự tạo document cửa hàng dựa theo `storeInfo` và `ownerId` POS.
     - Nếu `stores/{storeCode}/members/{uid}` chưa tồn tại (hoặc trước đó từng `kicked`): tự tạo / khôi phục ở trạng thái `active`, ánh xạ vai trò POS sang Chấm Công (`owner`, `manager_1`, `employee`), đồng thời đồng bộ hồ sơ `users/{uid}` trên Firestore.
     - Trả về `{ storeId, isNewMember }`.
2. **`codebase: "chamcong"` (`functions_chamcong/`):**
   - Toàn bộ trigger & callable thông báo đẩy Chấm Công chạy tại **`asia-southeast1`** (Node.js 22):
     - Triggers: `onScheduleChanged`, `onAdvanceCreated`, `onAdvanceUpdated`, `onMemberNotificationChanged`, `onAttendanceNotificationChanged`, `onStoreNotificationDeleted`, `onNotificationDeliveryCreated`, `onStoreOwnershipNotificationChanged`, `onUserDeleted` (dọn dữ liệu Firestore của user, **không** đụng RTDB của POS).
     - Callables: `registerNotificationDevice`, `requestChecklistNotification`.
     - Lịch cron (`Asia/Ho_Chi_Minh`): `dailyMorningDigest`, `retryNotificationDeliveries`.

## 3. Thông báo đẩy (Push Notifications FCM / APNs)

- App POS đã bật `NotificationService.remotePushEnabled = true` trên vùng `asia-southeast1`.
- Đăng ký FCM device token tự động khi đăng nhập / auto-login POS (`AuthService`) và hủy token khi đăng xuất POS (`clearTokenForUser`), giữ nguyên background handler `_firebaseMessagingBackgroundHandler` trong `main.dart`.
- iOS đã khai báo `aps-environment = production` (`Runner.entitlements`) và `UIBackgroundModes = remote-notification` (`Info.plist`). Với iOS Release / TestFlight, cần đảm bảo đã tải khóa APNs `.p8` cho bundle `com.tramblao.pos` lên Firebase Console của `postramblao`.

## 4. Dữ liệu & Công cụ chuyển đổi

- Tài liệu đối chiếu & kết quả migrate từ dự án cũ `chamcongtramblao` sang `postramblao` xem tại [migration_report_2026-11-23.md](./migration_report_2026-11-23.md).
- Bản sao lưu pre-migration Firestore được lưu trong buckets `gs://chamcongtramblao-backup/backup-2026-11-24` và `gs://postramblao-backup/backup-2026-11-24`; rules & indexes gốc lưu tại [backup_rules_2026-11-24/](./backup_rules_2026-11-24/).
