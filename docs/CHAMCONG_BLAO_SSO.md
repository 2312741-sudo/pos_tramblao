# Chấm Công Trạm BLAO — đăng nhập bằng tài khoản POS

Mô-đun chấm công trong app POS (`app_flutter/lib/chamcong_blao`) và web quản lý chấm công dùng **chính tài khoản POS**
(mã cửa hàng + tên đăng nhập + mật khẩu). Dữ liệu chấm công vẫn ở dự án Firebase riêng **`chamcongtramblao`**.

## Luồng

1. Người dùng đăng nhập POS (`staffSignIn`, dự án `postramblao`).
2. App / web gọi Cloud Function **`chamCongBlaoSignIn({ storeCode })`** (dự án POS, vùng `asia-southeast1`).
3. Hàm kiểm tra tài khoản POS còn hoạt động, tìm tài khoản chấm công tương ứng:
   - đã liên kết → dùng lại;
   - chưa liên kết → nối vào thành viên chấm công **cùng tên** (bỏ dấu, không phân biệt hoa thường) nếu chỉ có đúng
     1 người và người đó chưa thuộc tài khoản POS khác → **giữ lịch sử chấm công / lương**;
   - không ai / nhiều người trùng tên → tạo tài khoản chấm công mới (`pos_<storeCode>_<posUid>`), vai trò theo POS
     (Chủ → owner, Quản lý → manager_1, còn lại → employee).
4. Hàm cấp **custom token của dự án `chamcongtramblao`**; app / web đăng nhập Firebase chấm công bằng token đó.

Liên kết lưu ở RTDB POS (chỉ Admin SDK đọc/ghi): `chamcong_blao_links/...`. Mỗi lần nối / tạo tài khoản có ghi
Nhật ký kiểm soát (`CHAMCONG_BLAO_LINKED`).

## Cấu hình một lần

### 1. Quyền cho service account của Cloud Functions POS

Service account chạy Functions POS (thường `postramblao@appspot.gserviceaccount.com` hoặc
`<số dự án>-compute@developer.gserviceaccount.com` — xem Cloud Console → Cloud Functions → chi tiết hàm → Service account).

Trong **Google Cloud Console của dự án `chamcongtramblao`** → IAM & Admin → IAM → Grant access cho service account trên:

| Vai trò | Để làm gì |
|---|---|
| **Cloud Datastore User** (`roles/datastore.user`) | Đọc / ghi Firestore chấm công (thành viên, hồ sơ) |

Trong **IAM & Admin → Service Accounts** của dự án `chamcongtramblao`, mở service account
`firebase-adminsdk-xxxxx@chamcongtramblao.iam.gserviceaccount.com` → tab **Permissions** → Grant access cho service
account Functions POS vai trò **Service Account Token Creator** (`roles/iam.serviceAccountTokenCreator`).

### 2. Biến môi trường cho Functions POS

Tạo `functions/.env` (không commit nếu không muốn) hoặc đặt khi deploy:

```
CHAMCONG_BLAO_PROJECT_ID=chamcongtramblao
CHAMCONG_BLAO_SERVICE_ACCOUNT=firebase-adminsdk-xxxxx@chamcongtramblao.iam.gserviceaccount.com
```

Rồi deploy: `firebase deploy --only functions:pos:chamCongBlaoSignIn,functions:pos:chamCongBlaoListStores,functions:pos:chamCongBlaoLinkStore`
(hoặc `firebase deploy --only functions`).

### 3. Liên kết cửa hàng

Chủ quán mở app POS → Quản lý (menu ⋮) → **Liên kết Chấm Công BLAO** → chọn cửa hàng chấm công tương ứng.

## Lỗi thường gặp

| Thông báo | Nguyên nhân |
|---|---|
| "Cửa hàng chưa được liên kết với Chấm Công BLAO" | Chưa làm bước 3 |
| "Máy chủ chưa đủ quyền đọc / ghi dữ liệu Chấm Công BLAO" | Thiếu vai trò Cloud Datastore User (bước 1) |
| "Máy chủ chưa đủ quyền cấp phiên đăng nhập Chấm Công BLAO" | Thiếu Service Account Token Creator hoặc chưa đặt `CHAMCONG_BLAO_SERVICE_ACCOUNT` (bước 1–2) |
| "Bạn đã bị xóa khỏi cửa hàng chấm công" | Thành viên bị Chủ/Quản lý xóa bên chấm công — thêm lại bên chấm công |
