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
exports.createStore = void 0;
/**
 * Cloud Function "Tạo chi nhánh mới" (createStore) — web admin không còn ghi trực tiếp stores/{mới}
 * (rules chặn vì chưa có userIndex/{uid}/{mới}). Request: { storeCode, storeName, address?, phone?,
 * bankId?, bankAccount?, accountName?, wifiName?, defaultVatRate?, allowStackPromotions?, copyZonesFrom? }.
 * Response: { success, storeCode, zonesFrom: string | null, warning? }.
 * Logic thuần ở createStoreLogic.ts. Sao chép THỰC ĐƠN vẫn do client làm sau khi hàm trả về.
 */
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const deleteMyAccountLogic_1 = require("./deleteMyAccountLogic");
const createStoreLogic_1 = require("./createStoreLogic");
const FUNCTION_REGION = "asia-southeast1";
const db = () => admin.database();
/** Hồ sơ của uid tại từng chi nhánh (null nếu không có). */
async function loadProfiles(stores, uid) {
    const snaps = await Promise.all(stores.map((s) => db().ref(`stores/${s}/users/${uid}`).get()));
    const out = {};
    stores.forEach((s, i) => {
        out[s] = snaps[i].exists() ? snaps[i].val() : null;
    });
    return out;
}
exports.createStore = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }
    const uid = request.auth.uid;
    const data = (request.data || {});
    // 1. Quyền: chủ quán (đang hoạt động) ở ít nhất một chi nhánh trong userIndex/{uid}
    const indexStores = (0, deleteMyAccountLogic_1.storeCodesFromIndex)((await db().ref(`userIndex/${uid}`).get()).val());
    const profiles = await loadProfiles(indexStores, uid);
    const access = (0, createStoreLogic_1.decideOwnerAccess)(indexStores, profiles);
    if (!access.allowed) {
        throw new https_1.HttpsError("permission-denied", "Chỉ chủ quán mới được tạo cửa hàng");
    }
    // 2. Mã chi nhánh
    const norm = (0, createStoreLogic_1.normalizeStoreCode)(data.storeCode);
    if ("error" in norm) {
        throw new https_1.HttpsError("invalid-argument", norm.error);
    }
    const code = norm.code;
    const existing = await db().ref(`stores/${code}/storeInfo`).get();
    if (existing.exists()) {
        throw new https_1.HttpsError("already-exists", `Mã chi nhánh "${code}" đã tồn tại`);
    }
    // 3. Sao chép khu/bàn từ chi nhánh nguồn (tùy chọn; chỉ khi người gọi cũng là chủ quán ở nguồn)
    let layout = null;
    let copiedFrom = null;
    let warning;
    if (typeof data.copyZonesFrom === "string" && data.copyZonesFrom.trim()) {
        const src = (0, createStoreLogic_1.normalizeStoreCode)(data.copyZonesFrom);
        if ("error" in src) {
            warning = "Mã chi nhánh nguồn không hợp lệ nên dùng khu vực mặc định.";
        }
        else if (!(0, createStoreLogic_1.decideOwnerAccess)([src.code], profiles).allowed) {
            warning = `Bạn không phải chủ quán ở chi nhánh ${src.code} nên không sao chép khu vực/bàn; dùng khu vực mặc định.`;
        }
        else {
            const [zonesSnap, tablesSnap] = await Promise.all([
                db().ref(`stores/${src.code}/zones`).get(),
                db().ref(`stores/${src.code}/tables`).get(),
            ]);
            const candidate = (0, createStoreLogic_1.layoutFromSource)(zonesSnap.val(), tablesSnap.val());
            if (Object.keys(candidate.zones).length > 0) {
                layout = candidate;
                copiedFrom = src.code;
            }
            else {
                warning = `Chi nhánh ${src.code} chưa có khu vực nên dùng khu vực mặc định.`;
            }
        }
    }
    // 4. Ghi atomic (một multi-path update)
    const now = Date.now();
    const plan = (0, createStoreLogic_1.planCreateStore)({
        code,
        uid,
        now,
        auditId: `LOG_${now}_${Math.random().toString(36).substring(2, 7)}`,
        input: data,
        caller: access.profile,
        layout,
    });
    // Các chủ gốc khác của chuỗi (chủ ở mọi chi nhánh của người tạo) cũng được vào chi nhánh mới
    try {
        const snaps = await Promise.all(indexStores.map((s) => db().ref(`stores/${s}/users`).get()));
        const byStore = {};
        indexStores.forEach((s, i) => {
            byStore[s] = (snaps[i].val() || {});
        });
        for (const [ownerUid, prof] of Object.entries((0, createStoreLogic_1.chainOwners)(byStore, uid))) {
            plan.updates[`userIndex/${ownerUid}/${code}`] = true;
            plan.updates[`stores/${code}/users/${ownerUid}`] = (0, createStoreLogic_1.buildOwnerProfileForStore)(prof, ownerUid, code, now);
        }
    }
    catch (err) {
        console.error("createStore: không lấy được danh sách chủ chuỗi", err?.message);
    }
    try {
        await db().ref().update(plan.updates);
    }
    catch (err) {
        console.error("createStore: lỗi ghi RTDB", err?.message);
        throw new https_1.HttpsError("internal", "Không thể tạo chi nhánh lúc này. Vui lòng thử lại sau ít phút.");
    }
    return {
        success: true,
        storeCode: code,
        zonesFrom: plan.zonesFrom === "copied" ? copiedFrom : null,
        ...(warning ? { warning } : {}),
    };
});
//# sourceMappingURL=createStore.js.map