'use strict';
const { digest, canReceive } = require('./policy');
function createNotificationService(db, messaging, { Timestamp, FieldValue }, clock = () => Date.now(), accountEnabled = async () => true) {
  const inbox = (uid, storeId, scope) => scope === 'account'
    ? db.collection('notificationInboxes').doc(uid).collection('accountItems')
    : db.collection('notificationInboxes').doc(uid).collection('stores').doc(storeId).collection('items');
  async function memberContext(storeId, uid) {
    const [store, member] = await Promise.all([db.doc(`stores/${storeId}`).get(), db.doc(`stores/${storeId}/members/${uid}`).get()]);
    return { store: store.data(), member: member.data() };
  }
  async function enqueue(storeId, eventKey, plans, occurredAt) {
    // Persist a recipient manifest once: retries cannot add newly joined members.
    const eventRef = db.collection('notificationEvents').doc(digest(storeId, eventKey));
    const manifest = await db.runTransaction(async tx => {
      const existing = await tx.get(eventRef);
      if (existing.exists) return existing.data();
      const value = { storeId, eventKey, plans, occurredAt: occurredAt || Timestamp.now() };
      tx.create(eventRef, value);
      return value;
    });
    for (const item of manifest.plans) {
      if (!item.uid) continue;
      const { member, store } = await memberContext(storeId, item.uid);
      if (!canReceive(item, member, store)) continue;
      const id = digest(storeId, eventKey, item.uid, item.type);
      const ref = inbox(item.uid, storeId, item.scope).doc(id);
      const delivery = db.collection('notificationDeliveries').doc(id);
      await db.runTransaction(async tx => {
        if ((await tx.get(ref)).exists) return;
        tx.create(ref, {
          schemaVersion: 2, storeId, targetUserId: item.uid, scope: item.scope,
          eventKey, type: item.type, title: `${item.title} · ${store?.name || 'Cửa hàng'}`, body: item.body,
          createdAt: manifest.occurredAt, readAt: null,
          routePath: item.routePath || null, routeExtra: { ...item.routeExtra, storeId },
        });
        tx.create(delivery, { inboxPath: ref.path, uid: item.uid, storeId, scope: item.scope,
          status: 'pending', attempts: 0, nextAttemptAt: Timestamp.now(), sentDeviceIds: [], createdAt: Timestamp.now() });
      });
    }
  }
  async function deliver(id) {
    const ref = db.collection('notificationDeliveries').doc(id);
    const claimId = digest(id, clock(), Math.random());
    const job = await db.runTransaction(async tx => {
      const snap = await tx.get(ref);
      const value = snap.data();
      if (!value || value.status !== 'pending' || value.nextAttemptAt.toMillis() > clock()) return null;
      if (value.attempts >= 8) {
        tx.update(ref, { status: 'failed', errorCode: 'attempts-exhausted' });
        return null;
      }
      tx.update(ref, { claimId, attempts: value.attempts + 1, nextAttemptAt: Timestamp.fromMillis(clock() + 120000) });
      return { ...value, attempts: value.attempts + 1 };
    });
    if (!job) return;
    const finish = async fields => db.runTransaction(async tx => {
      const current = await tx.get(ref);
      if (current.data()?.claimId === claimId) tx.update(ref, { ...fields, updatedAt: Timestamp.now() });
    });
    try {
      const [{ store, member }, notification, user] = await Promise.all([
        memberContext(job.storeId, job.uid), db.doc(job.inboxPath).get(), db.doc(`users/${job.uid}`).get(),
      ]);
      if (!notification.exists || !user.exists || !canReceive(job, member, store) || !await accountEnabled(job.uid)) {
        await finish({ status: 'skipped', errorCode: 'recipient-no-longer-authorized' }); return;
      }
      const data = notification.data();
      if (data.scope === 'attendance' && user.data().notifyShiftInOut === false) {
        await finish({ status: 'skipped', errorCode: 'preference-disabled' }); return;
      }
      const deviceSnap = await db.collection('notificationDevices').where('uid', '==', job.uid).get();
      const devices = deviceSnap.docs.filter(d => !job.sentDeviceIds.includes(d.id));
      if (!deviceSnap.size) { await finish({ status: 'skipped', errorCode: 'no-device' }); return; }
      let retry = false;
      const sent = [...job.sentDeviceIds];
      for (const device of devices) {
        // Recheck registry ownership immediately before send (account switch).
        const current = await device.ref.get();
        if (current.data()?.uid !== job.uid) continue;
        const latestMembership = await memberContext(job.storeId, job.uid);
        if (!canReceive(job, latestMembership.member, latestMembership.store)) {
          await finish({ status: 'skipped', errorCode: 'recipient-no-longer-authorized' }); return;
        }
        try {
          await messaging.send({ token: current.data().token,
            notification: { title: 'Chấm Công Trạm', body: 'Bạn có thông báo mới. Mở ứng dụng để xem.' },
            data: { notificationId: id, targetUserId: job.uid, storeId: job.storeId, scope: job.scope, routePath: '/notifications' },
            android: { collapseKey: id, notification: { tag: id, channelId: 'cham_cong_notifications' } },
            apns: { headers: { 'apns-collapse-id': id }, payload: { aps: { sound: 'default' } } },
          });
          sent.push(device.id);
          await finish({ sentDeviceIds: [...sent] });
        } catch (error) {
          if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(error.code)) {
            await db.runTransaction(async tx => {
              const latest = await tx.get(device.ref);
              if (latest.data()?.uid === job.uid && latest.data()?.token === current.data().token) tx.delete(device.ref);
            });
          } else {
            retry = true;
            console.error('notification_delivery_error', { id, code: error.code || 'unknown', attempt: job.attempts });
          }
        }
      }
      await finish({ status: retry ? (job.attempts >= 8 ? 'failed' : 'pending') : (sent.length ? 'sent' : 'skipped'),
        sentDeviceIds: sent, nextAttemptAt: Timestamp.fromMillis(clock() + Math.min(3600000, 30000 * 2 ** job.attempts)),
        ...(retry ? { errorCode: 'push-delivery-failed' } : { sentAt: Timestamp.now() }) });
    } catch (error) {
      await finish({ status: job.attempts >= 8 ? 'failed' : 'pending', errorCode: error.code || 'internal',
        nextAttemptAt: Timestamp.fromMillis(clock() + Math.min(3600000, 30000 * 2 ** job.attempts)) });
      throw error;
    }
  }
  return { enqueue, deliver };
}
module.exports = { createNotificationService };
