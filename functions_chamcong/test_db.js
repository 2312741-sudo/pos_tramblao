const admin = require('firebase-admin');
admin.initializeApp();

async function run() {
  console.log("Querying advances...");
  const snap = await admin.firestore().collectionGroup('advances').get();
  console.log("Advances count:", snap.size);
  snap.forEach(doc => {
    console.log(doc.ref.path, doc.data());
  });
  console.log("Done.");
  process.exit(0);
}

run().catch(console.error);
