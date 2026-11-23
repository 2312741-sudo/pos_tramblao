const { test } = require('node:test');
const assert = require('node:assert/strict');
const p = require('../notifications/policy');
const members = { owner: { role: 'owner', status: 'active' }, m1: { role: 'manager_1', status: 'active' },
  legacy: { role: 'manager', status: 'active' }, m2: { role: 'manager_2', status: 'active' }, e1: { role: 'employee', status: 'active' },
  e2: { role: 'employee', status: 'active' }, kicked: { role: 'owner', status: 'kicked' } };
test('manager2 cannot receive attendance or approval; missing and inactive membership denied', () => {
  assert.deepEqual(p.allowedScopes(members.m2, {}), ['member']);
  assert.deepEqual(p.allowedScopes(members.kicked, {}), []);
  assert.deepEqual(p.allowedScopes(undefined, {}), []);
  assert.deepEqual(p.allowedScopes(members.owner, {status:'deleted'}), []);
  assert.deepEqual(p.allowedScopes({role:'unknown',status:'active'}, {}), []);
});
test('role aliases consistently retain legacy manager1 permissions', () => {
  for (const role of ['manager1','manager_1','manager','legacyManager']) assert.equal(p.roleOf(role), 'manager1');
});
test('only affected member receives a management change, including removal', () => {
  const before = { shifts: {e1:{monday:['morning']},e2:{monday:['evening']}} };
  const after = {shifts:{e1:{monday:[]},e2:{monday:['evening']}},updatedBy:'owner'};
  assert.deepEqual(p.schedulePlans(before,after,members,'2026-09-07').map(p=>p.uid),['e1']);
});
test('metadata changes and list reorder do not notify', () => {
  assert.deepEqual(p.schedulePlans({shifts:{e1:{monday:['morning','delivery']}}}, {shifts:{e1:{monday:['delivery','morning']}},updatedBy:'owner'},members,'week'),[]);
});
test('self registration only targets approvers and excludes actor', () => {
  const plans=p.schedulePlans(null,{shifts:{e1:{monday:['morning']}},updatedBy:'e1',notificationAction:'self_registration'},members,'week');
  assert.deepEqual(plans.map(p=>p.uid),['owner','m1','legacy']);
});
test('salary advance request only targets owner, result only requester', () => {
  const request={status:'pending',userId:'e1',amount:100};
  assert.deepEqual(p.advancePlans(null,request,members,{ownerId:'owner'},'a').map(p=>p.uid),['owner']);
  assert.deepEqual(p.advancePlans(request,{...request,status:'approved'},members,{ownerId:'owner'},'a').map(p=>p.uid),['e1']);
  assert.deepEqual(p.advancePlans(request,{...request,status:'cancelled'},members,{},'a'),[]);
  assert.deepEqual(p.advancePlans({...request,status:'approved'},{...request,status:'approved'},members,{},'a'),[]);
});
test('rejected and kicked member receives account result without store authorization', () => {
  const plans=p.membershipPlans({status:'pending'},{status:'kicked'},members,'e1');
  assert.equal(plans[0].scope,'account');
  assert.equal(p.canReceive(plans[0],null,null),true);
  assert.equal(plans[0].routePath,null);
});
test('attendance edits do not trigger check-in/out; manager2 excluded', () => {
  const plans=p.attendancePlans(null,{userId:'e1',checkIn:1},members,'a');
  assert.deepEqual(plans.map(p=>p.uid),['owner','m1','legacy']);
  assert.deepEqual(p.attendancePlans({checkOut:1},{userId:'e1',checkOut:2,isEdited:true},members,'a'),[]);
});
test('idempotency distinguishes event, recipient, type and store, not content', () => {
  const id=p.digest('s','event1','e1','schedule_changed');
  assert.equal(id,p.digest('s','event1','e1','schedule_changed'));
  assert.notEqual(id,p.digest('s','event2','e1','schedule_changed'));
  assert.notEqual(id,p.digest('s2','event1','e1','schedule_changed'));
});
test('history audit never conflates different edits in the same week', () => {
  const { audit }=require('../notifications/audit-history');
  const result=audit([
    {id:'a',storeId:'s',type:'schedule_changed',routeExtra:{weekStart:'2026-09-07'}},
    {id:'b',storeId:'s',type:'schedule_changed',routeExtra:{weekStart:'2026-09-07'}},
    {id:'c',storeId:'s',type:'birthday',routeExtra:{birthdayKey:'birthday:e1:2026-09-11'}},
    {id:'d',storeId:'s',type:'birthday',routeExtra:{birthdayKey:'birthday:e1:2026-09-11'}},
  ]);
  assert.equal(result.unverifiableEvents,2);assert.deepEqual(result.duplicateCandidates,[['c','d']]);
});
