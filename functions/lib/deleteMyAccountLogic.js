"use strict";
/**
 * Logic thuần cho "Xóa tài khoản của tôi" (deleteMyAccount) — KHÔNG truy cập RTDB/Auth.
 * Quy tắc:
 *   - Chủ quán gốc (isRootOwner) ở BẤT KỲ chi nhánh nào → từ chối (ROOT_OWNER).
 *   - Còn lại: ẩn danh hóa hồ sơ từng chi nhánh (giữ uid, roleId, mốc thời gian), không xóa cứng lịch sử.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.KEPT_PROFILE_KEYS = exports.DELETE_OWN_ACCOUNT_ACTION = exports.ROOT_OWNER_MESSAGE = exports.ROOT_OWNER_CODE = exports.DELETE_CONFIRM_WORD = void 0;
exports.isConfirmed = isConfirmed;
exports.storeCodesFromIndex = storeCodesFromIndex;
exports.placeholderUsername = placeholderUsername;
exports.findRootOwnerStores = findRootOwnerStores;
exports.decideStoreAction = decideStoreAction;
exports.planAccountDeletion = planAccountDeletion;
exports.chamCongUidOf = chamCongUidOf;
exports.buildAnonymisedProfile = buildAnonymisedProfile;
exports.buildSelfDeleteAudit = buildSelfDeleteAudit;
exports.DELETE_CONFIRM_WORD = "XOA";
exports.ROOT_OWNER_CODE = "ROOT_OWNER";
exports.ROOT_OWNER_MESSAGE = "Chủ quán gốc không thể tự xóa tài khoản. Vui lòng liên hệ đơn vị vận hành để chuyển quyền trước khi xóa.";
exports.DELETE_OWN_ACCOUNT_ACTION = "DELETE_OWN_ACCOUNT";
const CC_PREFIX = "cc_";
/** Các khóa được GIỮ khi ẩn danh hóa (không phải dữ liệu cá nhân). Mọi khóa khác bị loại bỏ. */
exports.KEPT_PROFILE_KEYS = ["uid", "roleId", "isRootOwner", "createdAt", "lastLoginAt", "updatedAt"];
function isConfirmed(value) {
    return value === exports.DELETE_CONFIRM_WORD;
}
/** userIndex/{uid} = { storeCode: true } → danh sách mã cửa hàng (bỏ qua dữ liệu lạ). */
function storeCodesFromIndex(index) {
    if (!index || typeof index !== "object" || Array.isArray(index))
        return [];
    return Object.keys(index);
}
/** Placeholder username không định danh được người dùng: "deleted_<8 ký tự đầu của uid>". */
function placeholderUsername(uid) {
    return `deleted_${uid.slice(0, 8)}`;
}
/** Các chi nhánh mà hồ sơ người gọi có isRootOwner = true. */
function findRootOwnerStores(profiles) {
    return Object.entries(profiles)
        .filter(([, p]) => !!p && typeof p === "object" && p.isRootOwner === true)
        .map(([storeCode]) => storeCode);
}
/** Có hồ sơ tại chi nhánh → ẩn danh hóa; không có (index mồ côi) → bỏ qua. */
function decideStoreAction(profile) {
    return profile && typeof profile === "object" ? "ANONYMISE" : "SKIP";
}
/**
 * Kế hoạch xóa: kiểm tra chủ quán gốc trước; nếu an toàn trả về cửa hàng cần ẩn danh hóa.
 * indexStores: mọi khóa trong userIndex/{uid} (sẽ bị gỡ, kể cả index mồ côi).
 */
function planAccountDeletion(indexStores, profiles) {
    const rootStores = findRootOwnerStores(profiles);
    if (rootStores.length > 0)
        return { kind: "ROOT_OWNER", rootStores };
    const anonymiseStores = [];
    const skippedStores = [];
    for (const storeCode of indexStores) {
        if (decideStoreAction(profiles[storeCode]) === "ANONYMISE")
            anonymiseStores.push(storeCode);
        else
            skippedStores.push(storeCode);
    }
    return { kind: "OK", anonymiseStores, skippedStores, indexStores: [...indexStores] };
}
/** Mã uid trong chamcong_links/users/{storeCode}/{ccUid}: lấy từ hồ sơ, hoặc suy ra từ uid "cc_<ccUid>". */
function chamCongUidOf(profile, posUid) {
    const fromProfile = profile?.chamCongUid;
    if (typeof fromProfile === "string" && fromProfile.trim())
        return fromProfile.trim();
    if (posUid.startsWith(CC_PREFIX) && posUid.length > CC_PREFIX.length)
        return posUid.slice(CC_PREFIX.length);
    return null;
}
/** Hồ sơ ẩn danh: chỉ giữ khóa không cá nhân; ghi đè toàn bộ node (loại email, SĐT, tên, avatar, quyền riêng...). */
function buildAnonymisedProfile(profile, uid, now) {
    const kept = {};
    for (const key of exports.KEPT_PROFILE_KEYS) {
        if (profile[key] !== undefined)
            kept[key] = profile[key];
    }
    kept.uid = uid;
    return {
        ...kept,
        username: placeholderUsername(uid),
        isActive: false,
        deactivatedBy: "self",
        deletedAt: now,
    };
}
/** Bản ghi audit: chỉ có uid (không tên, không SĐT, không email). */
function buildSelfDeleteAudit(uid, roleId, now) {
    return {
        timestamp: now,
        action: exports.DELETE_OWN_ACCOUNT_ACTION,
        username: placeholderUsername(uid),
        userRole: typeof roleId === "string" ? roleId : "",
        targetType: "USER",
        targetId: uid,
        isSuspicious: false,
        details: "Người dùng tự xóa tài khoản (hồ sơ đã ẩn danh hóa)",
    };
}
//# sourceMappingURL=deleteMyAccountLogic.js.map