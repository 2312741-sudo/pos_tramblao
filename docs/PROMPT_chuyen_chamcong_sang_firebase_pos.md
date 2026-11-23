# PROMPT: Chuyển toàn bộ Chấm Công Trạm BLAO sang Firebase POS (bỏ dự án `chamcongtramblao`)

> Dán toàn bộ nội dung dưới đây cho agent (Antigravity). Agent chạy trên máy của chủ dự án, đã/được phép
> `firebase login` và `gcloud auth login` bằng tài khoản Google có quyền Owner trên CẢ HAI dự án Firebase.

---

## 0. Mục tiêu

Hiện có 2 dự án Firebase:

| Dự án | Dùng cho |
|---|---|
| `postramblao` | App POS (Flutter), web quản lý POS (Next.js), Cloud Functions POS, Realtime Database (dữ liệu bán hàng), Firestore (chỉ collection `kmt_customers`) |
| `chamcongtramblao` | App Chấm Công Trạm BLAO + web quản lý chấm công: Firestore, Storage, Auth, Cloud Functions (thông báo) |

**Yêu cầu:** chuyển TOÀN BỘ chấm công sang dự án **`postramblao`** rồi ngừng dùng `chamcongtramblao`:
- Chấm công dùng **chính tài khoản POS** (Firebase Auth của `postramblao`; uid POS = mã thành viên chấm công).
- Dữ liệu chấm công (Firestore + file Storage) chép sang `postramblao`, **giữ lịch sử**.
- Cloud Functions chấm công chạy trong `postramblao`; **thông báo đẩy hoạt động lại**.
- App POS (đã gộp mô-đun chấm công) và web quản lý chấm công chỉ dùng `postramblao`.
- Web POS và web chấm công **vẫn là 2 web riêng**; web chấm công đăng nhập bằng **mã cửa hàng + tên đăng nhập + mật khẩu POS** như app POS.

Làm hết: code, chuyển dữ liệu, deploy, kiểm tra. Dừng lại hỏi chủ dự án CHỈ ở các điểm ghi **[DỪNG HỎI]**.

---

## 1. Mã nguồn & hiện trạng

### Repo 1: `2312741-sudo/pos_tramblao` — làm trên nhánh `feat/merge-chamcong-blao` (tạo nhánh mới từ đó: `feat/chamcong-on-pos-firebase`)

- `app_flutter/` — app POS Flutter (package `tram_flutter`, bundle/applicationId `com.tramblao.pos`).
  - **Mô-đun chấm công đã gộp sẵn**: `app_flutter/lib/chamcong_blao/` (chép từ app chấm công, import tương đối).
    - `cc_firebase.dart` — lớp `CcFirebase` trả Auth/Firestore/Storage/Functions của **Firebase app phụ** `chamcong_blao` (dự án `chamcongtramblao`). Mọi chỗ trong mô-đun đều lấy Firebase qua lớp này.
    - `cc_firebase_options.dart` — cấu hình dự án `chamcongtramblao`.
    - `pos_sso.dart` — đổi phiên POS lấy phiên chấm công qua Cloud Function `chamCongBlaoSignIn` (SSO).
    - `chamcong_blao_screen.dart` — cổng vào mô-đun (app con: `MaterialApp.router` + `ProviderContainer` riêng), gọi SSO trước khi mở.
    - `link_store_dialog.dart` — Chủ quán liên kết cửa hàng POS ↔ cửa hàng chấm công.
    - `core/services/notification_service.dart` — `remotePushEnabled = false` (đang TẮT thông báo đẩy vì mã FCM thuộc dự án POS).
    - `core/services/app_update_service.dart` — `embeddedInPos = true` (tắt kiểm tra cập nhật riêng của chấm công) — GIỮ NGUYÊN.
  - Lối vào mô-đun: menu Quản lý (`features/manager/manager_hub_screen.dart`: "Chấm công", "Liên kết Chấm Công BLAO"), biểu tượng đồng hồ ở Sơ đồ bàn (`features/tables/table_list_screen.dart`).
  - `core/services/auth_service.dart` — `AuthService()` (singleton): `isLoggedIn`, `currentStoreCode`, `currentUser`, `logout()` (đang gọi `ChamCongBlaoSso.signOut()`).
  - Test chấm công: `app_flutter/test/chamcong_blao/` (195 test). Toàn bộ `flutter test`: 830 đạt, **3 test hỏng sẵn từ trước, không liên quan** (campaign_module1_test, conditional_campaign_test ×2) — không cần sửa, không được làm tăng số test hỏng.
- `functions/` — Cloud Functions POS (TypeScript, firebase-functions v6 / API v2, codebase `pos`, vùng `asia-southeast1`). Test: `npx vitest run`.
  - `src/chamCongBlao.ts`, `src/chamCongBlaoLogic.ts` (+test) — SSO sang dự án chấm công (chamCongBlaoSignIn / chamCongBlaoListStores / chamCongBlaoLinkStore). **Logic so tên / đổi vai trò trong `chamCongBlaoLogic.ts` dùng lại được.**
  - Thư mục `lib/` là JS đã biên dịch và ĐƯỢC commit (giữ cách làm này: `npm run build` rồi commit cả `lib/`).
  - Đăng nhập POS: callable `staffSignIn({storeCode, username, password})` → `{ token }` (custom token, uid POS).
- `web/` — web quản lý POS (Next.js). Không cần sửa trong việc này.
- `database.rules.json` — rules Realtime Database POS (không cần sửa, trừ khi thật cần).
- `firebase.json` — hiện CHƯA có mục `firestore` / `storage`; functions: `[{ "source": "functions", "codebase": "pos" }]`.
- `docs/CHAMCONG_BLAO_SSO.md` — tài liệu SSO cũ (sẽ lỗi thời, cập nhật/thay bằng tài liệu mới).

Dữ liệu người dùng POS (Realtime Database `postramblao`):
- `stores/{storeCode}/users/{uid}`: `fullName`, `username`, `roleId` (`ROLE_OWNER`/`owner`, `ROLE_MANAGER`/`manager*`, `ROLE_STAFF`, `ROLE_KITCHEN`…), `isRootOwner`, `isActive`, `phone`, `employeeCode`.
- `userIndex/{uid}/{storeCode} = true`.
- `stores/{storeCode}/storeInfo` (`storeName`…).
- Liên kết SSO cũ (nếu đã có): `chamcong_blao_links/stores/{storeCode}` = `{ ccStoreId, ccStoreName }`, `chamcong_blao_links/users/{storeCode}/{posUid}` = ccUid.

### Repo 2: `2312741-sudo/chamcong_tramblao` — làm trên nhánh mới `feat/chamcong-on-pos-firebase` (tạo từ `feat/pos-account-login`)

- `cham_cong_tram/` — app chấm công Flutter GỐC (package `blao_workforce_hub`). Đây là nguồn đã chép sang POS; **không phát triển tiếp app này** (sẽ ngừng). Dùng để tra cứu.
- `cham_cong_web/` — web quản lý chấm công (Next.js 16).
  - `lib/firebase.ts` — cấu hình `chamcongtramblao` (cần đổi sang `postramblao`).
  - `lib/posSso.ts` + `app/login/page.tsx` — đã có form đăng nhập mã cửa hàng + tài khoản POS (qua SSO). Đổi sang đăng nhập thẳng bằng custom token POS.
  - `lib/auth.ts` — đăng nhập email/Google/Apple cũ (bỏ hẳn sau khi chuyển; tài khoản cũ không còn tồn tại ở dự án mới).
- `functions/` — Cloud Functions chấm công (JavaScript, `firebase-functions` ^5 **API v1**, Node 20, vùng `asia-east2`):
  - `index.js`: `onUserDeleted` (auth.user().onDelete — dọn dữ liệu chấm công khi xóa tài khoản).
  - `notifications/triggers.js` (+`policy.js`, `service.js`, `audit-history.js`): `onScheduleChanged`, `onAdvanceCreated`, `onAdvanceUpdated`, `onMemberNotificationChanged`, `onAttendanceNotificationChanged`, `onStoreNotificationDeleted`, `onNotificationDeliveryCreated`, `retryNotificationDeliveries` (mỗi phút), `registerNotificationDevice` (callable), `dailyMorningDigest` (8h sáng VN), `requestChecklistNotification` (callable), `onStoreOwnershipNotificationChanged`.
  - Test: `npm test`, `npm run test:emulator` (rules + thông báo trên emulator).
- `firestore.rules`, `storage.rules`, `firestore.indexes.json` — rules/index của chấm công.

### Mô hình dữ liệu Firestore chấm công (giữ NGUYÊN tên collection khi chuyển)

- `users/{uid}`: `id`, `name`, `email`, `phone`, `avatarUrl`, `birthday`, `currentStoreId`, `storeIds[]`, `notifyShiftInOut`, `createdAt`, `fcmToken`, `fcmTokens[]`.
- `stores/{storeId}`: `ownerId`, `name`, `code`… ; con: `members/{uid}` (`userId`, `name`, `phone`, `avatarUrl`, `role`: owner | manager_1 | manager_2 | manager | employee, `status`: active | pending | kicked, `employeeType`, lương cơ bản, `joinedAt`, `employeeCode`, `department`, `birthday`), `private/{docId}`, `schedules`, `attendances`, `advances`, `production_tasks`, `production_reports`, `notifications`, `audit_logs`, `assigned_tasks/{taskId}/submissions`.
- `notificationInboxes/{uid}/accountItems`, `notificationInboxes/{uid}/stores/{storeId}/items`.
- `notificationDevices`, `notificationEvents`, `notificationDeliveries`, `app_config`, `performance_sessions/{id}/measurements`, `performance_reports`, `kmt_customers`, `kmt_point_history`, `kmt_stores`.
- **Firestore `postramblao` đang dùng `kmt_customers`** (app POS đọc). Không được ghi đè / làm mất dữ liệu hay rules của các collection `kmt_*` đang có ở `postramblao`.

---

## 2. Quyết định đã chốt (không hỏi lại)

1. **Tài khoản:** uid chấm công = uid POS. Không còn tài khoản Auth riêng cho chấm công; bỏ SSO (`chamCongBlaoSignIn`, `pos_sso.dart`, Firebase app phụ).
2. **Mã cửa hàng chấm công = mã cửa hàng POS** (vd `TRAM01`): doc `stores/{storeCode}`. Thêm trường `posStoreCode`.
3. **Ghép tài khoản cũ:** mỗi tài khoản chấm công cũ → tài khoản POS:
   - nếu đã có `chamcong_blao_links/users/{storeCode}/{posUid} = ccUid` → dùng;
   - nếu chưa: so **tên** (bỏ dấu tiếng Việt kể cả đ, không phân biệt hoa thường, gộp khoảng trắng — dùng `normalizeName` trong `functions/src/chamCongBlaoLogic.ts`) giữa thành viên chấm công và `fullName` tài khoản POS cùng cửa hàng; ghép khi **khớp đúng 1–1**. Chủ dự án cho biết hiện có **2 nhân viên đã có dữ liệu chấm công** — phải ghép được cả 2.
   - Không ghép được → **[DỪNG HỎI]** liệt kê (tên, số bản ghi chấm công) để chủ dự án chỉ định tài khoản POS hoặc bỏ qua.
4. **Vai trò:** thành viên đã có giữ nguyên vai trò chấm công. Thành viên mới (tài khoản POS lần đầu mở chấm công): Chủ → `owner`, Quản lý → `manager_1`, còn lại → `employee` (dùng `mapPosRoleToCc`).
5. **Dữ liệu nguồn ở `chamcongtramblao` KHÔNG được xóa / sửa.** Chỉ đọc. Ngừng dùng sau khi chạy ổn (chủ dự án tự quyết lúc nào tắt).
6. **Web chấm công:** chỉ còn đăng nhập bằng tài khoản POS. Bỏ email/Google/Apple.
7. Không nâng số phiên bản app/web trong việc này (chủ dự án tự quyết khi phát hành).
8. Mọi chữ hiển thị cho người dùng bằng **tiếng Việt có dấu**.

---

## 3. Việc cần làm

### Bước A — Sao lưu trước khi đụng vào dữ liệu (BẮT BUỘC)
1. Export Firestore cả hai dự án ra Cloud Storage:
   `gcloud firestore export gs://<bucket-backup-chamcongtramblao>/backup-<ngày> --project chamcongtramblao`
   `gcloud firestore export gs://<bucket-backup-postramblao>/backup-<ngày> --project postramblao`
   (tạo bucket nếu chưa có; ghi lại đường dẫn vào báo cáo cuối).
2. Lưu lại **rules Firestore & Storage đang deploy** của `postramblao` (Firebase Console hoặc `firebase` CLI / REST) vào `pos_tramblao/docs/backup_rules_<ngày>/` trước khi deploy rules mới.
3. Export Realtime Database `postramblao` node `chamcong_blao_links` (nếu có) để tham chiếu.

### Bước B — Cloud Functions chấm công chạy trong `postramblao`
1. Chép `chamcong_tramblao/functions/` vào `pos_tramblao/functions_chamcong/` (giữ JS, API v1, package.json riêng) và thêm vào `pos_tramblao/firebase.json`:
   `{ "source": "functions_chamcong", "codebase": "chamcong", "ignore": ["node_modules", ".git", "*.local", "test"] }`.
   - Đổi vùng `asia-east2` → **`asia-southeast1`** cho mọi hàm (đồng bộ với POS), và cập nhật mọi chỗ gọi callable trong app/web (`CcFirebase.functions(region: 'asia-east2')`, `requestChecklistNotification`, `registerNotificationDevice`…).
   - **`onUserDeleted`**: trong `postramblao`, sự kiện xóa Auth là xóa tài khoản POS. Rà lại để chỉ dọn dữ liệu CHẤM CÔNG của uid đó (users/{uid}, membership, inbox, thiết bị thông báo) và không làm hỏng gì của POS; nếu không chắc an toàn → tắt hàm này và ghi rõ trong báo cáo.
   - Kiểm tra trùng tên hàm với codebase `pos` (tên hàm phải duy nhất trong dự án).
   - Chạy `npm test` của functions_chamcong.
2. Trong `functions/` (POS, TypeScript): thay `chamCongBlao.ts` bằng callable **`chamCongEnsureMember({ storeCode })`**:
   - Người gọi phải đăng nhập POS; kiểm tra `stores/{storeCode}/users/{uid}` tồn tại, `isActive !== false`, `userIndex/{uid}/{storeCode} === true` (dùng lại `loadPosCaller`).
   - Đảm bảo `stores/{storeCode}` (Firestore) tồn tại (tạo nếu chưa: `name` = `storeInfo.storeName`, `code` = storeCode, `posStoreCode`, `ownerId` = uid Chủ gốc nếu biết).
   - Đảm bảo `stores/{storeCode}/members/{uid}`: chưa có → tạo (`buildNewMember` + `joinedAt` Timestamp, vai trò theo `mapPosRoleToCc`); `pending` → `active`; `kicked` → từ chối (`permission-denied`, thông báo tiếng Việt).
   - Đảm bảo `users/{uid}`: `currentStoreId = storeCode`, `storeIds` arrayUnion, `name` nếu mới.
   - Trả `{ storeId, isNewMember }`. Ghi Nhật ký kiểm soát POS khi tạo thành viên mới.
   - Bỏ `chamCongBlaoSignIn`, `chamCongBlaoListStores`, `chamCongBlaoLinkStore` khỏi `index.ts` (xóa file; giữ/chuyển `chamCongBlaoLogic.ts` + test, đổi tên nếu hợp lý). Cập nhật test; `npm run build`; `npx vitest run` phải đạt hết.

### Bước C — Rules & index trên `postramblao`
1. Tạo `pos_tramblao/firestore.rules` = rules chấm công (`chamcong_tramblao/firestore.rules`) **GỘP** với rules hiện có của `postramblao` (đặc biệt `kmt_customers` và các collection `kmt_*` POS đang dùng — lấy từ bản sao lưu ở Bước A.2). Nếu hai bên có rules khác nhau cho cùng collection `kmt_*` → giữ bản đang chạy của POS và ghi chú.
2. `pos_tramblao/storage.rules` = gộp tương tự (rules chấm công cho ảnh đại diện / ảnh báo cáo + rules Storage POS đang có).
3. `pos_tramblao/firestore.indexes.json` = index chấm công + index POS hiện có (lấy bằng `firebase firestore:indexes --project postramblao`).
4. Thêm `firestore` và `storage` vào `pos_tramblao/firebase.json`.
5. Kiểm tra rules bằng emulator: chuyển các test rules/thông báo của chamcong (`test/firestore-rules-roles.test.js`, `test/notifications-emulator.test.js`) sang `functions_chamcong/test`, chạy với emulator dùng rules mới. Thêm test: nhân viên POS (uid thường) chỉ đọc/ghi được đúng phần của mình như rules cũ; `kmt_customers` vẫn đọc được như trước.

### Bước D — App POS (mô-đun chấm công) dùng Firebase mặc định
1. `cc_firebase.dart`: `CcFirebase.auth/firestore/storage/functions` trả về instance **mặc định** (`FirebaseAuth.instance`, `FirebaseFirestore.instance`, `FirebaseStorage.instance`, `FirebaseFunctions.instanceFor(region: 'asia-southeast1')`). Bỏ Firebase app phụ; xóa `cc_firebase_options.dart`. (Giữ lớp `CcFirebase` làm điểm truy cập duy nhất để thay đổi nhỏ.)
2. Thay `pos_sso.dart` bằng bước gọi `chamCongEnsureMember({storeCode: AuthService().currentStoreCode})` trước khi mở mô-đun (trong `chamcong_blao_screen.dart`); lỗi → màn báo lỗi tiếng Việt + nút "Thử lại" (đã có). Mất mạng nhưng thành viên đã có → vẫn cho vào (Firestore offline).
3. Mô-đun KHÔNG được tự đăng xuất / đăng nhập Firebase Auth nữa (Auth giờ là của POS!). Rà toàn bộ `lib/chamcong_blao` (auth_repository, auth_notifier, splash, welcome/login/register, profile_settings, store_drawer…): mọi `signOut`, `signInWith*`, `createUserWithEmailAndPassword`, `delete()` tài khoản, đổi mật khẩu/email → bỏ hoặc chuyển thành "đóng mô-đun" (`Navigator.maybePop`). Không được để người dùng xóa / đăng xuất tài khoản POS từ trong mô-đun. Router mô-đun: không bao giờ điều hướng tới welcome/login/register; nếu chưa có thành viên → màn báo lỗi.
4. Bỏ đoạn đăng xuất chấm công trong `AuthService.logout()` (không còn cần) và mục menu "Liên kết Chấm Công BLAO" + `link_store_dialog.dart` (cửa hàng chấm công = mã cửa hàng POS).
5. **Bật lại thông báo đẩy**: `remotePushEnabled = true`; đăng ký `FirebaseMessaging.onBackgroundMessage` ở `app_flutter/lib/main.dart` (handler top-level, `@pragma('vm:entry-point')`); gọi `NotificationService().initialize()` / `saveTokenForUser(uid)` khi vào mô-đun hoặc sau đăng nhập POS; callable `registerNotificationDevice` ở vùng `asia-southeast1`.
   - iOS: thêm `aps-environment` vào `ios/Runner/Runner.entitlements` (production cho bản phát hành), `UIBackgroundModes` (`remote-notification`) trong Info.plist; nhắc chủ dự án upload APNs key cho dự án `postramblao` trong Firebase Console nếu chưa có **[DỪNG HỎI nếu không tự kiểm tra được]**.
   - Android: quyền `POST_NOTIFICATIONS` đã có.
6. Ảnh (avatar, ảnh báo cáo) dùng bucket Storage `postramblao`; URL cũ trỏ bucket `chamcongtramblao` phải được đổi ở Bước F.
7. `flutter analyze` (không thêm lỗi/cảnh báo mới so với trước), `flutter test` (không tăng số test hỏng), `flutter build apk --release` thành công. Bổ sung test cho logic mới nếu có logic thuần.

### Bước E — Web quản lý chấm công dùng `postramblao`
1. `cham_cong_web/lib/firebase.ts`: cấu hình web `postramblao` (lấy từ `pos_tramblao/web/lib/firebase.ts`).
2. Đăng nhập: form mã cửa hàng + tên đăng nhập + mật khẩu → `staffSignIn` (vùng `asia-southeast1`) → `signInWithCustomToken(auth, token)` → gọi `chamCongEnsureMember({storeCode})` → vào dashboard. Bỏ `posSso.ts` dạng 2 app, bỏ đăng nhập email/Google/Apple và "Quên mật khẩu" email. Giữ thông báo lỗi tiếng Việt (khóa tạm khi sai mật khẩu nhiều lần…).
3. Rà các trang dashboard dùng `auth.currentUser.email` / provider / đổi mật khẩu → sửa cho phù hợp tài khoản POS (không có email).
4. `npm run build` + `npm run lint` (không thêm lỗi lint mới so với trước). Chụp màn hình trang đăng nhập để kiểm tra.
5. Kiểm tra domain web chấm công có trong **Authorized domains** của Auth `postramblao`; thiếu → thêm (Firebase Console / Identity Toolkit API).

### Bước F — Script chuyển dữ liệu (chạy một lần)
Viết `pos_tramblao/scripts/migrate_chamcong_to_pos/` (Node.js, firebase-admin, dùng ADC: `gcloud auth application-default login`; KHÔNG dùng / KHÔNG commit service account key):
1. Đọc nguồn `chamcongtramblao` (chỉ đọc), đích `postramblao`.
2. Bảng ghép **uid cũ → uid POS** theo mục 2.3 (đọc RTDB `postramblao`: `stores/*/users`, `chamcong_blao_links`). Bảng ghép **storeId cũ → storeCode POS** (từ `chamcong_blao_links/stores` hoặc ghép theo tên cửa hàng; không chắc → **[DỪNG HỎI]**).
3. **Rà toàn bộ code** (`cham_cong_tram/lib`, `cham_cong_web`, `functions`) để liệt kê MỌI trường chứa uid hoặc storeId (vd `userId`, `ownerId`, `createdBy`, `approvedBy`, `requestedBy`, `assignedTo`, `assigneeIds`, `targetUserIds`, `submittedBy`, `memberId`, `currentStoreId`, `storeIds`, `storeId`, mã doc là uid/storeId, đường dẫn inbox `notificationInboxes/{uid}/stores/{storeId}`…). Đưa danh sách này vào script (bảng cấu hình) và vào báo cáo.
4. Chép mọi collection ở mục 1 (trừ `kmt_*` nếu `postramblao` đã có dữ liệu `kmt_*` thật — khi đó **[DỪNG HỎI]**), giữ nguyên kiểu dữ liệu (Timestamp, GeoPoint, số…), đổi id doc và các trường theo 2 bảng ghép. Bỏ qua dữ liệu của uid không ghép được (ghi vào báo cáo). Không chép `notificationDevices`, `fcmToken(s)` (mã FCM cũ thuộc dự án cũ, không dùng được).
5. Storage: chép file từ bucket `chamcongtramblao` sang bucket `postramblao` (giữ đường dẫn, thay uid/storeId trong đường dẫn nếu có), rồi đổi URL trong Firestore (avatarUrl, ảnh báo cáo…) sang URL mới (tạo download token mới nếu cần).
6. Chế độ: `--dry-run` (mặc định, chỉ báo cáo: số doc mỗi collection, bảng ghép uid/storeId, doc bị bỏ qua, xung đột id ở đích) và `--apply`. Chạy lại `--apply` không tạo trùng (idempotent, ghi đè theo id).
7. Sau `--apply`: script tự đối chiếu số lượng doc nguồn/đích theo từng collection và kiểm tra ngẫu nhiên vài doc; xuất báo cáo `docs/migration_report_<ngày>.md`.
8. Trình tự chạy: dry-run → xem báo cáo (nếu có mục **[DỪNG HỎI]** thì hỏi) → apply.

### Bước G — Deploy & kiểm tra thật
Thứ tự (sau khi mọi test đạt):
1. `firebase deploy --only firestore:rules,firestore:indexes,storage --project postramblao`
2. `firebase deploy --only functions:pos,functions:chamcong --project postramblao`
3. Chạy script chuyển dữ liệu (Bước F) — nên chạy giờ quán nghỉ; nhắc chủ dự án báo nhân viên ngừng chấm công trên app cũ trong lúc chuyển.
4. Deploy web chấm công (Vercel — dự án đang nối với repo `chamcong_tramblao`, thư mục `cham_cong_web`) sau khi gộp nhánh; xác nhận biến môi trường / cấu hình trên Vercel không còn trỏ `chamcongtramblao`.
5. Build APK release (`flutter build apk --release`) để chủ dự án cài thử. **Lưu ý ký APK:** `android/app/build.gradle` đang ký bản release bằng khóa debug của máy build → build trên MacBook của chủ dự án để cài đè được (không cần gỡ app). Không đổi cấu hình ký.
6. Kiểm tra thật (ghi kết quả vào báo cáo):
   - Đăng nhập POS bằng tài khoản 2 nhân viên đã có dữ liệu → mở Chấm công → thấy đúng lịch sử chấm công / lương cũ.
   - Nhân viên POS chưa từng chấm công → mở Chấm công → được tạo thành viên, chấm công vào/ra (GPS, Wi-Fi) được.
   - Chủ / Quản lý: xem bảng công, duyệt ứng lương, xếp lịch.
   - Web chấm công: đăng nhập bằng tài khoản POS của Chủ → thấy dữ liệu.
   - Thông báo đẩy: đổi lịch / tạo ứng lương → máy nhận thông báo (Android + iOS).
   - App POS bán hàng, web POS, báo cáo, khách hàng (`kmt_customers`) vẫn chạy bình thường.

### Bước H — Dọn dẹp & tài liệu
1. Xóa code SSO cũ (`chamCongBlao.ts`, `pos_sso.dart`, `link_store_dialog.dart`, `cc_firebase_options.dart`, `cham_cong_web/lib/posSso.ts`, `docs/CHAMCONG_BLAO_SSO.md`).
2. Viết `pos_tramblao/docs/CHAMCONG_TREN_FIREBASE_POS.md`: kiến trúc mới, collection, Functions, rules, cách chạy lại script, cách khôi phục từ bản sao lưu.
3. Cập nhật `docs/database_schema.md` (thêm phần Firestore chấm công).
4. **Không** tắt / xóa dự án `chamcongtramblao` — ghi hướng dẫn để chủ dự án tự tắt sau vài ngày chạy ổn (tắt Functions, khóa rules Firestore/Storage thành chỉ đọc).

---

## 4. Quy tắc làm việc
- Commit nhỏ theo từng bước, message rõ ràng (tiếng Việt không dấu hoặc tiếng Anh), push lên nhánh `feat/chamcong-on-pos-firebase` ở cả hai repo. Gộp vào `main` chỉ sau khi Bước G đạt — **[DỪNG HỎI]** trước khi gộp.
- Không commit bí mật (service account key, token). Không đổi cấu hình ký APK. Không đổi rules Realtime Database POS trừ khi bắt buộc (nếu đổi phải giải thích).
- Giữ nguyên cách viết code hiện có (Flutter: Riverpod/Provider như mô-đun đang dùng; import tương đối trong `lib/chamcong_blao`; file Android có kết thúc dòng CRLF — giữ nguyên).
- Không xóa / sửa dữ liệu ở `chamcongtramblao`. Mọi thao tác ghi lên `postramblao` phải có sao lưu trước (Bước A).
- Gặp lỗi quyền (IAM, API chưa bật) → tự bật/cấp nếu tài khoản có quyền Owner, ghi lại đã làm gì; nếu không được → **[DỪNG HỎI]**.

## 5. Báo cáo cuối (bằng tiếng Việt)
- Danh sách thay đổi theo từng repo/nhánh/commit.
- Kết quả test (flutter test, functions vitest, functions_chamcong test, emulator rules, web build/lint).
- Đường dẫn bản sao lưu (Bước A).
- Báo cáo chuyển dữ liệu: bảng ghép uid/storeId, số doc từng collection nguồn/đích, những gì bị bỏ qua và lý do.
- Kết quả kiểm tra thật (Bước G.6), những gì chưa kiểm tra được.
- Việc còn lại cho chủ dự án (APNs key, tắt dự án cũ, phát hành app…).
