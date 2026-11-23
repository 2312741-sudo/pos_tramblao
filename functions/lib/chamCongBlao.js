"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.chamCongBlaoLinkStore = exports.chamCongBlaoListStores = exports.chamCongBlaoSignIn = void 0;
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
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const app_1 = require("firebase-admin/app");
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const permissions_1 = require("./permissions");
const chamCongBlaoLogic_1 = require("./chamCongBlaoLogic");
const FUNCTION_REGION = "asia-southeast1";
const CC_APP_NAME = "chamcong_blao";
const db = () => admin.database();
function ccApp() {
    const existing = (0, app_1.getApps)().find((a) => a.name === CC_APP_NAME);
    if (existing)
        return existing;
    const projectId = (process.env.CHAMCONG_BLAO_PROJECT_ID || "").trim() || "chamcongtramblao";
    const serviceAccountId = (process.env.CHAMCONG_BLAO_SERVICE_ACCOUNT || "").trim() || undefined;
    return (0, app_1.initializeApp)({ projectId, credential: (0, app_1.applicationDefault)(), ...(serviceAccountId ? { serviceAccountId } : {}) }, CC_APP_NAME);
}
const ccFs = () => (0, firestore_1.getFirestore)(ccApp());
function cleanStore(raw) {
    const s = typeof raw === "string" ? raw.trim().toUpperCase() : "";
    if (!/^[A-Z0-9_-]{2,30}$/.test(s))
        throw new https_1.HttpsError("invalid-argument", "Mã cửa hàng không hợp lệ.");
    return s;
}
function cleanCcStoreId(raw) {
    const s = typeof raw === "string" ? raw.trim() : "";
    if (!s || s.length > 128 || /[/.#$\[\]]/.test(s))
        throw new https_1.HttpsError("invalid-argument", "Mã cửa hàng Chấm Công không hợp lệ.");
    return s;
}
const newLogId = () => `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
async function writeAudit(storeCode, entry) {
    await db().ref(`stores/${storeCode}/audit_logs/${newLogId()}`).set({ timestamp: Date.now(), ...entry }).catch(() => undefined);
}
async function loadPosCaller(storeCode, uid) {
    const [profileSnap, indexSnap] = await Promise.all([
        db().ref(`stores/${storeCode}/users/${uid}`).get(),
        db().ref(`userIndex/${uid}/${storeCode}`).get(),
    ]);
    if (!profileSnap.exists() || indexSnap.val() !== true) {
        throw new https_1.HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
    }
    const profile = profileSnap.val();
    if (profile.isActive === false)
        throw new https_1.HttpsError("permission-denied", "Tài khoản POS đã bị khóa.");
    return profile;
}
function ccPermissionError(e, what) {
    if (e instanceof https_1.HttpsError)
        throw e;
    console.error(`chamcong_blao ${what} error`, e?.code, e?.message);
    throw new https_1.HttpsError("internal", `Máy chủ chưa đủ quyền ${what} Chấm Công BLAO (xem docs/CHAMCONG_BLAO_SSO.md).`);
}
/**
 * chamCongBlaoSignIn({ storeCode }) — người gọi đã đăng nhập POS.
 * → { customToken, ccUid, ccStoreId, ccStoreName, isNewMember, linkedExisting }
 */
exports.chamCongBlaoSignIn = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Vui lòng đăng nhập POS trước.");
    const data = (request.data || {});
    const storeCode = cleanStore(data.storeCode);
    const posUid = request.auth.uid;
    const caller = await loadPosCaller(storeCode, posUid);
    const linkSnap = await db().ref(`chamcong_blao_links/stores/${storeCode}`).get();
    const link = (linkSnap.val() || null);
    if (!link?.ccStoreId) {
        throw new https_1.HttpsError("failed-precondition", "Cửa hàng chưa được liên kết với Chấm Công BLAO. Chủ quán vào Quản lý → \"Liên kết Chấm Công BLAO\" để chọn cửa hàng chấm công.", { code: "STORE_NOT_LINKED" });
    }
    const ccStoreId = link.ccStoreId;
    const fs = ccFs();
    // 1. Tài khoản chấm công tương ứng
    const userLinkRef = db().ref(`chamcong_blao_links/users/${storeCode}/${posUid}`);
    const existingLink = (await userLinkRef.get()).val() || null;
    let decision = (0, chamCongBlaoLogic_1.decideCcAccount)({ existingLink, posFullName: caller.fullName || "", members: [], takenCcUids: new Set(), storeCode, posUid });
    if (!existingLink) {
        let members = [];
        try {
            const snap = await fs.collection("stores").doc(ccStoreId).collection("members").get();
            members = snap.docs.map((d) => ({ uid: d.id, name: String(d.get("name") || ""), status: String(d.get("status") || "") }));
        }
        catch (e) {
            ccPermissionError(e, "đọc thành viên");
        }
        const takenSnap = await db().ref(`chamcong_blao_links/byCc/${ccStoreId}`).get();
        const taken = new Set(Object.keys((takenSnap.val() || {})));
        decision = (0, chamCongBlaoLogic_1.decideCcAccount)({ existingLink: null, posFullName: caller.fullName || "", members, takenCcUids: taken, storeCode, posUid });
    }
    let ccUid = decision.ccUid;
    // Giữ chỗ uid chấm công (2 tài khoản POS không được nối vào cùng 1 tài khoản chấm công)
    const claim = await db()
        .ref(`chamcong_blao_links/byCc/${ccStoreId}/${ccUid}`)
        .transaction((cur) => (cur == null || cur === posUid ? posUid : undefined));
    if (!claim.committed) {
        if (decision.kind === "LINKED")
            throw new https_1.HttpsError("internal", "Liên kết tài khoản chấm công bị trùng. Liên hệ Chủ quán.");
        decision = (0, chamCongBlaoLogic_1.decideCcAccount)({ existingLink: null, posFullName: "", members: [], takenCcUids: new Set(), storeCode, posUid });
        ccUid = decision.ccUid;
        await db().ref(`chamcong_blao_links/byCc/${ccStoreId}/${ccUid}`).set(posUid);
    }
    // 2. Thành viên + hồ sơ bên chấm công
    const memberRef = fs.collection("stores").doc(ccStoreId).collection("members").doc(ccUid);
    let isNewMember = false;
    try {
        const memberSnap = await memberRef.get();
        const action = (0, chamCongBlaoLogic_1.memberAction)(memberSnap.exists ? memberSnap.data() : null);
        if (action === "KICKED") {
            throw new https_1.HttpsError("permission-denied", "Bạn đã bị xóa khỏi cửa hàng chấm công. Liên hệ Chủ quán.", { code: "CC_MEMBER_KICKED" });
        }
        if (action === "CREATE") {
            isNewMember = true;
            await memberRef.set({
                ...(0, chamCongBlaoLogic_1.buildNewMember)({
                    ccUid,
                    name: caller.fullName || caller.username || "Nhân viên",
                    phone: caller.phone,
                    employeeCode: caller.employeeCode,
                    role: (0, chamCongBlaoLogic_1.mapPosRoleToCc)(caller.roleId, caller.isRootOwner),
                }),
                joinedAt: firestore_1.Timestamp.now(),
            });
        }
        else if (action === "ACTIVATE") {
            await memberRef.set({ status: "active" }, { merge: true });
        }
        await fs
            .collection("users")
            .doc(ccUid)
            .set({
            id: ccUid,
            ...(isNewMember ? { name: caller.fullName || caller.username || "Nhân viên", email: "", createdAt: new Date().toISOString() } : {}),
            currentStoreId: ccStoreId,
            storeIds: firestore_1.FieldValue.arrayUnion(ccStoreId),
            posLink: { storeCode, posUid, username: caller.username || "" },
        }, { merge: true });
    }
    catch (e) {
        ccPermissionError(e, "ghi dữ liệu");
    }
    // 3. Phiên đăng nhập dự án chấm công
    let customToken;
    try {
        customToken = await (0, auth_1.getAuth)(ccApp()).createCustomToken(ccUid, { via: "pos", posStoreCode: storeCode });
    }
    catch (e) {
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
            details: decision.kind === "MATCHED"
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
exports.chamCongBlaoListStores = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Vui lòng đăng nhập POS trước.");
    const storeCode = cleanStore((request.data || {}).storeCode);
    const caller = await loadPosCaller(storeCode, request.auth.uid);
    if (!(0, permissions_1.isOwnerRole)(caller.roleId, caller.isRootOwner))
        throw new https_1.HttpsError("permission-denied", "Chỉ Chủ quán mới được liên kết.");
    let stores = [];
    try {
        const snap = await ccFs().collection("stores").limit(100).get();
        stores = snap.docs
            .map((d) => ({ ccStoreId: d.id, name: String(d.get("name") || d.id), code: String(d.get("code") || d.get("storeCode") || "") }))
            .sort((a, b) => a.name.localeCompare(b.name, "vi"));
    }
    catch (e) {
        ccPermissionError(e, "đọc cửa hàng");
    }
    const current = (await db().ref(`chamcong_blao_links/stores/${storeCode}`).get()).val() || null;
    return { stores, current };
});
/** Liên kết cửa hàng POS với một cửa hàng Chấm Công BLAO (Chủ quán) */
exports.chamCongBlaoLinkStore = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Vui lòng đăng nhập POS trước.");
    const data = (request.data || {});
    const storeCode = cleanStore(data.storeCode);
    const ccStoreId = cleanCcStoreId(data.ccStoreId);
    const caller = await loadPosCaller(storeCode, request.auth.uid);
    if (!(0, permissions_1.isOwnerRole)(caller.roleId, caller.isRootOwner))
        throw new https_1.HttpsError("permission-denied", "Chỉ Chủ quán mới được liên kết.");
    let name = ccStoreId;
    try {
        const doc = await ccFs().collection("stores").doc(ccStoreId).get();
        if (!doc.exists)
            throw new https_1.HttpsError("not-found", "Không tìm thấy cửa hàng chấm công đã chọn.");
        name = String(doc.get("name") || ccStoreId);
    }
    catch (e) {
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
//# sourceMappingURL=chamCongBlao.js.map