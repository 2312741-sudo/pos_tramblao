"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ASSIGNABLE_ROLES = void 0;
exports.isAssignableRole = isAssignableRole;
exports.canAssignAcrossStores = canAssignAcrossStores;
exports.buildAssignedProfile = buildAssignedProfile;
exports.shouldDisableAuthAccount = shouldDisableAuthAccount;
exports.countIndexedStores = countIndexedStores;
/**
 * Một nhân viên làm ở NHIỀU cửa hàng: một tài khoản (một mật khẩu), mỗi cửa hàng một hồ sơ + vai trò riêng.
 * Logic thuần (không Firebase) — dùng bởi assignStaffToStore / setStaffDisabled, có unit test.
 */
const permissions_1 = require("./permissions");
/** Vai trò được gán theo từng cửa hàng (Chủ quán KHÔNG gán qua API này) */
exports.ASSIGNABLE_ROLES = ["ROLE_MANAGER", "ROLE_STAFF", "ROLE_KITCHEN"];
function isAssignableRole(r) {
    return typeof r === "string" && exports.ASSIGNABLE_ROLES.includes(r);
}
/** Chỉ Chủ quán / Admin (isRootOwner hoặc vai trò chủ) ở CẢ cửa hàng nguồn và đích mới được gán */
function canAssignAcrossStores(callerAtSource, callerAtTarget) {
    const ok = (c) => !!c && c.isActive !== false && (0, permissions_1.isOwnerRole)(c.roleId, c.isRootOwner);
    return ok(callerAtSource) && ok(callerAtTarget);
}
function buildAssignedProfile(source, authUid, roleId, by, now) {
    return {
        uid: authUid,
        username: source.username,
        fullName: source.fullName,
        roleId,
        isRootOwner: false,
        isActive: true,
        phone: typeof source.phone === "string" ? source.phone : "",
        customPermissions: [], // quyền riêng không sao chép sang cửa hàng khác
        createdAt: now,
        mustChangePassword: false,
        assignedFromStore: by.storeCode,
        assignedBy: by.username ?? "",
    };
}
/**
 * Khóa tài khoản đăng nhập (Auth) CHỈ khi nhân viên thuộc 1 cửa hàng. Thuộc nhiều cửa hàng:
 * chỉ tắt isActive ở cửa hàng đang thao tác, các cửa hàng khác vẫn làm việc bình thường.
 */
function shouldDisableAuthAccount(storeCount) {
    return storeCount <= 1;
}
/** Số cửa hàng có userIndex = true */
function countIndexedStores(userIndex) {
    if (!userIndex || typeof userIndex !== "object")
        return 0;
    return Object.values(userIndex).filter((v) => v === true).length;
}
//# sourceMappingURL=multiStore.js.map