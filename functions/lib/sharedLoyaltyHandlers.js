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
exports.mirrorLedgerToHistory = exports.linkBranchCustomer = exports.mirrorMemberToBranches = exports.setLoyaltyConfig = exports.listLoyaltyLedger = exports.getMemberLedger = exports.lookupMember = exports.adjustLoyaltyPoints = exports.refundLoyaltyPoints = exports.redeemLoyaltyPoints = exports.applyLoyaltyEarn = void 0;
exports.runOp = runOp;
/**
 * Cloud Functions cho điểm DÙNG CHUNG toàn chuỗi (xem sharedLoyalty.ts cho mô hình dữ liệu).
 *
 * Callable (client KHÔNG ghi loyalty_members / loyalty_ledger / loyalty_config - rules đóng hoàn toàn):
 *  - applyLoyaltyEarn      tích điểm theo hóa đơn PAID (số điểm tính phía máy chủ từ finalAmount)
 *  - redeemLoyaltyPoints   đổi điểm trước khi ghi hóa đơn (không đủ → failed-precondition, details.code = "insufficient")
 *  - refundLoyaltyPoints   hoàn điểm đã đổi khi ghi hóa đơn thất bại (chỉ khi hóa đơn chưa PAID)
 *  - adjustLoyaltyPoints   chỉnh tay (Quản lý/Chủ): ADD | SUB | SET + lý do
 *  - lookupMember          tra số dư dùng chung theo SĐT hoặc khách của chi nhánh (Thu ngân trở lên)
 *  - getMemberLedger       lịch sử điểm xuyên chi nhánh
 *  - listLoyaltyLedger     sổ cái xuyên khách (Quản lý/Chủ): lọc thời gian/loại/tìm kiếm + tổng + phân trang
 *  - setLoyaltyConfig      cấu hình chuỗi: tỷ lệ tích/đổi + mốc hạng (Chủ)
 * Trigger:
 *  - mirrorMemberToBranches  loyalty_members → cache điểm trên mọi node khách chi nhánh cùng SĐT
 *  - linkBranchCustomer      node khách chi nhánh → tạo/gắn bản ghi dùng chung (+ sửa cache lệch)
 *  - mirrorLedgerToHistory   loyalty_ledger → Firestore kmt_point_history
 */
const https_1 = require("firebase-functions/v2/https");
const database_1 = require("firebase-functions/v2/database");
const firestore_1 = require("firebase-admin/firestore");
const admin = __importStar(require("firebase-admin"));
const permissions_1 = require("./permissions");
const customerSync_1 = require("./customerSync");
const sharedLoyalty_1 = require("./sharedLoyalty");
const loyaltyLedgerQuery_1 = require("./loyaltyLedgerQuery");
if (!admin.apps.length) {
    admin.initializeApp({
        databaseURL: process.env.DATABASE_URL || "https://postramblao-default-rtdb.asia-southeast1.firebasedatabase.app",
    });
}
const db = admin.database();
const REGION = "asia-southeast1";
/** Xác thực người gọi: thành viên ĐANG HOẠT ĐỘNG của chi nhánh [storeCode] với vai trò đủ cấp */
async function authorize(request, level) {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    const data = (request.data || {});
    if (!(0, customerSync_1.isValidStoreCode)(data.storeCode))
        throw new https_1.HttpsError("invalid-argument", "Mã cửa hàng không hợp lệ.");
    const store = data.storeCode.trim().toUpperCase();
    const uid = request.auth.uid;
    const [callerSnap, indexSnap] = await Promise.all([db.ref(`stores/${store}/users/${uid}`).get(), db.ref(`userIndex/${uid}/${store}`).get()]);
    const caller = (callerSnap.exists() ? callerSnap.val() : null);
    const inIndex = indexSnap.val() === true;
    const active = !!caller && caller.isActive !== false && inIndex;
    let ok = false;
    if (active && caller) {
        if (level === "cashier")
            ok = (0, permissions_1.canCallerImportCustomer)(caller, inIndex);
        else if (level === "manager")
            ok = (0, permissions_1.isOwnerRole)(caller.roleId, caller.isRootOwner) || (0, permissions_1.isManagerRole)(caller.roleId);
        else
            ok = (0, permissions_1.isOwnerRole)(caller.roleId, caller.isRootOwner);
    }
    if (!ok || !caller) {
        throw new https_1.HttpsError("permission-denied", level === "cashier" ? "Bạn không có quyền thao tác điểm của chi nhánh này." : level === "manager" ? "Chỉ Quản lý/Chủ quán được chỉnh điểm." : "Chỉ Chủ quán được đổi cấu hình điểm.");
    }
    return { uid, store, caller, staff: caller.username || "unknown", data };
}
/** Xác định bản ghi điểm cần thao tác từ customerId (node khách chi nhánh) hoặc phone */
async function resolveTarget(store, data) {
    const customerId = data.customerId;
    if (customerId !== undefined && customerId !== null && customerId !== "") {
        if (!(0, customerSync_1.isValidCustomerKey)(customerId))
            throw new https_1.HttpsError("invalid-argument", "Mã khách hàng không hợp lệ.");
        const snap = await db.ref(`stores/${store}/customers/${customerId}`).get();
        if (!snap.exists())
            throw new https_1.HttpsError("not-found", "Không tìm thấy khách hàng ở chi nhánh này.");
        const c = snap.val();
        const rawPhone = c.so_dien_thoai ?? c.phone;
        const key = (0, sharedLoyalty_1.memberKeyFor)(rawPhone, store, customerId);
        return { memberKey: key, customerId, name: String(c.ho_ten ?? c.name ?? ""), phone: (0, sharedLoyalty_1.isLocalMemberKey)(key) ? "" : key };
    }
    const phoneKey = (0, sharedLoyalty_1.memberKeyFor)(data.phone, "-", "-");
    if ((0, sharedLoyalty_1.isLocalMemberKey)(phoneKey))
        throw new https_1.HttpsError("invalid-argument", "Cần mã khách hàng hoặc số điện thoại hợp lệ.");
    return { memberKey: phoneKey, name: "", phone: phoneKey };
}
function clean(o) {
    return JSON.parse(JSON.stringify(o));
}
function withBranch(cur, store, customerId) {
    const base = cur ? { ...cur } : {};
    if (customerId) {
        const branches = { ...(base.branches || {}) };
        branches[store] = { ...(branches[store] || {}), [customerId]: true };
        base.branches = branches;
    }
    return base;
}
/** Ghi sổ cái + chỉ mục theo tháng trong MỘT lần cập nhật nguyên tử (chỉ Admin SDK). */
async function writeLedger(memberKey, opId, entry, storeCode) {
    const at = Number(entry.at);
    const updates = { [`loyalty_ledger/${memberKey}/${opId}`]: entry };
    if (Number.isFinite(at))
        updates[(0, loyaltyLedgerQuery_1.indexPath)(memberKey, opId, at)] = { memberKey, opId, at, storeCode, type: String(entry.type ?? "") };
    await db.ref().update(updates);
}
/** Chạy 1 thao tác điểm bằng transaction trên loyalty_members/{key} và ghi sổ cái (chỉ tạo mới). */
/** Xuất cho test trên emulator (src/runOp.emulator.test.ts) */
async function runOp(target, req, extra) {
    const ref = db.ref(`loyalty_members/${target.memberKey}`);
    const canCreate = req.type === "earn" || req.type === "adjust" || req.type === "opening";
    const request = { ...req, name: req.name ?? target.name, phone: req.phone ?? target.phone };
    let last;
    // Admin SDK chạy callback lần đầu với cache rỗng (cur === null). Nếu thao tác tính ra "không đổi"/"không đủ điểm"
    // trên số dư 0 giả và trả undefined thì giao dịch bị hủy mà KHÔNG được thử lại với dữ liệu thật
    // (lỗi: đặt lại số dư về 0 báo "không đổi", trừ bớt báo "không đủ điểm"). Đọc trước số liệu thật làm hạt giống.
    const seed = (await ref.get()).val();
    const tx = await ref.transaction((cur) => {
        const effective = cur === null ? seed : cur;
        if (effective === null && !canCreate) {
            // Thật sự chưa có bản ghi: ghi null để SDK chạy lại với dữ liệu thật
            last = undefined;
            return null;
        }
        const curMap = effective && typeof effective === "object" ? effective : null;
        const r = (0, sharedLoyalty_1.applyOp)((0, sharedLoyalty_1.readMember)(curMap), request);
        last = r;
        if (r.status !== "applied" || !r.member)
            return undefined;
        return clean({ ...withBranch(curMap, req.storeCode, target.customerId), ...r.member });
    });
    const res = last;
    if (!res || (tx.committed && !tx.snapshot.exists())) {
        return { status: req.type === "refund" ? "nothingToRefund" : "insufficient", applied: 0, before: 0, after: 0, totalAfter: 0 };
    }
    if (res.status === "applied" && !tx.committed)
        throw new https_1.HttpsError("aborted", "Điểm của khách vừa thay đổi. Vui lòng thử lại.");
    const ledgerRef = db.ref(`loyalty_ledger/${target.memberKey}/${req.opId}`);
    if (res.status === "applied") {
        const entry = clean((0, sharedLoyalty_1.buildLedgerEntry)(request, res, { ...extra, customerId: target.customerId }));
        await writeLedger(target.memberKey, req.opId, entry, req.storeCode)
            .catch((e) => console.error("loyalty_ledger write failed", target.memberKey, req.opId, e));
    }
    else if (res.status === "alreadyApplied") {
        // Lần trước commit số dư nhưng chưa kịp ghi sổ cái → bù bản ghi tối thiểu
        const snap = await ledgerRef.get();
        if (!snap.exists()) {
            await writeLedger(target.memberKey, req.opId, clean({ type: req.type, points: req.type === "redeem" ? -res.applied : res.applied, balanceAfter: res.after, storeCode: req.storeCode, staff: extra.staff, at: req.now, billId: extra.billId, healed: true }), req.storeCode)
                .catch(() => undefined);
        }
    }
    return res;
}
function resultPayload(r, memberKey) {
    return {
        success: r.status === "applied" || r.status === "alreadyApplied",
        status: r.status,
        memberKey,
        applied: r.applied,
        before: r.before,
        after: r.after,
        points: r.after,
        totalPoints: r.totalAfter,
    };
}
function toInt(v) {
    return typeof v === "number" && Number.isInteger(v) ? v : NaN;
}
function requireBillId(v) {
    if (typeof v !== "string" || !v.trim() || v.length > 128)
        throw new https_1.HttpsError("invalid-argument", "Thiếu hoặc sai mã hóa đơn.");
    return v.trim();
}
async function auditLog(store, caller, action, targetId, details) {
    const now = Date.now();
    await db
        .ref(`stores/${store}/audit_logs/LOG_${now}_${Math.random().toString(36).substring(2, 7)}`)
        .set({
        timestamp: now,
        action,
        username: caller.username || "unknown",
        userFullName: caller.fullName || "",
        userRole: caller.roleId || "",
        targetType: "CUSTOMER",
        targetId,
        details,
    })
        .catch(() => undefined);
}
// ---------------------------------------------------------------------------------------------
exports.applyLoyaltyEarn = (0, https_1.onCall)({ region: REGION }, async (request) => {
    const ctx = await authorize(request, "cashier");
    const billId = requireBillId(ctx.data.billId);
    const billSnap = await db.ref(`stores/${ctx.store}/bills/${billId}`).get();
    if (!billSnap.exists())
        throw new https_1.HttpsError("failed-precondition", "Hóa đơn chưa được đồng bộ lên máy chủ, thử lại sau.");
    const bill = billSnap.val();
    if (bill.status !== "PAID")
        throw new https_1.HttpsError("failed-precondition", "Chỉ tích điểm cho hóa đơn đã thanh toán.");
    const customerId = typeof bill.customerId === "string" ? bill.customerId.trim() : "";
    if (!customerId)
        return { success: true, status: "applied", applied: 0, skipped: "no-customer" };
    // Khuyến mãi khóa tích điểm (vd. KM sinh nhật): đơn vẫn gắn khách nhưng không cộng điểm
    const campaignIds = (0, sharedLoyalty_1.discountCampaignIds)(bill.discounts);
    if (campaignIds.length > 0) {
        const flags = {};
        await Promise.all(campaignIds.map(async (id) => {
            flags[id] = (await db.ref(`stores/${ctx.store}/campaigns/${id}/blockPoints`).get()).val() === true;
        }));
        if ((0, sharedLoyalty_1.billBlocksPoints)(bill.discounts, flags)) {
            return { success: true, status: "applied", applied: 0, skipped: "campaign-blocks-points" };
        }
    }
    const [cfgSnap, infoSnap] = await Promise.all([db.ref("loyalty_config").get(), db.ref(`stores/${ctx.store}/storeInfo`).get()]);
    const rates = (0, sharedLoyalty_1.resolveRates)(cfgSnap.val(), infoSnap.val());
    const finalAmount = typeof bill.finalAmount === "number" ? bill.finalAmount : 0;
    const points = (0, sharedLoyalty_1.computeEarnPoints)(finalAmount, rates.earnRate, rates.redeemRate);
    const target = await resolveTarget(ctx.store, { customerId });
    if (points <= 0)
        return { success: true, status: "applied", applied: 0, memberKey: target.memberKey };
    const r = await runOp(target, { type: "earn", points, opId: (0, sharedLoyalty_1.billOpId)(billId, "earn"), storeCode: ctx.store, now: Date.now() }, { billId, billCode: typeof bill.billCode === "string" ? bill.billCode : undefined, staff: ctx.staff });
    return resultPayload(r, target.memberKey);
});
exports.redeemLoyaltyPoints = (0, https_1.onCall)({ region: REGION }, async (request) => {
    const ctx = await authorize(request, "cashier");
    const billId = requireBillId(ctx.data.billId);
    const points = toInt(ctx.data.points);
    if (!Number.isInteger(points) || points <= 0 || points > sharedLoyalty_1.MAX_POINTS_PER_OP)
        throw new https_1.HttpsError("invalid-argument", "Số điểm đổi không hợp lệ.");
    const target = await resolveTarget(ctx.store, ctx.data);
    if (!target.customerId)
        throw new https_1.HttpsError("invalid-argument", "Thiếu mã khách hàng.");
    const r = await runOp(target, { type: "redeem", points, opId: (0, sharedLoyalty_1.billOpId)(billId, "redeem"), storeCode: ctx.store, now: Date.now() }, { billId, billCode: typeof ctx.data.billCode === "string" ? ctx.data.billCode : undefined, staff: ctx.staff });
    if (r.status === "insufficient") {
        throw new https_1.HttpsError("failed-precondition", `Khách chỉ còn ${r.before} điểm, không đủ ${points} điểm.`, { code: "insufficient", balance: r.before, requested: points });
    }
    if (r.status === "invalid")
        throw new https_1.HttpsError("invalid-argument", "Số điểm đổi không hợp lệ.");
    return resultPayload(r, target.memberKey);
});
exports.refundLoyaltyPoints = (0, https_1.onCall)({ region: REGION }, async (request) => {
    const ctx = await authorize(request, "cashier");
    const billId = requireBillId(ctx.data.billId);
    const billSnap = await db.ref(`stores/${ctx.store}/bills/${billId}/status`).get();
    if (billSnap.val() === "PAID")
        throw new https_1.HttpsError("failed-precondition", "Hóa đơn đã thanh toán, không hoàn điểm.");
    const target = await resolveTarget(ctx.store, ctx.data);
    const redeemSnap = await db.ref(`loyalty_members/${target.memberKey}/ops/${(0, sharedLoyalty_1.billOpId)(billId, "redeem")}/p`).get();
    const redeemed = typeof redeemSnap.val() === "number" ? redeemSnap.val() : 0;
    const asked = toInt(ctx.data.points);
    const points = Number.isInteger(asked) && asked > 0 ? Math.min(asked, redeemed || asked) : redeemed;
    if (points <= 0)
        return { success: true, status: "nothingToRefund", applied: 0, memberKey: target.memberKey };
    const r = await runOp(target, { type: "refund", points, opId: (0, sharedLoyalty_1.billOpId)(billId, "refund"), storeCode: ctx.store, now: Date.now() }, { billId, staff: ctx.staff });
    return resultPayload(r, target.memberKey);
});
exports.adjustLoyaltyPoints = (0, https_1.onCall)({ region: REGION }, async (request) => {
    const ctx = await authorize(request, "manager");
    const mode = String(ctx.data.mode ?? "").toUpperCase();
    const n = toInt(ctx.data.points);
    if (!["ADD", "SUB", "SET"].includes(mode) || !Number.isInteger(n) || n < 0 || n > sharedLoyalty_1.MAX_POINTS_PER_OP) {
        throw new https_1.HttpsError("invalid-argument", "Chế độ (ADD/SUB/SET) hoặc số điểm không hợp lệ.");
    }
    if (mode !== "SET" && n === 0)
        throw new https_1.HttpsError("invalid-argument", "Số điểm phải lớn hơn 0.");
    const reason = typeof ctx.data.reason === "string" ? ctx.data.reason.trim() : "";
    if (reason.length < 3 || reason.length > 300)
        throw new https_1.HttpsError("invalid-argument", "Cần ghi lý do chỉnh điểm (3-300 ký tự).");
    const target = await resolveTarget(ctx.store, ctx.data);
    const clientOp = typeof ctx.data.opId === "string" && /^[A-Za-z0-9_-]{6,64}$/.test(ctx.data.opId) ? ctx.data.opId : `${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const req = {
        type: "adjust",
        points: mode === "SUB" ? -n : n,
        setTo: mode === "SET" ? n : undefined,
        opId: `adj_${clientOp}`,
        storeCode: ctx.store,
        now: Date.now(),
    };
    const r = await runOp(target, req, { staff: ctx.staff, note: reason });
    if (r.status === "insufficient")
        throw new https_1.HttpsError("failed-precondition", `Khách chỉ còn ${r.before} điểm, không trừ được ${n}.`, { code: "insufficient", balance: r.before });
    if (r.status === "invalid")
        throw new https_1.HttpsError("invalid-argument", "Số điểm sau chỉnh không đổi hoặc không hợp lệ.");
    if (r.status === "applied") {
        await auditLog(ctx.store, ctx.caller, "LOYALTY_ADJUST", target.customerId ?? target.memberKey, `Chỉnh điểm ${mode} ${n}: ${r.before} → ${r.after} (${reason})`);
    }
    return resultPayload(r, target.memberKey);
});
exports.lookupMember = (0, https_1.onCall)({ region: REGION }, async (request) => {
    const ctx = await authorize(request, "cashier");
    const target = await resolveTarget(ctx.store, ctx.data).catch((e) => {
        if (e instanceof https_1.HttpsError && e.code === "not-found")
            return null;
        throw e;
    });
    if (!target)
        return { found: false };
    const snap = await db.ref(`loyalty_members/${target.memberKey}`).get();
    const m = (0, sharedLoyalty_1.readMember)(snap.val());
    if (!m)
        return { found: false, memberKey: target.memberKey };
    const branches = (snap.val().branches || {});
    return {
        found: true,
        memberKey: target.memberKey,
        local: (0, sharedLoyalty_1.isLocalMemberKey)(target.memberKey),
        name: m.name,
        phone: m.phone,
        points: m.points,
        totalPoints: m.totalPoints,
        lastStoreCode: m.lastStoreCode ?? "",
        joinedAt: m.joinedAt,
        branchCount: Object.keys(branches).length,
    };
});
exports.getMemberLedger = (0, https_1.onCall)({ region: REGION }, async (request) => {
    const ctx = await authorize(request, "cashier");
    const target = await resolveTarget(ctx.store, ctx.data);
    const limit = Math.min(Math.max(toInt(ctx.data.limit) || 100, 1), 300);
    const snap = await db.ref(`loyalty_ledger/${target.memberKey}`).get();
    const entries = [];
    snap.forEach((c) => {
        entries.push({ id: c.key, ...c.val() });
    });
    entries.sort((a, b) => Number(b.at ?? 0) - Number(a.at ?? 0));
    return { memberKey: target.memberKey, entries: entries.slice(0, limit) };
});
// ---------------------------------------------------------------------------------------------
// listLoyaltyLedger: sổ cái xuyên khách cho báo cáo Web
/** Các chi nhánh mà người gọi là Quản lý/Chủ ĐANG HOẠT ĐỘNG (userIndex + vai trò từng quán). */
async function managedStores(uid) {
    const idx = await db.ref(`userIndex/${uid}`).get();
    const codes = Object.entries((idx.val() || {})).filter(([, v]) => v === true).map(([k]) => k);
    const profiles = await Promise.all(codes.map((c) => db.ref(`stores/${c}/users/${uid}`).get()));
    return codes.filter((_, i) => {
        const u = profiles[i].exists() ? profiles[i].val() : null;
        return !!u && u.isActive !== false && ((0, permissions_1.isOwnerRole)(u.roleId, u.isRootOwner) || (0, permissions_1.isManagerRole)(u.roleId));
    });
}
const RANGE_TOO_LARGE = `Khoảng dữ liệu quá lớn (hơn ${loyaltyLedgerQuery_1.MAX_LEDGER_ENTRIES.toLocaleString("en-US")} giao dịch). Vui lòng thu hẹp khoảng thời gian hoặc bộ lọc.`;
/** Chưa có chỉ mục đầy đủ: đọc tuần tự sổ cái theo từng đợt khách, gom bản ghi + (backfill) ghi chỉ mục. */
async function scanLedger() {
    const raw = new Map();
    const index = [];
    let last = null;
    for (;;) {
        let q = db.ref("loyalty_ledger").orderByKey().limitToFirst(100);
        if (last !== null)
            q = db.ref("loyalty_ledger").orderByKey().startAt(last).limitToFirst(101);
        const snap = await q.get();
        let n = 0;
        snap.forEach((m) => {
            if (m.key === last)
                return;
            n += 1;
            last = m.key;
            m.forEach((e) => {
                const v = e.val();
                const at = Number(v?.at);
                if (!v || !Number.isFinite(at))
                    return;
                raw.set(`${m.key}~${e.key}`, v);
                index.push({ memberKey: m.key, opId: e.key, at, storeCode: String(v.storeCode ?? ""), type: String(v.type ?? "") });
            });
        });
        if (index.length > loyaltyLedgerQuery_1.MAX_LEDGER_ENTRIES * 2)
            throw new https_1.HttpsError("failed-precondition", RANGE_TOO_LARGE);
        if (n === 0)
            break;
    }
    return { raw, index };
}
/** Ghi chỉ mục cho các bản ghi cũ rồi đánh dấu đầy đủ (best effort, idempotent). */
async function backfillIndex(index) {
    for (let i = 0; i < index.length; i += 400) {
        const updates = {};
        for (const e of index.slice(i, i + 400))
            updates[(0, loyaltyLedgerQuery_1.indexPath)(e.memberKey, e.opId, e.at)] = e;
        await db.ref().update(updates);
    }
    await db.ref(`${loyaltyLedgerQuery_1.LEDGER_INDEX_ROOT}/${loyaltyLedgerQuery_1.LEDGER_INDEX_META}`).set({ complete: true, at: Date.now(), count: index.length });
}
async function readIndex(from, to) {
    const out = [];
    const addMonth = (month) => {
        month.forEach((e) => {
            const v = e.val();
            if (v && typeof v.at === "number")
                out.push(v);
        });
    };
    if (typeof from === "number") {
        const months = (0, loyaltyLedgerQuery_1.monthsBetween)(from, typeof to === "number" ? to : Date.now());
        const snaps = await Promise.all(months.map((m) => db.ref(`${loyaltyLedgerQuery_1.LEDGER_INDEX_ROOT}/${m}`).get()));
        snaps.forEach(addMonth);
    }
    else {
        const all = await db.ref(loyaltyLedgerQuery_1.LEDGER_INDEX_ROOT).get();
        all.forEach((m) => {
            if (m.key !== loyaltyLedgerQuery_1.LEDGER_INDEX_META)
                addMonth(m);
        });
    }
    return out;
}
exports.listLoyaltyLedger = (0, https_1.onCall)({ region: REGION, timeoutSeconds: 120, memory: "512MiB" }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    const d = (request.data || {});
    const uid = request.auth.uid;
    const reqStore = typeof d.storeCode === "string" ? d.storeCode.trim().toUpperCase() : "";
    if (!reqStore)
        throw new https_1.HttpsError("invalid-argument", "Thiếu mã cửa hàng.");
    let stores;
    if (reqStore === "ALL") {
        const mine = await managedStores(uid);
        if (mine.length === 0)
            throw new https_1.HttpsError("permission-denied", "Chỉ Quản lý/Chủ quán được xem lịch sử điểm.");
        stores = new Set(mine);
    }
    else {
        await authorize(request, "manager");
        stores = new Set([reqStore]);
    }
    const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
    const from = num(d.from);
    const to = num(d.to);
    const types = Array.isArray(d.types) ? d.types.filter((t) => typeof t === "string").slice(0, 10) : [];
    const search = typeof d.search === "string" ? d.search.slice(0, 100) : "";
    const cursor = typeof d.cursor === "string" && d.cursor ? d.cursor : undefined;
    const limit = (0, loyaltyLedgerQuery_1.clampLimit)(d.limit);
    const customerId = typeof d.customerId === "string" && d.customerId.trim() ? d.customerId.trim() : undefined;
    const filter = { stores, from, to, types, search, customerId };
    // Lấy danh sách ứng viên: dùng chỉ mục khi đã đầy đủ, ngược lại quét sổ cái (và backfill chỉ mục)
    const meta = await db.ref(`${loyaltyLedgerQuery_1.LEDGER_INDEX_ROOT}/${loyaltyLedgerQuery_1.LEDGER_INDEX_META}/complete`).get();
    let raw = null;
    let candidates;
    if (meta.val() === true) {
        candidates = (0, loyaltyLedgerQuery_1.filterIndex)(await readIndex(from, to), filter);
    }
    else {
        const scanned = await scanLedger();
        raw = scanned.raw;
        candidates = (0, loyaltyLedgerQuery_1.filterIndex)(scanned.index, filter);
        await backfillIndex(scanned.index).catch((e) => console.error("backfill loyalty_ledger_index failed", e));
    }
    if (candidates.length > loyaltyLedgerQuery_1.MAX_LEDGER_ENTRIES)
        throw new https_1.HttpsError("failed-precondition", RANGE_TOO_LARGE);
    // Thông tin khách (tên/SĐT) + bản ghi sổ cái đầy đủ
    const memberKeys = [...new Set(candidates.map((c) => c.memberKey))];
    const members = new Map();
    for (let i = 0; i < memberKeys.length; i += 50) {
        const part = memberKeys.slice(i, i + 50);
        const snaps = await Promise.all(part.map((k) => db.ref(`loyalty_members/${k}`).get()));
        part.forEach((k, j) => members.set(k, snaps[j].exists() ? snaps[j].val() : null));
    }
    const rows = [];
    for (let i = 0; i < candidates.length; i += 100) {
        const part = candidates.slice(i, i + 100);
        const vals = raw
            ? part.map((c) => raw.get(`${c.memberKey}~${c.opId}`) ?? null)
            : (await Promise.all(part.map((c) => db.ref(`loyalty_ledger/${c.memberKey}/${c.opId}`).get()))).map((s) => (s.exists() ? s.val() : null));
        part.forEach((c, j) => {
            const r = (0, loyaltyLedgerQuery_1.toRow)(c.memberKey, c.opId, vals[j], members.get(c.memberKey) ?? null);
            if (r)
                rows.push(r);
        });
    }
    const filtered = (0, loyaltyLedgerQuery_1.sortRows)((0, loyaltyLedgerQuery_1.filterRows)(rows, filter));
    const pg = (0, loyaltyLedgerQuery_1.paginate)(filtered, cursor, limit);
    if (!pg)
        throw new https_1.HttpsError("invalid-argument", "Con trỏ phân trang không hợp lệ.");
    return { entries: pg.page, nextCursor: pg.nextCursor, totals: (0, loyaltyLedgerQuery_1.computeTotals)(filtered) };
});
exports.setLoyaltyConfig = (0, https_1.onCall)({ region: REGION }, async (request) => {
    const ctx = await authorize(request, "owner");
    const d = ctx.data;
    const patch = {};
    if (d.pointEarnRate !== undefined) {
        const v = d.pointEarnRate;
        if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > 100)
            throw new https_1.HttpsError("invalid-argument", "Tỷ lệ tích điểm phải trong khoảng 0-100 (%).");
        patch.pointEarnRate = v;
    }
    if (d.pointRedeemRate !== undefined) {
        const v = d.pointRedeemRate;
        if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > 1_000_000)
            throw new https_1.HttpsError("invalid-argument", "Giá trị 1 điểm (đ) phải là số nguyên 1-1.000.000.");
        patch.pointRedeemRate = v;
    }
    if (d.loyaltyTiers !== undefined) {
        const arr = d.loyaltyTiers;
        if (!Array.isArray(arr) || arr.length > 20)
            throw new https_1.HttpsError("invalid-argument", "Danh sách hạng không hợp lệ (tối đa 20).");
        const tiers = arr.map((t) => {
            const o = (t || {});
            const name = typeof o.name === "string" ? o.name.trim() : "";
            const min = o.minPoints;
            if (!name || name.length > 40 || typeof min !== "number" || !Number.isInteger(min) || min < 0)
                throw new https_1.HttpsError("invalid-argument", "Mỗi hạng cần tên và ngưỡng điểm nguyên >= 0.");
            return { name, minPoints: min };
        });
        patch.loyaltyTiers = tiers;
    }
    if (Object.keys(patch).length === 0)
        throw new https_1.HttpsError("invalid-argument", "Không có cấu hình nào để lưu.");
    patch.updatedAt = Date.now();
    patch.updatedBy = ctx.staff;
    await db.ref("loyalty_config").update(patch);
    await auditLog(ctx.store, ctx.caller, "LOYALTY_CONFIG", "loyalty_config", `Cập nhật cấu hình điểm toàn chuỗi: ${Object.keys(patch).filter((k) => !k.startsWith("updated")).join(", ")}`);
    return { success: true };
});
// ---------------------------------------------------------------------------------------------
// Triggers
function branchRefs(member) {
    const out = [];
    const b = (member?.branches || {});
    for (const [storeCode, customers] of Object.entries(b)) {
        if (!customers || typeof customers !== "object")
            continue;
        for (const customerId of Object.keys(customers))
            out.push({ storeCode, customerId });
    }
    return out;
}
/** Cache điểm trên node khách chi nhánh luôn bằng bản ghi dùng chung */
exports.mirrorMemberToBranches = (0, database_1.onValueWritten)({ ref: "/loyalty_members/{memberKey}", region: REGION }, async (event) => {
    if (!event.data.after.exists())
        return;
    const after = event.data.after.val();
    const before = (event.data.before.exists() ? event.data.before.val() : null);
    const m = (0, sharedLoyalty_1.readMember)(after);
    if (!m)
        return;
    const refs = branchRefs(after);
    const unchanged = before && (0, sharedLoyalty_1.readMember)(before)?.points === m.points && (0, sharedLoyalty_1.readMember)(before)?.totalPoints === m.totalPoints && branchRefs(before).length === refs.length;
    if (unchanged || refs.length === 0)
        return;
    const nodes = await Promise.all(refs.map(async (r) => {
        const s = await db.ref(`stores/${r.storeCode}/customers/${r.customerId}`).get();
        return { ...r, node: s.exists() ? s.val() : null };
    }));
    const updates = (0, sharedLoyalty_1.planBranchCacheUpdates)(m, nodes);
    if (Object.keys(updates).length)
        await db.ref().update(updates);
});
/** Node khách chi nhánh ↔ bản ghi dùng chung: tạo/gắn, gộp khi khách thêm SĐT, sửa cache lệch */
exports.linkBranchCustomer = (0, database_1.onValueWritten)({ ref: "/stores/{storeCode}/customers/{customerId}", region: REGION }, async (event) => {
    const { storeCode, customerId } = event.params;
    if (!(0, customerSync_1.isValidCustomerKey)(customerId))
        return;
    const before = (event.data.before.exists() ? event.data.before.val() : null);
    const after = (event.data.after.exists() ? event.data.after.val() : null);
    const keyOf = (c) => (0, sharedLoyalty_1.memberKeyFor)(c.so_dien_thoai ?? c.phone, storeCode, customerId);
    const oldKey = before ? keyOf(before) : null;
    if (!after) {
        // Xóa khách ở chi nhánh: chỉ gỡ liên kết, số điểm chung được giữ nguyên
        if (oldKey)
            await db.ref(`loyalty_members/${oldKey}/branches/${storeCode}/${customerId}`).remove().catch(() => undefined);
        // Nếu là chi nhánh thuộc chuỗi 4 cửa hàng Trạm: đồng bộ xóa node khách trên các chi nhánh Trạm còn lại
        if ((0, sharedLoyalty_1.isTramChainStore)(storeCode)) {
            const otherStores = sharedLoyalty_1.TRAM_CHAIN_STORES.filter((s) => s !== storeCode);
            const delUpdates = {};
            for (const other of otherStores) {
                delUpdates[`stores/${other}/customers/${customerId}`] = null;
                if (oldKey) {
                    delUpdates[`loyalty_members/${oldKey}/branches/${other}/${customerId}`] = null;
                }
            }
            if (Object.keys(delUpdates).length)
                await db.ref().update(delUpdates).catch(() => undefined);
        }
        return;
    }
    const key = keyOf(after);
    const name = String(after.ho_ten ?? after.name ?? "");
    const now = Date.now();
    const seedPts = (0, customerSync_1.readCurrentPoints)(after);
    const seedTotal = Math.max((0, customerSync_1.readTotalPoints)(after), seedPts);
    const created = typeof after.createdAt === "number" ? after.createdAt : now;
    const mref = db.ref(`loyalty_members/${key}`);
    const tx = await mref.transaction((cur) => {
        if (cur === null) {
            // Lần đầu thấy SĐT này: khởi tạo từ số dư đang có trên node (di trú/nhập cũ); node mới do Thu ngân tạo luôn 0
            const m = { name, phone: (0, sharedLoyalty_1.isLocalMemberKey)(key) ? "" : key, points: seedPts, totalPoints: seedTotal, joinedAt: created, updatedAt: now, lastStoreCode: storeCode };
            return clean({ ...m, branches: { [storeCode]: { [customerId]: true } } });
        }
        const c = cur;
        const b = (c.branches || {});
        if (b[storeCode]?.[customerId] === true && (c.name || !name))
            return undefined; // đã gắn, không cần ghi
        return clean({ ...withBranch(c, storeCode, customerId), name: c.name || name });
    });
    const memberVal = (tx.snapshot.val() || null);
    const m = (0, sharedLoyalty_1.readMember)(memberVal);
    // Khách vừa thêm/đổi SĐT: số dư của bản ghi cũ (cục bộ L_...) được chuyển sang bản ghi theo SĐT
    if (oldKey && oldKey !== key && (0, sharedLoyalty_1.isLocalMemberKey)(oldKey)) {
        const oldSnap = await db.ref(`loyalty_members/${oldKey}`).get();
        const old = (0, sharedLoyalty_1.readMember)(oldSnap.val());
        if (old && old.points > 0) {
            const target = { memberKey: key, customerId, name, phone: key };
            const moved = await runOp(target, { type: "opening", points: old.points, opId: `merge_${(0, sharedLoyalty_1.sanitizeKey)(oldKey)}`, storeCode, now: Date.now() }, { staff: "system", note: `Gộp điểm từ ${oldKey}` });
            if (moved.status === "applied" || moved.status === "alreadyApplied") {
                await runOp({ memberKey: oldKey, name: old.name, phone: "" }, { type: "adjust", points: -old.points, opId: `merge_out_${(0, sharedLoyalty_1.sanitizeKey)(key)}`, storeCode, now: Date.now() }, { staff: "system", note: `Chuyển điểm sang ${key}` });
            }
        }
        await db.ref(`loyalty_members/${oldKey}/branches/${storeCode}/${customerId}`).remove().catch(() => undefined);
    }
    else if (oldKey && oldKey !== key) {
        await db.ref(`loyalty_members/${oldKey}/branches/${storeCode}/${customerId}`).remove().catch(() => undefined);
    }
    if (m) {
        const fresh = await db.ref(`loyalty_members/${key}`).get();
        const fm = (0, sharedLoyalty_1.readMember)(fresh.val()) ?? m;
        const updates = (0, sharedLoyalty_1.planBranchCacheUpdates)(fm, [{ storeCode, customerId, node: after }]);
        if (Object.keys(updates).length)
            await db.ref().update(updates);
    }
    // Nếu là cửa hàng thuộc chuỗi 4 chi nhánh Trạm: đồng bộ sang toàn bộ chi nhánh Trạm còn lại
    if ((0, sharedLoyalty_1.isTramChainStore)(storeCode)) {
        const otherStores = sharedLoyalty_1.TRAM_CHAIN_STORES.filter((s) => s !== storeCode);
        const chainUpdates = {};
        for (const other of otherStores) {
            const otherSnap = await db.ref(`stores/${other}/customers/${customerId}`).get();
            const existing = otherSnap.val();
            const needsSync = !existing ||
                existing.ho_ten !== after.ho_ten ||
                existing.so_dien_thoai !== after.so_dien_thoai ||
                existing.ngay_sinh !== after.ngay_sinh ||
                existing.gioi_tinh !== after.gioi_tinh ||
                existing.name !== after.name ||
                existing.phone !== after.phone ||
                existing.birthday !== after.birthday ||
                existing.gender !== after.gender;
            if (needsSync) {
                chainUpdates[`stores/${other}/customers/${customerId}`] = after;
                chainUpdates[`loyalty_members/${key}/branches/${other}/${customerId}`] = true;
            }
        }
        if (Object.keys(chainUpdates).length) {
            await db.ref().update(chainUpdates).catch(() => undefined);
        }
    }
});
/** Sổ cái chung → lịch sử điểm Firestore kmt_point_history (doc id cố định, chạy lại không trùng) */
exports.mirrorLedgerToHistory = (0, database_1.onValueCreated)({ ref: "/loyalty_ledger/{memberKey}/{opId}", region: REGION }, async (event) => {
    const { memberKey, opId } = event.params;
    const hist = (0, sharedLoyalty_1.buildLedgerHistory)(memberKey, opId, (event.data.val() || {}));
    if (!hist)
        return;
    await admin
        .firestore()
        .collection("kmt_point_history")
        .doc(hist.docId)
        .set({ ...hist.data, ngay_tich: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
});
//# sourceMappingURL=sharedLoyaltyHandlers.js.map