import { describe, it, expect } from "vitest";
import { DEFAULT_BLAO_CATEGORIES, DEFAULT_BLAO_PRODUCTS } from "../lib/default-menu";

describe("Thực đơn chuẩn Trạm BLAO", () => {
  it("chứa đúng 5 danh mục theo thứ tự (không có nhóm Topping ảo)", () => {
    expect(DEFAULT_BLAO_CATEGORIES).toHaveLength(5);
    expect(DEFAULT_BLAO_CATEGORIES.map((c) => c.name)).toEqual([
      "Trà Ô Long",
      "Bánh Lăn Nướng",
      "Món Đặc Biệt",
      "Combo Trà + Bánh",
      "Đồ Ăn Vặt",
    ]);
  });

  it("chứa đầy đủ 18 món từ menu poster thực tế (Thạch dừa là topping gắn kèm, không phải món độc lập)", () => {
    expect(DEFAULT_BLAO_PRODUCTS).toHaveLength(18);

    // Không dùng ảnh quán Trạm cũ
    for (const p of DEFAULT_BLAO_PRODUCTS) {
      expect(p.name).toBeTruthy();
      expect(p.code).toBeTruthy();
      expect(p.price).toBeGreaterThan(0);
      expect(p.category).toBeTruthy();
    }

    // Nhóm Trà Ô Long (8 món)
    const tras = DEFAULT_BLAO_PRODUCTS.filter((p) => p.category === "Trà Ô Long");
    expect(tras).toHaveLength(8);
    expect(tras.map((p) => p.name)).toEqual([
      "Trà Ô Long Chanh Tươi",
      "Trà Ô Long Chanh Đào",
      "Trà Ô Long Bưởi Hồng",
      "Trà Ô Long Xoài Đào",
      "Trà Ô Long Cam Đào",
      "Trà Xoài Chanh Dây",
      "Trà Ô Long Quýt Đào",
      "Trà Ô Long Quýt Hoàng Kim",
    ]);

    // Nhóm Bánh Lăn Nướng (3 món có size Lớn +5K)
    const banhs = DEFAULT_BLAO_PRODUCTS.filter((p) => p.category === "Bánh Lăn Nướng");
    expect(banhs).toHaveLength(3);
    for (const b of banhs) {
      expect(b.sizes).toEqual({ "Nhỏ": 0, "Lớn": 5000 });
    }

    // Nhóm Món Đặc Biệt (Flan vỏ chanh 29K, Marshmallow nướng 49K)
    const dacBiet = DEFAULT_BLAO_PRODUCTS.filter((p) => p.category === "Món Đặc Biệt");
    expect(dacBiet).toHaveLength(2);
    expect(dacBiet.find((p) => p.name === "Bánh Flan Vỏ Chanh")?.price).toBe(29000);
    expect(dacBiet.find((p) => p.name === "Set Marshmallow Nướng")?.price).toBe(49000);

    // Nhóm Combo (Combo Truyền Thống 29K, Phô Mai 39K, Choco Chip 39K)
    const combos = DEFAULT_BLAO_PRODUCTS.filter((p) => p.category === "Combo Trà + Bánh");
    expect(combos).toHaveLength(3);
    expect(combos.find((p) => p.name === "Combo Truyền Thống")?.price).toBe(29000);
    expect(combos.find((p) => p.name === "Combo Phô Mai")?.price).toBe(39000);
    expect(combos.find((p) => p.name === "Combo Choco Chip")?.price).toBe(39000);

    // Nhóm Đồ Ăn Vặt (Bánh tráng, Hạt hướng dương)
    const anVat = DEFAULT_BLAO_PRODUCTS.filter((p) => p.category === "Đồ Ăn Vặt");
    expect(anVat).toHaveLength(2);
    expect(anVat.map((p) => p.name)).toContain("Bánh tráng");
    expect(anVat.map((p) => p.name)).toContain("Hạt hướng dương");

    // Không còn nhóm Topping ảo độc lập
    const toppings = DEFAULT_BLAO_PRODUCTS.filter((p) => p.category === "Topping");
    expect(toppings).toHaveLength(0);
  });
});
