"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DELETE_CUSTOMER_CONFIRM = void 0;
exports.isDeleteConfirmed = isDeleteConfirmed;
exports.canCallerDeleteCustomer = canCallerDeleteCustomer;
exports.maskPhone = maskPhone;
exports.buildDeleteAuditDetails = buildDeleteAuditDetails;
exports.remainingBranchLinks = remainingBranchLinks;
exports.planDeleteCustomer = planDeleteCustomer;
/**
 * Logic THUẦN của callable deleteCustomer (xóa khách hàng ở một chi nhánh). Không phụ thuộc Firebase.
 * Xem deleteCustomer.ts cho phần I/O.
 */
const permissions_1 = require("./permissions");
const loyaltyLedgerQuery_1 = require("./loyaltyLedgerQuery");
const sharedLoyalty_1 = require("./sharedLoyalty");
exports.DELETE_CUSTOMER_CONFIRM = "XOA";
function isDeleteConfirmed(v) {
    return typeof v === "string" && v.trim().toUpperCase() === exports.DELETE_CUSTOMER_CONFIRM;
}
/** Chỉ Chủ quán / Quản lý ĐANG HOẠT ĐỘNG và là thành viên của quán (userIndex/{uid}/{store} === true). */
function canCallerDeleteCustomer(caller, inStoreIndex) {
    if (!caller || !inStoreIndex || caller.isActive === false)
        return false;
    return (0, permissions_1.isOwnerRole)(caller.roleId, caller.isRootOwner) || (0, permissions_1.isManagerRole)(caller.roleId);
}
/** "0912345678" → "...678" (không lưu đủ SĐT vào nhật ký). */
function maskPhone(raw) {
    const digits = String(raw ?? "").replace(/\D/g, "");
    return digits.length >= 3 ? `...${digits.slice(-3)}` : "";
}
function buildDeleteAuditDetails(name, phone, removedMember) {
    const n = String(name ?? "").trim() || "(không tên)";
    const p = maskPhone(phone);
    return `Xóa khách hàng ${n}${p ? ` (SĐT ${p})` : ""}${removedMember ? " - đã xóa cả điểm tích lũy" : " - giữ điểm vì khách còn ở chi nhánh khác"}`;
}
/** Số liên kết chi nhánh còn lại của member sau khi gỡ (storeCode, customerId). */
function remainingBranchLinks(member, storeCode, customerId) {
    const b = (member?.branches || {});
    let n = 0;
    for (const [s, customers] of Object.entries(b)) {
        if (!customers || typeof customers !== "object")
            continue;
        for (const [cid, v] of Object.entries(customers)) {
            if (!v)
                continue;
            if (s === storeCode && cid === customerId)
                continue;
            n++;
        }
    }
    return n;
}
/**
 * @param customer node stores/{s}/customers/{id}
 * @param member loyalty_members/{memberKey} hiện tại (null nếu chưa có)
 * @param ledger loyalty_ledger/{memberKey} hiện tại (opId → entry), để suy ra các khóa chỉ mục theo tháng
 */
function planDeleteCustomer(input) {
    const { storeCode, customerId, customer, member, ledger } = input;
    const memberKey = (0, sharedLoyalty_1.memberKeyFor)(customer.so_dien_thoai ?? customer.phone, storeCode, customerId);
    const updates = {
        [`stores/${storeCode}/customers/${customerId}`]: null,
    };
    if (member)
        updates[`loyalty_members/${memberKey}/branches/${storeCode}/${customerId}`] = null;
    const removedMember = !!member && remainingBranchLinks(member, storeCode, customerId) === 0;
    if (removedMember) {
        // Thay các lệnh gỡ liên kết bằng xóa cả nút
        delete updates[`loyalty_members/${memberKey}/branches/${storeCode}/${customerId}`];
        updates[`loyalty_members/${memberKey}`] = null;
        updates[`loyalty_ledger/${memberKey}`] = null;
        for (const [opId, e] of Object.entries(ledger || {})) {
            const at = Number(e?.at);
            if (Number.isFinite(at))
                updates[(0, loyaltyLedgerQuery_1.indexPath)(memberKey, opId, at)] = null;
        }
    }
    return { memberKey, removedMember, updates };
}
//# sourceMappingURL=deleteCustomerLogic.js.map