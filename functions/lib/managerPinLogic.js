"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ACTION_LABELS = exports.APPROVAL_TTL_MS = exports.APPROVABLE_ACTIONS = void 0;
exports.isApprovableAction = isApprovableAction;
exports.validatePinFormat = validatePinFormat;
exports.hashPin = hashPin;
exports.verifyPinHash = verifyPinHash;
exports.isApproverEligible = isApproverEligible;
exports.approverHasPermission = approverHasPermission;
exports.matchApprover = matchApprover;
exports.sanitizeContext = sanitizeContext;
/**
 * Logic thuần cho "Quản lý duyệt bằng PIN" (độc lập Firebase runtime, unit test được).
 *
 * - PIN của từng quản lý/chủ quán được lưu dạng băm scrypt + salt tại
 *   manager_pins/{storeCode}/{uid} — nút GỐC, ngoài stores/{storeCode}, nên không client nào
 *   đọc/ghi được (rules gốc .read/.write = false; chỉ Admin SDK truy cập).
 * - Người duyệt phải là chủ quán / quản lý đang hoạt động VÀ có quyền tương ứng hành động
 *   (bảng quyền khớp web/lib/auth.tsx ROLE_PERMISSIONS + customPermissions).
 */
const crypto_1 = require("crypto");
const permissions_1 = require("./permissions");
/** Hành động được phép duyệt bằng PIN */
exports.APPROVABLE_ACTIONS = ["DISCOUNT_ITEM", "CANCEL_KITCHEN_ITEM"];
/** Thời gian hiệu lực của một lần duyệt */
exports.APPROVAL_TTL_MS = 5 * 60 * 1000;
const SCRYPT_KEYLEN = 32;
const SCRYPT_OPTS = { N: 16384, r: 8, p: 1 };
function isApprovableAction(a) {
    return typeof a === "string" && exports.APPROVABLE_ACTIONS.includes(a);
}
/** PIN 4–8 chữ số, không chấp nhận dãy toàn một chữ số (VD 0000, 1111) */
function validatePinFormat(pin) {
    if (typeof pin !== "string" || !/^\d{4,8}$/.test(pin))
        return "PIN phải gồm 4–8 chữ số.";
    if (/^(\d)\1+$/.test(pin))
        return "PIN không được là dãy một chữ số lặp lại.";
    return null;
}
function hashPin(pin, saltHex) {
    const salt = saltHex ? Buffer.from(saltHex, "hex") : (0, crypto_1.randomBytes)(16);
    const hash = (0, crypto_1.scryptSync)(pin, salt, SCRYPT_KEYLEN, SCRYPT_OPTS);
    return { algo: "scrypt", salt: salt.toString("hex"), hash: hash.toString("hex") };
}
function verifyPinHash(pin, stored) {
    if (!stored || stored.algo !== "scrypt" || typeof stored.salt !== "string" || typeof stored.hash !== "string") {
        return false;
    }
    const expected = Buffer.from(stored.hash, "hex");
    if (expected.length !== SCRYPT_KEYLEN)
        return false;
    const actual = (0, crypto_1.scryptSync)(pin, Buffer.from(stored.salt, "hex"), SCRYPT_KEYLEN, SCRYPT_OPTS);
    return (0, crypto_1.timingSafeEqual)(actual, expected);
}
/** Quyền theo vai trò — chỉ các quyền liên quan tới duyệt PIN (khớp web/lib/auth.tsx) */
const ROLE_APPROVAL_PERMS = {
    // Quản lý (đã gộp QL1 + QL2): mặc định chỉ duyệt giảm giá món. CANCEL_KITCHEN_ITEM (hủy món đã gửi bếp)
    // chỉ Chủ quán, hoặc Quản lý được Chủ cấp riêng qua customPermissions.
    ROLE_MANAGER: ["DISCOUNT_ITEM"],
};
/** Hồ sơ có thể làm người duyệt (chủ quán / quản lý đang hoạt động) */
function isApproverEligible(p) {
    if (!p || p.isActive === false)
        return false;
    return (0, permissions_1.isOwnerRole)(p.roleId, p.isRootOwner) || (0, permissions_1.isManagerRole)(p.roleId);
}
/** Người duyệt có quyền thực hiện hành động này không */
function approverHasPermission(p, action) {
    if (!isApproverEligible(p))
        return false;
    const profile = p;
    if ((0, permissions_1.isOwnerRole)(profile.roleId, profile.isRootOwner))
        return true;
    const custom = Array.isArray(profile.customPermissions) ? profile.customPermissions : [];
    if (custom.includes(action))
        return true;
    // DISCOUNT_ITEM có alias MANUAL_DISCOUNT (giống web hasPermission)
    if (action === "DISCOUNT_ITEM" && custom.includes("MANUAL_DISCOUNT"))
        return true;
    const perms = ROLE_APPROVAL_PERMS[(0, permissions_1.normalizeRoleId)(profile.roleId)] || [];
    return perms.includes(action);
}
/**
 * Tìm người duyệt khớp PIN. approverUid (nếu có) giới hạn chỉ so với người đó.
 * Không chọn người duyệt: nhiều quản lý trùng PIN ⇒ AMBIGUOUS (yêu cầu chọn người duyệt).
 * Người khớp PIN nhưng thiếu quyền ⇒ NOT_PERMITTED (vẫn tính là một lần thử).
 */
function matchApprover(candidates, pin, action, approverUid) {
    const pool = candidates.filter((c) => isApproverEligible(c.profile) && (!approverUid || c.uid === approverUid));
    const matched = pool.filter((c) => verifyPinHash(pin, c.stored));
    if (matched.length === 0)
        return { ok: false, reason: "NO_MATCH" };
    const permitted = matched.filter((c) => approverHasPermission(c.profile, action));
    if (permitted.length === 0)
        return { ok: false, reason: "NOT_PERMITTED" };
    if (permitted.length > 1)
        return { ok: false, reason: "AMBIGUOUS" };
    return { ok: true, uid: permitted[0].uid, profile: permitted[0].profile };
}
exports.ACTION_LABELS = {
    DISCOUNT_ITEM: "Giảm giá món",
    CANCEL_KITCHEN_ITEM: "Hủy/giảm món đã gửi bếp",
};
/** Cắt ngắn mô tả ngữ cảnh do client gửi (chỉ để ghi nhật ký) */
function sanitizeContext(raw) {
    if (typeof raw !== "string")
        return "";
    return raw.replace(/[\u0000-\u001f]/g, " ").trim().slice(0, 200);
}
//# sourceMappingURL=managerPinLogic.js.map