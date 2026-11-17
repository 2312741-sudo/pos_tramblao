/**
 * Chỉnh SIZE của món trên web (Thực đơn & Sản phẩm).
 * Lưu tại stores/{store}/products/{id}/sizes = { "Nhỏ": 0, "Lớn": 5000 } — giá trị là PHỤ THU so với giá gốc.
 * App POS và web đọc trực tiếp từ Firebase nên đổi phụ thu không cần build lại app.
 * Đồ uống không chọn size khi gọi món (xem isDrinkProduct trong product-options.ts).
 */

export interface SizeRow {
  name: string;
  /** Phụ thu (đ) dạng chuỗi trong ô nhập */
  extra: string;
}

/** Ký tự Firebase không cho dùng trong tên khóa */
const FORBIDDEN = /[.#$/[\]]/;

/** sizes trong DB → các dòng để sửa (giữ thứ tự phụ thu tăng dần) */
export function sizesToRows(sizes?: Record<string, number> | null): SizeRow[] {
  if (!sizes || typeof sizes !== "object") return [];
  return Object.entries(sizes)
    .map(([name, v]) => ({ name, extra: String(Math.max(0, Math.trunc(Number(v)) || 0)) }))
    .sort((a, b) => Number(a.extra) - Number(b.extra));
}

/**
 * Các dòng đang sửa → giá trị lưu Firebase.
 * Bỏ qua dòng trống hoàn toàn; không còn dòng nào → null (xóa trường sizes).
 */
export function rowsToSizes(rows: SizeRow[]): { sizes: Record<string, number> | null; error?: string } {
  const out: Record<string, number> = {};
  const seen = new Set<string>();
  for (const r of rows) {
    const name = r.name.trim();
    const extraText = r.extra.trim().replace(/[.,\s]/g, "");
    if (!name && !extraText) continue;
    if (!name) return { sizes: null, error: "Tên size không được để trống" };
    if (name.length > 20) return { sizes: null, error: `Tên size "${name}" quá dài (tối đa 20 ký tự)` };
    if (FORBIDDEN.test(name)) return { sizes: null, error: `Tên size "${name}" không được chứa các ký tự . # $ / [ ]` };
    const key = name.toLocaleLowerCase("vi");
    if (seen.has(key)) return { sizes: null, error: `Size "${name}" bị trùng` };
    seen.add(key);
    const extra = extraText === "" ? 0 : Number(extraText);
    if (!Number.isInteger(extra) || extra < 0) return { sizes: null, error: `Phụ thu của size "${name}" không hợp lệ` };
    out[name] = extra;
  }
  return { sizes: Object.keys(out).length > 0 ? out : null };
}
