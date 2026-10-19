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
exports.getChamCongLinkStatus = exports.unlinkChamCongStore = exports.linkChamCongStore = exports.chamCongSignIn = void 0;
/**
 * "Đăng nhập bằng Chấm Công Trạm" — Cloud Functions (I/O). Logic thuần ở chamCongLogic.ts.
 *
 * Lưu trữ RTDB (ở GỐC → rules gốc từ chối mọi client, chỉ Admin SDK truy cập):
 *   chamcong_links/stores/{storeCode}               = { chamCongStoreId, chamCongStoreName, linkedByUid, linkedAt }
 *   chamcong_links/byChamCongStore/{chamCongStoreId} = storeCode
 *   chamcong_links/users/{storeCode}/{chamCongUid}   = posUid ("cc_" + chamCongUid)
 * Hiển thị: stores/{storeCode}/storeInfo/chamCongStoreId, chamCongStoreName.
 *
 * Xem docs/CHAMCONG_SSO.md để cấu hình IAM / đăng ký app.
 */
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const app_1 = require("firebase-admin/app");
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const permissions_1 = require("./permissions");
const chamCongLogic_1 = require("./chamCongLogic");
const FUNCTION_REGION = "asia-southeast1";
const CHAMCONG_APP_NAME = "chamcong";
// Lấy db/auth lười (index.ts gọi initializeApp sau khi import module này)
const db = () => admin.database();
const posAuth = () => admin.auth();
/** App Admin phụ trỏ tới project chấm công (mặc định "chamcongtram"), dùng ADC của service account Functions. */
function chamCongApp() {
    const existing = (0, app_1.getApps)().find((a) => a.name === CHAMCONG_APP_NAME);
    if (existing)
        return existing;
    const projectId = (process.env.CHAMCONG_PROJECT_ID || "").trim() || "chamcongtram";
    return (0, app_1.initializeApp)({ projectId, credential: (0, app_1.applicationDefault)() }, CHAMCONG_APP_NAME);
}
function fail(httpCode, code) {
    throw new https_1.HttpsError(httpCode, chamCongLogic_1.CHAMCONG_ERROR_MESSAGES[code], { code });
}
function cleanStore(raw) {
    const s = typeof raw === "string" ? raw.trim().toUpperCase() : "";
    if (!/^[A-Z0-9_-]{2,30}$/.test(s))
        throw new https_1.HttpsError("invalid-argument", "Mã cửa hàng không hợp lệ.");
    return s;
}
const newLogId = () => `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
async function writeAudit(storeCode, entry) {
    await db()
        .ref(`stores/${storeCode}/audit_logs/${newLogId()}`)
        .set({ timestamp: Date.now(), ...entry })
        .catch(() => undefined);
}
/**
 * Xác minh ID token do project chấm công cấp (chữ ký, aud/iss, hạn dùng).
 * Không bật checkRevoked: bước đó gọi Firebase Auth của chamcongtram và cần thêm quyền IAM;
 * quyền truy cập thật vẫn được kiểm tra lại mỗi lần qua trạng thái thành viên trong Firestore.
 */
async function verifyChamCongToken(idToken) {
    if (typeof idToken !== "string" || idToken.length < 20 || idToken.length > 8192)
        fail("unauthenticated", "INVALID_TOKEN");
    let decoded;
    try {
        decoded = await (0, auth_1.getAuth)(chamCongApp()).verifyIdToken(idToken, false);
    }
    catch (e) {
        const code = e?.code || "";
        if (code.startsWith("auth/") && code !== "auth/internal-error" && code !== "auth/insufficient-permission") {
            fail("unauthenticated", "INVALID_TOKEN");
        }
        console.error("chamcong verifyIdToken error", code, e?.message);
        throw new https_1.HttpsError("internal", "Máy chủ chưa đủ quyền xác minh tài khoản Chấm Công Trạm (xem docs/CHAMCONG_SSO.md).");
    }
    if (!(0, chamCongLogic_1.isValidChamCongUid)(decoded.uid) || decoded.firebase?.sign_in_provider === "anonymous") {
        fail("unauthenticated", "INVALID_TOKEN");
    }
    return decoded;
}
/** Đọc các membership chấm công của uid (collectionGroup members theo userId + stores theo ownerId). */
async function loadChamCongMemberships(ccUid) {
    const fs = (0, firestore_1.getFirestore)(chamCongApp());
    try {
        const [memberSnap, ownedSnap] = await Promise.all([
            fs.collectionGroup("members").where("userId", "==", ccUid).get(),
            fs.collection("stores").where("ownerId", "==", ccUid).get(),
        ]);
        const memberDocs = memberSnap.docs
            .filter((d) => d.ref.parent.parent && d.ref.parent.parent.parent.id === "stores")
            .map((d) => ({ storeId: d.ref.parent.parent.id, data: d.data() }));
        const ownedStores = new Map();
        ownedSnap.docs.forEach((d) => ownedStores.set(d.id, d.data()));
        return { memberDocs, ownedStores };
    }
    catch (e) {
        console.error("chamcong firestore read error", e?.message);
        throw new https_1.HttpsError("internal", "Máy chủ chưa đủ quyền đọc dữ liệu Chấm Công Trạm (xem docs/CHAMCONG_SSO.md).");
    }
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
        throw new https_1.HttpsError("permission-denied", "Tài khoản đã bị khóa.");
    return profile;
}
function requireOwner(p) {
    if (!(0, permissions_1.isOwnerRole)(p.roleId, p.isRootOwner)) {
        throw new https_1.HttpsError("permission-denied", "Chỉ Chủ quán mới được thực hiện thao tác này.");
    }
}
/** Khóa hồ sơ POS khi thành viên không còn hoạt động bên chấm công. */
async function revokeAccess(storeCodes, posUid, ccUid, reason) {
    let revokedAny = false;
    for (const storeCode of storeCodes) {
        const snap = await db().ref(`stores/${storeCode}/users/${posUid}`).get();
        const existing = (snap.exists() ? snap.val() : null);
        const patch = (0, chamCongLogic_1.buildRevokePatch)(existing, Date.now());
        if (!patch || !existing)
            continue;
        await db().ref(`stores/${storeCode}/users/${posUid}`).update(patch);
        revokedAny = true;
        await writeAudit(storeCode, {
            action: "CHAMCONG_ACCESS_REVOKED",
            username: existing.username || posUid,
            userFullName: existing.fullName || "",
            userRole: existing.roleId || "",
            targetType: "USER",
            targetId: posUid,
            isSuspicious: true,
            details: `Khóa tài khoản @${existing.username || posUid} vì ${reason} trên Chấm Công Trạm (uid ${ccUid})`,
        });
    }
    if (revokedAny)
        await posAuth().revokeRefreshTokens(posUid).catch(() => undefined);
}
/**
 * chamCongSignIn({ idToken, storeCode? })
 * → { status:"OK", customToken, storeCode, uid, roleId, isNewAccount } | { status:"CHOOSE_STORE", stores:[{storeCode, storeName}] }
 */
exports.chamCongSignIn = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    const data = (request.data || {});
    const requestedStore = data.storeCode == null || data.storeCode === "" ? null : cleanStore(data.storeCode);
    const decoded = await verifyChamCongToken(data.idToken);
    const ccUid = decoded.uid;
    const posUid = (0, chamCongLogic_1.posUidForChamCong)(ccUid);
    // 1. Liên kết cửa hàng + membership chấm công
    const linksSnap = await db().ref("chamcong_links/stores").get();
    const linksRaw = (linksSnap.val() || {});
    const links = {};
    for (const [sc, v] of Object.entries(linksRaw))
        if (v && typeof v.chamCongStoreId === "string")
            links[sc] = v.chamCongStoreId;
    const linkedStoreCodes = Object.keys(links);
    const priorSnaps = await Promise.all(linkedStoreCodes.map((sc) => db().ref(`chamcong_links/users/${sc}/${ccUid}`).get()));
    const prior = linkedStoreCodes.filter((_, i) => priorSnaps[i].exists());
    const { memberDocs, ownedStores } = await loadChamCongMemberships(ccUid);
    const memberships = (0, chamCongLogic_1.buildMemberships)(memberDocs, ownedStores.keys(), decoded.name || "");
    const decision = (0, chamCongLogic_1.decideSignIn)(links, memberships, prior, requestedStore);
    if (decision.revokeStoreCodes.length) {
        await revokeAccess(decision.revokeStoreCodes, posUid, ccUid, "không còn là thành viên đang hoạt động");
    }
    if (decision.kind === "DENY")
        fail("permission-denied", decision.code);
    if (decision.kind === "CHOOSE") {
        const names = {};
        const infoSnaps = await Promise.all(decision.storeCodes.map((sc) => db().ref(`stores/${sc}/storeInfo/storeName`).get()));
        decision.storeCodes.forEach((sc, i) => {
            const n = infoSnaps[i].val();
            names[sc] = typeof n === "string" && n.trim() ? n.trim() : linksRaw[sc]?.chamCongStoreName || sc;
        });
        return (0, chamCongLogic_1.buildChooseStoreResponse)(decision.storeCodes, names);
    }
    const storeCode = decision.storeCode;
    const membership = decision.membership;
    // 2. Firebase Auth user trong tramapp (không mật khẩu)
    try {
        const u = await posAuth().getUser(posUid);
        if (u.disabled)
            fail("permission-denied", "POS_ACCOUNT_DISABLED");
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        if (e?.code !== "auth/user-not-found") {
            throw new https_1.HttpsError("internal", "Không thể kiểm tra tài khoản POS. Vui lòng thử lại.");
        }
        await posAuth()
            .createUser({ uid: posUid, displayName: (membership.name || "Nhân viên").slice(0, 100) })
            .catch((err) => {
            if (err?.code !== "auth/uid-already-exists")
                throw err;
        });
    }
    // 3. Cấp / làm mới hồ sơ POS
    const profileRef = db().ref(`stores/${storeCode}/users/${posUid}`);
    const profileSnap = await profileRef.get();
    const existing = (profileSnap.exists() ? profileSnap.val() : null);
    let taken = [];
    if (!existing) {
        const usersSnap = await db().ref(`stores/${storeCode}/users`).get();
        taken = Object.values((usersSnap.val() || {}))
            .map((u) => (typeof u?.username === "string" ? u.username : ""))
            .filter(Boolean);
    }
    const now = Date.now();
    const pd = (0, chamCongLogic_1.decideProfile)({ existing, membership, posUid, chamCongUid: ccUid, takenUsernames: taken, now });
    if (pd.kind === "CONFLICT")
        fail("permission-denied", "POS_ACCOUNT_CONFLICT");
    if (pd.kind === "DISABLED")
        fail("permission-denied", "POS_ACCOUNT_DISABLED");
    const updates = {
        [`userIndex/${posUid}/${storeCode}`]: true,
        [`chamcong_links/users/${storeCode}/${ccUid}`]: posUid,
    };
    if (pd.isNew) {
        updates[`stores/${storeCode}/users/${posUid}`] = pd.values;
    }
    else {
        for (const [k, v] of Object.entries(pd.values))
            updates[`stores/${storeCode}/users/${posUid}/${k}`] = v;
    }
    await db().ref().update(updates);
    // 4. Custom token
    let customToken;
    try {
        customToken = await posAuth().createCustomToken(posUid, { storeCode, via: "chamcong" });
    }
    catch {
        throw new https_1.HttpsError("internal", "Máy chủ chưa đủ quyền cấp phiên đăng nhập (Service Account Token Creator).");
    }
    await profileRef.child("lastLoginAt").set(Date.now()).catch(() => undefined);
    // 5. Audit
    const finalProfile = { ...(existing || {}), ...pd.values };
    const actor = {
        username: finalProfile.username || posUid,
        userFullName: finalProfile.fullName || "",
        userRole: pd.roleId,
    };
    if (pd.isNew) {
        await writeAudit(storeCode, {
            action: "CHAMCONG_ACCOUNT_PROVISIONED",
            ...actor,
            targetType: "USER",
            targetId: posUid,
            details: `Tự cấp tài khoản @${actor.username} (${actor.userFullName}) từ Chấm Công Trạm, vai trò ${pd.roleId}`,
        });
    }
    if (pd.roleChange) {
        await writeAudit(storeCode, {
            action: "CHAMCONG_ROLE_SYNCED",
            ...actor,
            targetType: "USER",
            targetId: posUid,
            details: `Đồng bộ vai trò @${actor.username}: ${pd.roleChange.from || "(trống)"} → ${pd.roleChange.to} theo Chấm Công Trạm`,
        });
    }
    await writeAudit(storeCode, {
        action: "CHAMCONG_SIGN_IN",
        ...actor,
        targetType: "AUTH",
        targetId: posUid,
        details: `Đăng nhập bằng Chấm Công Trạm${pd.reactivated ? " (mở lại tài khoản sau khi được duyệt lại)" : ""}`,
    });
    return (0, chamCongLogic_1.buildOkResponse)({ customToken, storeCode, uid: posUid, roleId: pd.roleId, isNewAccount: pd.isNew });
});
/** Danh sách store chấm công mà người dùng token là Chủ. */
async function listOwnedChamCongStores(ccUid) {
    const { memberDocs, ownedStores } = await loadChamCongMemberships(ccUid);
    const ids = new Set(ownedStores.keys());
    for (const m of memberDocs)
        if ((0, chamCongLogic_1.isChamCongStoreOwner)(null, m.data, ccUid))
            ids.add(m.storeId);
    const fs = (0, firestore_1.getFirestore)(chamCongApp());
    const result = [];
    for (const id of ids) {
        let data = ownedStores.get(id) || null;
        if (!data) {
            const doc = await fs.collection("stores").doc(id).get().catch(() => null);
            if (!doc || !doc.exists)
                continue;
            data = doc.data();
        }
        result.push((0, chamCongLogic_1.summarizeChamCongStore)(id, data));
    }
    return result.sort((a, b) => a.name.localeCompare(b.name, "vi"));
}
/**
 * linkChamCongStore({ storeCode, idToken, chamCongStoreId? })
 * → { status:"CHOOSE_CHAMCONG_STORE", stores:[{chamCongStoreId, name, code}] } | { status:"LINKED", chamCongStoreId, chamCongStoreName }
 */
exports.linkChamCongStore = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    const data = (request.data || {});
    const storeCode = cleanStore(data.storeCode);
    const caller = await loadPosCaller(storeCode, request.auth.uid);
    requireOwner(caller);
    const decoded = await verifyChamCongToken(data.idToken);
    const owned = await listOwnedChamCongStores(decoded.uid);
    const wanted = typeof data.chamCongStoreId === "string" ? data.chamCongStoreId.trim() : "";
    if (!wanted)
        return { status: "CHOOSE_CHAMCONG_STORE", stores: owned };
    if (/[/.#$\[\]]/.test(wanted))
        throw new https_1.HttpsError("invalid-argument", "Mã cửa hàng Chấm Công không hợp lệ.");
    const target = owned.find((s) => s.chamCongStoreId === wanted);
    if (!target) {
        throw new https_1.HttpsError("permission-denied", "Tài khoản Chấm Công này không phải Chủ của cửa hàng đã chọn.", { code: "NOT_STORE_OWNER" });
    }
    // Giữ chỗ byChamCongStore bằng transaction (chống 2 POS cùng liên kết 1 store chấm công)
    const claimRef = db().ref(`chamcong_links/byChamCongStore/${wanted}`);
    let verdict = "OK";
    const tx = await claimRef.transaction((cur) => {
        verdict = (0, chamCongLogic_1.decideLink)(typeof cur === "string" ? cur : null, storeCode);
        return verdict === "OK" ? storeCode : undefined;
    });
    if (verdict === "ALREADY_LINKED" || !tx.committed)
        fail("failed-precondition", "ALREADY_LINKED");
    // Nếu POS này từng liên kết store chấm công khác → gỡ mapping cũ
    const prevSnap = await db().ref(`chamcong_links/stores/${storeCode}`).get();
    const prevId = prevSnap.exists() ? prevSnap.val().chamCongStoreId : undefined;
    const now = Date.now();
    const updates = {
        [`chamcong_links/stores/${storeCode}`]: {
            chamCongStoreId: wanted,
            chamCongStoreName: target.name,
            linkedByUid: request.auth.uid,
            linkedAt: now,
        },
        [`stores/${storeCode}/storeInfo/chamCongStoreId`]: wanted,
        [`stores/${storeCode}/storeInfo/chamCongStoreName`]: target.name,
    };
    if (prevId && prevId !== wanted) {
        const prevOwner = await db().ref(`chamcong_links/byChamCongStore/${prevId}`).get();
        if (prevOwner.val() === storeCode)
            updates[`chamcong_links/byChamCongStore/${prevId}`] = null;
    }
    await db().ref().update(updates);
    await writeAudit(storeCode, {
        action: "CHAMCONG_STORE_LINKED",
        username: caller.username || "unknown",
        userFullName: caller.fullName || "",
        userRole: caller.roleId || "",
        targetType: "STORE",
        targetId: wanted,
        details: `Liên kết cửa hàng với Chấm Công Trạm: ${target.name} (${wanted})${prevId && prevId !== wanted ? `, thay cho ${prevId}` : ""}`,
    });
    return { status: "LINKED", chamCongStoreId: wanted, chamCongStoreName: target.name };
});
/** unlinkChamCongStore({ storeCode }) → { status:"UNLINKED", wasLinked } */
exports.unlinkChamCongStore = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    const storeCode = cleanStore((request.data || {}).storeCode);
    const caller = await loadPosCaller(storeCode, request.auth.uid);
    requireOwner(caller);
    const linkSnap = await db().ref(`chamcong_links/stores/${storeCode}`).get();
    const link = (linkSnap.val() || null);
    const updates = {
        [`chamcong_links/stores/${storeCode}`]: null,
        [`stores/${storeCode}/storeInfo/chamCongStoreId`]: null,
        [`stores/${storeCode}/storeInfo/chamCongStoreName`]: null,
    };
    if (link?.chamCongStoreId) {
        const owner = await db().ref(`chamcong_links/byChamCongStore/${link.chamCongStoreId}`).get();
        if (owner.val() === storeCode)
            updates[`chamcong_links/byChamCongStore/${link.chamCongStoreId}`] = null;
    }
    await db().ref().update(updates);
    if (link) {
        await writeAudit(storeCode, {
            action: "CHAMCONG_STORE_UNLINKED",
            username: caller.username || "unknown",
            userFullName: caller.fullName || "",
            userRole: caller.roleId || "",
            targetType: "STORE",
            targetId: link.chamCongStoreId || "",
            details: `Hủy liên kết Chấm Công Trạm: ${link.chamCongStoreName || ""} (${link.chamCongStoreId || ""}). Tài khoản đã cấp vẫn giữ nguyên.`,
        });
    }
    return { status: "UNLINKED", wasLinked: !!link };
});
/** getChamCongLinkStatus({ storeCode }) → { linked, chamCongStoreId?, chamCongStoreName?, linkedAt?, provisionedCount } */
exports.getChamCongLinkStatus = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    const storeCode = cleanStore((request.data || {}).storeCode);
    const caller = await loadPosCaller(storeCode, request.auth.uid);
    if (!(0, permissions_1.isOwnerRole)(caller.roleId, caller.isRootOwner) && !(0, permissions_1.isManagerRole)(caller.roleId)) {
        throw new https_1.HttpsError("permission-denied", "Chỉ Chủ quán hoặc Quản lý mới xem được trạng thái liên kết.");
    }
    const [linkSnap, usersSnap] = await Promise.all([
        db().ref(`chamcong_links/stores/${storeCode}`).get(),
        db().ref(`chamcong_links/users/${storeCode}`).get(),
    ]);
    const provisionedCount = usersSnap.exists() ? usersSnap.numChildren() : 0;
    const link = (linkSnap.val() || null);
    if (!link?.chamCongStoreId)
        return { linked: false, provisionedCount };
    return {
        linked: true,
        chamCongStoreId: link.chamCongStoreId,
        chamCongStoreName: link.chamCongStoreName || "",
        linkedAt: link.linkedAt ?? null,
        provisionedCount,
    };
});
//# sourceMappingURL=chamCong.js.map