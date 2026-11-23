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
exports.chamCongEnsureMember = void 0;
/**
 * Chấm Công Trạm BLAO trên Firebase POS (`postramblao`) — Cloud Function `chamCongEnsureMember`.
 *
 * Người dùng chấm công sử dụng CHÍNH tài khoản Firebase Auth của POS (uid POS = uid chấm công)
 * và Firestore mặc định của `postramblao` (`stores/{storeCode}`, `stores/{storeCode}/members/{uid}`, `users/{uid}`).
 */
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const chamCongBlaoLogic_1 = require("./chamCongBlaoLogic");
const FUNCTION_REGION = "asia-southeast1";
const db = () => admin.database();
const fs = () => admin.firestore();
function cleanStore(raw) {
    const s = typeof raw === "string" ? raw.trim().toUpperCase() : "";
    if (!/^[A-Z0-9_-]{2,30}$/.test(s)) {
        throw new https_1.HttpsError("invalid-argument", "Mã cửa hàng không hợp lệ.");
    }
    return s;
}
const newLogId = () => `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
async function writeAudit(storeCode, entry) {
    await db()
        .ref(`stores/${storeCode}/audit_logs/${newLogId()}`)
        .set({ timestamp: Date.now(), ...entry })
        .catch(() => undefined);
}
async function loadPosCaller(storeCode, uid) {
    const [profileSnap, indexSnap] = await Promise.all([
        db().ref(`stores/${storeCode}/users/${uid}`).get(),
        db().ref(`userIndex/${uid}/${storeCode}`).get(),
    ]);
    if (!profileSnap.exists() || indexSnap.val() !== true) {
        throw new https_1.HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
    }
    const profile = profileSnap.val();
    if (profile.isActive === false) {
        throw new https_1.HttpsError("permission-denied", "Tài khoản POS đã bị khóa.");
    }
    return profile;
}
/**
 * chamCongEnsureMember({ storeCode }) — Người gọi đã đăng nhập POS (`postramblao`).
 * Đảm bảo cửa hàng `stores/{storeCode}`, thành viên `stores/{storeCode}/members/{uid}`
 * và hồ sơ `users/{uid}` trên Firestore `postramblao` tồn tại & hợp lệ.
 * Trả về: `{ storeId, isNewMember }`.
 */
exports.chamCongEnsureMember = (0, https_1.onCall)({ region: FUNCTION_REGION }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Vui lòng đăng nhập POS trước khi sử dụng Chấm Công.");
    }
    const data = (request.data || {});
    const storeCode = cleanStore(data.storeCode);
    const uid = request.auth.uid;
    const caller = await loadPosCaller(storeCode, uid);
    const firestore = fs();
    const storeRef = firestore.collection("stores").doc(storeCode);
    const storeSnap = await storeRef.get();
    if (!storeSnap.exists) {
        const [storeInfoSnap, storeUsersSnap] = await Promise.all([
            db().ref(`stores/${storeCode}/storeInfo`).get(),
            db().ref(`stores/${storeCode}/users`).get(),
        ]);
        const info = (storeInfoSnap.val() || {});
        const usersMap = (storeUsersSnap.val() || null);
        const ownerUid = (0, chamCongBlaoLogic_1.pickStoreOwnerUid)(usersMap, uid);
        const storeName = typeof info.storeName === "string" && info.storeName.trim() ? info.storeName.trim() : storeCode;
        const address = typeof info.address === "string" ? info.address.trim() : "";
        await storeRef.set({
            name: storeName,
            code: storeCode,
            posStoreCode: storeCode,
            address,
            ownerId: ownerUid,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    else if (storeSnap.get("posStoreCode") !== storeCode || storeSnap.get("code") !== storeCode) {
        await storeRef.set({ code: storeCode, posStoreCode: storeCode }, { merge: true });
    }
    const memberRef = storeRef.collection("members").doc(uid);
    const memberSnap = await memberRef.get();
    const action = (0, chamCongBlaoLogic_1.memberAction)(memberSnap.exists ? memberSnap.data() : null);
    if (action === "KICKED") {
        throw new https_1.HttpsError("permission-denied", "Bạn đã bị xóa khỏi cửa hàng chấm công. Liên hệ Chủ quán.", { code: "CC_MEMBER_KICKED" });
    }
    let isNewMember = false;
    if (action === "CREATE") {
        isNewMember = true;
        await memberRef.set({
            ...(0, chamCongBlaoLogic_1.buildNewMember)({
                ccUid: uid,
                name: caller.fullName || caller.username || "Nhân viên",
                phone: caller.phone,
                employeeCode: caller.employeeCode,
                role: (0, chamCongBlaoLogic_1.mapPosRoleToCc)(caller.roleId, caller.isRootOwner),
            }),
            joinedAt: firestore_1.Timestamp.now(),
        });
    }
    else if (action === "ACTIVATE") {
        await memberRef.set({ status: "active" }, { merge: true });
    }
    const userRef = firestore.collection("users").doc(uid);
    const userSnap = await userRef.get();
    const needNameInit = isNewMember || !userSnap.exists || !userSnap.get("name");
    await userRef.set({
        id: uid,
        ...(needNameInit
            ? {
                name: caller.fullName || caller.username || "Nhân viên",
                email: "",
                ...(userSnap.exists ? {} : { createdAt: new Date().toISOString() }),
            }
            : {}),
        currentStoreId: storeCode,
        storeIds: firestore_1.FieldValue.arrayUnion(storeCode),
    }, { merge: true });
    if (isNewMember) {
        await writeAudit(storeCode, {
            action: "CHAMCONG_MEMBER_CREATED",
            username: caller.username || uid,
            userFullName: caller.fullName || "",
            userRole: caller.roleId || "",
            targetType: "USER",
            targetId: uid,
            details: `Khởi tạo hồ sơ Chấm Công BLAO cho @${caller.username || uid} tại cửa hàng ${storeCode}`,
        });
    }
    return { storeId: storeCode, isNewMember };
});
//# sourceMappingURL=chamCongBlao.js.map