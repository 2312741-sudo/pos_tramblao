import { describe, it, expect } from "vitest";
import { defaultSelection, describeSelection, getProductOptions, looksLikeRef, makeConfiguredLine, type OptionProduct } from "../lib/product-options";
import { addLineToOrder } from "../lib/web-order";
import { lineUnitPrice } from "../lib/order-math";
import { parseCatalog } from "../lib/item-options";

const actor = { username: "nv1" };
const tea: OptionProduct = { id: "1", name: "Trà đào", price: 30000, category: "Trà", sizes: { S: 0, M: 5000, L: 10000 } };
const tops: OptionProduct[] = [
  { id: "90", name: "Trân châu đen", price: 5000, category: "Topping", isTopping: true },
  { id: "91", name: "Kem Cheese", price: 12000, category: "Topping", isTopping: true },
];
const cake: OptionProduct = { id: "2", name: "Bánh waffle", price: 55000, category: "Bánh" };

describe("tùy chọn món", () => {
  it("đồ uống KHÔNG chọn size (kể cả đã cấu hình S/M/L), vẫn có topping và đường/đá; bánh không có gì để hỏi", () => {
    const o = getProductOptions(tea, [], [tea, ...tops]);
    expect(o.sizes).toEqual([]);
    expect(o.iceSugar).toBe(true);
    expect(o.toppings.find((t) => t.name === "Kem Cheese")?.price).toBe(12000);
    expect(getProductOptions(cake, [], [cake, ...tops]).hasAny).toBe(false);
    expect(getProductOptions(tops[0], [], tops).hasAny).toBe(false);
  });

  it("thiếu size ở danh mục đồ uống → không tự thêm S/M/L", () => {
    const o = getProductOptions({ id: "3", name: "Sữa tươi", price: 20000, category: "Sữa" }, [], []);
    expect(o.sizes).toEqual([]);
    expect(o.iceSugar).toBe(true);
  });

  it("topping theo danh mục (allowedToppingIds) ưu tiên hơn mặc định", () => {
    const o = getProductOptions(tea, [{ name: "Trà", allowedToppingIds: ["91", "Thạch chanh"] }], [tea, ...tops]);
    expect(o.toppings).toEqual([{ name: "Kem Cheese", price: 12000 }, { name: "Thạch chanh", price: 5000 }]);
  });

  it("dòng đồ uống + topping: không ghi size, đơn giá = giá món + topping", () => {
    const o = getProductOptions(tea, [], [tea, ...tops]);
    const sel = { ...defaultSelection(o), size: "L", sugar: "70% đường", ice: "Không đá", toppings: ["Trân châu đen", "Kem Cheese"] };
    const line = makeConfiguredLine(tea, o, sel, 2, " ít ngọt ", actor, 1);
    expect(line).toMatchObject({ productId: 1, selectedSugar: "70% đường", selectedIce: "Không đá", toppingPrice: 17000, quantity: 2, note: "ít ngọt" });
    expect(line.selectedSize).toBeUndefined();
    expect(line.sizeExtraPrice).toBeUndefined();
    expect(lineUnitPrice(line)).toBe(30000 + 17000);
    expect(describeSelection(line)).toBe("70% đường • Không đá • + Trân châu đen, Kem Cheese");
  });

  it("mặc định đồ uống: không size, 100% đường/đá, không topping", () => {
    expect(defaultSelection(getProductOptions(tea, [], []))).toEqual({ size: "", sugar: "100% đường", ice: "100% đá", toppings: [] });
  });

  it("món không phải đồ uống (bánh Nhỏ/Lớn) vẫn giữ size", () => {
    const banh: OptionProduct = { id: "10", name: "Bánh Lăn Nướng", price: 29000, category: "Bánh Lăn Nướng", sizes: { "Nhỏ": 0, "Lớn": 5000 } };
    const oBanh = getProductOptions(banh, [], []);
    expect(oBanh.sizes).toEqual([{ name: "Nhỏ", extra: 0 }, { name: "Lớn", extra: 5000 }]);
  });

  it("chỉ gộp dòng khi cùng tùy chọn", () => {
    const o = getProductOptions(tea, [], [tea, ...tops]);
    const base = defaultSelection(o);
    const a = makeConfiguredLine(tea, o, base, 1, "", actor, 1);
    const same = makeConfiguredLine(tea, o, base, 1, "", actor, 2);
    const diff = makeConfiguredLine(tea, o, { ...base, sugar: "50% đường" }, 1, "", actor, 3);
    expect(addLineToOrder(addLineToOrder([], a), same)).toHaveLength(1);
    expect(addLineToOrder(addLineToOrder([], a), diff)).toHaveLength(2);
  });
});

describe("tùy chọn món theo danh mục note & topping", () => {
  const catalog = parseCatalog(
    { n1: { name: "Đồ uống", sortOrder: 1, items: [{ id: "a", text: "Ít đá" }] } },
    { t1: { name: "Topping trà", sortOrder: 1, items: [{ id: "1", name: "Trân châu", price: 7000 }] } }
  );
  const bakery: OptionProduct = { id: "5", name: "Bánh lăn choco - Size 30", price: 40000, category: "Bánh Lăn Nướng" };

  it("đã cấu hình nhưng chưa gắn gì: bánh không có topping/note; trà thuộc nhóm đã gắn mới có", () => {
    expect(getProductOptions(bakery, [{ name: "Bánh Lăn Nướng" }], [bakery], catalog).hasAny).toBe(false);
    const o = getProductOptions(tea, [{ name: "Trà", noteGroupIds: ["n1"], toppingGroupIds: ["t1"] }], [tea, ...tops], catalog);
    expect(o.catalogMode).toBe(true);
    expect(o.toppings).toEqual([{ name: "Trân châu", price: 7000 }]);
    expect(o.noteChips).toEqual(["Ít đá"]);
    expect(o.toppingGroups.map((g) => g.id)).toEqual(["t1"]);
  });

  it("món ghi đè nhóm món; gắn note cho bánh thì bánh hiện chip note nhưng vẫn không có topping", () => {
    const o = getProductOptions({ ...tea, toppingGroupIds: ["__none__"] }, [{ name: "Trà", toppingGroupIds: ["t1"] }], [tea], catalog);
    expect(o.toppings).toEqual([]);
    const b = getProductOptions({ ...bakery, noteGroupIds: ["n1"] }, [], [bakery], catalog);
    expect(b.hasAny).toBe(true);
    expect(b.toppings).toEqual([]);
    expect(b.noteChips).toEqual(["Ít đá"]);
  });

  it("chưa cấu hình (catalog rỗng/không truyền) giữ cách cũ", () => {
    const o = getProductOptions(tea, [], [tea, ...tops], parseCatalog(null, null));
    expect(o.catalogMode).toBe(false);
    expect(o.toppings.length).toBeGreaterThan(0);
  });

  it("giá topping lấy từ nhóm khi tạo dòng", () => {
    const o = getProductOptions(tea, [{ name: "Trà", toppingGroupIds: ["t1"] }], [tea], catalog);
    const line = makeConfiguredLine(tea, o, { ...defaultSelection(o), toppings: ["Trân châu"] }, 1, "", actor, 1);
    expect(line.toppingPrice).toBe(7000);
  });
});


describe("topping cho nhóm món lưu bằng KHÓA RTDB (Tăng giá Grab)", () => {
  const grab5 = { id: "-NgrabUp5k", name: "Tăng giá Grab 5K", price: 5000, category: "Topping", isTopping: true } as OptionProduct;
  const grab10 = { id: "-NgrabUp10k", name: "Tăng giá Grab 10K", price: 10000, category: "Topping", isTopping: true } as OptionProduct;
  const dish = { id: "-Ndish", name: "Cơm gà", price: 45000, category: "Món Grab" } as OptionProduct;
  it("hiện đúng tên + giá; khóa không còn món thì bỏ, không hiện mã với giá 5.000đ", () => {
    const o = getProductOptions(dish, [{ name: "Món Grab", allowedToppingIds: ["-NgrabUp5k", "-NgrabUp10k", "-NdaXoaMon123"] }], [dish, grab5, grab10]);
    expect(o.toppings).toEqual([
      { name: "Tăng giá Grab 5K", price: 5000 },
      { name: "Tăng giá Grab 10K", price: 10000 },
    ]);
  });
  it("looksLikeRef: mã / khóa thì đúng, tên topping thì không", () => {
    expect(looksLikeRef("-NgrabUp5k")).toBe(true);
    expect(looksLikeRef("123")).toBe(true);
    expect(looksLikeRef("p_17")).toBe(true);
    expect(looksLikeRef("Trân châu đen")).toBe(false);
    expect(looksLikeRef("Kem Cheese")).toBe(false);
  });
});
