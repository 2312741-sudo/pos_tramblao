import { describe, it, expect } from "vitest";
import {
  buildVarianceRows,
  lineKeyFor,
  openingFromPrevious,
  parseQty,
  previousDate,
  soldQtyByProduct,
  summarizeVariance,
  type StockProduct,
} from "../lib/daily-stock";
import type { HistoryOrder } from "../lib/reports";

const vn = (y: number, mo: number, d: number, h: number, mi = 0) => Date.UTC(y, mo - 1, d, h - 7, mi);

const products: StockProduct[] = [
  { id: "p1", name: "Trà ô long chanh", unit: "Ly", category: "Trà" },
  { id: "p2", name: "Bánh mì", unit: "Cái", category: "Bánh" },
  { id: "p3", name: "Nước suối", unit: "Chai", category: "Nước" },
];

const bill = (id: string, ts: number, items: Array<{ productId?: string; name: string; quantity: number }>, status = "PAID"): HistoryOrder =>
  ({ id, storeCode: "S1", status, closedAt: ts, timestamp: ts, items: items.map((i) => ({ ...i, price: 10000 })) }) as unknown as HistoryOrder;

describe("kiểm hàng đầu/cuối ngày", () => {
  it("parseQty: rỗng/sai/âm → null, hỗ trợ dấu phẩy", () => {
    expect(parseQty("")).toBeNull();
    expect(parseQty("abc")).toBeNull();
    expect(parseQty("-1")).toBeNull();
    expect(parseQty("2,5")).toBe(2.5);
    expect(parseQty(" 10 ")).toBe(10);
    expect(parseQty(0)).toBe(0);
  });

  it("lineKeyFor loại ký tự cấm của Firebase", () => {
    expect(lineKeyFor("a.b#c$d/e[f]")).toBe("a_b_c_d_e_f_");
  });

  it("previousDate qua đầu tháng/năm", () => {
    expect(previousDate("2026-01-01")).toBe("2025-12-31");
    expect(previousDate("2026-03-01")).toBe("2026-02-28");
  });

  it("đếm số bán theo ngày kinh doanh, bỏ hóa đơn hủy & ngày khác, khớp theo tên khi thiếu id", () => {
    const bills = [
      bill("b1", vn(2026, 11, 1, 9), [{ productId: "p1", name: "Trà ô long chanh", quantity: 3 }]),
      bill("b2", vn(2026, 11, 1, 20), [{ name: "Bánh mì", quantity: 2 }, { productId: "p1", name: "Trà ô long chanh", quantity: 1 }]),
      bill("b3", vn(2026, 11, 1, 21), [{ productId: "p1", name: "Trà ô long chanh", quantity: 5 }], "CANCELLED"),
      bill("b4", vn(2026, 11, 2, 1), [{ productId: "p1", name: "Trà ô long chanh", quantity: 7 }]), // 01:00 ngày 2 → thuộc ngày 1 nếu mốc 04:00
      bill("b5", vn(2026, 10, 31, 9), [{ productId: "p1", name: "Trà ô long chanh", quantity: 9 }]),
    ];
    const sold0 = soldQtyByProduct(bills, products, "2026-11-01", "S1", 0);
    expect(sold0.get("p1")).toBe(4);
    expect(sold0.get("p2")).toBe(2);
    const sold4h = soldQtyByProduct(bills, products, "2026-11-01", "S1", 240);
    expect(sold4h.get("p1")).toBe(11);
  });

  it("tính chênh lệch & trạng thái", () => {
    const record = {
      date: "2026-11-01",
      lines: {
        p1: { productId: "p1", name: "Trà ô long chanh", opening: 20, received: 10, closing: 24 }, // xuất 6, bán 4 → thiếu 2
        p2: { productId: "p2", name: "Bánh mì", opening: 10, closing: 9 }, // xuất 1, bán 2 → dư 1
        p3: { productId: "p3", name: "Nước suối", opening: 5 }, // thiếu tồn cuối
        old: { productId: "old", name: "Món đã xóa", opening: 3, closing: 3 },
      },
    };
    const sold = new Map([["p1", 4], ["p2", 2]]);
    const rows = buildVarianceRows(products, record, sold);
    const by = Object.fromEntries(rows.map((r) => [r.key, r]));
    expect(by.p1).toMatchObject({ countedOut: 6, sold: 4, variance: 2, status: "SHORT" });
    expect(by.p2).toMatchObject({ countedOut: 1, sold: 2, variance: -1, status: "OVER" });
    expect(by.p3).toMatchObject({ variance: null, status: "INCOMPLETE" });
    expect(by.old).toMatchObject({ variance: 0, status: "MATCH", name: "Món đã xóa" });

    const s = summarizeVariance(rows);
    expect(s).toMatchObject({ counted: 4, match: 1, short: 1, over: 1, incomplete: 1, shortQty: 2, overQty: 1 });

    // Dung sai ±2 → p1 khớp
    const tolRows = buildVarianceRows(products, record, sold, 2);
    expect(tolRows.find((r) => r.key === "p1")?.status).toBe("MATCH");
  });

  it("món chưa kiểm → EMPTY", () => {
    const rows = buildVarianceRows(products, null, new Map([["p3", 1]]));
    expect(rows.every((r) => r.status === "EMPTY")).toBe(true);
    expect(rows.find((r) => r.key === "p3")?.sold).toBe(1);
  });

  it("tồn đầu gợi ý = tồn cuối ngày trước", () => {
    expect(openingFromPrevious({ date: "x", lines: { a: { productId: "a", name: "A", closing: 4 }, b: { productId: "b", name: "B", opening: 2 } } })).toEqual({ a: 4 });
    expect(openingFromPrevious(null)).toEqual({});
  });
});
