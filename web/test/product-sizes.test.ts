import { describe, it, expect } from "vitest";
import { rowsToSizes, sizesToRows } from "../lib/product-sizes";

describe("chỉnh size món trên web", () => {
  it("sizes → dòng sửa, sắp theo phụ thu tăng dần", () => {
    expect(sizesToRows({ "Lớn": 5000, "Nhỏ": 0 })).toEqual([{ name: "Nhỏ", extra: "0" }, { name: "Lớn", extra: "5000" }]);
    expect(sizesToRows(undefined)).toEqual([]);
  });

  it("dòng sửa → sizes; chấp nhận 8.000 / 8,000; phụ thu trống = 0", () => {
    expect(rowsToSizes([{ name: " Nhỏ ", extra: "" }, { name: "Lớn", extra: "8.000" }])).toEqual({ sizes: { "Nhỏ": 0, "Lớn": 8000 } });
    expect(rowsToSizes([{ name: "Lớn", extra: "8,000" }]).sizes).toEqual({ "Lớn": 8000 });
  });

  it("không còn size → null (xóa trường sizes); bỏ qua dòng trống", () => {
    expect(rowsToSizes([])).toEqual({ sizes: null });
    expect(rowsToSizes([{ name: "", extra: "" }])).toEqual({ sizes: null });
  });

  it("báo lỗi: thiếu tên, trùng tên, ký tự cấm, phụ thu âm/sai", () => {
    expect(rowsToSizes([{ name: "", extra: "5000" }]).error).toMatch(/trống/);
    expect(rowsToSizes([{ name: "Lớn", extra: "0" }, { name: "lớn", extra: "1" }]).error).toMatch(/trùng/);
    expect(rowsToSizes([{ name: "L.1", extra: "0" }]).error).toMatch(/ký tự/);
    expect(rowsToSizes([{ name: "Lớn", extra: "-5000" }]).error).toMatch(/không hợp lệ/);
    expect(rowsToSizes([{ name: "Lớn", extra: "abc" }]).error).toMatch(/không hợp lệ/);
  });
});
