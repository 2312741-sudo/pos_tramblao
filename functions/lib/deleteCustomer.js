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
exports.deleteCustomer = void 0;
/**
 * Cloud Function "Xóa khách hàng" (deleteCustomer). Request: { storeCode, customerId, confirm: "XOA" }.
 * Response: { success: true, removedMember: boolean }. Logic thuần ở deleteCustomerLogic.ts.
 *
 * - Chỉ Chủ quán / Quản lý đang hoạt động của chi nhánh.
 * - Xóa stores/{s}/customers/{id} + gỡ liên kết chi nhánh trong loyalty_members (một multi-path update).
 * - Nếu khách không còn ở chi nhánh nào: xóa luôn loyalty_members, loyalty_ledger và chỉ mục sổ cái (không còn SĐT).
 *   Nếu còn chi nhánh khác: giữ điểm/sổ cái chung, chỉ gỡ liên kết chi nhánh này.
 * - Hóa đơn cũ giữ nguyên (kế toán). Bản sao Firestore kmt_customers xóa theo kiểu best-effort.
 */
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const customerSync_1 = require("./customerSync");
const deleteCustomerLogic_1 = require("./deleteCustomerLogic");
const sharedLoyalty_1 = require("./sharedLoyalty");
const FUNCTION_REGION = "asia-southeast1";
const db = () => admin.database();
exports.deleteCustomer = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }
    const data = (request.data || {});
    const storeCode = typeof data.storeCode === "string" ? data.storeCode.trim().toUpperCase() : "";
    const customerId = typeof data.customerId === "string" ? data.customerId : "";
    if (!(0, customerSync_1.isValidStoreCode)(storeCode))
        throw new https_1.HttpsError("invalid-argument", "Mã chi nhánh không hợp lệ.");
    if (!(0, customerSync_1.isValidCustomerKey)(customerId))
        throw new https_1.HttpsError("invalid-argument", "Mã khách hàng không hợp lệ.");
    if (!(0, deleteCustomerLogic_1.isDeleteConfirmed)(data.confirm)) {
        throw new https_1.HttpsError("invalid-argument", `Vui lòng nhập đúng từ khóa "${deleteCustomerLogic_1.DELETE_CUSTOMER_CONFIRM}" để xác nhận.`);
    }
    const uid = request.auth.uid;
    const [callerSnap, indexSnap] = await Promise.all([
        db().ref(`stores/${storeCode}/users/${uid}`).get(),
        db().ref(`userIndex/${uid}/${storeCode}`).get(),
    ]);
    const caller = (callerSnap.exists() ? callerSnap.val() : null);
    if (!(0, deleteCustomerLogic_1.canCallerDeleteCustomer)(caller, indexSnap.val() === true)) {
        throw new https_1.HttpsError("permission-denied", "Chỉ Chủ quán hoặc Quản lý mới được xóa khách hàng.");
    }
    const customerSnap = await db().ref(`stores/${storeCode}/customers/${customerId}`).get();
    if (!customerSnap.exists()) {
        throw new https_1.HttpsError("not-found", "Không tìm thấy khách hàng (có thể đã bị xóa).");
    }
    const customer = (customerSnap.val() || {});
    // Đọc member (và sổ cái nếu cần) để quyết định có xóa dữ liệu dùng chung không
    const memberKey = (0, deleteCustomerLogic_1.planDeleteCustomer)({ storeCode, customerId, customer, member: null, ledger: null }).memberKey;
    const memberSnap = await db().ref(`loyalty_members/${memberKey}`).get();
    const member = (memberSnap.exists() ? memberSnap.val() : null);
    let ledger = null;
    const first = (0, deleteCustomerLogic_1.planDeleteCustomer)({ storeCode, customerId, customer, member, ledger: null });
    if (first.removedMember) {
        const ls = await db().ref(`loyalty_ledger/${memberKey}`).get();
        ledger = (ls.exists() ? ls.val() : null);
    }
    const plan = (0, deleteCustomerLogic_1.planDeleteCustomer)({ storeCode, customerId, customer, member, ledger });
    const now = Date.now();
    const logId = `LOG_${now}_${Math.random().toString(36).substring(2, 7)}`;
    const updates = {
        ...plan.updates,
        [`stores/${storeCode}/audit_logs/${logId}`]: {
            timestamp: now,
            action: "DELETE_CUSTOMER",
            username: caller?.username || "unknown",
            userFullName: caller?.fullName || "",
            userRole: caller?.roleId || "",
            targetType: "CUSTOMER",
            targetId: customerId,
            details: (0, deleteCustomerLogic_1.buildDeleteAuditDetails)(customer.ho_ten ?? customer.name, customer.so_dien_thoai ?? customer.phone, plan.removedMember),
        },
    };
    if ((0, sharedLoyalty_1.isTramChainStore)(storeCode)) {
        for (const other of sharedLoyalty_1.TRAM_CHAIN_STORES) {
            if (other !== storeCode) {
                updates[`stores/${other}/customers/${customerId}`] = null;
                if (memberKey) {
                    updates[`loyalty_members/${memberKey}/branches/${other}/${customerId}`] = null;
                }
            }
        }
    }
    await db().ref().update(updates);
    // Bản sao Firestore (best-effort): chỉ xóa khi bản sao đúng của chi nhánh này
    try {
        const ref = admin.firestore().collection("kmt_customers").doc(customerId);
        const doc = await ref.get();
        if (doc.exists && (doc.data() || {}).pointsSource === `rtdb:stores/${storeCode}/customers`)
            await ref.delete();
    }
    catch (e) {
        console.error("deleteCustomer: xóa kmt_customers lỗi", storeCode, customerId, e);
    }
    return { success: true, removedMember: plan.removedMember };
});
//# sourceMappingURL=deleteCustomer.js.map