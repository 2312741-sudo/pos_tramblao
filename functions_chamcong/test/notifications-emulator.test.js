const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, getDocs, updateDoc, collection, query, where, orderBy, limit, serverTimestamp, onSnapshot, writeBatch } = require('firebase/firestore');
const admin = require('firebase-admin');
const { createNotificationService } = require('../notifications/service');
const { plan, digest } = require('../notifications/policy');
let env, db, app, triggers;
const projectId = 'demo-chamcong-notifications';
const item = (scope='member', uid='e1') => ({ storeId:'s',targetUserId:uid,scope,readAt:null,createdAt:admin.firestore.Timestamp.now(),type:'schedule_changed',title:'test',body:'test' });
const path = (uid='e1', id='n') => `notificationInboxes/${uid}/stores/s/items/${id}`;
const client = uid => env.authenticatedContext(uid).firestore();
before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Emulator only; refusing live database access');
  env = await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});
  app=admin.initializeApp({projectId}); db=app.firestore(); triggers=require('../notifications/triggers');
});
after(async () => { await env?.cleanup(); await app?.delete(); });
beforeEach(async () => {
  await env.clearFirestore();
  await db.doc('stores/s').set({ownerId:'owner',status:'active'});
  for(const [uid,role] of Object.entries({owner:'owner',m1:'manager_1',m2:'manager_2',e1:'employee',e2:'employee'})) {
    await db.doc(`stores/s/members/${uid}`).set({userId:uid,role,status:'active'});
    await db.doc(`users/${uid}`).set({name:uid});
  }
});
test('own inbox query succeeds; other users, anonymous, legacy collection and forgery fail',async()=>{
  await db.doc(path()).set(item());
  const e1=client('e1');
  await assertSucceeds(getDocs(query(collection(e1,'notificationInboxes/e1/stores/s/items'),where('scope','in',['member']),orderBy('createdAt','desc'),limit(50))));
  await assertFails(getDoc(doc(client('e2'),path())));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),path())));
  await assertFails(setDoc(doc(e1,path('e1','forged')),{...item(),createdAt:new Date()}));
  await assertFails(getDocs(collection(e1,'stores/s/notifications')));
  await assertFails(setDoc(doc(e1,'stores/s/notifications/forged'),{...item(),createdAt:new Date()}));
  await assertFails(getDocs(collection(e1,'notificationDevices')));
  await assertFails(getDocs(collection(e1,'notificationDeliveries')));
});
test('only readAt server timestamp may be updated; unread streams synchronize between sessions',async()=>{
  await db.doc(path()).set(item()); const e1=client('e1');
  await assertFails(updateDoc(doc(e1,path()),{title:'forged'}));
  await assertFails(updateDoc(doc(e1,path()),{scope:'owner'}));
  await assertFails(updateDoc(doc(client('e2'),path()),{readAt:serverTimestamp()}));
  const source=query(collection(e1,'notificationInboxes/e1/stores/s/items'),where('scope','in',['member']),where('readAt','==',null));
  const values=[];
  await new Promise((resolve,reject)=>{
    const stop=onSnapshot(source,async snap=>{
      values.push(snap.size);
      if(snap.size===1) await updateDoc(doc(client('e1'),path()),{readAt:serverTimestamp()});
      if(snap.size===0) {stop();resolve();}
    },reject);
  });
  assert.ok(values.includes(1)); assert.equal(values.at(-1),0);
});
test('role downgrade and membership revocation deny historical sensitive inbox access',async()=>{
  await db.doc(path('m1')).set(item('attendance','m1'));
  await assertSucceeds(getDoc(doc(client('m1'),path('m1'))));
  await db.doc('stores/s/members/m1').update({role:'manager_2'});
  await assertFails(getDoc(doc(client('m1'),path('m1'))));
  await db.doc(path()).set(item());
  await db.doc('stores/s/members/e1').update({status:'kicked'});
  await assertFails(getDoc(doc(client('e1'),path())));
  await db.doc('notificationInboxes/e1/accountItems/rejected').set(item('account'));
  await assertSucceeds(getDoc(doc(client('e1'),'notificationInboxes/e1/accountItems/rejected')));
});
test('cannot grant oneself role, alter store owner or write schedules directly',async()=>{
  const e1=client('e1');
  await assertFails(updateDoc(doc(e1,'stores/s/members/e1'),{role:'owner'}));
  await assertFails(updateDoc(doc(e1,'stores/s'),{ownerId:'e1'}));
  await assertFails(setDoc(doc(e1,'stores/s/schedules/2026-09-07'),{updatedBy:'owner',shifts:{}}));
  await assertFails(setDoc(doc(e1,'stores/s/members/attacker'),{userId:'attacker',role:'owner',status:'active'}));
});
test('advance recipient authorization matches source authorization',async()=>{
  await db.doc('stores/s/advances/a').set({userId:'e1',storeId:'s',status:'pending',amount:100});
  await assertFails(getDoc(doc(client('m1'),'stores/s/advances/a')));
  await assertFails(updateDoc(doc(client('m1'),'stores/s/advances/a'),{status:'approved'}));
  await assertSucceeds(updateDoc(doc(client('owner'),'stores/s/advances/a'),{status:'approved'}));
  await assertSucceeds(getDoc(doc(client('e1'),'stores/s/advances/a')));
  await assertFails(getDoc(doc(client('e2'),'stores/s/advances/a')));
});
test('concurrent event retries atomically create one inbox item and one outbox job',async()=>{
  const service=createNotificationService(db,{send:()=>{throw Error('must not send')}},admin.firestore);
  const plans=[plan('e1','member','schedule_changed','same title','same body','/schedule')];
  await Promise.all(Array.from({length:8},()=>service.enqueue('s','event1',plans)));
  assert.equal((await db.collection('notificationDeliveries').get()).size,1);
  assert.equal((await db.collection('notificationInboxes/e1/stores/s/items').get()).size,1);
  // A distinct event with identical content remains distinct.
  await service.enqueue('s','event2',plans);
  assert.equal((await db.collection('notificationDeliveries').get()).size,2);
  // A retry cannot expand the original recipient manifest.
  await service.enqueue('s','event1',[...plans,plan('e2','member','schedule_changed','same','same','/schedule')]);
  assert.equal((await db.collection('notificationInboxes/e2/stores/s/items').get()).size,0);
});
test('send lease prevents parallel sends; failed device retries without resending successful devices',async()=>{
  let now=Date.now()+1000;const calls=[];let failures=1;
  const service=createNotificationService(db,{send:async message=>{
    calls.push(message.token);
    if(message.token==='bad' && failures-->0) {const error=Error('transient');error.code='messaging/internal-error';throw error;}
  }},admin.firestore,()=>now);
  await db.doc('notificationDevices/good').set({uid:'e1',token:'good'});
  await db.doc('notificationDevices/bad').set({uid:'e1',token:'bad'});
  await service.enqueue('s','event',[plan('e1','member','schedule_changed','t','b','/schedule')]);
  const id=digest('s','event','e1','schedule_changed');
  await Promise.all([service.deliver(id),service.deliver(id)]);
  assert.equal(calls.filter(v=>v==='good').length,1);
  assert.equal((await db.doc(`notificationDeliveries/${id}`).get()).data().status,'pending');
  now+=4000000;await service.deliver(id);
  assert.equal(calls.filter(v=>v==='good').length,1);
  assert.equal(calls.filter(v=>v==='bad').length,2);
  assert.equal((await db.doc(`notificationDeliveries/${id}`).get()).data().status,'sent');
});
test('revoked member and disabled attendance preference skip queued push but preserve inbox',async()=>{
  let count=0;const service=createNotificationService(db,{send:async()=>count++},admin.firestore,()=>Date.now()+1000);
  await service.enqueue('s','event',[plan('m1','attendance','check_in','t','b','/attendance-table')]);
  await db.doc('notificationDevices/m1').set({uid:'m1',token:'token'});
  await db.doc('users/m1').update({notifyShiftInOut:false});
  const id=digest('s','event','m1','check_in');await service.deliver(id);
  assert.equal(count,0);assert.equal((await db.doc(`notificationDeliveries/${id}`).get()).data().status,'skipped');
  assert.equal((await db.collection('notificationInboxes/m1/stores/s/items').get()).size,1);
  await service.enqueue('s','event2',[plan('e1','member','schedule_changed','t','b','/schedule')]);
  await db.doc('stores/s/members/e1').update({status:'kicked'});
  await service.deliver(digest('s','event2','e1','schedule_changed'));
  assert.equal(count,0);
});
test('account result is readable after soft deletion, store-scoped history is denied',async()=>{
  await db.doc(path()).set(item());await db.doc('notificationInboxes/e1/accountItems/deleted').set(item('account'));
  await db.doc('stores/s').update({status:'deleted'});
  await assertFails(getDoc(doc(client('e1'),path())));
  await assertSucceeds(getDoc(doc(client('e1'),'notificationInboxes/e1/accountItems/deleted')));
});

test('device ownership switches atomically and stale logout cannot unregister new account',async()=>{
  const token='example-emulator-device-token';
  await triggers.registerNotificationDevice.run({token},{auth:{uid:'e1'}});
  await triggers.registerNotificationDevice.run({token},{auth:{uid:'e2'}});
  await triggers.registerNotificationDevice.run({token,remove:true},{auth:{uid:'e1'}});
  assert.equal((await db.doc(`notificationDevices/${digest(token)}`).get()).data().uid,'e2');
  await triggers.registerNotificationDevice.run({token,remove:true},{auth:{uid:'e2'}});
  assert.equal((await db.doc(`notificationDevices/${digest(token)}`).get()).exists,false);
});
test('atomic owner transfer is allowed only to an active successor; self-leave cannot edit other members',async()=>{
  const owner=client('owner');
  const batch=writeBatch(owner);
  batch.update(doc(owner,'stores/s'),{ownerId:'m1'});
  batch.update(doc(owner,'stores/s/members/m1'),{role:'owner'});
  batch.update(doc(owner,'stores/s/members/owner'),{role:'manager_1'});
  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(doc(client('e1'),'stores/s/members/e2'),{status:'kicked',kickedReason:'member_left'}));
  await assertSucceeds(updateDoc(doc(client('e1'),'stores/s/members/e1'),{status:'kicked',kickedReason:'member_left',kickedAt:serverTimestamp()}));
});
test('membership onboarding and reapply preserve source authorization',async()=>{
  const uid='new'; const user=client(uid);
  const application={userId:uid,name:'New',role:'employee',status:'pending',employeeType:'fulltime',baseMonthlySalary:0,baseHourlyRate:0,standardHoursPerMonth:208,joinedAt:new Date()};
  await assertFails(setDoc(doc(user,'stores/s/members/new'),{...application,baseMonthlySalary:999999}));
  await assertSucceeds(setDoc(doc(user,'stores/s/members/new'),application));
  await assertSucceeds(updateDoc(doc(client('m1'),'stores/s/members/new'),{status:'kicked',approvedBy:'m1',approvedAt:serverTimestamp()}));
  await assertSucceeds(setDoc(doc(user,'stores/s/members/new'),application));
  await assertFails(updateDoc(doc(client('m2'),'stores/s/members/new'),{status:'active'}));
});
test('disabled account skips delivery; repeated failures stop after eight attempts',async()=>{
  const service=createNotificationService(db,{send:async()=>{throw Error('must not send')}},admin.firestore,()=>Date.now()+1000,async()=>false);
  await service.enqueue('s','disabled',[plan('e1','member','schedule_changed','t','b','/schedule')]);
  const id=digest('s','disabled','e1','schedule_changed');
  await service.deliver(id);
  assert.equal((await db.doc(`notificationDeliveries/${id}`).get()).data().status,'skipped');
  await db.doc(`notificationDeliveries/${id}`).update({status:'pending',attempts:8,nextAttemptAt:admin.firestore.Timestamp.fromMillis(0)});
  await service.deliver(id);
  assert.equal((await db.doc(`notificationDeliveries/${id}`).get()).data().status,'failed');
});
test('Thursday reminder and timestamp birthday use Vietnam date and deduplicate calendar events',async()=>{
  await db.doc('users/e1').update({birthday:admin.firestore.Timestamp.fromDate(new Date('1999-09-09T17:00:00Z'))});
  const context={timestamp:'2026-09-10T01:00:00Z'}; // Thursday 08:00 Vietnam.
  await triggers.dailyMorningDigest.run(context);await triggers.dailyMorningDigest.run(context);
  const result=await db.collection('notificationInboxes/e1/stores/s/items').get();
  assert.equal(result.size,2);
  assert.deepEqual(result.docs.map(d=>d.data().type).sort(),['birthday','schedule_registration_reminder']);
  assert.equal(result.docs.find(d=>d.data().type==='schedule_registration_reminder').data().routeExtra.weekStart,'2026-09-14');
});
