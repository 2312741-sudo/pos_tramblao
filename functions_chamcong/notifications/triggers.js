'use strict';
const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const { createNotificationService } = require('./service');
const { digest, roleOf, changedUsers, plan, schedulePlans, advancePlans, membershipPlans, attendancePlans, days } = require('./policy');
const db = admin.firestore();
const service = createNotificationService(db, admin.messaging(), admin.firestore, Date.now, async uid => {
  try { return !(await admin.auth().getUser(uid)).disabled; }
  catch (error) { if (error.code === 'auth/user-not-found') return false; throw error; }
});
const trigger = functions.region('asia-southeast1').runWith({ failurePolicy: true, timeoutSeconds: 120 });
async function contextFor(storeId) {
  const [store, members] = await Promise.all([db.doc(`stores/${storeId}`).get(), db.collection(`stores/${storeId}/members`).get()]);
  return { store: store.data(), members: Object.fromEntries(members.docs.map(d => [d.id, d.data()])) };
}
async function emit(context, snapshot, plans) {
  return service.enqueue(context.params.storeId, context.eventId, plans, snapshot.updateTime || snapshot.createTime);
}
exports.onScheduleChanged = trigger.firestore.document('stores/{storeId}/schedules/{scheduleId}').onWrite(async (change, context) => {
  const { members, store } = await contextFor(context.params.storeId);
  if (!store || store.status === 'deleted') return;
  return emit(context, change.after, schedulePlans(change.before.data(), change.after.data(), members, context.params.scheduleId));
});
exports.onAdvanceCreated = trigger.firestore.document('stores/{storeId}/advances/{advanceId}').onCreate(async (snap, context) => {
  const { members, store } = await contextFor(context.params.storeId);
  if (!store || store.status === 'deleted') return;
  return emit(context, snap, advancePlans(null, snap.data(), members, store, context.params.advanceId));
});
exports.onAdvanceUpdated = trigger.firestore.document('stores/{storeId}/advances/{advanceId}').onUpdate(async (change, context) => {
  const { members, store } = await contextFor(context.params.storeId);
  if (!store || store.status === 'deleted') return;
  return emit(context, change.after, advancePlans(change.before.data(), change.after.data(), members, store, context.params.advanceId));
});
exports.onMemberNotificationChanged = trigger.firestore.document('stores/{storeId}/members/{memberId}').onWrite(async (change, context) => {
  const { members, store } = await contextFor(context.params.storeId);
  if (!store || store.status === 'deleted') return;
  return emit(context, change.after, membershipPlans(change.before.data(), change.after.data(), members, context.params.memberId));
});
exports.onAttendanceNotificationChanged = trigger.firestore.document('stores/{storeId}/attendances/{attendanceId}').onWrite(async (change, context) => {
  const { members, store } = await contextFor(context.params.storeId);
  if (!store || store.status === 'deleted') return;
  return emit(context, change.after, attendancePlans(change.before.data(), change.after.data(), members, context.params.attendanceId));
});
exports.onStoreNotificationDeleted = trigger.firestore.document('stores/{storeId}').onUpdate(async (change, context) => {
  if (change.before.data().status === 'deleted' || change.after.data().status !== 'deleted') return;
  const { members } = await contextFor(context.params.storeId);
  const plans = Object.entries(members).filter(([uid, m]) => m.status === 'active' && uid !== change.after.data().deletedBy)
    .map(([uid]) => plan(uid, 'account', 'store_deleted', 'Cửa hàng đã đóng', 'Cửa hàng đã bị xóa bởi chủ cửa hàng.', null));
  return emit(context, change.after, plans);
});

exports.onNotificationDeliveryCreated = trigger.firestore.document('notificationDeliveries/{deliveryId}').onCreate((snap, context) => service.deliver(context.params.deliveryId));
exports.retryNotificationDeliveries = functions.region('asia-southeast1').runWith({ timeoutSeconds: 120 }).pubsub.schedule('every 1 minutes').onRun(async () => {
  const jobs = await db.collection('notificationDeliveries').where('status', '==', 'pending')
    .where('nextAttemptAt', '<=', admin.firestore.Timestamp.now()).orderBy('nextAttemptAt').limit(100).get();
  // Bound concurrent sends; a failed job must not prevent other recipients from retrying.
  for (let offset = 0; offset < jobs.size; offset += 10) {
    await Promise.allSettled(jobs.docs.slice(offset, offset + 10).map(doc => service.deliver(doc.id)));
  }
});
function requireAuth(context) {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Vui lòng đăng nhập.');
  return context.auth.uid;
}
exports.registerNotificationDevice = functions.region('asia-southeast1').https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const token = data?.token;
  if (typeof token !== 'string' || token.length < 20 || token.length > 4096) throw new functions.https.HttpsError('invalid-argument', 'Token không hợp lệ.');
  const ref = db.collection('notificationDevices').doc(digest(token));
  // A token has exactly one account owner; clients cannot enumerate other accounts' tokens.
  await db.runTransaction(async tx => {
    const current = await tx.get(ref);
    if (data.remove !== true && current.data()?.uid !== uid) {
      const devices = await tx.get(db.collection('notificationDevices').where('uid', '==', uid).limit(20));
      if (devices.size >= 20) throw new functions.https.HttpsError('resource-exhausted', 'Đã đạt giới hạn thiết bị thông báo.');
    }
    if (data.remove === true) {
      if (current.data()?.uid === uid) tx.delete(ref);
    } else tx.set(ref, { uid, token, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  });
  return { registered: data.remove !== true };
});

// All scheduled notifications are generated server-side with deterministic calendar keys.
const dateString = date => date.toISOString().slice(0, 10);
const monday = date => { const copy = new Date(date); copy.setUTCDate(copy.getUTCDate() - ((copy.getUTCDay() + 6) % 7)); return dateString(copy); };
// Cron chạy MỘT LẦN DUY NHẤT mỗi ngày vào 08:00 sáng (Asia/Ho_Chi_Minh).
// Thay thế hàm shiftReminders cũ (chạy 5 phút/lần, ngốn ~28.000 lượt đọc Firestore/ngày).
// Xử lý: (1) Chúc mừng sinh nhật thành viên, (2) Nhắc đăng ký lịch tuần tới vào Thứ Năm.
// Nhắc ca làm việc đã được chuyển hoàn toàn sang Local Scheduled Notification trên thiết bị người dùng.
exports.dailyMorningDigest = functions.region('asia-southeast1').runWith({ timeoutSeconds: 300 }).pubsub.schedule('0 8 * * *').timeZone('Asia/Ho_Chi_Minh').retryConfig({retryCount: 3, minBackoffSeconds: 30, maxBackoffSeconds: 300}).onRun(async context => {
  const instant = new Date(context.timestamp);
  const local = new Date(instant.getTime() + 7 * 3600000);
  const stores = await db.collection('stores').get();
  for (const storeDoc of stores.docs) {
    const store = storeDoc.data();
    if (store.status === 'deleted') continue;
    const { members } = await contextFor(storeDoc.id);
    const active = Object.entries(members).filter(([, m]) => m.status === 'active');
    const today = dateString(local);

    // 1. Chúc mừng sinh nhật
    const birthdayPlans = [];
    for (const [uid, member] of active) {
      let birthday = member.birthday;
      if (!birthday) birthday = (await db.doc(`users/${uid}`).get()).data()?.birthday;
      const date = birthday?.toDate ? new Date(birthday.toDate().getTime() + 7 * 3600000) : new Date(birthday);
      if (birthday && Number.isFinite(date.getTime()) && date.getUTCMonth() === local.getUTCMonth() && date.getUTCDate() === local.getUTCDate()) {
        birthdayPlans.push(...active.map(([recipient]) => plan(recipient, 'member', 'birthday', 'Chúc mừng sinh nhật', `Hôm nay là sinh nhật của ${member.name || 'một thành viên'}. Cùng gửi lời chúc mừng nhé!`, null, { memberId: uid })));
        await service.enqueue(storeDoc.id, `birthday:${uid}:${today}`, birthdayPlans.splice(0), admin.firestore.Timestamp.fromDate(instant));
      }
    }

    // 2. Nhắc đăng ký lịch tuần tới vào Thứ Năm
    if (local.getUTCDay() === 4) {
      const next = new Date(local); next.setUTCDate(next.getUTCDate() + 7);
      const weekStart = monday(next);
      await service.enqueue(storeDoc.id, `registration:${weekStart}`, active.map(([uid]) => plan(uid, 'member', 'schedule_registration_reminder',
        'Nhắc đăng ký lịch tuần tới', `Vui lòng hoàn tất đăng ký lịch tuần ${weekStart} trước 23:59 Thứ Sáu.`, '/schedule', { weekStart })), admin.firestore.Timestamp.fromDate(instant));
    }
  }
});
exports.requestChecklistNotification = functions.region('asia-southeast1').https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const { storeId, attendanceId } = data || {};
  if (![storeId, attendanceId].every(v => typeof v === 'string' && v.length && !v.includes('/'))) throw new functions.https.HttpsError('invalid-argument', 'Dữ liệu không hợp lệ.');
  const attendance = (await db.doc(`stores/${storeId}/attendances/${attendanceId}`).get()).data();
  if (!attendance || attendance.userId !== uid || attendance.checkOut) throw new functions.https.HttpsError('permission-denied', 'Không có ca làm hợp lệ.');
  const report = await db.collection(`stores/${storeId}/production_reports`).where('userId', '==', uid).where('date', '==', attendance.date).limit(1).get();
  if (report.empty) await service.enqueue(storeId, `checklist:${attendanceId}`, [plan(uid, 'member', 'checklist_reminder',
    'Chưa nộp báo cáo sản xuất', 'Vui lòng hoàn tất báo cáo sản xuất trước khi kết thúc ca.', '/check-in', { attendanceId, date: attendance.date })]);
  return { ok: true };
});
exports.onStoreOwnershipNotificationChanged = trigger.firestore.document('stores/{storeId}').onUpdate(async (change, context) => {
  const before = change.before.data(), after = change.after.data();
  if (before.ownerId === after.ownerId || !after.ownerId || after.status === 'deleted') return;
  const { members } = await contextFor(context.params.storeId);
  const name = members[after.ownerId]?.name || 'Thành viên';
  const plans = Object.entries(members).filter(([, member]) => member.status === 'active').map(([uid]) =>
    plan(uid, 'member', uid === after.ownerId ? 'ownership_transferred' : 'new_owner_assigned',
      uid === after.ownerId ? 'Bạn đã trở thành chủ cửa hàng' : 'Cửa hàng có chủ mới',
      `${name} đã nhận quyền chủ cửa hàng.`, uid === after.ownerId ? '/splash' : null));
  return emit(context, change.after, plans);
});
