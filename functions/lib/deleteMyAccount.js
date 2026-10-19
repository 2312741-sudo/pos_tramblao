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
exports.deleteMyAccount = void 0;
/**
 * Cloud Function "Xóa tài khoản của tôi" (deleteMyAccount) — Apple Guideline 5.1.1(v).
 * Request: { confirm: "XOA" }. Yêu cầu đăng nhập. Logic thuần ở deleteMyAccountLogic.ts.
 *
 * Thứ tự an toàn:
 *   1. Kiểm tra chủ quán gốc ở mọi chi nhánh (chưa ghi gì) → ROOT_OWNER nếu có.
 *   2. Thu hồi refresh token (chặn phiên mới).
 *   3. Một lần update RTDB: ẩn danh hồ sơ, gỡ userIndex, gỡ chamcong_links/users, ghi audit.
 *   4. Xóa Firebase Auth user (bước cuối → nếu lỗi, gọi lại vẫn an toàn vì index đã gỡ).
 */
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const deleteMyAccountLogic_1 = require("./deleteMyAccountLogic");
const FUNCTION_REGION = "asia-southeast1";
// Lấy db/auth lười (index.ts gọi initializeApp trước khi hàm chạy)
const db = () => admin.database();
const auth = () => admin.auth();
exports.deleteMyAccount = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }
    const data = (request.data || {});
    if (!(0, deleteMyAccountLogic_1.isConfirmed)(data.confirm)) {
        throw new https_1.HttpsError("invalid-argument", `Vui lòng nhập đúng từ khóa "${deleteMyAccountLogic_1.DELETE_CONFIRM_WORD}" để xác nhận.`);
    }
    const uid = request.auth.uid;
    // 1. Tìm mọi chi nhánh có hồ sơ của người gọi
    const indexSnap = await db().ref(`userIndex/${uid}`).get();
    const indexStores = (0, deleteMyAccountLogic_1.storeCodesFromIndex)(indexSnap.val());
    const profileSnaps = await Promise.all(indexStores.map((s) => db().ref(`stores/${s}/users/${uid}`).get()));
    const profiles = {};
    indexStores.forEach((s, i) => {
        profiles[s] = profileSnaps[i].exists() ? profileSnaps[i].val() : null;
    });
    const plan = (0, deleteMyAccountLogic_1.planAccountDeletion)(indexStores, profiles);
    if (plan.kind === "ROOT_OWNER") {
        throw new https_1.HttpsError("failed-precondition", deleteMyAccountLogic_1.ROOT_OWNER_MESSAGE, { code: deleteMyAccountLogic_1.ROOT_OWNER_CODE });
    }
    // 2. Chặn phiên mới (lỗi nếu user đã bị xóa trước đó → bỏ qua)
    await auth().revokeRefreshTokens(uid).catch(() => undefined);
    // 3. Ghi RTDB một lần
    const now = Date.now();
    const updates = {};
    try {
        for (const s of plan.anonymiseStores) {
            const profile = profiles[s];
            updates[`stores/${s}/users/${uid}`] = (0, deleteMyAccountLogic_1.buildAnonymisedProfile)(profile, uid, now);
            const ccUid = (0, deleteMyAccountLogic_1.chamCongUidOf)(profile, uid);
            if (ccUid) {
                const linkSnap = await db().ref(`chamcong_links/users/${s}/${ccUid}`).get();
                if (linkSnap.val() === uid)
                    updates[`chamcong_links/users/${s}/${ccUid}`] = null;
            }
            const logId = `LOG_${now}_${Math.random().toString(36).substring(2, 7)}`;
            updates[`stores/${s}/audit_logs/${logId}`] = (0, deleteMyAccountLogic_1.buildSelfDeleteAudit)(uid, profile.roleId, now);
        }
        for (const s of plan.indexStores) {
            updates[`userIndex/${uid}/${s}`] = null;
        }
        if (Object.keys(updates).length > 0) {
            await db().ref().update(updates);
        }
    }
    catch (err) {
        console.error("deleteMyAccount: lỗi ghi RTDB", err?.message);
        throw new https_1.HttpsError("internal", "Không thể xóa tài khoản lúc này. Vui lòng thử lại sau ít phút.");
    }
    // 4. Xóa tài khoản đăng nhập (idempotent: không còn thì coi như xong)
    try {
        await auth().deleteUser(uid);
    }
    catch (err) {
        if (err?.code !== "auth/user-not-found") {
            console.error("deleteMyAccount: lỗi xóa Auth user", err?.message);
            throw new https_1.HttpsError("internal", "Hồ sơ đã được xóa nhưng chưa xóa xong tài khoản đăng nhập. Vui lòng thử lại.");
        }
    }
    return { success: true };
});
//# sourceMappingURL=deleteMyAccount.js.map