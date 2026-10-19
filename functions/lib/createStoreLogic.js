"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_TABLES = exports.DEFAULT_ZONES = exports.DEFAULT_ACCOUNT_NAME = exports.DEFAULT_BANK_ID = exports.DEFAULT_WIFI = exports.DEFAULT_ADDRESS = exports.STORE_CODE_MAX = exports.STORE_CODE_MIN = exports.CREATE_STORE_ACTION = void 0;
exports.normalizeStoreCode = normalizeStoreCode;
exports.isActiveOwner = isActiveOwner;
exports.decideOwnerAccess = decideOwnerAccess;
exports.layoutFromSource = layoutFromSource;
exports.buildStoreInfo = buildStoreInfo;
exports.buildOwnerProfileForStore = buildOwnerProfileForStore;
exports.planCreateStore = planCreateStore;
exports.chainOwners = chainOwners;
/**
 * Logic thuần cho "Tạo chi nhánh mới" (createStore) — KHÔNG truy cập RTDB/Auth.
 * Quy tắc:
 *   - Chỉ Chủ quán ĐANG HOẠT ĐỘNG ở ít nhất một chi nhánh trong userIndex/{uid} mới được tạo.
 *   - Mã chi nhánh chuẩn hóa GIỐNG web (in hoa, chỉ A-Z 0-9 _, 2–20 ký tự).
 *   - Mọi thứ ghi ra RTDB gom vào MỘT bản cập nhật đa đường dẫn (atomic) — xem planCreateStore.
 */
const permissions_1 = require("./permissions");
exports.CREATE_STORE_ACTION = "CREATE_STORE";
exports.STORE_CODE_MIN = 2;
exports.STORE_CODE_MAX = 20;
const FORBIDDEN_KEY_CHARS = /[.#$/[\]]/;
/** Mặc định giống web (lib/data-context.tsx createStore). */
exports.DEFAULT_ADDRESS = "Chi nhánh mới";
exports.DEFAULT_WIFI = "Tram_FnB_Free";
exports.DEFAULT_BANK_ID = "MB";
exports.DEFAULT_ACCOUNT_NAME = "CHU CUA HANG";
/** Khu vực & bàn mặc định — đúng bộ web đang tạo (lib/data-context.tsx). */
exports.DEFAULT_ZONES = {
    "Tầng 1": { name: "Tầng 1" },
    "Tầng 2": { name: "Tầng 2" },
    "Sân Vườn": { name: "Sân Vườn" },
};
exports.DEFAULT_TABLES = {
    "Tầng 1_Bàn 01": { name: "Bàn 01", zone: "Tầng 1", inUse: false },
    "Tầng 1_Bàn 02": { name: "Bàn 02", zone: "Tầng 1", inUse: false },
    "Tầng 1_Bàn 03": { name: "Bàn 03", zone: "Tầng 1", inUse: false },
    "Tầng 2_Bàn 04": { name: "Bàn 04", zone: "Tầng 2", inUse: false },
    "Tầng 2_Bàn 05": { name: "Bàn 05", zone: "Tầng 2", inUse: false },
    "Sân Vườn_Bàn SV1": { name: "Bàn SV1", zone: "Sân Vườn", inUse: false },
};
/** Chuẩn hóa mã chi nhánh: in hoa, bỏ ký tự ngoài A-Z 0-9 _; rỗng / quá ngắn / quá dài → lỗi. */
function normalizeStoreCode(raw) {
    const code = String(raw ?? "").toUpperCase().trim().replace(/[^A-Z0-9_]/g, "");
    if (!code)
        return { error: "Mã chi nhánh không được để trống và chỉ gồm chữ cái, số." };
    if (code.length < exports.STORE_CODE_MIN)
        return { error: `Mã chi nhánh phải có ít nhất ${exports.STORE_CODE_MIN} ký tự.` };
    if (code.length > exports.STORE_CODE_MAX)
        return { error: `Mã chi nhánh tối đa ${exports.STORE_CODE_MAX} ký tự.` };
    return { code };
}
/** Chủ quán đang hoạt động (isRootOwner hoặc vai trò Chủ quán). */
function isActiveOwner(p) {
    return !!p && typeof p === "object" && p.isActive !== false && (0, permissions_1.isOwnerRole)(p.roleId, p.isRootOwner === true);
}
/**
 * Quyết định quyền tạo chi nhánh: chỉ cần là chủ quán ở MỘT chi nhánh trong danh sách index.
 * profiles[s] = stores/{s}/users/{uid} (null nếu không có hồ sơ tại s).
 */
function decideOwnerAccess(indexStores, profiles) {
    for (const s of indexStores) {
        const p = profiles[s];
        if (p && isActiveOwner(p))
            return { allowed: true, viaStore: s, profile: p };
    }
    return { allowed: false };
}
/**
 * Khu vực + bàn sao chép từ chi nhánh nguồn (chỉ tên): bàn đặt inUse=false, currentOrderJson="".
 * Bỏ khu/bàn có ký tự cấm trong khóa RTDB. Tên khu = tập hợp khu khai báo ∪ khu của các bàn.
 */
function layoutFromSource(zonesRaw, tablesRaw) {
    const zones = {};
    const tables = {};
    const addZone = (n) => {
        const name = n.trim();
        if (name && !FORBIDDEN_KEY_CHARS.test(name))
            zones[name] = { name };
    };
    if (zonesRaw && typeof zonesRaw === "object") {
        for (const [key, raw] of Object.entries(zonesRaw)) {
            const n = raw && typeof raw === "object" ? String(raw.name ?? key) : key;
            addZone(n);
        }
    }
    if (tablesRaw && typeof tablesRaw === "object") {
        for (const [key, raw] of Object.entries(tablesRaw)) {
            if (!raw || typeof raw !== "object")
                continue;
            const v = raw;
            const name = String(v.name ?? key).trim();
            const zone = String(v.zone ?? "").trim();
            if (!name || !zone)
                continue;
            const nodeKey = `${zone}_${name}`;
            if (FORBIDDEN_KEY_CHARS.test(nodeKey))
                continue;
            addZone(zone);
            tables[nodeKey] = { name, zone, inUse: false, currentOrderJson: "" };
        }
    }
    return { zones, tables };
}
const text = (v, fallback = "") => {
    const s = typeof v === "string" ? v.trim() : "";
    return s || fallback;
};
/** storeInfo của chi nhánh mới (điền mặc định cho trường trống). */
function buildStoreInfo(code, input, now) {
    const vat = typeof input.defaultVatRate === "number" && Number.isFinite(input.defaultVatRate) ? input.defaultVatRate : 0;
    return {
        id: code,
        storeCode: code,
        storeName: text(input.storeName, `POS Trạm - ${code}`),
        address: text(input.address, exports.DEFAULT_ADDRESS),
        phone: text(input.phone),
        wifiName: text(input.wifiName, exports.DEFAULT_WIFI),
        bankId: text(input.bankId, exports.DEFAULT_BANK_ID),
        bankAccount: text(input.bankAccount),
        accountName: text(input.accountName, exports.DEFAULT_ACCOUNT_NAME),
        defaultVatRate: vat,
        allowStackPromotions: typeof input.allowStackPromotions === "boolean" ? input.allowStackPromotions : true,
        active: true,
        createdAt: now,
    };
}
/** Hồ sơ của chính chủ quán tại chi nhánh mới (sao từ hồ sơ họ đang có ở chi nhánh khác). */
function buildOwnerProfileForStore(caller, uid, code, now) {
    const out = {
        uid,
        username: text(caller.username),
        fullName: text(caller.fullName),
        roleId: text(caller.roleId),
        isRootOwner: caller.isRootOwner === true,
        isActive: true,
        phone: text(caller.phone),
        customPermissions: Array.isArray(caller.customPermissions)
            ? caller.customPermissions.filter((p) => typeof p === "string")
            : [],
        createdAt: now,
        storeCode: code,
    };
    if (typeof caller.role === "string")
        out.role = caller.role;
    return out;
}
/**
 * Kế hoạch ghi (một multi-path update):
 *   stores/{code}/storeInfo, stores/{code}/zones, stores/{code}/tables,
 *   userIndex/{uid}/{code} = true, stores/{code}/users/{uid}, stores/{code}/audit_logs/{auditId}.
 */
function planCreateStore(args) {
    const { code, uid, now, caller } = args;
    const info = buildStoreInfo(code, args.input, now);
    const copied = args.layout !== null && Object.keys(args.layout.zones).length > 0;
    const zones = copied ? args.layout.zones : { ...exports.DEFAULT_ZONES };
    const tables = copied ? args.layout.tables : { ...exports.DEFAULT_TABLES };
    const base = `stores/${code}`;
    const updates = {
        [`${base}/storeInfo`]: info,
        [`${base}/zones`]: zones,
        [`${base}/tables`]: tables,
        [`userIndex/${uid}/${code}`]: true,
        [`${base}/users/${uid}`]: buildOwnerProfileForStore(caller, uid, code, now),
        [`${base}/audit_logs/${args.auditId}`]: {
            action: exports.CREATE_STORE_ACTION,
            targetType: "STORE",
            targetId: code,
            details: `Tạo chi nhánh mới: ${info.storeName} (${code})`,
            timestamp: now,
            username: text(caller.username),
            userFullName: text(caller.fullName),
            userRole: text(caller.roleId),
        },
    };
    return { updates, zonesFrom: copied ? "copied" : "default" };
}
/**
 * Chủ gốc "toàn chuỗi": mọi uid (khác người tạo) là chủ gốc ĐANG HOẠT ĐỘNG ở TẤT CẢ chi nhánh người tạo thuộc về.
 * Dùng để chi nhánh mới tự có đủ các tài khoản chủ của chuỗi (không chỉ người bấm tạo).
 * usersByStore: mã chi nhánh -> (uid -> hồ sơ). Trả về uid -> hồ sơ lấy từ chi nhánh đầu tiên.
 */
function chainOwners(usersByStore, creatorUid) {
    const stores = Object.keys(usersByStore);
    if (stores.length === 0)
        return {};
    const isRoot = (u) => !!u && u.isRootOwner === true && u.isActive !== false;
    const first = usersByStore[stores[0]] || {};
    const out = {};
    for (const [uid, prof] of Object.entries(first)) {
        if (uid === creatorUid || !isRoot(prof))
            continue;
        if (stores.every((s) => isRoot((usersByStore[s] || {})[uid])))
            out[uid] = prof;
    }
    return out;
}
//# sourceMappingURL=createStoreLogic.js.map