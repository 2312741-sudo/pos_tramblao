/**
 * THỰC ĐƠN CHUẨN HỆ THỐNG TRẠM BLAO
 * "Trạm Trà - Trạm Bánh - Hẹn Nhau Ở BLAO"
 *
 * Gồm 5 danh mục & 18 món:
 * 1. Trà Ô Long (8 món)
 * 2. Bánh Lăn Nướng (3 món, có tuỳ chọn size Nhỏ/Lớn)
 * 3. Món Đặc Biệt (Bánh Flan Vỏ Chanh, Set Marshmallow Nướng)
 * 4. Combo Trà + Bánh (3 combo)
 * 5. Đồ Ăn Vặt (Bánh tráng, Hạt hướng dương)
 *
 * Lưu ý quy định: Không sử dụng ảnh của Trạm cũ, để trống hình ảnh cho chủ quán cập nhật sau.
 */

export interface DefaultCategoryItem {
  name: string;
  order: number;
  allowedToppingIds?: string[];
}

export interface DefaultProductItem {
  id: number;
  code: string;
  name: string;
  price: number;
  unit: string;
  category: string;
  imageResourceName?: string;
  hasIceSugarOptions?: boolean;
  allowedToppings?: string[];
  sizes?: Record<string, number>;
  isTopping?: boolean;
}

export const DEFAULT_BLAO_CATEGORIES: DefaultCategoryItem[] = [
  { name: "Trà Ô Long", order: 1, allowedToppingIds: ["Thạch dừa"] },
  { name: "Bánh Lăn Nướng", order: 2 },
  { name: "Món Đặc Biệt", order: 3 },
  { name: "Combo Trà + Bánh", order: 4 },
  { name: "Đồ Ăn Vặt", order: 5 },
];

export const DEFAULT_BLAO_PRODUCTS: DefaultProductItem[] = [
  // ==================== 1. TRÀ Ô LONG ====================
  {
    id: 1,
    code: "TRA01",
    name: "Trà Ô Long Chanh Tươi",
    price: 15000,
    unit: "Ly",
    category: "Trà Ô Long",
    imageResourceName: "tra_olong_chanh_tuoi.jpg",
    hasIceSugarOptions: true,
    allowedToppings: ["Thạch dừa"],
  },
  {
    id: 2,
    code: "TRA02",
    name: "Trà Ô Long Chanh Đào",
    price: 20000,
    unit: "Ly",
    category: "Trà Ô Long",
    imageResourceName: "tra_olong_chanh_dao.jpg",
    hasIceSugarOptions: true,
    allowedToppings: ["Thạch dừa"],
  },
  {
    id: 3,
    code: "TRA03",
    name: "Trà Ô Long Bưởi Hồng",
    price: 20000,
    unit: "Ly",
    category: "Trà Ô Long",
    imageResourceName: "tra_olong_buoi_hong.jpg",
    hasIceSugarOptions: true,
    allowedToppings: ["Thạch dừa"],
  },
  {
    id: 4,
    code: "TRA04",
    name: "Trà Ô Long Xoài Đào",
    price: 20000,
    unit: "Ly",
    category: "Trà Ô Long",
    imageResourceName: "tra_olong_xoai_dao.jpg",
    hasIceSugarOptions: true,
    allowedToppings: ["Thạch dừa"],
  },
  {
    id: 5,
    code: "TRA05",
    name: "Trà Ô Long Cam Đào",
    price: 20000,
    unit: "Ly",
    category: "Trà Ô Long",
    imageResourceName: "tra_olong_cam_dao.jpg",
    hasIceSugarOptions: true,
    allowedToppings: ["Thạch dừa"],
  },
  {
    id: 6,
    code: "TRA06",
    name: "Trà Ô Long Xoài Chanh Dây",
    price: 20000,
    unit: "Ly",
    category: "Trà Ô Long",
    imageResourceName: "tra_olong_xoai_chanh_day.jpg",
    hasIceSugarOptions: true,
    allowedToppings: ["Thạch dừa"],
  },
  {
    id: 7,
    code: "TRA07",
    name: "Trà Ô Long Quýt Đào",
    price: 20000,
    unit: "Ly",
    category: "Trà Ô Long",
    imageResourceName: "tra_olong_quyt_dao.jpg",
    hasIceSugarOptions: true,
    allowedToppings: ["Thạch dừa"],
  },
  {
    id: 8,
    code: "TRA08",
    name: "Trà Ô Long Quýt Hoàng Kim",
    price: 20000,
    unit: "Ly",
    category: "Trà Ô Long",
    imageResourceName: "tra_olong_quyt_hoang_kim.jpg",
    hasIceSugarOptions: true,
    allowedToppings: ["Thạch dừa"],
  },

  // ==================== 2. BÁNH LĂN NƯỚNG ====================
  {
    id: 9,
    code: "BANH01",
    name: "Bánh Lăn Nướng Truyền Thống",
    price: 15000,
    unit: "Cái",
    category: "Bánh Lăn Nướng",
    sizes: { "Nhỏ": 0, "Lớn": 5000 },
  },
  {
    id: 10,
    code: "BANH02",
    name: "Bánh Lăn Nướng Phô Mai Chảy",
    price: 20000,
    unit: "Cái",
    category: "Bánh Lăn Nướng",
    sizes: { "Nhỏ": 0, "Lớn": 5000 },
  },
  {
    id: 11,
    code: "BANH03",
    name: "Bánh Lăn Nướng Choco Chip",
    price: 20000,
    unit: "Cái",
    category: "Bánh Lăn Nướng",
    sizes: { "Nhỏ": 0, "Lớn": 5000 },
  },

  // ==================== 3. MÓN ĐẶC BIỆT ====================
  {
    id: 12,
    code: "DB01",
    name: "Bánh Flan Vỏ Chanh",
    price: 29000,
    unit: "Dĩa",
    category: "Món Đặc Biệt",
  },
  {
    id: 13,
    code: "DB02",
    name: "Set Marshmallow Nướng",
    price: 49000,
    unit: "Set",
    category: "Món Đặc Biệt",
  },

  // ==================== 4. COMBO TRÀ + BÁNH ====================
  {
    id: 14,
    code: "CB01",
    name: "Combo Truyền Thống",
    price: 29000,
    unit: "Combo",
    category: "Combo Trà + Bánh",
  },
  {
    id: 15,
    code: "CB02",
    name: "Combo Phô Mai",
    price: 39000,
    unit: "Combo",
    category: "Combo Trà + Bánh",
  },
  {
    id: 16,
    code: "CB03",
    name: "Combo Choco Chip",
    price: 39000,
    unit: "Combo",
    category: "Combo Trà + Bánh",
  },

  // ==================== 5. ĐỒ ĂN VẶT ====================
  {
    id: 17,
    code: "VAT01",
    name: "Bánh tráng",
    price: 10000,
    unit: "Bịch",
    category: "Đồ Ăn Vặt",
  },
  {
    id: 18,
    code: "VAT02",
    name: "Hạt hướng dương",
    price: 10000,
    unit: "Gói",
    category: "Đồ Ăn Vặt",
  },
];
