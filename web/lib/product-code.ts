/**
 * Tra mã món (SKU) cho dòng món trong hóa đơn.
 * Ưu tiên mã hiện tại trong danh mục món (tra theo productId, rồi theo tên — danh mục nạp lại có thể đổi id),
 * sau đó mới dùng mã chụp sẵn trên dòng hóa đơn (hóa đơn cũ có thể trống hoặc lỗi thời).
 * Bản Dart song song: ReportCalculator.resolveProductCode (app_flutter/lib/core/reports/report_calculator.dart).
 */
/**
 * Id món hợp lệ trên dòng hóa đơn, hoặc undefined khi thiếu / rỗng / 0.
 * App POS ghi productId = 0 cho món không có id số → KHÔNG được gộp các món đó theo id (sẽ dồn mọi món
 * vào một dòng mang tên món đầu tiên); phải lùi về gộp theo tên như ReportCalculator bên Dart (prodId > 0 ? id : name).
 */
export function lineProductId(v: unknown): string | number | undefined {
  if (v == null) return undefined;
  if (typeof v === "number") return Number.isFinite(v) && v !== 0 ? v : undefined;
  const s = String(v).trim();
  if (!s || s === "0" || s === "null" || s === "undefined") return undefined;
  return v as string;
}

export interface CodeSource {
  code?: string;
  productCode?: string;
  name?: string;
}

export type ProductCodeMap = Record<string | number, CodeSource>;

export interface CodeLine {
  productId?: number | string | null;
  name?: string;
  productCode?: string;
  code?: string;
}

const codeOf = (p?: CodeSource): string => String(p?.code || p?.productCode || "").trim();

export function resolveProductCode(line: CodeLine, map?: ProductCodeMap): string {
  if (map) {
    const pid = lineProductId(line.productId);
    if (pid != null) {
      const byId = codeOf(map[pid]);
      if (byId) return byId;
    }
    if (line.name) {
      const byName = codeOf(map[line.name]);
      if (byName) return byName;
    }
  }
  return String(line.productCode || line.code || "").trim();
}

/** Bảng tra mã món theo id và theo tên từ danh mục món */
export function buildProductCodeMap(products: Array<CodeSource & { id?: string | number; productId?: string | number }>): ProductCodeMap {
  const map: ProductCodeMap = {};
  for (const p of products) {
    if (p.id != null) map[p.id] = p;
    if (p.productId != null) map[p.productId] = p;
    if (p.name) map[p.name] = p;
  }
  return map;
}
