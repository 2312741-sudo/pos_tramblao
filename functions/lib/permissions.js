"use strict";
/**
 * Logic kiểm tra quyền hạn thuần túy cho Cloud Functions
 * Độc lập với Firebase runtime, có thể unit test 100%.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.OWNER_GRANT_ONLY_PERMISSIONS = exports.MANAGER_ROLE_LABEL = exports.STAFF_ROLE_LABEL = exports.ROLE_KITCHEN_ID = exports.ROLE_STAFF_ID = exports.ROLE_MANAGER_ID = void 0;
exports.isOwnerRole = isOwnerRole;
exports.normalizeRoleId = normalizeRoleId;
exports.isManagerRole = isManagerRole;
exports.isStaffRole = isStaffRole;
exports.sanitizeCustomPermissions = sanitizeCustomPermissions;
exports.canCallerManageUsers = canCallerManageUsers;
exports.canCallerCreateRole = canCallerCreateRole;
exports.canCallerResetPassword = canCallerResetPassword;
exports.canCallerSetDisabled = canCallerSetDisabled;
exports.normalizeUsername = normalizeUsername;
exports.buildSyntheticEmail = buildSyntheticEmail;
exports.isCashierRole = isCashierRole;
exports.canCallerImportCustomer = canCallerImportCustomer;
exports.resolveStaffAuthUid = resolveStaffAuthUid;
exports.isChamCongAccount = isChamCongAccount;
function isOwnerRole(roleId, isRootOwner) {
    if (isRootOwner === true)
        return true;
    if (!roleId)
        return false;
    const clean = roleId.toLowerCase();
    return clean === "owner" || clean === "role_owner" || clean === "chu" || clean === "admin";
}
/** Mã vai trò chuẩn của "Quản lý" (đã gộp Quản lý 1 + Quản lý 2). */
exports.ROLE_MANAGER_ID = "ROLE_MANAGER";
/** Mã vai trò chuẩn của "Nhân viên" (đã gộp Thu ngân + Phục vụ). */
exports.ROLE_STAFF_ID = "ROLE_STAFF";
exports.ROLE_KITCHEN_ID = "ROLE_KITCHEN";
/** Tên hiển thị của vai trò gộp Thu ngân/Phục vụ — đổi một chỗ này khi cần đổi tên. */
exports.STAFF_ROLE_LABEL = "Nhân viên";
exports.MANAGER_ROLE_LABEL = "Quản lý";
const norm = (raw) => raw.trim().toLowerCase().replace(/[-\s]+/g, "_");
/** Mọi mã cũ/biến thể của vai trò Quản lý. */
const MANAGER_ROLE_ALIASES = new Set([
    "manager", "role_manager", "manager_1", "manager_2", "role_manager_1", "role_manager_2",
    "manager1", "manager2", "legacymanager", "legacy_manager",
    "ql", "ql1", "ql2", "ql_1", "ql_2", "quan_ly", "quan_ly_1", "quan_ly_2",
]);
/** Mọi mã cũ/biến thể của vai trò Nhân viên (Thu ngân + Phục vụ + employee). */
const STAFF_ROLE_ALIASES = new Set([
    "role_staff", "staff", "employee", "role_employee", "cashier", "role_cashier",
    "waiter", "role_waiter", "nhan_vien", "nv", "thu_ngan", "phuc_vu",
]);
/**
 * Chuẩn hóa mã vai trò: mọi biến thể Quản lý → "ROLE_MANAGER"; mọi biến thể Thu ngân/Phục vụ/employee
 * → "ROLE_STAFF". Vai trò khác (owner, ROLE_KITCHEN...) giữ nguyên (đã trim).
 * Mọi bản ghi MỚI phải ghi mã đã chuẩn hóa.
 */
function normalizeRoleId(raw) {
    if (raw == null)
        return "";
    const trimmed = String(raw).trim();
    const clean = norm(trimmed);
    if (MANAGER_ROLE_ALIASES.has(clean))
        return exports.ROLE_MANAGER_ID;
    if (STAFF_ROLE_ALIASES.has(clean))
        return exports.ROLE_STAFF_ID;
    return trimmed;
}
function isManagerRole(roleId) {
    if (!roleId)
        return false;
    return normalizeRoleId(roleId) === exports.ROLE_MANAGER_ID;
}
/** Vai trò Nhân viên (đã gộp Thu ngân + Phục vụ). */
function isStaffRole(roleId) {
    if (!roleId)
        return false;
    return normalizeRoleId(roleId) === exports.ROLE_STAFF_ID;
}
/**
 * Quyền CHỈ Chủ quán được cấp thêm (qua customPermissions) cho từng tài khoản — Quản lý mặc định KHÔNG có,
 * và Quản lý cũng không tự cấp / cấp cho người khác. Giữ đồng bộ với:
 *  - app_flutter/lib/core/permissions/app_permissions.dart (ownerGrantOnly)
 *  - web/lib/permission-catalog.ts (OWNER_GRANT_ONLY_PERMISSIONS)
 *  - database.rules.json (users/$uid/customPermissions/$i .validate — hiện chặn đủ 4 mã này)
 */
exports.OWNER_GRANT_ONLY_PERMISSIONS = [
    "CANCEL_BILL",
    "CANCEL_KITCHEN_ITEM",
    "VIEW_AUDIT_LOGS",
    "EXPORT_AUDIT_LOGS",
];
/**
 * Lọc danh sách quyền riêng khi tạo tài khoản: chỉ chuỗi hợp lệ; người gọi KHÔNG phải Chủ quán
 * thì bị bỏ các quyền thuộc [OWNER_GRANT_ONLY_PERMISSIONS].
 */
function sanitizeCustomPermissions(caller, requested) {
    if (!Array.isArray(requested))
        return [];
    const isOwner = !!caller && isOwnerRole(caller.roleId, caller.isRootOwner);
    const out = [];
    for (const p of requested) {
        if (typeof p !== "string" || !p.trim())
            continue;
        const code = p.trim();
        if (!isOwner && exports.OWNER_GRANT_ONLY_PERMISSIONS.includes(code))
            continue;
        if (!out.includes(code))
            out.push(code);
    }
    return out;
}
function canCallerManageUsers(caller) {
    if (!caller || caller.isActive === false)
        return false;
    return isOwnerRole(caller.roleId, caller.isRootOwner) || isManagerRole(caller.roleId);
}
function canCallerCreateRole(caller, targetRoleId, targetIsRootOwner) {
    if (caller.isActive === false)
        return false;
    if (targetIsRootOwner === true)
        return false; // Không ai được tạo thêm root owner qua API
    const callerIsOwner = isOwnerRole(caller.roleId, caller.isRootOwner);
    if (callerIsOwner)
        return true;
    const callerIsManager = isManagerRole(caller.roleId);
    if (callerIsManager) {
        // Quản lý không được tạo chủ quán
        return !isOwnerRole(targetRoleId);
    }
    return false;
}
function canCallerResetPassword(caller, target, isSelf) {
    if (caller.isActive === false)
        return false;
    if (isSelf)
        return true;
    if (target.isRootOwner === true) {
        // Mật khẩu chủ quán gốc chỉ chính chủ mới đặt lại được
        return false;
    }
    const callerIsOwner = isOwnerRole(caller.roleId, caller.isRootOwner);
    if (callerIsOwner)
        return true;
    const callerIsManager = isManagerRole(caller.roleId);
    if (callerIsManager) {
        // Quản lý chỉ đặt lại mật khẩu cho Nhân viên / Bếp; không đụng tới Chủ quán hay Quản lý khác
        return !isOwnerRole(target.roleId, target.isRootOwner) && !isManagerRole(target.roleId);
    }
    return false;
}
function canCallerSetDisabled(caller, target, targetUid, callerUid) {
    if (caller.isActive === false)
        return false;
    if (callerUid === targetUid)
        return false; // Không được tự khóa chính mình
    if (target.isRootOwner === true)
        return false; // Không bao giờ được khóa chủ quán gốc
    const callerIsOwner = isOwnerRole(caller.roleId, caller.isRootOwner);
    if (callerIsOwner)
        return true;
    const callerIsManager = isManagerRole(caller.roleId);
    if (callerIsManager) {
        // Quản lý không được khóa Chủ quán hoặc Quản lý khác
        return !isOwnerRole(target.roleId, target.isRootOwner) && !isManagerRole(target.roleId);
    }
    return false;
}
function normalizeUsername(raw) {
    return raw
        .trim()
        .toLowerCase()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/đ/g, "d")
        .replace(/[^a-z0-9_.-]/g, "");
}
function buildSyntheticEmail(username, storeCode) {
    const cleanUser = normalizeUsername(username);
    const cleanStore = storeCode.trim().toLowerCase().replace(/[^a-z0-9]/g, "");
    return `${cleanUser}.${cleanStore}@tram.local`;
}
/** @deprecated Thu ngân đã gộp vào Nhân viên — giữ tên cũ cho mã gọi cũ. */
function isCashierRole(roleId) {
    return isStaffRole(roleId);
}
/**
 * Nhập khách hàng từ Firestore kmt_customers vào RTDB của quán (importCustomerToStore):
 * người gọi phải là thành viên ĐANG HOẠT ĐỘNG của quán (userIndex/{uid}/{store} === true)
 * với vai trò Thu ngân trở lên.
 */
function canCallerImportCustomer(caller, inStoreIndex) {
    if (!caller || !inStoreIndex || caller.isActive === false)
        return false;
    return isOwnerRole(caller.roleId, caller.isRootOwner) || isManagerRole(caller.roleId) || isCashierRole(caller.roleId);
}
/** UID Firebase Auth thật của nhân viên: trường `uid` trong hồ sơ, nếu không có thì khóa nút. */
function resolveStaffAuthUid(nodeKey, record) {
    const fromRecord = record && typeof record.uid === "string" ? record.uid.trim() : "";
    return fromRecord || nodeKey;
}
/** Tài khoản tự tạo khi đăng nhập bằng Chấm Công Trạm (không có mật khẩu POS). */
function isChamCongAccount(nodeKey, record) {
    return (record && record.authProvider === "chamcong") || nodeKey.startsWith("cc_");
}
//# sourceMappingURL=permissions.js.map