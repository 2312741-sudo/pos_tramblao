"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CHAMCONG_ERROR_MESSAGES = exports.DEACTIVATED_BY_CHAMCONG = exports.AUTH_PROVIDER_CHAMCONG = exports.POS_ROLE_LOWEST = exports.POS_ROLE_MANAGER = exports.POS_ROLE_OWNER = void 0;
exports.normalizeChamCongRole = normalizeChamCongRole;
exports.posRoleForChamCongRole = posRoleForChamCongRole;
exports.decidePosRole = decidePosRole;
exports.slugifyUsername = slugifyUsername;
exports.buildUsernameBase = buildUsernameBase;
exports.pickUniqueUsername = pickUniqueUsername;
exports.buildMemberships = buildMemberships;
exports.decideSignIn = decideSignIn;
exports.posUidForChamCong = posUidForChamCong;
exports.isValidChamCongUid = isValidChamCongUid;
exports.decideProfile = decideProfile;
exports.buildRevokePatch = buildRevokePatch;
exports.isChamCongStoreOwner = isChamCongStoreOwner;
exports.summarizeChamCongStore = summarizeChamCongStore;
exports.decideLink = decideLink;
exports.buildOkResponse = buildOkResponse;
exports.buildChooseStoreResponse = buildChooseStoreResponse;
/**
 * Logic thuần cho "Đăng nhập bằng Chấm Công Trạm" (SSO từ project Firebase `chamcongtram`).
 * Không phụ thuộc Firebase runtime → unit test 100% (xem chamCongLogic.test.ts).
 * Phần I/O (verify token, đọc Firestore chấm công, ghi RTDB) nằm ở chamCong.ts.
 */
const permissions_1 = require("./permissions");
/** Vai trò POS tương ứng (khớp app_permissions.dart / web/lib/auth.tsx / database.rules.json). */
exports.POS_ROLE_OWNER = "owner";
/** Mã Quản lý chuẩn (đã gộp Quản lý 1 + 2). */
exports.POS_ROLE_MANAGER = permissions_1.ROLE_MANAGER_ID;
/** Vai trò thấp nhất của POS: Nhân viên (đã gộp Thu ngân + Phục vụ). */
exports.POS_ROLE_LOWEST = permissions_1.ROLE_STAFF_ID;
exports.AUTH_PROVIDER_CHAMCONG = "chamcong";
exports.DEACTIVATED_BY_CHAMCONG = "chamcong";
const OWNER_ALIASES = new Set(["owner", "chu", "role_owner", "chu_cua_hang"]);
/** Chuẩn hóa vai trò Chấm Công (owner | manager | manager1/2 | manager_1/2 | legacyManager | chu → owner/manager/employee). */
function normalizeChamCongRole(raw) {
    const clean = typeof raw === "string" ? raw.trim().toLowerCase().replace(/[-\s]+/g, "_") : "";
    if (OWNER_ALIASES.has(clean))
        return "owner";
    if ((0, permissions_1.isManagerRole)(clean))
        return "manager";
    return "employee";
}
function posRoleForChamCongRole(kind) {
    switch (kind) {
        case "owner":
            return exports.POS_ROLE_OWNER;
        case "manager":
            return exports.POS_ROLE_MANAGER;
        default:
            return exports.POS_ROLE_LOWEST;
    }
}
/**
 * Chính sách vai trò POS:
 * - Lần đầu: theo bảng ánh xạ (nhân viên → ROLE_STAFF).
 * - Các lần sau: Chủ/Quản lý bên chấm công → luôn đặt vai trò ánh xạ;
 *   Nhân viên bên chấm công mà POS đang là chủ/quản lý → hạ về ROLE_STAFF;
 *   còn lại giữ vai trò chủ quán đã chọn trong POS (Bếp...); mã cũ Thu ngân/Phục vụ
 *   được chuẩn hóa thành ROLE_STAFF (đã gộp một vai trò). Chủ quán không còn "nâng
 *   nhân viên lên thu ngân" vì Thu ngân = Nhân viên; chỉ còn Bếp hoặc Quản lý.
 */
function decidePosRole(kind, existingRoleId) {
    if (existingRoleId == null || existingRoleId === "")
        return posRoleForChamCongRole(kind);
    if (kind !== "employee")
        return posRoleForChamCongRole(kind);
    if ((0, permissions_1.isOwnerRole)(existingRoleId) || (0, permissions_1.isManagerRole)(existingRoleId))
        return exports.POS_ROLE_LOWEST;
    return (0, permissions_1.normalizeRoleId)(existingRoleId);
}
// ---------------------------------------------------------------------------
// Username
// ---------------------------------------------------------------------------
const USERNAME_MAX = 24;
/** Slug an toàn cho username POS: chỉ [a-z0-9_-] (khớp regex staffSignIn). */
function slugifyUsername(raw) {
    if (typeof raw !== "string")
        return "";
    return raw
        .trim()
        .toLowerCase()
        .replace(/đ/g, "d")
        .normalize("NFD")
        .replace(/[̀-ͯ]/g, "")
        .replace(/\s+/g, "")
        .replace(/[^a-z0-9_-]/g, "")
        .slice(0, USERNAME_MAX);
}
/** Username gốc: mã nhân viên (viết thường) → slug họ tên → "nv" + 6 ký tự uid. */
function buildUsernameBase(employeeCode, fullName, chamCongUid) {
    const fromCode = slugifyUsername(employeeCode);
    if (fromCode.length >= 3)
        return fromCode;
    const fromName = slugifyUsername(fullName);
    if (fromName.length >= 3)
        return fromName;
    const fromUid = slugifyUsername(chamCongUid).slice(0, 6);
    return `nv${fromUid || "user"}`;
}
/** Chọn username chưa bị dùng trong quán: base, base-2, base-3... (so sánh không phân biệt hoa thường). */
function pickUniqueUsername(base, taken) {
    const used = new Set();
    for (const t of taken)
        if (typeof t === "string")
            used.add(t.trim().toLowerCase());
    if (!used.has(base))
        return base;
    for (let i = 2; i < 10000; i++) {
        const suffix = `-${i}`;
        const candidate = `${base.slice(0, USERNAME_MAX - suffix.length)}${suffix}`;
        if (!used.has(candidate))
            return candidate;
    }
    return `${base.slice(0, 14)}-${Date.now().toString(36)}`;
}
const str = (v) => (typeof v === "string" ? v.trim() : "");
function normalizeStatus(raw) {
    const s = str(raw).toLowerCase();
    if (s === "active" || s === "pending" || s === "kicked")
        return s;
    return "missing";
}
/**
 * Gộp dữ liệu Firestore chấm công thành map storeId → membership.
 * - memberDocs: kết quả collectionGroup('members').where('userId','==',uid) (kèm storeId cha).
 * - ownedStoreIds: các store có ownerId === uid → luôn coi là Chủ đang hoạt động.
 */
function buildMemberships(memberDocs, ownedStoreIds, fallbackName = "") {
    const out = new Map();
    for (const { storeId, data } of memberDocs) {
        out.set(storeId, {
            chamCongStoreId: storeId,
            status: normalizeStatus(data.status),
            roleKind: normalizeChamCongRole(data.role),
            name: str(data.name) || fallbackName,
            phone: str(data.phone),
            avatarUrl: str(data.avatarUrl),
            employeeCode: str(data.employeeCode),
        });
    }
    for (const storeId of ownedStoreIds) {
        const prev = out.get(storeId);
        out.set(storeId, {
            chamCongStoreId: storeId,
            status: "active",
            roleKind: "owner",
            name: prev?.name || fallbackName,
            phone: prev?.phone || "",
            avatarUrl: prev?.avatarUrl || "",
            employeeCode: prev?.employeeCode || "",
        });
    }
    return out;
}
/**
 * Quyết định đăng nhập.
 * @param links storeCode POS → chamCongStoreId (chamcong_links/stores)
 * @param memberships map từ buildMemberships
 * @param previouslyProvisioned storeCode đã từng cấp tài khoản cho user này (chamcong_links/users/{sc}/{ccUid}):
 *        nếu member doc bị xóa hẳn → coi như "missing" (không hoạt động) để khóa tài khoản POS.
 * @param requestedStoreCode storeCode client gửi (tùy chọn, đã chuẩn hóa UPPERCASE)
 */
function decideSignIn(links, memberships, previouslyProvisioned, requestedStoreCode) {
    const prior = new Set(previouslyProvisioned);
    const entries = [];
    for (const storeCode of Object.keys(links).sort()) {
        const m = memberships.get(links[storeCode]) || null;
        if (m)
            entries.push({ storeCode, membership: m, active: m.status === "active" });
        else if (prior.has(storeCode))
            entries.push({ storeCode, membership: null, active: false });
    }
    if (requestedStoreCode) {
        const e = entries.find((x) => x.storeCode === requestedStoreCode);
        if (!e)
            return { kind: "DENY", code: "NOT_LINKED", revokeStoreCodes: [] };
        if (!e.active || !e.membership)
            return { kind: "DENY", code: "NOT_ACTIVE_MEMBER", revokeStoreCodes: [e.storeCode] };
        return { kind: "PROCEED", storeCode: e.storeCode, membership: e.membership, revokeStoreCodes: [] };
    }
    if (entries.length === 0)
        return { kind: "DENY", code: "NOT_LINKED", revokeStoreCodes: [] };
    const revokeStoreCodes = entries.filter((e) => !e.active).map((e) => e.storeCode);
    const actives = entries.filter((e) => e.active && e.membership);
    if (actives.length === 0)
        return { kind: "DENY", code: "NOT_ACTIVE_MEMBER", revokeStoreCodes };
    if (actives.length === 1) {
        return { kind: "PROCEED", storeCode: actives[0].storeCode, membership: actives[0].membership, revokeStoreCodes };
    }
    return { kind: "CHOOSE", storeCodes: actives.map((e) => e.storeCode), revokeStoreCodes };
}
// ---------------------------------------------------------------------------
// Hồ sơ POS
// ---------------------------------------------------------------------------
function posUidForChamCong(chamCongUid) {
    return `cc_${chamCongUid}`;
}
/** UID Firebase tối đa 128 ký tự → uid chấm công tối đa 125 để còn tiền tố "cc_". */
function isValidChamCongUid(uid) {
    return typeof uid === "string" && uid.length > 0 && uid.length <= 125 && !/[/.#$\[\]]/.test(uid);
}
function decideProfile(params) {
    const { existing, membership, posUid, chamCongUid, now } = params;
    if (!existing) {
        const roleId = posRoleForChamCongRole(membership.roleKind);
        const username = pickUniqueUsername(buildUsernameBase(membership.employeeCode, membership.name, chamCongUid), params.takenUsernames);
        return {
            kind: "WRITE",
            isNew: true,
            roleId,
            roleChange: null,
            reactivated: false,
            values: {
                uid: posUid,
                username,
                fullName: membership.name || username,
                employeeCode: membership.employeeCode ? membership.employeeCode.trim().toUpperCase() : "",
                phone: membership.phone,
                avatarUrl: membership.avatarUrl,
                roleId,
                isRootOwner: false,
                isActive: true,
                authProvider: exports.AUTH_PROVIDER_CHAMCONG,
                chamCongUid,
                chamCongStoreId: membership.chamCongStoreId,
                mustChangePassword: false,
                customPermissions: [],
                createdAt: now,
            },
        };
    }
    // Không bao giờ ghi đè tài khoản POS gốc (không phải do chấm công cấp)
    if (existing.authProvider !== exports.AUTH_PROVIDER_CHAMCONG)
        return { kind: "CONFLICT" };
    // Bị quản lý POS khóa thủ công → từ chối. Bị khóa do chấm công (kick/pending) → mở lại khi đã active.
    const deactivatedByChamCong = existing.deactivatedBy === exports.DEACTIVATED_BY_CHAMCONG;
    if (existing.isActive === false && !deactivatedByChamCong)
        return { kind: "DISABLED" };
    const currentRole = typeof existing.roleId === "string" ? existing.roleId : "";
    if (existing.isRootOwner === true) {
        // Không đụng vào hồ sơ chủ quán gốc
        return { kind: "WRITE", isNew: false, values: {}, roleId: currentRole, roleChange: null, reactivated: false };
    }
    const values = {};
    if (membership.name && existing.fullName !== membership.name)
        values.fullName = membership.name;
    if (membership.employeeCode) {
        const cleanCode = membership.employeeCode.trim().toUpperCase();
        if (existing.employeeCode !== cleanCode)
            values.employeeCode = cleanCode;
    }
    if (membership.phone && existing.phone !== membership.phone)
        values.phone = membership.phone;
    if (membership.avatarUrl && existing.avatarUrl !== membership.avatarUrl)
        values.avatarUrl = membership.avatarUrl;
    if (existing.chamCongStoreId !== membership.chamCongStoreId)
        values.chamCongStoreId = membership.chamCongStoreId;
    const roleId = decidePosRole(membership.roleKind, currentRole);
    let roleChange = null;
    if (roleId !== currentRole) {
        values.roleId = roleId;
        roleChange = { from: currentRole, to: roleId };
    }
    let reactivated = false;
    if (existing.isActive === false && deactivatedByChamCong) {
        values.isActive = true;
        values.deactivatedBy = null;
        values.chamCongRevokedAt = null;
        reactivated = true;
    }
    return { kind: "WRITE", isNew: false, values, roleId, roleChange, reactivated };
}
/** Patch khóa hồ sơ POS khi thành viên bị kick/pending/xóa bên chấm công. null = không cần ghi. */
function buildRevokePatch(existing, now) {
    if (!existing)
        return null;
    if (existing.authProvider !== exports.AUTH_PROVIDER_CHAMCONG)
        return null;
    if (existing.isRootOwner === true)
        return null;
    if (existing.isActive === false)
        return null;
    return { isActive: false, deactivatedBy: exports.DEACTIVATED_BY_CHAMCONG, chamCongRevokedAt: now };
}
/** Người dùng token là Chủ của store chấm công: store.ownerId === uid HOẶC member role owner/chu đang active. */
function isChamCongStoreOwner(store, member, uid) {
    if (store && store.ownerId === uid)
        return true;
    if (!member)
        return false;
    return normalizeStatus(member.status) === "active" && normalizeChamCongRole(member.role) === "owner";
}
function summarizeChamCongStore(storeId, data) {
    return { chamCongStoreId: storeId, name: str(data?.name) || storeId, code: str(data?.code) };
}
/** Kiểm tra store chấm công đã liên kết với POS khác chưa. */
function decideLink(existingPosStoreForChamCong, targetStoreCode) {
    if (existingPosStoreForChamCong && existingPosStoreForChamCong !== targetStoreCode)
        return "ALREADY_LINKED";
    return "OK";
}
// ---------------------------------------------------------------------------
// Định dạng phản hồi
// ---------------------------------------------------------------------------
function buildOkResponse(p) {
    return {
        status: "OK",
        customToken: p.customToken,
        storeCode: p.storeCode,
        uid: p.uid,
        roleId: p.roleId,
        isNewAccount: p.isNewAccount,
    };
}
function buildChooseStoreResponse(storeCodes, storeNames) {
    return {
        status: "CHOOSE_STORE",
        stores: storeCodes.map((storeCode) => ({ storeCode, storeName: storeNames[storeCode] || storeCode })),
    };
}
exports.CHAMCONG_ERROR_MESSAGES = {
    INVALID_TOKEN: "Phiên đăng nhập Chấm Công Trạm không hợp lệ hoặc đã hết hạn. Vui lòng đăng nhập lại.",
    NOT_LINKED: "Cửa hàng Chấm Công của bạn chưa được liên kết với POS Trạm. Vui lòng liên hệ chủ quán.",
    NOT_ACTIVE_MEMBER: "Bạn chưa được duyệt hoặc đã bị xóa khỏi cửa hàng trên Chấm Công Trạm.",
    POS_ACCOUNT_DISABLED: "Tài khoản POS của bạn đã bị chủ quán tạm khóa.",
    POS_ACCOUNT_CONFLICT: "Tài khoản POS trùng mã với tài khoản sẵn có. Vui lòng liên hệ chủ quán.",
    ALREADY_LINKED: "Cửa hàng Chấm Công này đã được liên kết với một cửa hàng POS khác.",
};
//# sourceMappingURL=chamCongLogic.js.map