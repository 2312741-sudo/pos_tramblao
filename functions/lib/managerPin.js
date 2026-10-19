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
exports.setManagerPin = exports.verifyManagerPin = void 0;
/**
 * Callable "Quản lý duyệt bằng PIN" (verifyManagerPin) và đặt PIN duyệt (setManagerPin).
 *
 * Lưu trữ (chỉ Admin SDK — nằm ngoài stores/{storeCode} nên quyền đọc cấp ở cấp cửa hàng
 * KHÔNG lan xuống; rules gốc mặc định từ chối):
 *   manager_pins/{storeCode}/{uid}          = { algo, salt, hash, updatedAt }
 *   manager_pin_attempts/{storeCode}/{uid}  = bộ đếm sai PIN theo NGƯỜI GỌI (khóa tạm 15 phút sau 5 lần)
 * Cờ hiển thị (không nhạy cảm): stores/{storeCode}/users/{uid}/hasApprovalPin = true
 */
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const loginLockout_1 = require("./loginLockout");
const managerPinLogic_1 = require("./managerPinLogic");
const FUNCTION_REGION = "asia-southeast1";
// Lấy db lười (index.ts gọi initializeApp sau khi import module này)
const db = () => admin.database();
function cleanStore(raw) {
    const s = typeof raw === "string" ? raw.trim().toUpperCase() : "";
    if (!/^[A-Z0-9_-]{2,30}$/.test(s))
        throw new https_1.HttpsError("invalid-argument", "Mã cửa hàng không hợp lệ.");
    return s;
}
async function loadMember(storeCode, uid) {
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
function lockMessage(seconds) {
    const minutes = Math.max(1, Math.ceil(seconds / 60));
    return `Nhập sai PIN quá nhiều lần. Chức năng duyệt bằng PIN bị khóa tạm ${minutes} phút.`;
}
const newLogId = () => `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
/**
 * verifyManagerPin({ storeCode, pin, action, approverUid?, context? })
 * → { approvalId, approverUid, approverName, approverUsername, action, approvedAt, expiresAt }
 */
exports.verifyManagerPin = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    const data = (request.data || {});
    const storeCode = cleanStore(data.storeCode);
    const pin = typeof data.pin === "string" ? data.pin.trim() : "";
    const action = data.action;
    const approverUid = typeof data.approverUid === "string" && data.approverUid ? data.approverUid : null;
    const context = (0, managerPinLogic_1.sanitizeContext)(data.context);
    if (!(0, managerPinLogic_1.isApprovableAction)(action))
        throw new https_1.HttpsError("invalid-argument", "Hành động không hỗ trợ duyệt bằng PIN.");
    if (!/^\d{4,8}$/.test(pin))
        throw new https_1.HttpsError("invalid-argument", "PIN phải gồm 4–8 chữ số.");
    const callerUid = request.auth.uid;
    const caller = await loadMember(storeCode, callerUid);
    // 1. Giữ chỗ 1 lượt thử (transaction — an toàn khi gửi song song)
    const attemptRef = db().ref(`manager_pin_attempts/${storeCode}/${callerUid}`);
    let allowed = false;
    const reserveTx = await attemptRef.transaction((cur) => {
        const r = (0, loginLockout_1.reserveAttempt)(cur, Date.now());
        allowed = r.allowed;
        return r.next;
    });
    if (!allowed) {
        const rec = (reserveTx.snapshot.val() || null);
        const remaining = Math.max((0, loginLockout_1.remainingLockSeconds)(rec, Date.now()), 1);
        throw new https_1.HttpsError("resource-exhausted", lockMessage(remaining), { reason: "LOCKED_OUT", remainingSeconds: remaining });
    }
    // 2. So PIN với hồ sơ quản lý / chủ quán
    const [usersSnap, pinsSnap] = await Promise.all([
        db().ref(`stores/${storeCode}/users`).get(),
        db().ref(`manager_pins/${storeCode}`).get(),
    ]);
    const users = (usersSnap.val() || {});
    const pins = (pinsSnap.val() || {});
    const candidates = Object.entries(users)
        .filter(([uid]) => pins[uid])
        .map(([uid, profile]) => ({ uid, profile, stored: pins[uid] }));
    const result = (0, managerPinLogic_1.matchApprover)(candidates, pin, action, approverUid);
    const now = Date.now();
    if (!result.ok) {
        if (result.reason === "AMBIGUOUS") {
            throw new https_1.HttpsError("failed-precondition", "Vui lòng chọn người duyệt rồi nhập lại PIN.", { reason: "AMBIGUOUS" });
        }
        let justLocked = false;
        let rec = null;
        await attemptRef.transaction((cur) => {
            const r = (0, loginLockout_1.applyFailure)(cur, Date.now());
            justLocked = r.justLocked;
            rec = r.next;
            return r.next;
        });
        if (justLocked) {
            await db()
                .ref(`stores/${storeCode}/audit_logs/${newLogId()}`)
                .set({
                timestamp: now,
                action: "MANAGER_PIN_LOCKED_OUT",
                username: caller.username || callerUid,
                userFullName: caller.fullName || caller.username || "Nhân viên",
                userRole: caller.roleId || "UNKNOWN",
                targetType: "APPROVAL",
                targetId: action,
                isSuspicious: true,
                details: `Nhập sai PIN quản lý nhiều lần (${managerPinLogic_1.ACTION_LABELS[action]}) — khóa duyệt PIN 15 phút${context ? `. ${context}` : ""}`,
            })
                .catch(() => undefined);
            const remaining = Math.max((0, loginLockout_1.remainingLockSeconds)(rec, now), 1);
            throw new https_1.HttpsError("resource-exhausted", lockMessage(remaining), { reason: "LOCKED_OUT", remainingSeconds: remaining });
        }
        throw new https_1.HttpsError("permission-denied", "PIN không đúng hoặc người duyệt không có quyền cho thao tác này.");
    }
    // 3. Thành công: xóa bộ đếm, ghi nhật ký duyệt (phía máy chủ, không giả mạo được người duyệt)
    await attemptRef.remove().catch(() => undefined);
    const approver = result.profile;
    const approverName = String(approver.fullName || approver.username || "Quản lý");
    const approvalId = newLogId();
    const expiresAt = now + managerPinLogic_1.APPROVAL_TTL_MS;
    await db()
        .ref(`stores/${storeCode}/audit_logs/${approvalId}`)
        .set({
        timestamp: now,
        action: "MANAGER_PIN_APPROVED",
        username: caller.username || callerUid,
        userFullName: caller.fullName || caller.username || "Nhân viên",
        userRole: caller.roleId || "UNKNOWN",
        targetType: "APPROVAL",
        targetId: action,
        approvedBy: result.uid,
        approvedByName: approverName,
        approvedByUsername: approver.username || null,
        approvalAction: action,
        expiresAt,
        details: `${approverName} duyệt bằng PIN: ${managerPinLogic_1.ACTION_LABELS[action]} cho ${caller.fullName || caller.username || "nhân viên"}${context ? ` — ${context}` : ""}`,
    });
    return {
        approvalId,
        approverUid: result.uid,
        approverName,
        approverUsername: approver.username || null,
        action,
        approvedAt: now,
        expiresAt,
    };
});
/**
 * setManagerPin({ storeCode, pin })  — quản lý/chủ quán đặt (hoặc xóa khi pin = null) PIN duyệt của CHÍNH MÌNH.
 */
exports.setManagerPin = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    const data = (request.data || {});
    const storeCode = cleanStore(data.storeCode);
    const uid = request.auth.uid;
    const caller = await loadMember(storeCode, uid);
    if (!(0, managerPinLogic_1.isApproverEligible)(caller)) {
        throw new https_1.HttpsError("permission-denied", "Chỉ Chủ quán hoặc Quản lý mới được đặt PIN duyệt.");
    }
    const now = Date.now();
    const clearing = data.pin === null;
    if (!clearing) {
        const err = (0, managerPinLogic_1.validatePinFormat)(typeof data.pin === "string" ? data.pin.trim() : data.pin);
        if (err)
            throw new https_1.HttpsError("invalid-argument", err);
    }
    const updates = {};
    updates[`manager_pins/${storeCode}/${uid}`] = clearing
        ? null
        : { ...(0, managerPinLogic_1.hashPin)(String(data.pin).trim()), updatedAt: now };
    updates[`stores/${storeCode}/users/${uid}/hasApprovalPin`] = clearing ? null : true;
    updates[`stores/${storeCode}/audit_logs/${newLogId()}`] = {
        timestamp: now,
        action: clearing ? "CLEAR_MANAGER_PIN" : "SET_MANAGER_PIN",
        username: caller.username || uid,
        userFullName: caller.fullName || caller.username || "Quản lý",
        userRole: caller.roleId || "UNKNOWN",
        targetType: "USER",
        targetId: uid,
        details: clearing ? "Xóa PIN duyệt quản lý" : "Đặt/đổi PIN duyệt quản lý",
    };
    await db().ref().update(updates);
    return { success: true, hasPin: !clearing };
});
//# sourceMappingURL=managerPin.js.map