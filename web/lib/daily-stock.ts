/**
 * KIỂM HÀNG ĐẦU NGÀY / CUỐI NGÀY & ĐỐI CHIẾU VỚI HÀNG BÁN RA
 *
 * Mỗi ngày kinh doanh nhân viên đếm hàng hoá (theo món trong thực đơn):
 *   - Tồn đầu ngày (đếm lúc mở cửa)
 *   - Nhập thêm trong ngày (nhận hàng / chuyển đến)
 *   - Tồn cuối ngày (đếm lúc đóng cửa)
 *
 * Xuất theo kiểm đếm = Tồn đầu + Nhập thêm − Tồn cuối
 * Bán theo hệ thống  = số lượng trên hóa đơn ĐÃ THANH TOÁN của ngày kinh doanh (POS + Web)
 * Chênh lệch         = Xuất theo kiểm đếm − Bán theo hệ thống
 *   > 0  → thiếu hàng (hao hụt / bán không lên bill / hủy bỏ)
 *   < 0  → dư hàng (đếm sai / bill ghi thừa)
 *
 * Lưu tại: stores/{store}/daily_stock_counts/{YYYY-MM-DD}
 *   { date, lines: { [lineKey]: { productId, name, unit, category, opening, received, closing, note } },
 *     openingSavedAt/By/ByName, closingSavedAt/By/ByName, updatedAt, updatedBy, updatedByName,
 *     locked, lockedAt, lockedBy, lockedByName }
 * Rules: thành viên cửa hàng ghi được khi phiếu chưa chốt; chốt / mở chốt / xóa chỉ Chủ & Quản lý.
 */
import { businessDateOf } from "./business-day";
import { calculateProductReport, getBillTimestamp, type HistoryOrder, type ProductLookup } from "./reports";

export interface DailyStockLine {
  productId: string;
  name: string;
  unit?: string;
  category?: string;
  opening?: number | null;
  received?: number | null;
  closing?: number | null;
  note?: string;
}

export interface DailyStockRecord {
  date: string;
  lines?: Record<string, DailyStockLine>;
  openingSavedAt?: number;
  openingSavedBy?: string;
  openingSavedByName?: string;
  closingSavedAt?: number;
  closingSavedBy?: string;
  closingSavedByName?: string;
  updatedAt?: number;
  updatedBy?: string;
  updatedByName?: string;
  locked?: boolean;
  lockedAt?: number;
  lockedBy?: string;
  lockedByName?: string;
}

export interface StockProduct {
  id: string;
  name: string;
  unit?: string;
  category?: string;
  isTopping?: boolean;
}

export type VarianceStatus = "MATCH" | "SHORT" | "OVER" | "INCOMPLETE" | "EMPTY";

export interface VarianceRow {
  key: string;
  productId: string;
  name: string;
  unit: string;
  category: string;
  opening: number | null;
  received: number | null;
  closing: number | null;
  /** Xuất theo kiểm đếm (null khi thiếu tồn đầu hoặc tồn cuối) */
  countedOut: number | null;
  /** Bán theo hệ thống (hóa đơn đã thanh toán) */
  sold: number;
  /** Chênh lệch = countedOut − sold (null khi chưa đủ số liệu) */
  variance: number | null;
  status: VarianceStatus;
}

export const VARIANCE_STATUS_LABEL: Record<VarianceStatus, string> = {
  MATCH: "Khớp",
  SHORT: "Thiếu hàng",
  OVER: "Dư hàng",
  INCOMPLETE: "Chưa đủ số liệu",
  EMPTY: "Chưa kiểm",
};

/** Khóa an toàn cho Firebase (không chứa . # $ / [ ]) */
export function lineKeyFor(productId: string): string {
  const k = String(productId).trim().replace(/[.#$/[\]]/g, "_");
  return k || "_";
}

/** Chuỗi nhập → số không âm (rỗng/sai → null). Hỗ trợ dấu phẩy thập phân. */
export function parseQty(text: string | number | null | undefined): number | null {
  if (text == null) return null;
  if (typeof text === "number") return Number.isFinite(text) && text >= 0 ? text : null;
  const t = text.trim().replace(",", ".");
  if (t === "") return null;
  const n = Number(t);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.round(n * 1000) / 1000;
}

const round3 = (n: number) => Math.round(n * 1000) / 1000;
const norm = (s: string) => s.trim().toLowerCase();

/**
 * Số lượng bán theo món trong NGÀY KINH DOANH [ymd] của cửa hàng.
 * Trả về Map theo id món (khớp theo productId, dự phòng theo tên món).
 * Topping được tách thành dòng riêng (giống báo cáo Hàng hoá bán ra).
 */
export function soldQtyByProduct(
  bills: HistoryOrder[],
  products: StockProduct[],
  ymd: string,
  storeCode: string,
  startMinute: number
): Map<string, number> {
  const dayBills = bills.filter((b) => {
    if (storeCode && b.storeCode && b.storeCode !== storeCode) return false;
    const ts = getBillTimestamp(b);
    if (!ts) return false;
    return businessDateOf(ts, startMinute) === ymd;
  });

  const lookup: Record<string, ProductLookup> = {};
  for (const p of products) {
    const entry = p as unknown as ProductLookup;
    lookup[p.id] = entry;
    if (p.name) lookup[p.name] = entry;
  }
  const report = calculateProductReport(dayBills, lookup);

  const byId = new Map(products.map((p) => [String(p.id), p]));
  const byName = new Map<string, StockProduct>();
  for (const p of products) if (p.name && !byName.has(norm(p.name))) byName.set(norm(p.name), p);

  const out = new Map<string, number>();
  for (const r of report) {
    const p = byId.get(String(r.productId)) || byName.get(norm(String(r.productName || "")));
    const id = p ? p.id : `name:${r.productName}`;
    out.set(id, round3((out.get(id) || 0) + Number(r.quantity || 0)));
  }
  return out;
}

/** Ghép số liệu kiểm đếm + số bán để ra bảng đối chiếu */
export function buildVarianceRows(
  products: StockProduct[],
  record: DailyStockRecord | null | undefined,
  sold: Map<string, number>,
  tolerance = 0
): VarianceRow[] {
  const lines = record?.lines || {};
  const rows: VarianceRow[] = [];
  const seen = new Set<string>();

  const make = (key: string, productId: string, name: string, unit: string, category: string): VarianceRow => {
    const l = lines[key];
    const opening = l?.opening ?? null;
    const received = l?.received ?? null;
    const closing = l?.closing ?? null;
    const soldQty = sold.get(productId) || 0;
    let countedOut: number | null = null;
    let variance: number | null = null;
    let status: VarianceStatus;
    if (opening == null && closing == null && received == null) {
      status = "EMPTY";
    } else if (opening == null || closing == null) {
      status = "INCOMPLETE";
    } else {
      countedOut = round3(opening + (received || 0) - closing);
      variance = round3(countedOut - soldQty);
      status = Math.abs(variance) <= tolerance ? "MATCH" : variance > 0 ? "SHORT" : "OVER";
    }
    return { key, productId, name, unit, category, opening, received, closing, countedOut, sold: soldQty, variance, status };
  };

  for (const p of products) {
    const key = lineKeyFor(p.id);
    seen.add(key);
    rows.push(make(key, p.id, p.name, p.unit || "", p.category || ""));
  }
  // Món đã bị xóa khỏi thực đơn nhưng vẫn còn số kiểm đếm trong phiếu
  for (const [key, l] of Object.entries(lines)) {
    if (seen.has(key)) continue;
    rows.push(make(key, l.productId, l.name || l.productId, l.unit || "", l.category || ""));
  }
  return rows;
}

export interface VarianceSummary {
  counted: number;
  match: number;
  short: number;
  over: number;
  incomplete: number;
  shortQty: number;
  overQty: number;
  soldQty: number;
}

export function summarizeVariance(rows: VarianceRow[]): VarianceSummary {
  const s: VarianceSummary = { counted: 0, match: 0, short: 0, over: 0, incomplete: 0, shortQty: 0, overQty: 0, soldQty: 0 };
  for (const r of rows) {
    if (r.status === "EMPTY") continue;
    s.counted++;
    s.soldQty += r.sold;
    if (r.status === "MATCH") s.match++;
    else if (r.status === "INCOMPLETE") s.incomplete++;
    else if (r.status === "SHORT") {
      s.short++;
      s.shortQty += r.variance || 0;
    } else if (r.status === "OVER") {
      s.over++;
      s.overQty += -(r.variance || 0);
    }
  }
  s.shortQty = round3(s.shortQty);
  s.overQty = round3(s.overQty);
  s.soldQty = round3(s.soldQty);
  return s;
}

/** Ngày "YYYY-MM-DD" liền trước */
export function previousDate(ymd: string): string {
  const [y, m, d] = ymd.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d - 1)).toISOString().slice(0, 10);
}

/** Tồn đầu gợi ý = tồn cuối của phiếu ngày trước (chỉ những món có tồn cuối) */
export function openingFromPrevious(prev: DailyStockRecord | null | undefined): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [key, l] of Object.entries(prev?.lines || {})) {
    if (l && l.closing != null) out[key] = l.closing;
  }
  return out;
}
