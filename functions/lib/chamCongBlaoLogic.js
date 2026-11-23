"use strict";
/**
 * Đăng nhập Chấm Công Trạm BLAO bằng TÀI KHOẢN POS — logic thuần (không phụ thuộc Firebase), kiểm thử được.
 *
 * Mô-đun chấm công (trong app POS) và web quản lý chấm công đều đổi phiên đăng nhập POS lấy phiên đăng nhập
 * dự án chấm công `chamcongtramblao` qua hàm chamCongBlaoSignIn (chamCongBlao.ts).
 *
 * Tài khoản chấm công tương ứng của một tài khoản POS:
 *  1. Đã liên kết trước đó → dùng lại.
 *  2. Chưa liên kết: tìm thành viên chấm công CÙNG TÊN (bỏ dấu, không phân biệt hoa thường, gộp khoảng trắng)
 *     chưa thuộc tài khoản POS nào và chưa bị xóa khỏi cửa hàng. Đúng MỘT người → nối vào (giữ lịch sử chấm công,
 *     lương). Không có / nhiều người trùng tên → tạo tài khoản chấm công mới (tránh nối nhầm).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeName = normalizeName;
exports.mapPosRoleToCc = mapPosRoleToCc;
exports.newCcUid = newCcUid;
exports.decideCcAccount = decideCcAccount;
exports.memberAction = memberAction;
exports.buildNewMember = buildNewMember;
/** Chuẩn hóa tên để so khớp: bỏ dấu tiếng Việt (kể cả đ), chữ thường, gộp khoảng trắng */
function normalizeName(name) {
    if (typeof name !== "string")
        return "";
    return name
        .normalize("NFD")
        .replace(/[̀-ͯ]/g, "")
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
/** uid chấm công cho tài khoản tạo mới từ POS (ổn định, hợp lệ cho Firebase Auth / Firestore) */
function newCcUid(storeCode, posUid) {
    const clean = (s) => s.replace(/[^A-Za-z0-9_-]/g, "_");
    return `pos_${clean(storeCode)}_${clean(posUid)}`.slice(0, 128);
}
function decideCcAccount(args) {
    if (args.existingLink)
        return { kind: "LINKED", ccUid: args.existingLink };
    const want = normalizeName(args.posFullName);
    const candidates = want
        ? args.members.filter((m) => normalizeName(m.name) === want &&
            !args.takenCcUids.has(m.uid) &&
            (m.status || "").toLowerCase() !== "kicked")
        : [];
    if (candidates.length === 1)
        return { kind: "MATCHED", ccUid: candidates[0].uid };
    return { kind: "NEW", ccUid: newCcUid(args.storeCode, args.posUid), ambiguous: candidates.length > 1 };
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