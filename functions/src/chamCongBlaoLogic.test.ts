import { describe, it, expect } from "vitest";
import { buildNewMember, mapPosRoleToCc, memberAction, normalizeName, pickStoreOwnerUid } from "./chamCongBlaoLogic";

describe("Chấm Công BLAO trên Firebase POS — logic thuần", () => {
  it("chuẩn hóa tên: bỏ dấu, đ, hoa thường, khoảng trắng", () => {
    expect(normalizeName("  Nguyễn   Thị Đào ")).toBe("nguyen thi dao");
    expect(normalizeName("NGUYEN THI DAO")).toBe("nguyen thi dao");
    expect(normalizeName("Đỗ Nguyễn Nguyên Quân")).toBe("do nguyen nguyen quan");
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

  it("chọn chủ cửa hàng từ map users RTDB", () => {
    expect(
      pickStoreOwnerUid(
        {
          u1: { roleId: "ROLE_STAFF", isRootOwner: false, isActive: true },
          u2: { roleId: "ROLE_OWNER", isRootOwner: false, isActive: true },
          u3: { roleId: "ROLE_OWNER", isRootOwner: true, isActive: true },
        },
        "u1"
      )
    ).toBe("u3");
    expect(
      pickStoreOwnerUid(
        {
          u1: { roleId: "ROLE_STAFF", isRootOwner: false, isActive: true },
          u2: { roleId: "ROLE_OWNER", isRootOwner: false, isActive: true },
        },
        "u1"
      )
    ).toBe("u2");
    expect(pickStoreOwnerUid(null, "u_fallback")).toBe("u_fallback");
  });

  it("trạng thái thành viên → việc cần làm", () => {
    expect(memberAction(null)).toBe("CREATE");
    expect(memberAction({ status: "active" })).toBe("OK");
    expect(memberAction({ status: "pending" })).toBe("ACTIVATE");
    expect(memberAction({ status: "kicked" })).toBe("KICKED");
  });

  it("hồ sơ thành viên mới đủ trường app chấm công đọc", () => {
    const m = buildNewMember({ ccUid: "uid_pos_1", name: " Lan ", phone: "", employeeCode: "NV01", role: "employee" });
    expect(m).toMatchObject({
      userId: "uid_pos_1",
      name: "Lan",
      phone: null,
      role: "employee",
      status: "active",
      employeeType: "fulltime",
      standardHoursPerMonth: 208,
      employeeCode: "NV01",
      createdVia: "pos",
    });
  });
});
