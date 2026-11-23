const admin = require('firebase-admin');
admin.initializeApp();

async function testPush() {
  const usersSnap = await admin.firestore().collection('users').get();
  const tokens = [];
  usersSnap.forEach(doc => {
    if (doc.data().fcmToken) tokens.push(doc.data().fcmToken);
  });

  if (tokens.length === 0) {
    console.log('No tokens found');
    return;
  }

  console.log('Found tokens:', tokens);

  const message = {
    notification: {
      title: 'Cap nhat lich lam viec',
      body: 'Lich lam viec cua Cua hang vua co thay doi. Bam de xem chi tiet.',
    },
    data: {
      type: 'schedule_update',
      storeId: 'test_store',
    },
    android: {
      notification: {
        channelId: 'schedule_updates',
      }
    },
    tokens: tokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log('Sent ' + response.successCount + ' notifications, ' + response.failureCount + ' failures');
  } catch (error) {
    console.error('Error sending:', error);
  }
}

testPush().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
