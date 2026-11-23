"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.findDuplicateTarget = findDuplicateTarget;
exports.mergedProduct = mergedProduct;
const norm = (v) => String(v ?? "").trim().toLowerCase().replace(/\s+/g, " ");
/** Khóa món cũ cần gộp vào (null = món mới thật, không trùng) */
function findDuplicateTarget(newKey, created, products) {
    const name = norm(created.name);
    if (!name)
        return null;
    const matches = Object.entries(products)
        .filter(([k, v]) => k !== newKey && v && typeof v === "object" && norm(v.name) === name)
        .map(([k]) => k);
    // Nhiều hơn 1 món cùng tên: không đoán, để nguyên
    return matches.length === 1 ? matches[0] : null;
}
/** Nội dung ghi đè lên món cũ: dữ liệu vừa sửa, giữ mã định danh `id` của món cũ */
function mergedProduct(target, created) {
    const out = { ...target, ...created };
    if (target.id !== undefined)
        out.id = target.id;
    else
        delete out.id;
    return out;
}
//# sourceMappingURL=productDedupeLogic.js.map