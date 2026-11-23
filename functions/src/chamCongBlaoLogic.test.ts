import { describe, it, expect } from "vitest";
import { buildNewMember, decideCcAccount, mapPosRoleToCc, memberAction, newCcUid, normalizeName } from "./chamCongBlaoLogic";

describe("Chấm Công BLAO — đăng nhập bằng tài khoản POS", () => {
  it("chuẩn hóa tên: bỏ dấu, đ, hoa thường, khoảng trắng", () => {
    expect(normalizeName("  Nguyễn   Thị Đào ")).toBe("nguyen thi dao");
    expect(normalizeName("NGUYEN THI DAO")).toBe("nguyen thi dao");
    expect(normalizeName(undefined)).toBe("");
  });

  it("vai trò POS → vai trò chấm công", () => {
    expect(mapPosRoleToCc("staff", true)).toBe("owner");
    expect(mapPosRoleToCc("ROLE_OWNER", false)).toBe("owner");
    expect(mapPosRoleToCc("ROLE_MANAGER", false)).toBe("manager_1");
    expect(mapPosRoleToCc("manager_2", false)).toBe("manager_1");
    expect(mapPosRoleToCc("ROLE_STAFF", false)).toBe("employee");
    expect(mapPosRoleToCc("ROLE_KITCHEN", false)).toBe("employee");
    expect(mapPosRoleToCc(undefined, undefined)).toBe("employee");
  });

  it("uid chấm công cho tài khoản mới hợp lệ", () => {
    expect(newCcUid("TRAM01", "abc.def/1")).toBe("pos_TRAM01_abc_def_1");
  });

  const base = { storeCode: "TRAM01", posUid: "u1", takenCcUids: new Set<string>() };

  it("đã liên kết → dùng lại", () => {
    expect(decideCcAccount({ ...base, existingLink: "cc9", posFullName: "A", members: [] })).toEqual({ kind: "LINKED", ccUid: "cc9" });
  });

  it("trùng tên đúng 1 người → nối vào tài khoản cũ (giữ lịch sử)", () => {
    const members = [
      { uid: "ccA", name: "Nguyễn Văn An", status: "active" },
      { uid: "ccB", name: "Trần Thị Bình", status: "active" },
    ];
    expect(decideCcAccount({ ...base, existingLink: null, posFullName: "nguyen van an", members })).toEqual({ kind: "MATCHED", ccUid: "ccA" });
  });

  it("không trùng / trùng nhiều / đã bị nối / đã bị xóa → tạo mới", () => {
    const members = [
      { uid: "ccA", name: "Lê Hoa", status: "active" },
      { uid: "ccB", name: "Le Hoa", status: "active" },
      { uid: "ccC", name: "Phạm Nam", status: "kicked" },
      { uid: "ccD", name: "Võ Lan", status: "active" },
    ];
    expect(decideCcAccount({ ...base, existingLink: null, posFullName: "Lê Hoa", members })).toEqual({ kind: "NEW", ccUid: "pos_TRAM01_u1", ambiguous: true });
    expect(decideCcAccount({ ...base, existingLink: null, posFullName: "Phạm Nam", members }).kind).toBe("NEW");
    expect(decideCcAccount({ ...base, existingLink: null, posFullName: "Võ Lan", members, takenCcUids: new Set(["ccD"]) }).kind).toBe("NEW");
    expect(decideCcAccount({ ...base, existingLink: null, posFullName: "", members }).kind).toBe("NEW");
  });

  it("trạng thái thành viên → việc cần làm", () => {
    expect(memberAction(null)).toBe("CREATE");
    expect(memberAction({ status: "active" })).toBe("OK");
    expect(memberAction({ status: "pending" })).toBe("ACTIVATE");
    expect(memberAction({ status: "kicked" })).toBe("KICKED");
  });

  it("hồ sơ thành viên mới đủ trường app chấm công đọc", () => {
    const m = buildNewMember({ ccUid: "pos_X", name: " Lan ", phone: "", employeeCode: "NV01", role: "employee" });
    expect(m).toMatchObject({ userId: "pos_X", name: "Lan", phone: null, role: "employee", status: "active", employeeType: "fulltime", standardHoursPerMonth: 208, employeeCode: "NV01" });
  });
});
