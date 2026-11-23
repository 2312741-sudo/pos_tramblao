/**
 * Chấm Công Trạm BLAO trên Firebase POS (`postramblao`) — Cloud Function `chamCongEnsureMember`.
 *
 * Người dùng chấm công sử dụng CHÍNH tài khoản Firebase Auth của POS (uid POS = uid chấm công)
 * và Firestore mặc định của `postramblao` (`stores/{storeCode}`, `stores/{storeCode}/members/{uid}`, `users/{uid}`).
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { UserProfile } from "./permissions";
import { buildNewMember, mapPosRoleToCc, memberAction, pickStoreOwnerUid } from "./chamCongBlaoLogic";

const FUNCTION_REGION = "asia-southeast1";
const db = () => admin.database();
const fs = () => admin.firestore();

function cleanStore(raw: unknown): string {
  const s = typeof raw === "string" ? raw.trim().toUpperCase() : "";
  if (!/^[A-Z0-9_-]{2,30}$/.test(s)) {
    throw new HttpsError("invalid-argument", "Mã cửa hàng không hợp lệ.");
  }
  return s;
}

const newLogId = () => `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;

async function writeAudit(storeCode: string, entry: Record<string, unknown>): Promise<void> {
  await db()
    .ref(`stores/${storeCode}/audit_logs/${newLogId()}`)
    .set({ timestamp: Date.now(), ...entry })
    .catch(() => undefined);
}

async function loadPosCaller(storeCode: string, uid: string): Promise<UserProfile & { phone?: string }> {
  const [profileSnap, indexSnap] = await Promise.all([
    db().ref(`stores/${storeCode}/users/${uid}`).get(),
    db().ref(`userIndex/${uid}/${storeCode}`).get(),
  ]);
  if (!profileSnap.exists() || indexSnap.val() !== true) {
    throw new HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
  }
  const profile = profileSnap.val() as UserProfile & { phone?: string };
  if (profile.isActive === false) {
    throw new HttpsError("permission-denied", "Tài khoản POS đã bị khóa.");
  }
  return profile;
}

/**
 * chamCongEnsureMember({ storeCode }) — Người gọi đã đăng nhập POS (`postramblao`).
 * Đảm bảo cửa hàng `stores/{storeCode}`, thành viên `stores/{storeCode}/members/{uid}`
 * và hồ sơ `users/{uid}` trên Firestore `postramblao` tồn tại & hợp lệ.
 * Trả về: `{ storeId, isNewMember }`.
 */
export const chamCongEnsureMember = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập POS trước khi sử dụng Chấm Công.");
  }
  const data = (request.data || {}) as Record<string, unknown>;
  const storeCode = cleanStore(data.storeCode);
  const uid = request.auth.uid;
  const caller = await loadPosCaller(storeCode, uid);

  const firestore = fs();
  const storeRef = firestore.collection("stores").doc(storeCode);
  const storeSnap = await storeRef.get();

  if (!storeSnap.exists) {
    const [storeInfoSnap, storeUsersSnap] = await Promise.all([
      db().ref(`stores/${storeCode}/storeInfo`).get(),
      db().ref(`stores/${storeCode}/users`).get(),
    ]);
    const info = (storeInfoSnap.val() || {}) as Record<string, unknown>;
    const usersMap = (storeUsersSnap.val() || null) as Record<
      string,
      { roleId?: string; isRootOwner?: boolean; isActive?: boolean }
    > | null;
    const ownerUid = pickStoreOwnerUid(usersMap, uid);
    const storeName = typeof info.storeName === "string" && info.storeName.trim() ? info.storeName.trim() : storeCode;
    const address = typeof info.address === "string" ? info.address.trim() : "";

    await storeRef.set(
      {
        name: storeName,
        code: storeCode,
        posStoreCode: storeCode,
        address,
        ownerId: ownerUid,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  } else if (storeSnap.get("posStoreCode") !== storeCode || storeSnap.get("code") !== storeCode) {
    await storeRef.set({ code: storeCode, posStoreCode: storeCode }, { merge: true });
  }

  const memberRef = storeRef.collection("members").doc(uid);
  const memberSnap = await memberRef.get();
  const action = memberAction(memberSnap.exists ? (memberSnap.data() as Record<string, unknown>) : null);

  if (action === "KICKED") {
    throw new HttpsError(
      "permission-denied",
      "Bạn đã bị xóa khỏi cửa hàng chấm công. Liên hệ Chủ quán.",
      { code: "CC_MEMBER_KICKED" }
    );
  }

  let isNewMember = false;
  if (action === "CREATE") {
    isNewMember = true;
    await memberRef.set({
      ...buildNewMember({
        ccUid: uid,
        name: caller.fullName || caller.username || "Nhân viên",
        phone: caller.phone,
        employeeCode: caller.employeeCode,
        role: mapPosRoleToCc(caller.roleId, caller.isRootOwner),
      }),
      joinedAt: Timestamp.now(),
    });
  } else if (action === "ACTIVATE") {
    await memberRef.set({ status: "active" }, { merge: true });
  }

  const userRef = firestore.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const needNameInit = isNewMember || !userSnap.exists || !userSnap.get("name");
  await userRef.set(
    {
      id: uid,
      ...(needNameInit
        ? {
            name: caller.fullName || caller.username || "Nhân viên",
            email: "",
            ...(userSnap.exists ? {} : { createdAt: new Date().toISOString() }),
          }
        : {}),
      currentStoreId: storeCode,
      storeIds: FieldValue.arrayUnion(storeCode),
    },
    { merge: true }
  );

  if (isNewMember) {
    await writeAudit(storeCode, {
      action: "CHAMCONG_MEMBER_CREATED",
      username: caller.username || uid,
      userFullName: caller.fullName || "",
      userRole: caller.roleId || "",
      targetType: "USER",
      targetId: uid,
      details: `Khởi tạo hồ sơ Chấm Công BLAO cho @${caller.username || uid} tại cửa hàng ${storeCode}`,
    });
  }

  return { storeId: storeCode, isNewMember };
});
