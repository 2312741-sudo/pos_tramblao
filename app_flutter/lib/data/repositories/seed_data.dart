import '../models/app_models.dart';

class SeedData {
  static List<TableModel> get defaultTables => [
    // Khu A
    TableModel(name: 'A1', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A2', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A3', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A4', zone: 'Khu A', capacity: 4),
    TableModel(name: 'A5', zone: 'Khu A', capacity: 4),
    // Khu B
    TableModel(name: 'B1', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B2', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B3', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B4', zone: 'Khu B', capacity: 4),
    TableModel(name: 'B5', zone: 'Khu B', capacity: 4),
    // Khu C
    TableModel(name: 'C1', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C2', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C3', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C4', zone: 'Khu C', capacity: 4),
    TableModel(name: 'C5', zone: 'Khu C', capacity: 4),
    // Khu D
    TableModel(name: 'D1', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D2', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D3', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D4', zone: 'Khu D', capacity: 4),
    TableModel(name: 'D5', zone: 'Khu D', capacity: 4),
    // Mang về
    TableModel(name: 'Mang về', zone: 'Mang về', capacity: 2),
  ];

  static List<CategoryModel> get defaultCategories => [
    CategoryModel(name: "Trà Ô Long", order: 1, allowedToppingIds: ["Thạch dừa"]),
    CategoryModel(name: "Bánh Lăn Nướng", order: 2),
    CategoryModel(name: "Món Đặc Biệt", order: 3),
    CategoryModel(name: "Combo Trà + Bánh", order: 4),
    CategoryModel(name: "Đồ Ăn Vặt", order: 5),
    CategoryModel(name: "Topping", order: 6),
  ];

  static List<ZoneModel> get defaultZones => [
    ZoneModel(name: 'Khu A'),
    ZoneModel(name: 'Khu B'),
    ZoneModel(name: 'Khu C'),
    ZoneModel(name: 'Khu D'),
    ZoneModel(name: 'Mang về'),
  ];

  static List<ProductModel> get defaultProducts => [
    // ==================== 1. TRÀ Ô LONG ====================
    ProductModel(
      id: 1,
      code: "TRA01",
      name: "Trà Ô Long Chanh Tươi",
      price: 15000,
      unit: "Ly",
      category: "Trà Ô Long",
      hasIceSugarOptions: true,
      allowedToppings: ["Thạch dừa"],
    ),
    ProductModel(
      id: 2,
      code: "TRA02",
      name: "Trà Ô Long Chanh Đào",
      price: 20000,
      unit: "Ly",
      category: "Trà Ô Long",
      hasIceSugarOptions: true,
      allowedToppings: ["Thạch dừa"],
    ),
    ProductModel(
      id: 3,
      code: "TRA03",
      name: "Trà Ô Long Bưởi Hồng",
      price: 20000,
      unit: "Ly",
      category: "Trà Ô Long",
      hasIceSugarOptions: true,
      allowedToppings: ["Thạch dừa"],
    ),
    ProductModel(
      id: 4,
      code: "TRA04",
      name: "Trà Ô Long Xoài Đào",
      price: 20000,
      unit: "Ly",
      category: "Trà Ô Long",
      hasIceSugarOptions: true,
      allowedToppings: ["Thạch dừa"],
    ),
    ProductModel(
      id: 5,
      code: "TRA05",
      name: "Trà Ô Long Cam Đào",
      price: 20000,
      unit: "Ly",
      category: "Trà Ô Long",
      hasIceSugarOptions: true,
      allowedToppings: ["Thạch dừa"],
    ),
    ProductModel(
      id: 6,
      code: "TRA06",
      name: "Trà Xoài Chanh Dây",
      price: 20000,
      unit: "Ly",
      category: "Trà Ô Long",
      hasIceSugarOptions: true,
      allowedToppings: ["Thạch dừa"],
    ),
    ProductModel(
      id: 7,
      code: "TRA07",
      name: "Trà Ô Long Quýt Đào",
      price: 20000,
      unit: "Ly",
      category: "Trà Ô Long",
      hasIceSugarOptions: true,
      allowedToppings: ["Thạch dừa"],
    ),
    ProductModel(
      id: 8,
      code: "TRA08",
      name: "Trà Ô Long Quýt Hoàng Kim",
      price: 20000,
      unit: "Ly",
      category: "Trà Ô Long",
      hasIceSugarOptions: true,
      allowedToppings: ["Thạch dừa"],
    ),

    // ==================== 2. BÁNH LĂN NƯỚNG ====================
    ProductModel(
      id: 9,
      code: "BANH01",
      name: "Bánh Lăn Nướng Truyền Thống",
      price: 15000,
      unit: "Cái",
      category: "Bánh Lăn Nướng",
      sizes: {"Nhỏ": 0, "Lớn": 5000},
    ),
    ProductModel(
      id: 10,
      code: "BANH02",
      name: "Bánh Lăn Nướng Phô Mai Chảy",
      price: 20000,
      unit: "Cái",
      category: "Bánh Lăn Nướng",
      sizes: {"Nhỏ": 0, "Lớn": 5000},
    ),
    ProductModel(
      id: 11,
      code: "BANH03",
      name: "Bánh Lăn Nướng Choco Chip",
      price: 20000,
      unit: "Cái",
      category: "Bánh Lăn Nướng",
      sizes: {"Nhỏ": 0, "Lớn": 5000},
    ),

    // ==================== 3. MÓN ĐẶC BIỆT ====================
    ProductModel(
      id: 12,
      code: "DB01",
      name: "Bánh Flan Vỏ Chanh",
      price: 29000,
      unit: "Dĩa",
      category: "Món Đặc Biệt",
    ),
    ProductModel(
      id: 13,
      code: "DB02",
      name: "Set Marshmallow Nướng",
      price: 49000,
      unit: "Set",
      category: "Món Đặc Biệt",
    ),

    // ==================== 4. COMBO TRÀ + BÁNH ====================
    ProductModel(
      id: 14,
      code: "CB01",
      name: "Combo Truyền Thống",
      price: 29000,
      unit: "Combo",
      category: "Combo Trà + Bánh",
    ),
    ProductModel(
      id: 15,
      code: "CB02",
      name: "Combo Phô Mai",
      price: 39000,
      unit: "Combo",
      category: "Combo Trà + Bánh",
    ),
    ProductModel(
      id: 16,
      code: "CB03",
      name: "Combo Choco Chip",
      price: 39000,
      unit: "Combo",
      category: "Combo Trà + Bánh",
    ),

    // ==================== 5. ĐỒ ĂN VẶT ====================
    ProductModel(
      id: 17,
      code: "VAT01",
      name: "Bánh tráng",
      price: 10000,
      unit: "Bịch",
      category: "Đồ Ăn Vặt",
    ),
    ProductModel(
      id: 18,
      code: "VAT02",
      name: "Hạt hướng dương",
      price: 10000,
      unit: "Gói",
      category: "Đồ Ăn Vặt",
    ),

    // ==================== 6. TOPPING ====================
    ProductModel(
      id: 19,
      code: "TOP01",
      name: "Thạch dừa",
      price: 5000,
      unit: "Phần",
      category: "Topping",
      isTopping: true,
    ),
  ];
}
