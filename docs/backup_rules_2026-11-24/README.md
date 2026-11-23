# Sao lưu trước khi chuyển Chấm Công sang Firebase POS (`2026-11-24`)

- `storage.rules`: rules Storage đang deploy trên `postramblao` (`projects/postramblao/rulesets/6c2d2018-b800-48c3-a559-59d7242596f4`).
- `releases.json`: metadata release Firebase Rules của `postramblao` trước khi triển khai (`firestore` chưa có release vì Cloud Firestore chưa từng được bật trên `postramblao` trước ngày `2026-11-24`).
- `postramblao_indexes.json`: kết quả `collectionGroups/-/indexes` của `postramblao` sau khi bật Firestore (trống).
- `chamcong_blao_links.json`: giá trị node RTDB `/chamcong_blao_links` trên `postramblao` (`null` — chưa có liên kết SSO nào).
- **Cloud Storage Firestore Export:**
  - `chamcongtramblao`: `gs://chamcongtramblao-backup/backup-2026-11-24`
  - `postramblao`: `gs://postramblao-backup/backup-2026-11-24`
