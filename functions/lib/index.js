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
exports.deleteCustomer = exports.pullPooledPoints = exports.mirrorLedgerToHistory = exports.linkBranchCustomer = exports.mirrorMemberToBranches = exports.setLoyaltyConfig = exports.listLoyaltyLedger = exports.getMemberLedger = exports.lookupMember = exports.adjustLoyaltyPoints = exports.refundLoyaltyPoints = exports.redeemLoyaltyPoints = exports.applyLoyaltyEarn = exports.createStore = exports.deleteMyAccount = exports.getChamCongLinkStatus = exports.unlinkChamCongStore = exports.linkChamCongStore = exports.chamCongSignIn = exports.setManagerPin = exports.verifyManagerPin = exports.mirrorCustomerToFirestore = exports.importCustomerToStore = exports.staffSignIn = exports.assignStaffToStore = exports.setStaffDisabled = exports.resetStaffPassword = exports.createStaffAccount = void 0;
const https_1 = require("firebase-functions/v2/https");
const database_1 = require("firebase-functions/v2/database");
const params_1 = require("firebase-functions/params");
const admin = __importStar(require("firebase-admin"));
const multiStore_1 = require("./multiStore");
const permissions_1 = require("./permissions");
const customerSync_1 = require("./customerSync");
const loginLockout_1 = require("./loginLockout");
if (!admin.apps.length) {
    admin.initializeApp({
        databaseURL: process.env.DATABASE_URL || "https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app",
    });
}
const db = admin.database();
const auth = admin.auth();
const FUNCTION_REGION = "asia-southeast1";
/**
 * Web API Key của project (không phải bí mật, nhưng KHÔNG hardcode trong mã nguồn).
 * Khai báo trong functions/.env (WEB_API_KEY=...) hoặc nhập khi `firebase deploy` hỏi.
 */
const WEB_API_KEY = (0, params_1.defineString)("WEB_API_KEY", {
    description: "Firebase Web API Key dùng để xác minh mật khẩu qua Identity Toolkit REST (signInWithPassword)",
});
/**
 * 1. Hàm tạo tài khoản nhân viên (createStaffAccount)
 */
exports.createStaffAccount = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }
    const { storeCode, username, fullName, roleId, tempPassword, phone, customPermissions, } = request.data || {};
    if (!storeCode || !username || !fullName || !roleId || !tempPassword) {
        throw new https_1.HttpsError("invalid-argument", "Thiếu thông tin bắt buộc để tạo tài khoản.");
    }
    if (String(tempPassword).length < 6) {
        throw new https_1.HttpsError("invalid-argument", "Mật khẩu tạm phải có độ dài tối thiểu 6 ký tự.");
    }
    const callerUid = request.auth.uid;
    const cleanStoreCode = String(storeCode).trim().toUpperCase();
    const cleanUser = (0, permissions_1.normalizeUsername)(String(username));
    if (!cleanUser) {
        throw new https_1.HttpsError("invalid-argument", "Tên đăng nhập không hợp lệ sau khi chuẩn hóa.");
    }
    // Lấy hồ sơ người gọi
    const callerNode = await findCallerNode(cleanStoreCode, callerUid);
    if (!callerNode) {
        throw new https_1.HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
    }
    const caller = callerNode.record;
    if (!(0, permissions_1.canCallerManageUsers)(caller)) {
        throw new https_1.HttpsError("permission-denied", "Bạn không có quyền quản lý nhân viên.");
    }
    if (!(0, permissions_1.canCallerCreateRole)(caller, roleId)) {
        throw new https_1.HttpsError("permission-denied", "Quản lý không được phép tạo tài khoản có vai trò Chủ quán.");
    }
    // Kiểm tra trùng username trong quán
    const storeUsersSnap = await db.ref(`stores/${cleanStoreCode}/users`).get();
    if (storeUsersSnap.exists()) {
        const usersMap = storeUsersSnap.val();
        for (const u of Object.values(usersMap)) {
            if (u.username && (0, permissions_1.normalizeUsername)(u.username) === cleanUser) {
                throw new https_1.HttpsError("already-exists", `Tên đăng nhập "${cleanUser}" đã tồn tại trong quán.`);
            }
        }
    }
    const syntheticEmail = (0, permissions_1.buildSyntheticEmail)(cleanUser, cleanStoreCode);
    let newUid = "";
    try {
        // 1. Tạo Firebase Auth user
        const userRecord = await auth.createUser({
            email: syntheticEmail,
            password: String(tempPassword),
            displayName: String(fullName),
            disabled: false,
        });
        newUid = userRecord.uid;
        // 2. Ghi hồ sơ RTDB tại stores/{storeCode}/users/{uid}
        const userProfile = {
            uid: newUid,
            username: cleanUser,
            fullName: String(fullName).trim(),
            roleId: (0, permissions_1.normalizeRoleId)(String(roleId)),
            isRootOwner: false,
            isActive: true,
            phone: phone ? String(phone).trim() : "",
            customPermissions: (0, permissions_1.sanitizeCustomPermissions)(caller, customPermissions),
            createdAt: Date.now(),
            mustChangePassword: true,
        };
        await db.ref(`stores/${cleanStoreCode}/users/${newUid}`).set(userProfile);
        // 3. Ghi index userIndex/{uid}/{storeCode} = true
        await db.ref(`userIndex/${newUid}/${cleanStoreCode}`).set(true);
        // 4. Ghi audit log
        const logId = `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
        await db.ref(`stores/${cleanStoreCode}/audit_logs/${logId}`).set({
            timestamp: Date.now(),
            action: "CREATE_STAFF_ACCOUNT",
            staffUsername: caller.username || "unknown",
            staffFullName: caller.fullName || "Quản lý",
            details: `Tạo tài khoản nhân viên @${cleanUser} (${fullName}) với vai trò ${roleId}`,
        });
        return {
            success: true,
            uid: newUid,
            email: syntheticEmail,
            message: "Tạo tài khoản nhân viên thành công.",
        };
    }
    catch (err) {
        // Rollback: Xóa auth user nếu ghi RTDB lỗi
        if (newUid) {
            await auth.deleteUser(newUid).catch(() => { });
        }
        if (err instanceof https_1.HttpsError)
            throw err;
        throw new https_1.HttpsError("internal", err?.message || "Lỗi tạo tài khoản nhân viên.");
    }
});
/**
 * 2. Hàm đặt lại mật khẩu nhân viên (resetStaffPassword)
 */
exports.resetStaffPassword = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }
    const { storeCode, targetUid, newPassword } = request.data || {};
    if (!storeCode || !targetUid || !newPassword) {
        throw new https_1.HttpsError("invalid-argument", "Thiếu thông tin bắt buộc để đặt lại mật khẩu.");
    }
    if (String(newPassword).length < 6) {
        throw new https_1.HttpsError("invalid-argument", "Mật khẩu mới phải có tối thiểu 6 ký tự.");
    }
    const callerUid = request.auth.uid;
    const cleanStoreCode = String(storeCode).trim().toUpperCase();
    // Lấy hồ sơ người gọi
    const callerNode = await findCallerNode(cleanStoreCode, callerUid);
    if (!callerNode) {
        throw new https_1.HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
    }
    // Lấy hồ sơ người bị tác động (chấp nhận khóa nút, trường uid hoặc tên đăng nhập)
    const found = await findStaffNode(cleanStoreCode, String(targetUid));
    if (!found) {
        throw new https_1.HttpsError("not-found", "Không tìm thấy hồ sơ nhân viên trong quán.");
    }
    const { nodeKey, record: target } = found;
    const caller = callerNode.record;
    const authUidGuess = (0, permissions_1.resolveStaffAuthUid)(nodeKey, target);
    const isSelf = callerUid === authUidGuess || callerUid === nodeKey;
    if (!(0, permissions_1.canCallerResetPassword)(caller, target, isSelf)) {
        throw new https_1.HttpsError("permission-denied", "Bạn không có quyền đặt lại mật khẩu cho tài khoản này (Quản lý không đặt lại được mật khẩu của Chủ quán hoặc Quản lý khác).");
    }
    if ((0, permissions_1.isChamCongAccount)(nodeKey, target)) {
        throw new https_1.HttpsError("failed-precondition", "Tài khoản này đăng nhập bằng Chấm Công Trạm nên không có mật khẩu POS để đặt lại.");
    }
    // Cập nhật Auth (khóa nút cũ theo tên đăng nhập → thử tra uid thật qua email tổng hợp)
    let authUid = authUidGuess;
    try {
        await auth.updateUser(authUid, { password: String(newPassword) });
    }
    catch (err) {
        const code = String(err?.code || "");
        if (code === "auth/user-not-found" || code === "auth/invalid-uid") {
            const email = target.username ? (0, permissions_1.buildSyntheticEmail)(String(target.username), cleanStoreCode) : "";
            let resolved = null;
            if (email) {
                resolved = await auth.getUserByEmail(email).then((u) => u.uid).catch(() => null);
            }
            if (!resolved) {
                throw new https_1.HttpsError("not-found", "Tài khoản này chưa có đăng nhập Firebase (hồ sơ cũ). Hãy xóa và tạo lại tài khoản nhân viên.");
            }
            authUid = resolved;
            await auth.updateUser(authUid, { password: String(newPassword) }).catch((e2) => {
                throw new https_1.HttpsError("internal", e2?.message || "Không cập nhật được mật khẩu.");
            });
        }
        else if (code === "auth/invalid-password" || code === "auth/weak-password") {
            throw new https_1.HttpsError("invalid-argument", "Mật khẩu mới không hợp lệ (tối thiểu 6 ký tự).");
        }
        else {
            throw new https_1.HttpsError("internal", err?.message || "Không cập nhật được mật khẩu.");
        }
    }
    // Bật mustChangePassword trong RTDB (trên đúng nút hồ sơ)
    await db.ref(`stores/${cleanStoreCode}/users/${nodeKey}/mustChangePassword`).set(true);
    // Ghi audit log
    const logId = `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    await db.ref(`stores/${cleanStoreCode}/audit_logs/${logId}`).set({
        timestamp: Date.now(),
        action: "RESET_STAFF_PASSWORD",
        staffUsername: caller.username || "unknown",
        staffFullName: caller.fullName || "Quản lý",
        details: `Đặt lại mật khẩu cho tài khoản @${target.username || nodeKey} (Bắt buộc đổi mật khẩu lần tới)`,
    });
    return {
        success: true,
        message: "Đặt lại mật khẩu thành công.",
    };
});
/**
 * Hồ sơ NGƯỜI GỌI: khóa nút = uid, hoặc (nút cũ khóa theo tên đăng nhập) nút có trường `uid` đúng bằng uid đăng nhập.
 * Không khớp theo username để tránh mạo danh.
 */
async function findCallerNode(storeCode, callerUid) {
    const direct = await db.ref(`stores/${storeCode}/users/${callerUid}`).get();
    if (direct.exists())
        return { nodeKey: callerUid, record: direct.val() };
    const all = await db.ref(`stores/${storeCode}/users`).get();
    if (!all.exists())
        return null;
    for (const [nodeKey, rec] of Object.entries(all.val())) {
        if (rec && typeof rec === "object" && rec.uid === callerUid)
            return { nodeKey, record: rec };
    }
    return null;
}
/** Tìm nút hồ sơ nhân viên: theo khóa nút, rồi theo trường uid / username. */
async function findStaffNode(storeCode, key) {
    const direct = await db.ref(`stores/${storeCode}/users/${key}`).get();
    if (direct.exists())
        return { nodeKey: key, record: direct.val() };
    const all = await db.ref(`stores/${storeCode}/users`).get();
    if (!all.exists())
        return null;
    const lower = key.toLowerCase();
    for (const [nodeKey, rec] of Object.entries(all.val())) {
        if (!rec || typeof rec !== "object")
            continue;
        if (rec.uid === key || String(rec.username || "").toLowerCase() === lower) {
            return { nodeKey, record: rec };
        }
    }
    return null;
}
/**
 * 3. Hàm khóa / mở khóa tài khoản nhân viên (setStaffDisabled)
 */
exports.setStaffDisabled = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }
    const { storeCode, targetUid, disabled } = request.data || {};
    if (!storeCode || !targetUid || typeof disabled !== "boolean") {
        throw new https_1.HttpsError("invalid-argument", "Thiếu thông tin bắt buộc để khóa/mở tài khoản.");
    }
    const callerUid = request.auth.uid;
    const cleanStoreCode = String(storeCode).trim().toUpperCase();
    // Lấy hồ sơ người gọi
    const callerNode = await findCallerNode(cleanStoreCode, callerUid);
    if (!callerNode) {
        throw new https_1.HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
    }
    // Lấy hồ sơ người bị tác động
    const found = await findStaffNode(cleanStoreCode, String(targetUid));
    if (!found) {
        throw new https_1.HttpsError("not-found", "Không tìm thấy hồ sơ nhân viên trong quán.");
    }
    const { nodeKey, record: target } = found;
    const authUid = (0, permissions_1.resolveStaffAuthUid)(nodeKey, target);
    const caller = callerNode.record;
    if (!(0, permissions_1.canCallerSetDisabled)(caller, target, authUid, callerUid)) {
        throw new https_1.HttpsError("permission-denied", "Không thể thực hiện khóa/mở khóa tài khoản này.");
    }
    // Nhân viên làm ở nhiều cửa hàng: chỉ khóa hồ sơ ở cửa hàng này, KHÔNG khóa tài khoản đăng nhập (Auth)
    const storeCount = (0, multiStore_1.countIndexedStores)((await db.ref(`userIndex/${authUid}`).get()).val());
    const touchAuth = (0, multiStore_1.shouldDisableAuthAccount)(storeCount);
    // 1. Cập nhật Auth
    if (touchAuth)
        await auth.updateUser(authUid, { disabled }).catch((e) => {
            if (String(e?.code) === "auth/user-not-found")
                return; // hồ sơ cũ không có Auth: vẫn cập nhật isActive
            throw e;
        });
    if (disabled && touchAuth) {
        // Hủy bỏ refresh token ngay lập tức
        await auth.revokeRefreshTokens(authUid).catch(() => { });
    }
    // 2. Cập nhật isActive trong RTDB
    await db.ref(`stores/${cleanStoreCode}/users/${nodeKey}/isActive`).set(!disabled);
    // 3. Ghi audit log
    const logId = `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    await db.ref(`stores/${cleanStoreCode}/audit_logs/${logId}`).set({
        timestamp: Date.now(),
        action: disabled ? "LOCK_STAFF_ACCOUNT" : "UNLOCK_STAFF_ACCOUNT",
        staffUsername: caller.username || "unknown",
        staffFullName: caller.fullName || "Quản lý",
        details: `${disabled ? "Khóa" : "Mở khóa"} tài khoản @${target.username || nodeKey}`,
    });
    return {
        success: true,
        message: `${disabled ? "Khóa" : "Mở khóa"} tài khoản thành công.`,
    };
});
/**
 * 3b. Gán nhân viên có sẵn vào cửa hàng khác (assignStaffToStore)
 *
 * Một người = MỘT tài khoản (một mật khẩu) làm ở nhiều cửa hàng, mỗi cửa hàng một vai trò riêng.
 * Chỉ Chủ quán / Admin ở CẢ cửa hàng nguồn và đích mới được gọi. Ghi hồ sơ ở cửa hàng đích + userIndex + nhật ký.
 */
exports.assignStaffToStore = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }
    const { sourceStoreCode, targetStoreCode, targetUid, roleId } = (request.data || {});
    if (!sourceStoreCode || !targetStoreCode || !targetUid) {
        throw new https_1.HttpsError("invalid-argument", "Thiếu cửa hàng nguồn / đích hoặc nhân viên.");
    }
    if (!(0, multiStore_1.isAssignableRole)(roleId)) {
        throw new https_1.HttpsError("invalid-argument", `Vai trò phải là một trong: ${multiStore_1.ASSIGNABLE_ROLES.join(", ")}.`);
    }
    const source = String(sourceStoreCode).trim().toUpperCase();
    const target = String(targetStoreCode).trim().toUpperCase();
    if (source === target)
        throw new https_1.HttpsError("invalid-argument", "Cửa hàng đích phải khác cửa hàng hiện tại.");
    const callerUid = request.auth.uid;
    const [atSource, atTarget] = await Promise.all([findCallerNode(source, callerUid), findCallerNode(target, callerUid)]);
    if (!(0, multiStore_1.canAssignAcrossStores)(atSource?.record ?? null, atTarget?.record ?? null)) {
        throw new https_1.HttpsError("permission-denied", "Chỉ Chủ quán / Admin của cả hai cửa hàng mới được gán nhân viên sang cửa hàng khác.");
    }
    const targetStoreExists = (await db.ref(`stores/${target}/storeInfo`).get()).exists();
    if (!targetStoreExists)
        throw new https_1.HttpsError("not-found", `Không tìm thấy cửa hàng ${target}.`);
    const found = await findStaffNode(source, String(targetUid));
    if (!found)
        throw new https_1.HttpsError("not-found", "Không tìm thấy hồ sơ nhân viên ở cửa hàng hiện tại.");
    const authUid = (0, permissions_1.resolveStaffAuthUid)(found.nodeKey, found.record);
    if (isOwnerRoleProfile(found.record)) {
        throw new https_1.HttpsError("failed-precondition", "Không gán tài khoản Chủ quán bằng chức năng này.");
    }
    try {
        await auth.getUser(authUid);
    }
    catch {
        throw new https_1.HttpsError("failed-precondition", "Nhân viên này chưa có tài khoản đăng nhập hợp lệ.");
    }
    if ((await db.ref(`stores/${target}/users/${authUid}`).get()).exists()) {
        throw new https_1.HttpsError("already-exists", `Nhân viên đã có hồ sơ ở cửa hàng ${target}.`);
    }
    const now = Date.now();
    const caller = atSource.record;
    const profile = (0, multiStore_1.buildAssignedProfile)(found.record, authUid, roleId, { username: caller.username, storeCode: source }, now);
    await db.ref().update({
        [`stores/${target}/users/${authUid}`]: profile,
        [`userIndex/${authUid}/${target}`]: true,
        [`stores/${target}/audit_logs/LOG_${now}_assign_${Math.random().toString(36).substring(2, 7)}`]: {
            timestamp: now,
            action: "ASSIGN_STAFF_TO_STORE",
            username: caller.username || "unknown",
            userFullName: caller.fullName || "",
            userRole: caller.roleId || "",
            targetType: "USER",
            targetId: authUid,
            details: `Thêm @${found.record.username} từ ${source} vào ${target} với vai trò ${roleId}`,
        },
    });
    return { success: true, uid: authUid, storeCode: target, roleId };
});
function isOwnerRoleProfile(p) {
    return p.isRootOwner === true || /owner|^chu$/i.test(String(p.roleId ?? ""));
}
/**
 * Xác minh mật khẩu qua Identity Toolkit REST (signInWithPassword).
 * Trả về uid nếu đúng, ném lỗi kèm mã lỗi REST nếu sai.
 */
async function verifyPasswordViaRest(email, password) {
    const emulatorHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
    const base = emulatorHost
        ? `http://${emulatorHost}/identitytoolkit.googleapis.com`
        : "https://identitytoolkit.googleapis.com";
    const apiKey = WEB_API_KEY.value() || (emulatorHost ? "fake-api-key" : "");
    if (!apiKey) {
        throw new https_1.HttpsError("failed-precondition", "Máy chủ chưa cấu hình WEB_API_KEY cho chức năng đăng nhập.");
    }
    const resp = await fetch(`${base}/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password, returnSecureToken: false }),
    });
    const body = (await resp.json().catch(() => ({})));
    if (resp.ok && body.localId) {
        return { ok: true, uid: body.localId };
    }
    return { ok: false, code: body.error?.message || `HTTP_${resp.status}` };
}
/**
 * 4. Đăng nhập nhân viên có khóa tạm chống brute-force (staffSignIn)
 *
 * - Kiểm tra & ghi bộ đếm sai tại login_attempts/{storeCode}/{username} ở GỐC (ngoài stores/{s} để không bị
 *   quyền đọc của thành viên quán lan xuống; rules chặn hoàn toàn, chỉ Admin SDK truy cập được).
 * - Xác minh mật khẩu phía máy chủ qua Identity Toolkit REST.
 * - Thành công: trả về Custom Token để client gọi signInWithCustomToken.
 * - Sai {MAX_FAILED_ATTEMPTS} lần liên tiếp: khóa tạm 15 phút (mã lỗi resource-exhausted).
 * - Không tạo bản ghi đếm cho username không tồn tại (tránh rác dữ liệu / dò tài khoản hàng loạt).
 */
exports.staffSignIn = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    const { storeCode, username, password } = (request.data || {});
    if (typeof storeCode !== "string" || typeof username !== "string" || typeof password !== "string") {
        throw new https_1.HttpsError("invalid-argument", "Thiếu mã cửa hàng, tên đăng nhập hoặc mật khẩu.");
    }
    const cleanStoreCode = storeCode.trim().toUpperCase();
    const cleanUser = (0, permissions_1.normalizeUsername)(username);
    if (!/^[A-Z0-9_-]{2,30}$/.test(cleanStoreCode)) {
        throw new https_1.HttpsError("invalid-argument", "Mã cửa hàng không hợp lệ.");
    }
    if (!/^[a-z0-9_-]{3,30}$/.test(cleanUser)) {
        throw new https_1.HttpsError("invalid-argument", "Tên đăng nhập không hợp lệ.");
    }
    if (!password || password.length > 256) {
        throw new https_1.HttpsError("invalid-argument", "Mật khẩu không hợp lệ.");
    }
    const INVALID_MSG = "Sai tài khoản hoặc mật khẩu.";
    let email = (0, permissions_1.buildSyntheticEmail)(cleanUser, cleanStoreCode);
    // 1. Tài khoản không tồn tại -> trả lỗi chung, KHÔNG ghi bộ đếm
    try {
        await auth.getUserByEmail(email);
    }
    catch (e) {
        if (e?.code !== "auth/user-not-found") {
            throw new https_1.HttpsError("internal", "Không thể kiểm tra tài khoản. Vui lòng thử lại sau.");
        }
        // Chủ nhiều chi nhánh dùng MỘT tài khoản Auth (email theo chi nhánh đầu tiên) nhưng có hồ sơ ở nhiều quán:
        // tìm hồ sơ theo tên đăng nhập trong quán đang đăng nhập rồi dùng email thật của tài khoản đó.
        let resolved = null;
        try {
            // Không dùng orderByChild (RTDB chưa khai báo .indexOn cho username) — quán chỉ có vài chục tài khoản
            const all = (await db.ref(`stores/${cleanStoreCode}/users`).get()).val();
            const found = Object.entries(all || {}).find(([, u]) => u && u.username && (0, permissions_1.normalizeUsername)(u.username) === cleanUser)?.[0] ??
                null;
            if (found)
                resolved = (await auth.getUser(found)).email ?? null;
        }
        catch {
            resolved = null;
        }
        if (!resolved)
            throw new https_1.HttpsError("unauthenticated", INVALID_MSG);
        email = resolved;
    }
    // 2. Giữ chỗ 1 lượt thử bằng transaction (an toàn khi gửi song song)
    const attemptRef = db.ref((0, loginLockout_1.loginAttemptPath)(cleanStoreCode, cleanUser));
    let allowed = false;
    const reserveTx = await attemptRef.transaction((current) => {
        const r = (0, loginLockout_1.reserveAttempt)(current, Date.now());
        allowed = r.allowed;
        return r.next;
    });
    const afterReserve = (reserveTx.snapshot.val() || null);
    if (!allowed) {
        const remaining = Math.max((0, loginLockout_1.remainingLockSeconds)(afterReserve, Date.now()), 1);
        throw new https_1.HttpsError("resource-exhausted", (0, loginLockout_1.buildLockoutMessage)(remaining), {
            reason: "LOCKED_OUT",
            remainingSeconds: remaining,
            lockedUntil: afterReserve?.lockedUntil ?? null,
        });
    }
    // 3. Xác minh mật khẩu
    const result = await verifyPasswordViaRest(email, password).catch((e) => {
        if (e instanceof https_1.HttpsError)
            throw e;
        throw new https_1.HttpsError("unavailable", "Không thể kết nối máy chủ xác thực. Vui lòng thử lại.");
    });
    if (!result.ok) {
        if (result.code.startsWith("USER_DISABLED")) {
            throw new https_1.HttpsError("permission-denied", "Tài khoản đã bị tạm khóa bởi chủ quán.");
        }
        if (!(0, loginLockout_1.isInvalidCredentialError)(result.code)) {
            // Lỗi hạ tầng (quota, cấu hình...) -> trả lại lượt đã giữ chỗ
            await attemptRef
                .transaction((current) => {
                if (!current || typeof current.failedCount !== "number")
                    return current;
                return { ...current, failedCount: Math.max(current.failedCount - 1, 0) };
            })
                .catch(() => undefined);
            if (result.code.startsWith("TOO_MANY_ATTEMPTS")) {
                throw new https_1.HttpsError("resource-exhausted", "Hệ thống đang tạm hạn chế đăng nhập do quá nhiều yêu cầu. Vui lòng thử lại sau ít phút.");
            }
            throw new https_1.HttpsError("internal", "Đăng nhập thất bại do lỗi máy chủ xác thực.");
        }
        let justLocked = false;
        let lockedRec = null;
        await attemptRef.transaction((current) => {
            const r = (0, loginLockout_1.applyFailure)(current, Date.now());
            justLocked = r.justLocked;
            lockedRec = r.next;
            return r.next;
        });
        if (justLocked) {
            const now = Date.now();
            const logId = `LOG_${now}_${Math.random().toString(36).substring(2, 7)}`;
            await db
                .ref(`stores/${cleanStoreCode}/audit_logs/${logId}`)
                .set({
                timestamp: now,
                action: "LOGIN_ATTEMPT_LOCKED_OUT",
                username: cleanUser,
                userFullName: cleanUser,
                userRole: "UNKNOWN",
                targetType: "AUTH",
                targetId: cleanUser,
                isSuspicious: true,
                details: `Tài khoản @${cleanUser} bị khóa tạm 15 phút do nhập sai mật khẩu nhiều lần liên tiếp`,
            })
                .catch(() => undefined);
            const remaining = Math.max((0, loginLockout_1.remainingLockSeconds)(lockedRec, now), 1);
            throw new https_1.HttpsError("resource-exhausted", (0, loginLockout_1.buildLockoutMessage)(remaining), {
                reason: "LOCKED_OUT",
                remainingSeconds: remaining,
            });
        }
        throw new https_1.HttpsError("unauthenticated", INVALID_MSG);
    }
    // 4. Mật khẩu đúng -> xóa bộ đếm
    const uid = result.uid;
    await attemptRef.remove().catch(() => undefined);
    // 5. Kiểm tra hồ sơ & quyền thuộc quán (userIndex chỉ Admin SDK ghi được)
    const [profileSnap, indexSnap] = await Promise.all([
        db.ref(`stores/${cleanStoreCode}/users/${uid}`).get(),
        db.ref(`userIndex/${uid}/${cleanStoreCode}`).get(),
    ]);
    if (!profileSnap.exists() || indexSnap.val() !== true) {
        throw new https_1.HttpsError("permission-denied", `Không tìm thấy thông tin tài khoản nhân viên tại chi nhánh ${cleanStoreCode}. Vui lòng liên hệ Quản lý.`);
    }
    const profile = profileSnap.val();
    if (profile.isActive === false) {
        throw new https_1.HttpsError("permission-denied", "Tài khoản đã bị tạm khóa bởi chủ quán.");
    }
    // 6. Cấp Custom Token
    let token;
    try {
        token = await auth.createCustomToken(uid);
    }
    catch {
        // Thường do service account của Functions thiếu quyền iam.serviceAccounts.signBlob
        throw new https_1.HttpsError("internal", "Máy chủ chưa đủ quyền cấp phiên đăng nhập (Service Account Token Creator).");
    }
    await db.ref(`stores/${cleanStoreCode}/users/${uid}/lastLoginAt`).set(Date.now()).catch(() => undefined);
    return {
        success: true,
        token,
        uid,
        mustChangePassword: profile.mustChangePassword === true,
    };
});
/**
 * 5. Nhập khách hàng từ Firestore kmt_customers vào RTDB của quán (importCustomerToStore)
 *
 * - Thu ngân trở lên, đang hoạt động, thuộc quán (userIndex) mới được gọi.
 * - Đọc Firestore bằng Admin SDK, ghi RTDB với SỐ DƯ THẬT (client không tự sao chép được nữa:
 *   rules chỉ cho Thu ngân tạo khách với 0 điểm).
 * - Idempotent: node RTDB đã có → giữ nguyên, trả về created=false (RTDB là nguồn chuẩn).
 * - Ghi audit log IMPORT_CUSTOMER khi thực sự tạo mới.
 */
exports.importCustomerToStore = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }
    const { storeCode, customerId } = (request.data || {});
    if (!(0, customerSync_1.isValidStoreCode)(storeCode) || !(0, customerSync_1.isValidCustomerKey)(customerId)) {
        throw new https_1.HttpsError("invalid-argument", "Mã cửa hàng hoặc mã khách hàng không hợp lệ.");
    }
    const cleanStoreCode = storeCode.trim().toUpperCase();
    const callerUid = request.auth.uid;
    const [callerSnap, indexSnap] = await Promise.all([
        db.ref(`stores/${cleanStoreCode}/users/${callerUid}`).get(),
        db.ref(`userIndex/${callerUid}/${cleanStoreCode}`).get(),
    ]);
    const caller = (callerSnap.exists() ? callerSnap.val() : null);
    if (!(0, permissions_1.canCallerImportCustomer)(caller, indexSnap.val() === true)) {
        throw new https_1.HttpsError("permission-denied", "Bạn không có quyền nhập khách hàng cho chi nhánh này.");
    }
    const customerRef = db.ref(`stores/${cleanStoreCode}/customers/${customerId}`);
    const existing = await customerRef.get();
    if (existing.exists()) {
        return { success: true, created: false, currentPoints: (0, customerSync_1.readCurrentPoints)(existing.val()) };
    }
    const doc = await admin.firestore().collection("kmt_customers").doc(customerId).get();
    if (!doc.exists) {
        throw new https_1.HttpsError("not-found", `Không tìm thấy khách hàng ${customerId} trên hệ thống Khuyến Mãi Trạm.`);
    }
    const seed = (0, customerSync_1.buildRtdbCustomerFromFirestore)((doc.data() || {}), customerId, Date.now());
    let created = false;
    const tx = await customerRef.transaction((current) => {
        const d = (0, customerSync_1.decideImport)(current, seed);
        created = d.action === "create";
        return d.action === "create" ? d.value : undefined; // undefined = hủy, giữ nguyên dữ liệu hiện có
    });
    const finalVal = (tx.snapshot.val() || null);
    if (created && tx.committed) {
        const now = Date.now();
        const logId = `LOG_${now}_${Math.random().toString(36).substring(2, 7)}`;
        await db
            .ref(`stores/${cleanStoreCode}/audit_logs/${logId}`)
            .set({
            timestamp: now,
            action: "IMPORT_CUSTOMER",
            username: caller?.username || "unknown",
            userFullName: caller?.fullName || "",
            userRole: caller?.roleId || "",
            targetType: "CUSTOMER",
            targetId: customerId,
            details: `Nhập khách ${seed.ho_ten || customerId} (${customerId}) từ kmt_customers với ${seed.currentPoints} điểm`,
        })
            .catch(() => undefined);
    }
    return { success: true, created: created && tx.committed, currentPoints: (0, customerSync_1.readCurrentPoints)(finalVal) };
});
/**
 * 6. Đồng bộ một chiều RTDB → Firestore kmt_customers (mirrorCustomerToFirestore)
 *
 * Điểm chuẩn nằm ở RTDB loyalty_members/{memberKey}; stores/{s}/customers/{id} là cache do trigger mirrorMemberToBranches
 * cập nhật; Firestore chỉ là bản sao để
 * hệ sinh thái Khuyến Mãi Trạm / web đọc. Client KHÔNG ghi điểm vào Firestore nữa.
 * - Doc id Firestore = customerId (khóa RTDB).
 * - Ghi lịch sử kmt_point_history với doc id cố định (chạy lại không trùng).
 * - Xóa khách trên RTDB không xóa Firestore (giữ lịch sử cho hệ thống khác).
 */
exports.mirrorCustomerToFirestore = (0, database_1.onValueWritten)({ ref: "/stores/{storeCode}/customers/{customerId}", region: FUNCTION_REGION }, async (event) => {
    const { storeCode, customerId } = event.params;
    const before = (event.data.before.exists() ? event.data.before.val() : null);
    const after = (event.data.after.exists() ? event.data.after.val() : null);
    if (!after || !(0, customerSync_1.shouldMirror)(before, after))
        return;
    if (!(0, customerSync_1.isValidCustomerKey)(customerId))
        return;
    const fs = admin.firestore();
    const now = Date.now();
    await fs.collection("kmt_customers").doc(customerId).set((0, customerSync_1.buildFirestoreMirror)(after, storeCode, now), { merge: true });
    // Lịch sử điểm (kmt_point_history) KHÔNG ghi ở đây nữa: điểm đổi ở bản ghi dùng chung nên mỗi dòng
    // sổ cái loyalty_ledger/{memberKey}/{opId} sinh đúng 1 bản ghi lịch sử (mirrorLedgerToHistory).
});
// Quản lý duyệt bằng PIN (xem managerPin.ts)
var managerPin_1 = require("./managerPin");
Object.defineProperty(exports, "verifyManagerPin", { enumerable: true, get: function () { return managerPin_1.verifyManagerPin; } });
Object.defineProperty(exports, "setManagerPin", { enumerable: true, get: function () { return managerPin_1.setManagerPin; } });
// Đăng nhập bằng Chấm Công Trạm (xem chamCong.ts, docs/CHAMCONG_SSO.md)
var chamCong_1 = require("./chamCong");
Object.defineProperty(exports, "chamCongSignIn", { enumerable: true, get: function () { return chamCong_1.chamCongSignIn; } });
Object.defineProperty(exports, "linkChamCongStore", { enumerable: true, get: function () { return chamCong_1.linkChamCongStore; } });
Object.defineProperty(exports, "unlinkChamCongStore", { enumerable: true, get: function () { return chamCong_1.unlinkChamCongStore; } });
Object.defineProperty(exports, "getChamCongLinkStatus", { enumerable: true, get: function () { return chamCong_1.getChamCongLinkStatus; } });
// Tự xóa tài khoản (Apple 5.1.1(v)) — xem deleteMyAccount.ts, docs/APP_REVIEW.md
var deleteMyAccount_1 = require("./deleteMyAccount");
Object.defineProperty(exports, "deleteMyAccount", { enumerable: true, get: function () { return deleteMyAccount_1.deleteMyAccount; } });
// Tạo chi nhánh mới (chủ quán) — xem createStore.ts, createStoreLogic.ts
var createStore_1 = require("./createStore");
Object.defineProperty(exports, "createStore", { enumerable: true, get: function () { return createStore_1.createStore; } });
// Điểm DÙNG CHUNG toàn chuỗi: bản ghi loyalty_members + callable/trigger (xem sharedLoyaltyHandlers.ts)
var sharedLoyaltyHandlers_1 = require("./sharedLoyaltyHandlers");
Object.defineProperty(exports, "applyLoyaltyEarn", { enumerable: true, get: function () { return sharedLoyaltyHandlers_1.applyLoyaltyEarn; } });
Object.defineProperty(exports, "redeemLoyaltyPoints", { enumerable: true, get: function () { return sharedLoyaltyHandlers_1.redeemLoyaltyPoints; } });
Object.defineProperty(exports, "refundLoyaltyPoints", { enumerable: true, get: function () { return sharedLoyaltyHandlers_1.refundLoyaltyPoints; } });
Object.defineProperty(exports, "adjustLoyaltyPoints", { enumerable: true, get: function () { return sharedLoyaltyHandlers_1.adjustLoyaltyPoints; } });
Object.defineProperty(exports, "lookupMember", { enumerable: true, get: function () { return sharedLoyaltyHandlers_1.lookupMember; } });
Object.defineProperty(exports, "getMemberLedger", { enumerable: true, get: function () { return sharedLoyaltyHandlers_1.getMemberLedger; } });
Object.defineProperty(exports, "listLoyaltyLedger", { enumerable: true, get: function () { return sharedLoyaltyHandlers_1.listLoyaltyLedger; } });
Object.defineProperty(exports, "setLoyaltyConfig", { enumerable: true, get: function () { return sharedLoyaltyHandlers_1.setLoyaltyConfig; } });
Object.defineProperty(exports, "mirrorMemberToBranches", { enumerable: true, get: function () { return sharedLoyaltyHandlers_1.mirrorMemberToBranches; } });
Object.defineProperty(exports, "linkBranchCustomer", { enumerable: true, get: function () { return sharedLoyaltyHandlers_1.linkBranchCustomer; } });
Object.defineProperty(exports, "mirrorLedgerToHistory", { enumerable: true, get: function () { return sharedLoyaltyHandlers_1.mirrorLedgerToHistory; } });
/**
 * @deprecated Đã bị thay bằng bản ghi điểm dùng chung duy nhất (loyalty_members). KHÔNG còn chuyển điểm giữa
 * các chi nhánh nữa: hàm giữ lại để app cũ chưa cập nhật không bị lỗi 404, luôn trả pulled = 0 / othersPoints = 0
 * và KHÔNG ghi dữ liệu. Có thể xóa sau khi mọi POS đã cập nhật.
 */
exports.pullPooledPoints = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }
    return { success: true, pulled: 0, othersPoints: 0, alreadyApplied: true, deprecated: true };
});
// Xóa khách hàng (Chủ quán/Quản lý) — xem deleteCustomer.ts, deleteCustomerLogic.ts
var deleteCustomer_1 = require("./deleteCustomer");
Object.defineProperty(exports, "deleteCustomer", { enumerable: true, get: function () { return deleteCustomer_1.deleteCustomer; } });
//# sourceMappingURL=index.js.map