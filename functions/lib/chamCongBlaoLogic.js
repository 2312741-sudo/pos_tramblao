"use strict";
/**
 * Chấm Công Trạm BLAO trên Firebase POS (`postramblao`) — logic thuần, kiểm thử được.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeName = normalizeName;
exports.mapPosRoleToCc = mapPosRoleToCc;
exports.memberAction = memberAction;
exports.pickStoreOwnerUid = pickStoreOwnerUid;
exports.buildNewMember = buildNewMember;
/** Chuẩn hóa tên để so khớp: bỏ dấu tiếng Việt (kể cả đ), chữ thường, gộp khoảng trắng */
function normalizeName(name) {
    if (typeof name !== "string")
        return "";
    return name
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/đ/g, "d")
        .replace(/Đ/g, "D")
        .toLowerCase()
        .replace(/\s+/g, " ")
        .trim();
}
/** Vai trò chấm công cho tài khoản MỚI theo vai trò POS: Chủ → owner, Quản lý → manager_1, còn lại → employee */
function mapPosRoleToCc(roleId, isRootOwner) {
    if (isRootOwner === true)
        return "owner";
    const r = (roleId || "").trim().toLowerCase();
    if (r === "owner" || r === "role_owner" || r === "chu" || r === "admin")
        return "owner";
    if (r === "manager" || r.startsWith("manager_") || r === "role_manager" || r.startsWith("role_manager_"))
        return "manager_1";
    return "employee";
}
/** Trạng thái thành viên chấm công hiện có → việc cần làm khi đăng nhập bằng POS */
function memberAction(existing) {
    if (!existing)
        return "CREATE";
    const s = typeof existing.status === "string" ? existing.status.toLowerCase() : "";
    if (s === "kicked")
        return "KICKED";
    if (s === "active")
        return "OK";
    return "ACTIVATE"; // pending / thiếu trạng thái: tài khoản POS hợp lệ nên coi như đã được duyệt
}
/** Tìm UID Chủ cửa hàng trong map users của RTDB để gán ownerId khi khởi tạo store Firestore */
function pickStoreOwnerUid(usersMap, fallbackUid) {
    if (!usersMap || typeof usersMap !== "object")
        return fallbackUid;
    const entries = Object.entries(usersMap).filter(([, u]) => u && u.isActive !== false);
    const rootOwner = entries.find(([, u]) => u.isRootOwner === true);
    if (rootOwner)
        return rootOwner[0];
    const anyOwner = entries.find(([, u]) => mapPosRoleToCc(u.roleId, u.isRootOwner) === "owner");
    if (anyOwner)
        return anyOwner[0];
    return fallbackUid;
}
/** Hồ sơ thành viên chấm công cho tài khoản tạo mới (joinedAt do tầng I/O gắn Timestamp) */
function buildNewMember(args) {
    return {
        userId: args.ccUid,
        name: args.name.trim().slice(0, 100) || "Nhân viên",
        phone: args.phone?.trim() || null,
        avatarUrl: null,
        role: args.role,
        status: "active",
        employeeType: "fulltime",
        baseMonthlySalary: 0,
        baseHourlyRate: 0,
        standardHoursPerMonth: 208,
        employeeCode: args.employeeCode?.trim() || null,
        department: null,
        createdVia: "pos",
    };
}
//# sourceMappingURL=chamCongBlaoLogic.js.map