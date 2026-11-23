const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
admin.initializeApp();
Object.assign(exports, require('./notifications/triggers'));

// 6. Trigger when a Firebase Auth user is deleted (Console or Admin SDK)
// Đảm bảo đồng nhất dữ liệu: tự động dọn dẹp các subcollection members và /users/{uid}
exports.onUserDeleted = functions.region('asia-southeast1').auth.user().onDelete(async (user) => {
  const uid = user.uid;
  console.log(`[onUserDeleted] User ${uid} deleted from Auth. Starting Firestore cleanup...`);

  const db = admin.firestore();

  try {
    const storeIds = new Set();

    // 1. Kiểm tra /users/{uid} document
    const userDoc = await db.collection('users').doc(uid).get();
    if (userDoc.exists) {
      const data = userDoc.data() || {};
      (data.storeIds || []).forEach(id => { if (id) storeIds.add(id); });
      if (data.currentStoreId) storeIds.add(data.currentStoreId);
    }

    // 2. Tìm tất cả store subcollections qua collectionGroup('members')
    try {
      const memberDocs = await db.collectionGroup('members')
        .where('userId', '==', uid)
        .get();

      memberDocs.forEach(mDoc => {
        const storeRef = mDoc.ref.parent.parent;
        if (storeRef && storeRef.id) {
          storeIds.add(storeRef.id);
        }
      });
    } catch (e) {
      console.warn('[onUserDeleted] collectionGroup members query warning:', e);
    }

    // 3. Mark status = 'kicked' trong tất cả cửa hàng, chuyển quyền nếu là Chủ & dọn dẹp memberOrder
    for (const storeId of storeIds) {
      try {
        const storeRef = db.collection('stores').doc(storeId);
        const storeSnap = await storeRef.get();
        const isOwner = storeSnap.exists && storeSnap.data().ownerId === uid;

        if (isOwner) {
          // Tìm QL1 hoặc người kế nhiệm thích hợp
          const membersSnap = await storeRef.collection('members')
            .where('status', '==', 'active')
            .get();

          const candidates = [];
          membersSnap.forEach(d => {
            if (d.id !== uid) {
              candidates.push({ id: d.id, ...d.data() });
            }
          });

          function compareCandidates(a, b) {
            const timeA = a.joinedAt ? (a.joinedAt.toMillis ? a.joinedAt.toMillis() : new Date(a.joinedAt).getTime()) : 0;
            const timeB = b.joinedAt ? (b.joinedAt.toMillis ? b.joinedAt.toMillis() : new Date(b.joinedAt).getTime()) : 0;
            if (timeA !== timeB) return timeA - timeB;
            return String(a.id || '').localeCompare(String(b.id || ''));
          }

          let nextOwnerId = null;
          let nextOwnerName = '';
          let promotedFromRole = '';

          if (candidates.length > 0) {
            // 1. Ưu tiên Quản lý 1
            const ql1List = candidates.filter(m => m.role === 'manager_1' || m.role === 'manager1' || m.role === 'manager');
            if (ql1List.length > 0) {
              ql1List.sort(compareCandidates);
              nextOwnerId = ql1List[0].id;
              nextOwnerName = ql1List[0].name || '';
              promotedFromRole = ql1List[0].role || 'manager_1';
            } else {
              // 2. Quản lý 2
              const ql2List = candidates.filter(m => m.role === 'manager_2' || m.role === 'manager2');
              if (ql2List.length > 0) {
                ql2List.sort(compareCandidates);
                nextOwnerId = ql2List[0].id;
                nextOwnerName = ql2List[0].name || '';
                promotedFromRole = ql2List[0].role || 'manager_2';
              } else {
                // 3. Nhân viên thâm niên nhất
                candidates.sort(compareCandidates);
                nextOwnerId = candidates[0].id;
                nextOwnerName = candidates[0].name || '';
                promotedFromRole = candidates[0].role || 'employee';
              }
            }
          }

          if (nextOwnerId) {
            const batch = db.batch();
            batch.update(storeRef, {
              ownerId: nextOwnerId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            batch.update(storeRef.collection('members').doc(nextOwnerId), {
              role: 'owner',
              promotedAt: admin.firestore.FieldValue.serverTimestamp(),
              promotedReason: 'auth_account_deleted',
              promotedFrom: promotedFromRole
            });
            const auditRef = storeRef.collection('audit_logs').doc();
            batch.set(auditRef, {
              action: 'ownership_inheritance',
              storeId,
              previousOwnerId: uid,
              newOwnerId: nextOwnerId,
              newOwnerName: nextOwnerName,
              promotedFromRole: promotedFromRole,
              reason: 'auth_account_deleted',
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              source: 'cloud_function_onUserDeleted',
              isOrphaned: false
            });
            await batch.commit();
            console.log(`[onUserDeleted] Transferred ownership of store ${storeId} to user ${nextOwnerId} (${nextOwnerName})`);
          } else {
            const batch = db.batch();
            batch.update(storeRef, {
              status: 'orphaned',
              ownerId: '',
              orphanedAt: admin.firestore.FieldValue.serverTimestamp(),
              orphanedReason: 'no_successor_available',
              orphanedBy: uid
            });
            const auditRef = storeRef.collection('audit_logs').doc();
            batch.set(auditRef, {
              action: 'store_orphaned',
              storeId,
              previousOwnerId: uid,
              reason: 'auth_account_deleted',
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              source: 'cloud_function_onUserDeleted',
              isOrphaned: true
            });
            await batch.commit();
            console.log(`[onUserDeleted] No remaining members. Marked store ${storeId} as orphaned`);
          }
        }

        const memberRef = storeRef.collection('members').doc(uid);
        const memberDoc = await memberRef.get();
        if (memberDoc.exists) {
          await memberRef.update({
            status: 'kicked',
            kickedAt: admin.firestore.FieldValue.serverTimestamp(),
            kickedReason: 'account_deleted_firebase_auth'
          });
        }

        // Xóa khỏi memberOrder và hiddenScheduleUserIds
        await storeRef.update({
          memberOrder: admin.firestore.FieldValue.arrayRemove(uid),
          hiddenScheduleUserIds: admin.firestore.FieldValue.arrayRemove(uid)
        });
        console.log(`[onUserDeleted] Cleaned membership in store ${storeId} for user ${uid}`);
      } catch (err) {
        console.error(`[onUserDeleted] Error cleaning store ${storeId} for user ${uid}:`, err);
      }
    }


    // 4. Xóa document /users/{uid} nếu vẫn còn
    if (userDoc.exists) {
      await db.collection('users').doc(uid).delete();
      console.log(`[onUserDeleted] Deleted /users/${uid} document`);
    }

    // 5. Dọn thiết bị thông báo & hộp thư thông báo Firestore của uid (không đụng dữ liệu POS RTDB)
    try {
      const devicesSnap = await db.collection('notificationDevices').where('uid', '==', uid).get();
      if (!devicesSnap.empty) {
        const batch = db.batch();
        devicesSnap.docs.forEach(d => batch.delete(d.ref));
        await batch.commit();
      }
      const inboxRef = db.collection('notificationInboxes').doc(uid);
      const accountItems = await inboxRef.collection('accountItems').get();
      if (!accountItems.empty) {
        const batch = db.batch();
        accountItems.docs.forEach(d => batch.delete(d.ref));
        await batch.commit();
      }
      const storeInboxes = await inboxRef.collection('stores').listDocuments();
      for (const sRef of storeInboxes) {
        const items = await sRef.collection('items').get();
        if (!items.empty) {
          const batch = db.batch();
          items.docs.forEach(d => batch.delete(d.ref));
          await batch.commit();
        }
      }
    } catch (cleanupErr) {
      console.warn(`[onUserDeleted] Notification cleanup warning for ${uid}:`, cleanupErr);
    }
  } catch (error) {
    console.error(`[onUserDeleted] Fatal error during cleanup for user ${uid}:`, error);
  }

  return null;
});

