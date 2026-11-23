/**
 * Chấm Công Trạm BLAO — đăng nhập bằng TÀI KHOẢN POS (Cloud Functions, I/O). Logic thuần: chamCongBlaoLogic.ts.
 *
 * Dùng cho:
 *  - Mô-đun chấm công trong app POS (lib/chamcong_blao): nhân viên đã đăng nhập POS → tự vào chấm công.
 *  - Web quản lý chấm công: đăng nhập bằng mã cửa hàng + tài khoản POS (staffSignIn) rồi gọi hàm này.
 *
 * Dự án chấm công: CHAMCONG_BLAO_PROJECT_ID (mặc định "chamcongtramblao"). Ký custom token cho dự án đó cần
 * service account CỦA dự án chấm công: CHAMCONG_BLAO_SERVICE_ACCOUNT (vd. firebase-adminsdk-xxx@chamcongtramblao...),
 * và service account của Functions POS phải có quyền Service Account Token Creator trên account đó.
 * Xem docs/CHAMCONG_BLAO_SSO.md.
 *
 * Lưu trữ RTDB (ở GỐC → rules từ chối mọi client, chỉ Admin SDK):
 *   chamcong_blao_links/stores/{storeCode}            = { ccStoreId, ccStoreName, linkedByUid, linkedAt }
 *   chamcong_blao_links/users/{storeCode}/{posUid}    = ccUid
 *   chamcong_blao_links/byCc/{ccStoreId}/{ccUid}      = posUid   (một tài khoản chấm công chỉ thuộc 1 tài khoản POS)
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { App, applicationDefault, getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { UserProfile, isOwnerRole } from "./permissions";
import { buildNewMember, decideCcAccount, mapPosRoleToCc, memberAction, type CcMemberLite } from "./chamCongBlaoLogic";

const FUNCTION_REGION = "asia-southeast1";
const CC_APP_NAME = "chamcong_blao";
const db = () => admin.database();

function ccApp(): App {
  const existing = getApps().find((a) => a.name === CC_APP_NAME);
  if (existing) return existing;
  const projectId = (process.env.CHAMCONG_BLAO_PROJECT_ID || "").trim() || "chamcongtramblao";
  const serviceAccountId = (process.env.CHAMCONG_BLAO_SERVICE_ACCOUNT || "").trim() || undefined;
  return initializeApp({ projectId, credential: applicationDefault(), ...(serviceAccountId ? { serviceAccountId } : {}) }, CC_APP_NAME);
}
const ccFs = () => getFirestore(ccApp());

function cleanStore(raw: unknown): string {
  const s = typeof raw === "string" ? raw.trim().toUpperCase() : "";
  if (!/^[A-Z0-9_-]{2,30}$/.test(s)) throw new HttpsError("invalid-argument", "Mã cửa hàng không hợp lệ.");
  return s;
}

function cleanCcStoreId(raw: unknown): string {
  const s = typeof raw === "string" ? raw.trim() : "";
  if (!s || s.length > 128 || /[/.#$\[\]]/.test(s)) throw new HttpsError("invalid-argument", "Mã cửa hàng Chấm Công không hợp lệ.");
  return s;
}

const newLogId = () => `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
async function writeAudit(storeCode: string, entry: Record<string, unknown>): Promise<void> {
  await db().ref(`stores/${storeCode}/audit_logs/${newLogId()}`).set({ timestamp: Date.now(), ...entry }).catch(() => undefined);
}

async function loadPosCaller(storeCode: string, uid: string): Promise<UserProfile & { phone?: string }> {
  const [profileSnap, indexSnap] = await Promise.all([
    db().ref(`stores/${storeCode}/users/${uid}`).get(),
    db().ref(`userIndex/${uid}/${storeCode}`).get(),
  ]);
  if (!profileSnap.exists() || indexSnap.val() !== true) {
    throw new HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
  }
  const profile = profileSnap.val() as UserProfile & { phone?: string };
  if (profile.isActive === false) throw new HttpsError("permission-denied", "Tài khoản POS đã bị khóa.");
  return profile;
}

function ccPermissionError(e: unknown, what: string): never {
  if (e instanceof HttpsError) throw e;
  console.error(`chamcong_blao ${what} error`, (e as { code?: string })?.code, (e as Error)?.message);
  throw new HttpsError("internal", `Máy chủ chưa đủ quyền ${what} Chấm Công BLAO (xem docs/CHAMCONG_BLAO_SSO.md).`);
}

/**
 * chamCongBlaoSignIn({ storeCode }) — người gọi đã đăng nhập POS.
 * → { customToken, ccUid, ccStoreId, ccStoreName, isNewMember, linkedExisting }
 */
export const chamCongBlaoSignIn = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Vui lòng đăng nhập POS trước.");
  const data = (request.data || {}) as Record<string, unknown>;
  const storeCode = cleanStore(data.storeCode);
  const posUid = request.auth.uid;
  const caller = await loadPosCaller(storeCode, posUid);

  const linkSnap = await db().ref(`chamcong_blao_links/stores/${storeCode}`).get();
  const link = (linkSnap.val() || null) as { ccStoreId?: string; ccStoreName?: string } | null;
  if (!link?.ccStoreId) {
    throw new HttpsError(
      "failed-precondition",
      "Cửa hàng chưa được liên kết với Chấm Công BLAO. Chủ quán vào Quản lý → \"Liên kết Chấm Công BLAO\" để chọn cửa hàng chấm công.",
      { code: "STORE_NOT_LINKED" }
    );
  }
  const ccStoreId = link.ccStoreId;
  const fs = ccFs();

  // 1. Tài khoản chấm công tương ứng
  const userLinkRef = db().ref(`chamcong_blao_links/users/${storeCode}/${posUid}`);
  const existingLink = ((await userLinkRef.get()).val() as string | null) || null;
  let decision = decideCcAccount({ existingLink, posFullName: caller.fullName || "", members: [], takenCcUids: new Set(), storeCode, posUid });
  if (!existingLink) {
    let members: CcMemberLite[] = [];
    try {
      const snap = await fs.collection("stores").doc(ccStoreId).collection("members").get();
      members = snap.docs.map((d) => ({ uid: d.id, name: String(d.get("name") || ""), status: String(d.get("status") || "") }));
    } catch (e) {
      ccPermissionError(e, "đọc thành viên");
    }
    const takenSnap = await db().ref(`chamcong_blao_links/byCc/${ccStoreId}`).get();
    const taken = new Set(Object.keys((takenSnap.val() || {}) as Record<string, unknown>));
    decision = decideCcAccount({ existingLink: null, posFullName: caller.fullName || "", members, takenCcUids: taken, storeCode, posUid });
  }
  let ccUid = decision.ccUid;

  // Giữ chỗ uid chấm công (2 tài khoản POS không được nối vào cùng 1 tài khoản chấm công)
  const claim = await db()
    .ref(`chamcong_blao_links/byCc/${ccStoreId}/${ccUid}`)
    .transaction((cur) => (cur == null || cur === posUid ? posUid : undefined));
  if (!claim.committed) {
    if (decision.kind === "LINKED") throw new HttpsError("internal", "Liên kết tài khoản chấm công bị trùng. Liên hệ Chủ quán.");
    decision = decideCcAccount({ existingLink: null, posFullName: "", members: [], takenCcUids: new Set(), storeCode, posUid });
    ccUid = decision.ccUid;
    await db().ref(`chamcong_blao_links/byCc/${ccStoreId}/${ccUid}`).set(posUid);
  }

  // 2. Thành viên + hồ sơ bên chấm công
  const memberRef = fs.collection("stores").doc(ccStoreId).collection("members").doc(ccUid);
  let isNewMember = false;
  try {
    const memberSnap = await memberRef.get();
    const action = memberAction(memberSnap.exists ? (memberSnap.data() as Record<string, unknown>) : null);
    if (action === "KICKED") {
      throw new HttpsError("permission-denied", "Bạn đã bị xóa khỏi cửa hàng chấm công. Liên hệ Chủ quán.", { code: "CC_MEMBER_KICKED" });
    }
    if (action === "CREATE") {
      isNewMember = true;
      await memberRef.set({
        ...buildNewMember({
          ccUid,
          name: caller.fullName || caller.username || "Nhân viên",
          phone: caller.phone,
          employeeCode: caller.employeeCode,
          role: mapPosRoleToCc(caller.roleId, caller.isRootOwner),
        }),
        joinedAt: Timestamp.now(),
      });
    } else if (action === "ACTIVATE") {
      await memberRef.set({ status: "active" }, { merge: true });
    }
    await fs
      .collection("users")
      .doc(ccUid)
      .set(
        {
          id: ccUid,
          ...(isNewMember ? { name: caller.fullName || caller.username || "Nhân viên", email: "", createdAt: new Date().toISOString() } : {}),
          currentStoreId: ccStoreId,
          storeIds: FieldValue.arrayUnion(ccStoreId),
          posLink: { storeCode, posUid, username: caller.username || "" },
        },
        { merge: true }
      );
  } catch (e) {
    ccPermissionError(e, "ghi dữ liệu");
  }

  // 3. Phiên đăng nhập dự án chấm công
  let customToken: string;
  try {
    customToken = await getAuth(ccApp()).createCustomToken(ccUid, { via: "pos", posStoreCode: storeCode });
  } catch (e) {
    ccPermissionError(e, "cấp phiên đăng nhập");
  }

  if (!existingLink) {
    await userLinkRef.set(ccUid);
    await writeAudit(storeCode, {
      action: "CHAMCONG_BLAO_LINKED",
      username: caller.username || posUid,
      userFullName: caller.fullName || "",
      userRole: caller.roleId || "",
      targetType: "USER",
      targetId: posUid,
      details:
        decision.kind === "MATCHED"
          ? `Nối tài khoản POS @${caller.username} với tài khoản chấm công cũ cùng tên (${ccUid}) — giữ lịch sử chấm công`
          : `Tạo tài khoản chấm công mới ${ccUid} cho @${caller.username}${decision.kind === "NEW" && decision.ambiguous ? " (có nhiều người trùng tên, không tự nối)" : ""}`,
    });
  }

  return {
    customToken,
    ccUid,
    ccStoreId,
    ccStoreName: link.ccStoreName || "",
    isNewMember,
    linkedExisting: decision.kind === "MATCHED",
  };
});

/** Danh sách cửa hàng bên Chấm Công BLAO (Chủ quán chọn để liên kết) + liên kết hiện tại */
export const chamCongBlaoListStores = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Vui lòng đăng nhập POS trước.");
  const storeCode = cleanStore((request.data || {}).storeCode);
  const caller = await loadPosCaller(storeCode, request.auth.uid);
  if (!isOwnerRole(caller.roleId, caller.isRootOwner)) throw new HttpsError("permission-denied", "Chỉ Chủ quán mới được liên kết.");
  let stores: { ccStoreId: string; name: string; code: string }[] = [];
  try {
    const snap = await ccFs().collection("stores").limit(100).get();
    stores = snap.docs
      .map((d) => ({ ccStoreId: d.id, name: String(d.get("name") || d.id), code: String(d.get("code") || d.get("storeCode") || "") }))
      .sort((a, b) => a.name.localeCompare(b.name, "vi"));
  } catch (e) {
    ccPermissionError(e, "đọc cửa hàng");
  }
  const current = (await db().ref(`chamcong_blao_links/stores/${storeCode}`).get()).val() || null;
  return { stores, current };
});

/** Liên kết cửa hàng POS với một cửa hàng Chấm Công BLAO (Chủ quán) */
export const chamCongBlaoLinkStore = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Vui lòng đăng nhập POS trước.");
  const data = (request.data || {}) as Record<string, unknown>;
  const storeCode = cleanStore(data.storeCode);
  const ccStoreId = cleanCcStoreId(data.ccStoreId);
  const caller = await loadPosCaller(storeCode, request.auth.uid);
  if (!isOwnerRole(caller.roleId, caller.isRootOwner)) throw new HttpsError("permission-denied", "Chỉ Chủ quán mới được liên kết.");
  let name = ccStoreId;
  try {
    const doc = await ccFs().collection("stores").doc(ccStoreId).get();
    if (!doc.exists) throw new HttpsError("not-found", "Không tìm thấy cửa hàng chấm công đã chọn.");
    name = String(doc.get("name") || ccStoreId);
  } catch (e) {
    ccPermissionError(e, "đọc cửa hàng");
  }
  await db().ref(`chamcong_blao_links/stores/${storeCode}`).set({ ccStoreId, ccStoreName: name, linkedByUid: request.auth.uid, linkedAt: Date.now() });
  await writeAudit(storeCode, {
    action: "CHAMCONG_BLAO_STORE_LINKED",
    username: caller.username || request.auth.uid,
    userFullName: caller.fullName || "",
    userRole: caller.roleId || "",
    targetType: "STORE",
    targetId: storeCode,
    details: `Liên kết cửa hàng với Chấm Công BLAO: ${name} (${ccStoreId})`,
  });
  return { ccStoreId, ccStoreName: name };
});
