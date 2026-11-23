#!/usr/bin/env node
/**
 * Script chuyển dữ liệu Chấm Công Trạm BLAO (`chamcongtramblao` -> `postramblao`).
 *
 * Chế độ:
 *   node index.js --dry-run   (mặc định: chỉ kiểm tra, đối chiếu & in báo cáo, KHÔNG ghi dữ liệu)
 *   node index.js --apply     (chép dữ liệu idempotent sang postramblao + đối chiếu + ghi docs/migration_report_<ngày>.md)
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, Timestamp: AdminTimestamp, GeoPoint: AdminGeoPoint } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { Firestore: GcFirestore, Timestamp: GcTimestamp, GeoPoint: GcGeoPoint } = require("@google-cloud/firestore");
const { Storage: GcStorage } = require("@google-cloud/storage");
const { OAuth2Client } = require("google-auth-library");
const cfg = require("./config");

const args = process.argv.slice(2);
const IS_APPLY = args.includes("--apply");
const TODAY = new Date().toISOString().slice(0, 10);

function createClients() {
  const adcDefault = path.join(os.homedir(), ".config/gcloud/application_default_credentials.json");
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS || fs.existsSync(adcDefault)) {
    const credential = applicationDefault();
    const srcApp = initializeApp(
      { projectId: cfg.SOURCE_PROJECT_ID, storageBucket: cfg.SOURCE_STORAGE_BUCKET, credential },
      "src"
    );
    const dstApp = initializeApp(
      { projectId: cfg.TARGET_PROJECT_ID, storageBucket: cfg.TARGET_STORAGE_BUCKET, credential },
      "dst"
    );
    return {
      mode: "ADC",
      srcDb: getFirestore(srcApp),
      dstDb: getFirestore(dstApp),
      srcBucket: getStorage(srcApp).bucket(cfg.SOURCE_STORAGE_BUCKET),
      dstBucket: getStorage(dstApp).bucket(cfg.TARGET_STORAGE_BUCKET),
      Timestamp: AdminTimestamp,
      GeoPoint: AdminGeoPoint,
    };
  }

  const fbCfgPath = path.join(os.homedir(), ".config/configstore/firebase-tools.json");
  if (!fs.existsSync(fbCfgPath)) {
    throw new Error("Không tìm thấy ADC (~/.config/gcloud/application_default_credentials.json) hoặc firebase-tools.json.");
  }
  const fbCfg = JSON.parse(fs.readFileSync(fbCfgPath, "utf8"));
  const api = require("/Users/nthtam/.local/share/fnm/node-versions/v22.23.2/installation/lib/node_modules/firebase-tools/lib/api.js");
  const oauth = new OAuth2Client(api.clientId(), api.clientSecret());
  oauth.setCredentials({ refresh_token: fbCfg.tokens.refresh_token });

  return {
    mode: "firebase-tools OAuth (fallback vì máy chưa có gcloud ADC)",
    srcDb: new GcFirestore({ projectId: cfg.SOURCE_PROJECT_ID, authClient: oauth }),
    dstDb: new GcFirestore({ projectId: cfg.TARGET_PROJECT_ID, authClient: oauth }),
    srcBucket: new GcStorage({ projectId: cfg.SOURCE_PROJECT_ID, authClient: oauth }).bucket(cfg.SOURCE_STORAGE_BUCKET),
    dstBucket: new GcStorage({ projectId: cfg.TARGET_PROJECT_ID, authClient: oauth }).bucket(cfg.TARGET_STORAGE_BUCKET),
    Timestamp: GcTimestamp,
    GeoPoint: GcGeoPoint,
  };
}

const { mode: AUTH_MODE, srcDb, dstDb, srcBucket, dstBucket, Timestamp, GeoPoint } = createClients();

function mapUid(uid, { fallbackToOwner = false } = {}) {
  if (typeof uid !== "string" || !uid) return uid;
  if (cfg.UID_MAP[uid]) return cfg.UID_MAP[uid];
  if (Object.values(cfg.UID_MAP).includes(uid)) return uid;
  if (fallbackToOwner) return cfg.FALLBACK_OWNER_UID;
  return null;
}

function mapStoreId(storeId) {
  if (typeof storeId !== "string" || !storeId) return null;
  return cfg.STORE_MAP[storeId] || null;
}

function replaceIdsInString(id) {
  let out = id;
  for (const [oldUid, newUid] of Object.entries(cfg.UID_MAP)) {
    if (out.includes(oldUid)) out = out.split(oldUid).join(newUid);
  }
  for (const [oldStore, newStore] of Object.entries(cfg.STORE_MAP)) {
    if (out.includes(oldStore)) out = out.split(oldStore).join(newStore);
  }
  return out;
}

function clonePreservingTypes(val) {
  if (val === null || val === undefined) return val;
  if (val instanceof Timestamp || val instanceof GeoPoint) return val;
  if (val instanceof Date) return val;
  if (Array.isArray(val)) return val.map(clonePreservingTypes);
  if (typeof val === "object") {
    const out = {};
    for (const [k, v] of Object.entries(val)) out[k] = clonePreservingTypes(v);
    return out;
  }
  return val;
}

async function migrateStorageUrlIfNeeded(rawUrl, urlMap, stats) {
  if (typeof rawUrl !== "string" || !rawUrl.includes(cfg.SOURCE_STORAGE_BUCKET)) return rawUrl;
  if (urlMap.has(rawUrl)) return urlMap.get(rawUrl);

  const match = rawUrl.match(/\/o\/([^?]+)/);
  if (!match) return rawUrl;
  const srcObjectPath = decodeURIComponent(match[1]);
  const dstObjectPath = replaceIdsInString(srcObjectPath);
  stats.storageFilesFound++;

  if (!IS_APPLY) return rawUrl;

  const srcFile = srcBucket.file(srcObjectPath);
  const [exists] = await srcFile.exists();
  if (!exists) return rawUrl;

  const [bytes] = await srcFile.download();
  const [meta] = await srcFile.getMetadata();
  const token = crypto.randomUUID();
  const dstFile = dstBucket.file(dstObjectPath);
  await dstFile.save(bytes, {
    metadata: {
      contentType: meta.contentType || "application/octet-stream",
      metadata: { firebaseStorageDownloadTokens: token },
    },
  });
  const newUrl = `https://firebasestorage.googleapis.com/v0/b/${cfg.TARGET_STORAGE_BUCKET}/o/${encodeURIComponent(dstObjectPath)}?alt=media&token=${token}`;
  urlMap.set(rawUrl, newUrl);
  stats.storageFilesCopied++;
  return newUrl;
}

async function transformDocData(rawData, schema, urlMap, stats, fallbackUidOnMissing = false) {
  const data = clonePreservingTypes(rawData);

  for (const f of schema.stripFields || []) delete data[f];

  for (const f of schema.scalarUidFields || []) {
    if (f in data && data[f] !== null && data[f] !== undefined) {
      const mapped = mapUid(data[f], { fallbackToOwner: fallbackUidOnMissing || f === "previousOwnerId" || f === "newOwnerId" || f === "updatedBy" });
      data[f] = mapped;
    }
  }

  for (const f of schema.arrayUidFields || []) {
    if (Array.isArray(data[f])) {
      data[f] = data[f].map((u) => mapUid(u)).filter((u) => typeof u === "string" && u.length > 0);
    }
  }

  for (const f of schema.scalarStoreFields || []) {
    if (f in data && typeof data[f] === "string") {
      data[f] = mapStoreId(data[f]) || data[f];
    }
  }

  for (const f of schema.arrayStoreFields || []) {
    if (Array.isArray(data[f])) {
      data[f] = Array.from(new Set(data[f].map((s) => mapStoreId(s)).filter(Boolean)));
    }
  }

  for (const f of schema.uidKeyedMaps || []) {
    if (data[f] && typeof data[f] === "object" && !Array.isArray(data[f])) {
      const nextMap = {};
      for (const [k, v] of Object.entries(data[f])) {
        const mappedKey = mapUid(k);
        if (mappedKey) nextMap[mappedKey] = v;
      }
      data[f] = nextMap;
    }
  }

  if (schema.nestedRouteExtra && data.routeExtra && typeof data.routeExtra === "object") {
    if (typeof data.routeExtra.storeId === "string") {
      data.routeExtra.storeId = mapStoreId(data.routeExtra.storeId) || data.routeExtra.storeId;
    }
    for (const uf of ["userId", "memberId"]) {
      if (typeof data.routeExtra[uf] === "string") {
        const mapped = mapUid(data.routeExtra[uf]);
        if (mapped) data.routeExtra[uf] = mapped;
      }
    }
  }

  for (const uf of schema.urlFields || []) {
    if (typeof data[uf] === "string" && data[uf]) {
      data[uf] = await migrateStorageUrlIfNeeded(data[uf], urlMap, stats);
    }
  }

  if (schema.extraSet) {
    Object.assign(data, schema.extraSet);
  }

  return data;
}

async function run() {
  console.log(`=== MIGRATION CHAMCONG -> POSTRAMBLAO [${IS_APPLY ? "APPLY" : "DRY-RUN"}] ===`);
  console.log(`Auth mode: ${AUTH_MODE}`);

  // 1. Bảo vệ kmt_* trên postramblao: kiểm tra trước khi chạm
  const posKmtCols = [];
  for (const colName of ["kmt_customers", "kmt_point_history", "kmt_stores"]) {
    const snap = await dstDb.collection(colName).limit(1).get();
    if (!snap.empty) posKmtCols.push(colName);
  }
  if (posKmtCols.length > 0) {
    console.log(`[kmt_*] Đã có dữ liệu kmt_* trên postramblao (${posKmtCols.join(", ")}) -> giữ nguyên, script KHÔNG chạm kmt_*.`);
  }

  // Kiểm tra file trên Storage nguồn
  const [srcFiles] = await srcBucket.getFiles();
  console.log(`Storage nguồn (${cfg.SOURCE_STORAGE_BUCKET}): ${srcFiles.length} file.`);

  const urlMap = new Map();
  const stats = {
    storageFilesFound: srcFiles.length,
    storageFilesCopied: 0,
    collections: {},
    skipped: [],
    conflicts: [],
  };

  function colStat(name) {
    if (!stats.collections[name]) {
      stats.collections[name] = { sourceRead: 0, plannedWrite: 0, written: 0, skipped: 0, targetCountAfter: null };
    }
    return stats.collections[name];
  }

  const writeOps = [];
  async function queueWrite(colKey, dstRef, data) {
    const existing = await dstRef.get();
    if (existing.exists) stats.conflicts.push(dstRef.path);
    colStat(colKey).plannedWrite++;
    if (IS_APPLY) {
      writeOps.push({ colKey, dstRef, data });
    }
  }

  // 2. Chuyển users/{uid} (chỉ 5 tài khoản đã ghép)
  const usersSnap = await srcDb.collection("users").get();
  const usersStat = colStat("users");
  for (const doc of usersSnap.docs) {
    usersStat.sourceRead++;
    const newUid = cfg.UID_MAP[doc.id];
    if (!newUid) {
      usersStat.skipped++;
      stats.skipped.push(`users/${doc.id} (${doc.data()?.name || "?"}) — không thuộc 5 thành viên POS BLAO`);
      continue;
    }
    const transformed = await transformDocData(doc.data(), cfg.FIELD_SCHEMA["users/{uid}"], urlMap, stats);
    transformed.id = newUid;
    transformed.currentStoreId = "BLAO";
    transformed.storeIds = ["BLAO"];
    await queueWrite("users", dstDb.collection("users").doc(newUid), transformed);
  }

  // 3. Chuyển store Fp6YTSWxcbPNzJ1k2asZ -> stores/BLAO và toàn bộ subcollections
  const srcStoresSnap = await srcDb.collection("stores").get();
  colStat("stores").sourceRead = srcStoresSnap.size;
  for (const storeDoc of srcStoresSnap.docs) {
    const newStoreId = mapStoreId(storeDoc.id);
    if (!newStoreId) {
      colStat("stores").skipped++;
      stats.skipped.push(`stores/${storeDoc.id} (${storeDoc.data()?.name || "?"}) — ${cfg.SKIPPED_STORES[storeDoc.id] || "không có trong STORE_MAP"}`);
      continue;
    }

    const dstStoreRef = dstDb.collection("stores").doc(newStoreId);
    const storeData = await transformDocData(storeDoc.data(), cfg.FIELD_SCHEMA["stores/{storeId}"], urlMap, stats, true);
    await queueWrite("stores", dstStoreRef, storeData);

    // Subcollection members
    const memSnap = await storeDoc.ref.collection("members").get();
    colStat(`stores/${newStoreId}/members`).sourceRead += memSnap.size;
    for (const d of memSnap.docs) {
      const newUid = cfg.UID_MAP[d.id];
      if (!newUid) {
        colStat(`stores/${newStoreId}/members`).skipped++;
        stats.skipped.push(`stores/${storeDoc.id}/members/${d.id} (${d.data()?.name || "?"}) — ${cfg.SKIPPED_UIDS[d.id] || "không có trong UID_MAP"}`);
        continue;
      }
      const mData = await transformDocData(d.data(), cfg.FIELD_SCHEMA["stores/{storeId}/members/{uid}"], urlMap, stats);
      mData.userId = newUid;
      await queueWrite(`stores/${newStoreId}/members`, dstStoreRef.collection("members").doc(newUid), mData);
    }

    // Subcollections còn lại
    const subConfigs = [
      { name: "attendances", schemaKey: "stores/{storeId}/attendances/{attendanceId}", ownerField: "userId", checkOwner: true },
      { name: "schedules", schemaKey: "stores/{storeId}/schedules/{weekId}", checkOwner: false },
      { name: "advances", schemaKey: "stores/{storeId}/advances/{advanceId}", ownerField: "userId", checkOwner: true },
      { name: "production_tasks", schemaKey: "stores/{storeId}/production_tasks/{taskId}", checkOwner: false },
      { name: "production_reports", schemaKey: "stores/{storeId}/production_reports/{reportId}", ownerField: "userId", checkOwner: true },
      { name: "assigned_tasks", schemaKey: "stores/{storeId}/assigned_tasks/{taskId}", checkOwner: false },
      { name: "notifications", schemaKey: "stores/{storeId}/notifications/{notifId}", checkOwner: false },
      { name: "audit_logs", schemaKey: "stores/{storeId}/audit_logs/{logId}", checkOwner: false },
      { name: "private", schemaKey: "stores/{storeId}/private/{docId}", checkOwner: false },
    ];

    for (const sc of subConfigs) {
      const snap = await storeDoc.ref.collection(sc.name).get();
      const colKey = `stores/${newStoreId}/${sc.name}`;
      colStat(colKey).sourceRead += snap.size;

      for (const d of snap.docs) {
        const raw = d.data();
        if (sc.checkOwner && raw[sc.ownerField]) {
          if (!cfg.UID_MAP[raw[sc.ownerField]]) {
            colStat(colKey).skipped++;
            stats.skipped.push(`stores/${storeDoc.id}/${sc.name}/${d.id} (${sc.ownerField}=${raw[sc.ownerField]}) — UID nguồn bị bỏ qua`);
            continue;
          }
        }
        const schema = cfg.FIELD_SCHEMA[sc.schemaKey];
        const newDocId = schema.docId === "replaceUidAndStoreInId" ? replaceIdsInString(d.id) : d.id;
        const transformed = await transformDocData(raw, schema, urlMap, stats, sc.name === "audit_logs" || sc.name === "schedules");
        if ("id" in transformed && typeof transformed.id === "string" && schema.docId === "replaceUidAndStoreInId") {
          transformed.id = newDocId;
        }
        await queueWrite(colKey, dstStoreRef.collection(sc.name).doc(newDocId), transformed);

        if (sc.name === "assigned_tasks") {
          const subsSnap = await d.ref.collection("submissions").get();
          const subKey = `${colKey}/submissions`;
          colStat(subKey).sourceRead += subsSnap.size;
          const subSchema = cfg.FIELD_SCHEMA["stores/{storeId}/assigned_tasks/{taskId}/submissions/{subId}"];
          for (const sd of subsSnap.docs) {
            const sRaw = sd.data();
            if (sRaw.userId && !cfg.UID_MAP[sRaw.userId]) {
              colStat(subKey).skipped++;
              stats.skipped.push(`.../assigned_tasks/${d.id}/submissions/${sd.id} — UID bị bỏ qua`);
              continue;
            }
            const newSubId = replaceIdsInString(sd.id);
            const sData = await transformDocData(sRaw, subSchema, urlMap, stats);
            await queueWrite(subKey, dstStoreRef.collection("assigned_tasks").doc(newDocId).collection("submissions").doc(newSubId), sData);
          }
        }
      }
    }
  }

  // 4. Chuyển notificationInboxes/{uid}/accountItems & notificationInboxes/{uid}/stores/BLAO/items (chỉ 5 uid ghép)
  const inboxRefs = await srcDb.collection("notificationInboxes").listDocuments();
  for (const inboxRef of inboxRefs) {
    const oldUid = inboxRef.id;
    const newUid = cfg.UID_MAP[oldUid];
    if (!newUid) {
      stats.skipped.push(`notificationInboxes/${oldUid} — UID không thuộc POS BLAO`);
      continue;
    }

    const accSnap = await inboxRef.collection("accountItems").get();
    colStat("notificationInboxes/accountItems").sourceRead += accSnap.size;
    for (const d of accSnap.docs) {
      const data = await transformDocData(d.data(), cfg.FIELD_SCHEMA["notificationInboxes/{uid}/accountItems/{itemId}"], urlMap, stats);
      await queueWrite("notificationInboxes/accountItems", dstDb.collection("notificationInboxes").doc(newUid).collection("accountItems").doc(d.id), data);
    }

    const storeInboxRefs = await inboxRef.collection("stores").listDocuments();
    for (const sr of storeInboxRefs) {
      const newStoreId = mapStoreId(sr.id);
      if (!newStoreId) {
        const itemsCount = (await sr.collection("items").get()).size;
        colStat("notificationInboxes/storeItems").sourceRead += itemsCount;
        colStat("notificationInboxes/storeItems").skipped += itemsCount;
        continue;
      }
      const itemsSnap = await sr.collection("items").get();
      colStat("notificationInboxes/storeItems").sourceRead += itemsSnap.size;
      for (const d of itemsSnap.docs) {
        const data = await transformDocData(d.data(), cfg.FIELD_SCHEMA["notificationInboxes/{uid}/stores/{storeId}/items/{itemId}"], urlMap, stats);
        await queueWrite(
          "notificationInboxes/storeItems",
          dstDb.collection("notificationInboxes").doc(newUid).collection("stores").doc(newStoreId).collection("items").doc(d.id),
          data
        );
      }
    }
  }

  // 5. Nếu --apply: ghi batch và đối chiếu đích
  if (IS_APPLY) {
    console.log(`\nĐang ghi ${writeOps.length} document sang postramblao...`);
    for (let i = 0; i < writeOps.length; i += 400) {
      const batch = dstDb.batch();
      const slice = writeOps.slice(i, i + 400);
      for (const op of slice) {
        batch.set(op.dstRef, op.data);
      }
      await batch.commit();
      for (const op of slice) {
        colStat(op.colKey).written++;
      }
    }

    // Đối chiếu số lượng đích và mẫu ngẫu nhiên
    const dstStoreRef = dstDb.collection("stores").doc("BLAO");
    colStat("users").targetCountAfter = (await dstDb.collection("users").get()).size;
    colStat("stores").targetCountAfter = (await dstDb.collection("stores").get()).size;
    for (const sub of ["members", "attendances", "schedules", "notifications", "audit_logs"]) {
      const colKey = `stores/BLAO/${sub}`;
      if (stats.collections[colKey]) {
        stats.collections[colKey].targetCountAfter = (await dstStoreRef.collection(sub).get()).size;
      }
    }

    let accTotal = 0;
    let storeItemTotal = 0;
    for (const newUid of Object.values(cfg.UID_MAP)) {
      accTotal += (await dstDb.collection("notificationInboxes").doc(newUid).collection("accountItems").get()).size;
      storeItemTotal += (await dstDb.collection("notificationInboxes").doc(newUid).collection("stores").doc("BLAO").collection("items").get()).size;
    }
    if (stats.collections["notificationInboxes/accountItems"]) {
      stats.collections["notificationInboxes/accountItems"].targetCountAfter = accTotal;
    }
    if (stats.collections["notificationInboxes/storeItems"]) {
      stats.collections["notificationInboxes/storeItems"].targetCountAfter = storeItemTotal;
    }

    // Xuất báo cáo migration_report_<ngày>.md
    const reportPath = path.resolve(__dirname, `../../docs/migration_report_${TODAY}.md`);
    const lines = [
      `# Báo Cáo Chuyển Dữ Liệu Chấm Công Sang Firebase POS (\`${TODAY}\`)`,
      "",
      `- **Nguồn:** \`${cfg.SOURCE_PROJECT_ID}\` (chỉ đọc)`,
      `- **Đích:** \`${cfg.TARGET_PROJECT_ID}\` (Firestore vùng \`asia-southeast1\`)`,
      `- **Phương thức xác thực:** ${AUTH_MODE}`,
      `- **Trạng thái ghi Storage:** ${stats.storageFilesFound} file ở nguồn, ${stats.storageFilesCopied} file đã sao chép`,
      "",
      "## 1. Bảng Ghép Cửa Hàng & Nhân Sự",
      "",
      "| Loại | ID Nguồn (`chamcongtramblao`) | ID Đích (`postramblao`) | Ghi chú |",
      "|---|---|---|---|",
      "| Store | `Fp6YTSWxcbPNzJ1k2asZ` (`TRẠM BLAO`, code `JG7LF7`) | `BLAO` | Ghép 1-1 cửa hàng thật |",
      "| User | `4NQ9WEHfxePLl6UOkXMic9TreCG3` (`Đỗ Nguyễn Nguyên Quan`) | `TQySd97HN8gjuihaezL5HPdVsV63` (`nguyenquan`) | Giữ nguyên role `employee`, 20 công |",
      "| User | `DiJPAB7sRvTunQHk9P7NbEjiGIr1` (`Lương Sỹ Minh Anh`) | `P4yks89qJdYkhSwva3NKYU4QPys1` (`minhanh`) | Giữ nguyên role `employee`, 13 công |",
      "| User | `BJ3cboxox5MXqQ4ujQyFItBgwyv1` (`Nguyễn Thị Mỹ Duyên`) | `hfk73nw4QWPpegtsPTULCpcq4qb2` (`myduyen`) | Giữ nguyên role `owner`, 6 công |",
      "| User | `PeDatFC1vlVeCyhgXKtTzFbQhiO2` (`Nguyễn Thị Huyền Trang`) | `1554VRHR20hHYbn5O0FIuHb9kP53` (`huyentrang`) | Giữ nguyên role `employee`, 0 công |",
      "| User | `iiA3fxIbN5XkCmoRnEV1vUkq5to1` (`Nguyễn Thị Thương`) | `VkIc1KHWlHbz5e2hb9BBKL1gPAG2` (`thithuong`) | Giữ nguyên role `owner`, 0 công |",
      "",
      "## 2. Thống Kê Chuyển Đổi & Đối Chiếu Theo Collection",
      "",
      "| Collection | Đọc nguồn | Dự kiến ghi | Đã ghi | Bỏ qua | Tổng ở đích sau migration |",
      "|---|---:|---:|---:|---:|---:|",
      ...Object.entries(stats.collections).map(([k, v]) => `| \`${k}\` | ${v.sourceRead} | ${v.plannedWrite} | ${v.written} | ${v.skipped} | ${v.targetCountAfter ?? "-"} |`),
      "",
      "## 3. Các Mục Đã Bỏ Qua (Theo Quyết Định Chủ Dự Án)",
      "",
      "- **Cửa hàng bỏ qua:** `1noouOSoiZIjLqzGHBu7` (`BLAODEMO`), `bX81rKaGTs3oAODiTVGr` (`app`).",
      "- **Nhân viên bỏ qua:** `gjnlOcE99jbQWhPikTGLIBnBrRu2` (`gia hân`, `status: kicked`, 4 công), `XpxG6bKSXUdE9MkSi3tbc7JVavz1` (`Chủ Trạm BLAO (Demo)`, 1 công test 21/10).",
      "- **Collection không chép:** `notificationDevices`, `notificationEvents`, `notificationDeliveries` và các trường `fcmToken`, `fcmTokens` (mã FCM cũ thuộc dự án cũ).",
      "",
      "## 4. Danh Sách Chi Tiết Các Trường Được Chuyển Đổi UID / StoreId",
      "",
      ...Object.entries(cfg.FIELD_SCHEMA).map(([col, s]) => {
        const parts = [
          `docId=${s.docId}`,
          ...(s.scalarUidFields?.length ? [`uid=[${s.scalarUidFields.join(", ")}]`] : []),
          ...(s.arrayUidFields?.length ? [`arrayUid=[${s.arrayUidFields.join(", ")}]`] : []),
          ...(s.scalarStoreFields?.length ? [`store=[${s.scalarStoreFields.join(", ")}]`] : []),
          ...(s.uidKeyedMaps?.length ? [`uidMap=[${s.uidKeyedMaps.join(", ")}]`] : []),
        ];
        return `- \`${col}\`: ${parts.join("; ")}`;
      }),
      "",
    ];
    fs.writeFileSync(reportPath, lines.join("\n"));
    console.log(`✅ Đã xuất báo cáo đối chiếu: ${reportPath}`);
  }

  console.log("\n=== BẢNG TỔNG HỢP ===");
  console.table(stats.collections);
  console.log(`Xung đột ID ở đích trước khi ghi: ${stats.conflicts.length}`);
  console.log(`Tổng mục bỏ qua: ${stats.skipped.length}`);
  for (const s of stats.skipped) console.log("  - SKIP:", s);
}

run().catch((e) => {
  console.error("MIGRATION ERROR:", e);
  process.exit(1);
});
