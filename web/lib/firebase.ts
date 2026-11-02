// lib/firebase.ts
import { initializeApp, getApps } from "firebase/app";
import { getDatabase, onValue, ref } from "firebase/database";
import { getFirestore } from "firebase/firestore";
import { getAuth } from "firebase/auth";
import { getFunctions } from "firebase/functions";

const firebaseConfig = {
  apiKey: "AIzaSyB6Sk10Xy9tIi4uYgdpT5ohyajr6863ybk",
  authDomain: "postramblao.firebaseapp.com",
  databaseURL: "https://postramblao-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "postramblao",
  storageBucket: "postramblao.firebasestorage.app",
  messagingSenderId: "351954155486",
  appId: "1:351954155486:web:4dbd4ecf4cff30f3a10f4f",
};

// Kiểm tra tính đồng nhất của cấu hình Firebase khi khởi động
if (firebaseConfig.databaseURL && firebaseConfig.projectId) {
  if (!firebaseConfig.databaseURL.includes(firebaseConfig.projectId)) {
    const errorMsg = `[LỖI CẤU HÌNH FIREBASE] projectId ("${firebaseConfig.projectId}") không khớp với project trong databaseURL ("${firebaseConfig.databaseURL}"). Vui lòng kiểm tra lại cấu hình Firebase!`;
    console.error(errorMsg);
    if (process.env.NODE_ENV !== "production") {
      throw new Error(errorMsg);
    }
  }
}

const app = getApps().length === 0 ? initializeApp(firebaseConfig) : getApps()[0];
export const db = getDatabase(app);
export const firestore = getFirestore(app);
export const auth = getAuth(app);
export const functions = getFunctions(app, "asia-southeast1");
export { firebaseConfig };
export default app;

/**
 * Đồng hồ máy chạy NHANH hơn máy chủ → rules từ chối nhật ký thao tác có timestamp "ở tương lai"
 * (PERMISSION_DENIED khi mở ca, xóa món, thanh toán...). Lấy độ lệch từ `.info/serverTimeOffset`
 * và kéo Date.now() về giờ máy chủ để mọi timestamp web ghi đều khớp giờ Firebase.
 */
if (typeof window !== "undefined") {
  const clientNow = Date.now.bind(Date);
  let offset = 0;
  Date.now = () => clientNow() + offset;
  onValue(ref(db, ".info/serverTimeOffset"), (snap) => {
    const v = Number(snap.val());
    // Chỉ kéo lùi khi máy nhanh hơn máy chủ (offset âm); máy chậm thì rules vẫn chấp nhận
    offset = Number.isFinite(v) && v < 0 ? v : 0;
  });
}
