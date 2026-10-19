"use strict";
/**
 * Truy vấn sổ cái điểm dùng chung xuyên khách hàng (callable listLoyaltyLedger) - phần logic THUẦN.
 *
 * Sổ cái gốc:  loyalty_ledger/{memberKey}/{opId}  (khóa theo khách → không truy vấn khoảng thời gian được).
 * Chỉ mục:     loyalty_ledger_index/{yyyyMM}/{memberKey}~{opId} = { memberKey, opId, at, storeCode, type }
 *              (chỉ Admin SDK ghi/đọc; tháng tính theo giờ Việt Nam UTC+7).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.MAX_LIMIT = exports.DEFAULT_LIMIT = exports.MAX_LEDGER_ENTRIES = exports.LEDGER_INDEX_META = exports.LEDGER_INDEX_ROOT = void 0;
exports.monthKey = monthKey;
exports.monthsBetween = monthsBetween;
exports.indexKey = indexKey;
exports.indexPath = indexPath;
exports.fold = fold;
exports.filterIndex = filterIndex;
exports.filterRows = filterRows;
exports.computeTotals = computeTotals;
exports.sortRows = sortRows;
exports.encodeCursor = encodeCursor;
exports.clampLimit = clampLimit;
exports.paginate = paginate;
exports.toRow = toRow;
exports.LEDGER_INDEX_ROOT = "loyalty_ledger_index";
/** Nút đánh dấu chỉ mục đã đầy đủ (đã backfill toàn bộ sổ cái cũ). */
exports.LEDGER_INDEX_META = "_meta";
exports.MAX_LEDGER_ENTRIES = 20000;
exports.DEFAULT_LIMIT = 200;
exports.MAX_LIMIT = 500;
const VN_OFFSET_MS = 7 * 3600 * 1000;
/** Khóa tháng yyyyMM theo giờ Việt Nam */
function monthKey(at) {
    const d = new Date(at + VN_OFFSET_MS);
    return `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}
/** Các tháng (yyyyMM) chạm khoảng [from, to]; cả hai bắt buộc hữu hạn. */
function monthsBetween(from, to) {
    const out = [];
    if (!(from <= to))
        return out;
    const s = new Date(from + VN_OFFSET_MS);
    const e = new Date(to + VN_OFFSET_MS);
    let y = s.getUTCFullYear();
    let m = s.getUTCMonth();
    const ey = e.getUTCFullYear();
    const em = e.getUTCMonth();
    while (y < ey || (y === ey && m <= em)) {
        out.push(`${y}${String(m + 1).padStart(2, "0")}`);
        m += 1;
        if (m > 11) {
            m = 0;
            y += 1;
        }
        if (out.length > 600)
            break;
    }
    return out;
}
function indexKey(memberKey, opId) {
    return `${memberKey}~${opId}`;
}
function indexPath(memberKey, opId, at) {
    return `${exports.LEDGER_INDEX_ROOT}/${monthKey(at)}/${indexKey(memberKey, opId)}`;
}
/** Bỏ dấu tiếng Việt + hạ chữ thường để tìm không phân biệt dấu */
function fold(s) {
    return String(s ?? "")
        .normalize("NFD")
        .replace(/[̀-ͯ]/g, "")
        .replace(/đ/gi, "d")
        .toLowerCase()
        .trim();
}
function inRange(at, f) {
    if (typeof f.from === "number" && at < f.from)
        return false;
    if (typeof f.to === "number" && at > f.to)
        return false;
    return true;
}
/** Lọc ở mức chỉ mục (chưa cần đọc bản ghi): chi nhánh, thời gian, loại. */
function filterIndex(entries, f) {
    const types = f.types && f.types.length ? new Set(f.types) : null;
    return entries.filter((e) => {
        if (f.stores && !f.stores.has(e.storeCode))
            return false;
        if (!inRange(e.at, f))
            return false;
        if (types && !types.has(e.type))
            return false;
        return true;
    });
}
/** Lọc đầy đủ (thêm tìm kiếm theo tên/SĐT/mã HĐ/ghi chú/người thực hiện, không phân biệt dấu). */
function filterRows(rows, f) {
    const types = f.types && f.types.length ? new Set(f.types) : null;
    const q = fold(f.search);
    return rows.filter((r) => {
        if (f.stores && !f.stores.has(r.storeCode))
            return false;
        if (!inRange(r.at, f))
            return false;
        if (types && !types.has(r.type))
            return false;
        if (f.customerId && r.customerId !== f.customerId)
            return false;
        if (q) {
            const hay = fold(`${r.memberName} ${r.memberPhone} ${r.memberKey} ${r.billCode} ${r.billId} ${r.note} ${r.staff}`);
            if (!hay.includes(q))
                return false;
        }
        return true;
    });
}
function computeTotals(rows) {
    const t = { earned: 0, redeemed: 0, manual: 0, count: rows.length };
    for (const r of rows) {
        if (r.type === "earn" || r.type === "refund")
            t.earned += r.points;
        else if (r.type === "redeem")
            t.redeemed += Math.abs(r.points);
        else
            t.manual += r.points;
    }
    return t;
}
/** Mới nhất trước; cùng thời điểm thì theo khóa ổn định để phân trang không lặp/sót. */
function sortRows(rows) {
    return [...rows].sort((a, b) => b.at - a.at || (a.memberKey + a.opId < b.memberKey + b.opId ? 1 : -1));
}
const rowId = (r) => `${r.memberKey}~${r.opId}`;
function encodeCursor(r) {
    return `${r.at}|${rowId(r)}`;
}
function clampLimit(v) {
    const n = typeof v === "number" && Number.isFinite(v) ? Math.floor(v) : exports.DEFAULT_LIMIT;
    return Math.min(Math.max(n, 1), exports.MAX_LIMIT);
}
/** Phân trang trên danh sách ĐÃ sắp xếp mới → cũ. Cursor hỏng → null (caller báo lỗi). */
function paginate(sorted, cursor, limit) {
    let start = 0;
    if (cursor) {
        const i = cursor.indexOf("|");
        const at = Number(cursor.slice(0, i));
        if (i < 1 || !Number.isFinite(at))
            return null;
        const id = cursor.slice(i + 1);
        // Vị trí đầu tiên đứng SAU cursor trong thứ tự sắp xếp
        start = sorted.findIndex((r) => r.at < at || (r.at === at && rowId(r) < id));
        if (start < 0)
            start = sorted.length;
    }
    const page = sorted.slice(start, start + limit);
    const hasMore = start + limit < sorted.length;
    return { page, nextCursor: hasMore && page.length ? encodeCursor(page[page.length - 1]) : undefined };
}
/** Ghép bản ghi sổ cái thô + thông tin khách thành dòng trả về (an toàn với dữ liệu thiếu trường). */
function toRow(memberKey, opId, raw, member) {
    if (!raw || typeof raw !== "object")
        return null;
    const at = Number(raw.at);
    if (!Number.isFinite(at))
        return null;
    const s = (v) => (typeof v === "string" ? v : "");
    const n = (v) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
    return {
        opId,
        memberKey,
        memberName: s(member?.name),
        memberPhone: s(member?.phone) || (memberKey.startsWith("L_") ? "" : memberKey),
        type: s(raw.type),
        points: n(raw.points),
        balanceAfter: n(raw.balanceAfter),
        billId: s(raw.billId),
        billCode: s(raw.billCode),
        storeCode: s(raw.storeCode),
        customerId: s(raw.customerId),
        staff: s(raw.staff),
        note: s(raw.note),
        at,
    };
}
//# sourceMappingURL=loyaltyLedgerQuery.js.map