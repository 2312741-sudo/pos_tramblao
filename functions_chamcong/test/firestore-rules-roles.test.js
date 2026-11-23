const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, collection, query, where, serverTimestamp } = require('firebase/firestore');
const admin = require('firebase-admin');

let env, db, app;
const projectId = 'demo-chamcong-roles';

const client = uid => env.authenticatedContext(uid).firestore();
const anonClient = () => env.unauthenticatedContext().firestore();

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Emulator only; refusing live database access');
  env = await initializeTestEnvironment({
    projectId,
    firestore: { rules: fs.readFileSync('../firestore.rules', 'utf8') },
  });
  app = admin.initializeApp({ projectId }, 'roles-app');
  db = app.firestore();
});

after(async () => {
  await env?.cleanup();
  await app?.delete();
});

beforeEach(async () => {
  await env.clearFirestore();

  // Setup Store 1 (s1) with 4 roles: owner, manager_1, manager_2, employee
  await db.doc('stores/s1').set({ ownerId: 'owner1', status: 'active', name: 'Trạm Chanh' });
  for (const [uid, role] of Object.entries({
    owner1: 'owner',
    m1: 'manager_1',
    m2: 'manager_2',
    e1: 'employee',
    e2: 'employee',
  })) {
    await db.doc(`stores/s1/members/${uid}`).set({ userId: uid, role, status: 'active', name: uid });
    await db.doc(`users/${uid}`).set({ name: uid, email: `${uid}@example.com` });
  }

  // Setup Store 2 (s2) for cross-store isolation testing
  await db.doc('stores/s2').set({ ownerId: 'owner2', status: 'active', name: 'Trạm Sữa' });
  await db.doc('stores/s2/members/owner2').set({ userId: 'owner2', role: 'owner', status: 'active' });
  await db.doc('stores/s2/members/s2_emp').set({ userId: 's2_emp', role: 'employee', status: 'active' });
});

// ============================================================================
// 1. CỬA HÀNG (STORES) - QUYỀN SỞ HỮU, SỬA, XÓA
// ============================================================================
test('store CRUD permissions: only owner can delete, owner and m1 can update, m2 and emp cannot update', async () => {
  // Read store: signed-in users can read store details (for joining by code/link)
  await assertSucceeds(getDoc(doc(client('e1'), 'stores/s1')));
  await assertSucceeds(getDoc(doc(client('m1'), 'stores/s1')));
  await assertFails(getDoc(doc(anonClient(), 'stores/s1')));

  // Update store (name, memberOrder, etc.): Owner & Manager 1 can update
  await assertSucceeds(updateDoc(doc(client('owner1'), 'stores/s1'), { memberOrder: ['owner1', 'm1'] }));
  await assertSucceeds(updateDoc(doc(client('m1'), 'stores/s1'), { memberOrder: ['owner1', 'm1', 'e1'] }));

  // Manager 2 and Employee CANNOT update store metadata
  await assertFails(updateDoc(doc(client('m2'), 'stores/s1'), { memberOrder: ['m2'] }));
  await assertFails(updateDoc(doc(client('e1'), 'stores/s1'), { memberOrder: ['e1'] }));

  // Delete store: ONLY owner can delete
  await assertFails(deleteDoc(doc(client('m1'), 'stores/s1')));
  await assertFails(deleteDoc(doc(client('m2'), 'stores/s1')));
  await assertFails(deleteDoc(doc(client('e1'), 'stores/s1')));
  await assertSucceeds(deleteDoc(doc(client('owner1'), 'stores/s1')));
});

// ============================================================================
// 2. THÀNH VIÊN (MEMBERS) & KICK/DELETE (VẤN ĐỀ 1 VÀ PHÂN QUYỀN)
// ============================================================================
test('member kick and role management: m1 can kick employee without modifying /users/{uid}', async () => {
  // Manager 1 kicks employee e1 by updating member status to 'kicked'
  await assertSucceeds(updateDoc(doc(client('m1'), 'stores/s1/members/e1'), {
    status: 'kicked',
    kickedAt: serverTimestamp(),
    kickedBy: 'm1',
  }));

  // BUT Manager 1 CANNOT touch /users/e1 (this was root cause of permission-denied in batch update)
  await assertFails(updateDoc(doc(client('m1'), 'users/e1'), {
    storeIds: [],
  }));

  // Employee can only update own profile in /users/e1
  await assertSucceeds(updateDoc(doc(client('e1'), 'users/e1'), {
    name: 'Updated Name',
  }));

  // Manager 2 CANNOT kick employees
  await assertFails(updateDoc(doc(client('m2'), 'stores/s1/members/e2'), {
    status: 'kicked',
  }));

  // Employee CANNOT kick other employees
  await assertFails(updateDoc(doc(client('e2'), 'stores/s1/members/m1'), {
    status: 'kicked',
  }));

  // Employee CAN self-leave (kick self)
  await assertSucceeds(updateDoc(doc(client('e2'), 'stores/s1/members/e2'), {
    status: 'kicked',
    kickedReason: 'member_left',
  }));

  // Manager 2 is kicked by owner
  await assertSucceeds(updateDoc(doc(client('owner1'), 'stores/s1/members/m2'), {
    status: 'kicked',
    kickedAt: serverTimestamp(),
  }));

  // Manager 2 re-applies to store as pending employee with 0 salary
  await assertSucceeds(setDoc(doc(client('m2'), 'stores/s1/members/m2'), {
    userId: 'm2',
    name: 'm2',
    role: 'employee',
    status: 'pending',
    employeeType: 'fulltime',
    baseMonthlySalary: 0,
    baseHourlyRate: 0,
    standardHoursPerMonth: 208,
    joinedAt: new Date(),
  }));

  // Manager 1 is kicked by owner
  await assertSucceeds(updateDoc(doc(client('owner1'), 'stores/s1/members/m1'), {
    status: 'kicked',
    kickedAt: serverTimestamp(),
  }));

  // Manager 1 re-applies to store as pending employee with 0 salary
  await assertSucceeds(setDoc(doc(client('m1'), 'stores/s1/members/m1'), {
    userId: 'm1',
    name: 'm1',
    role: 'employee',
    status: 'pending',
    employeeType: 'fulltime',
    baseMonthlySalary: 0,
    baseHourlyRate: 0,
    standardHoursPerMonth: 208,
    joinedAt: new Date(),
  }));

  // Employee e2 was kicked, then re-applies
  await assertSucceeds(setDoc(doc(client('e2'), 'stores/s1/members/e2'), {
    userId: 'e2',
    name: 'e2',
    role: 'employee',
    status: 'pending',
    employeeType: 'fulltime',
    baseMonthlySalary: 0,
    baseHourlyRate: 0,
    standardHoursPerMonth: 208,
    joinedAt: new Date(),
  }));

  // FRAUD ATTEMPTS when re-applying MUST FAIL:
  // Cannot re-apply with manager role
  await assertFails(setDoc(doc(client('m2'), 'stores/s1/members/m2'), {
    userId: 'm2',
    name: 'm2',
    role: 'manager_2',
    status: 'pending',
    baseMonthlySalary: 0,
    baseHourlyRate: 0,
  }));

  // Cannot re-apply with non-zero salary
  await assertFails(setDoc(doc(client('m2'), 'stores/s1/members/m2'), {
    userId: 'm2',
    name: 'm2',
    role: 'employee',
    status: 'pending',
    baseMonthlySalary: 10000000,
    baseHourlyRate: 0,
  }));

  // Cannot re-apply directly as active
  await assertFails(setDoc(doc(client('m2'), 'stores/s1/members/m2'), {
    userId: 'm2',
    name: 'm2',
    role: 'employee',
    status: 'active',
    baseMonthlySalary: 0,
    baseHourlyRate: 0,
  }));

  // Applicant 1 submits join request
  await assertSucceeds(setDoc(doc(client('app1'), 'stores/s1/members/app1'), {
    userId: 'app1',
    name: 'Applicant 1',
    role: 'employee',
    status: 'pending',
    employeeType: 'fulltime',
    baseMonthlySalary: 0,
    baseHourlyRate: 0,
    standardHoursPerMonth: 208,
    joinedAt: new Date(),
  }));

  // Other user e1 cannot delete applicant 1's join request
  await assertFails(deleteDoc(doc(client('e1'), 'stores/s1/members/app1')));

  // Applicant 1 cancels own join request (deleteDoc)
  await assertSucceeds(deleteDoc(doc(client('app1'), 'stores/s1/members/app1')));

  // Applicant 2 submits join request
  await assertSucceeds(setDoc(doc(client('app2'), 'stores/s1/members/app2'), {
    userId: 'app2',
    name: 'Applicant 2',
    role: 'employee',
    status: 'pending',
    employeeType: 'fulltime',
    baseMonthlySalary: 0,
    baseHourlyRate: 0,
    standardHoursPerMonth: 208,
    joinedAt: new Date(),
  }));

  // Applicant 2 cancels own request by setting status to kicked
  await assertSucceeds(updateDoc(doc(client('app2'), 'stores/s1/members/app2'), {
    status: 'kicked',
  }));
});


// ============================================================================
// 3. TẠM ỨNG (ADVANCES) - CHỈ CHỦ ĐƯỢC DUYỆT, NHÂN VIÊN CHỈ XEM/TẠO CỦA MÌNH
// ============================================================================
test('advances: employee can create self pending advance, only owner can approve, m1 cannot approve', async () => {
  // Employee e1 requests advance
  await assertSucceeds(setDoc(doc(client('e1'), 'stores/s1/advances/adv_e1'), {
    userId: 'e1',
    amount: 500000,
    status: 'pending',
    storeId: 's1',
  }));

  // Employee e1 cannot create advance for e2
  await assertFails(setDoc(doc(client('e1'), 'stores/s1/advances/adv_e2'), {
    userId: 'e2',
    amount: 500000,
    status: 'pending',
    storeId: 's1',
  }));

  // Employee e2 cannot read e1's advance
  await assertFails(getDoc(doc(client('e2'), 'stores/s1/advances/adv_e1')));

  // Employee e1 cannot approve own advance
  await assertFails(updateDoc(doc(client('e1'), 'stores/s1/advances/adv_e1'), {
    status: 'approved',
  }));

  // Manager 1 cannot read or approve e1's advance (Owner only privilege)
  await assertFails(getDoc(doc(client('m1'), 'stores/s1/advances/adv_e1')));
  await assertFails(updateDoc(doc(client('m1'), 'stores/s1/advances/adv_e1'), {
    status: 'approved',
  }));

  // Owner CAN read and approve e1's advance
  await assertSucceeds(getDoc(doc(client('owner1'), 'stores/s1/advances/adv_e1')));
  await assertSucceeds(updateDoc(doc(client('owner1'), 'stores/s1/advances/adv_e1'), {
    status: 'approved',
  }));
});

// ============================================================================
// 4. LỊCH LÀM VIỆC (SCHEDULES) - TỰ ĐĂNG KÝ VÀ QUẢN LÝ LỊCH
// ============================================================================
test('schedules: managers and owner can write, employee can only write own shift', async () => {
  // Owner & Manager 1 can write schedules
  await assertSucceeds(setDoc(doc(client('owner1'), 'stores/s1/schedules/2026-09-14'), {
    shifts: { e1: { monday: ['morning'] }, e2: { monday: ['evening'] } },
    updatedBy: 'owner1',
  }));

  await assertSucceeds(updateDoc(doc(client('m1'), 'stores/s1/schedules/2026-09-14'), {
    'shifts.e1.tuesday': ['morning'],
  }));

  // Employee e1 can update own shift
  await assertSucceeds(updateDoc(doc(client('e1'), 'stores/s1/schedules/2026-09-14'), {
    'shifts.e1.wednesday': ['morning'],
  }));

  // Employee e1 CANNOT update employee e2's shift
  await assertFails(updateDoc(doc(client('e1'), 'stores/s1/schedules/2026-09-14'), {
    'shifts.e2.wednesday': ['evening'],
  }));

  // Employee CANNOT forge an empty shifts map or someone else in updatedBy
  await assertFails(setDoc(doc(client('e1'), 'stores/s1/schedules/2026-09-21'), {
    updatedBy: 'owner1',
    shifts: {},
  }));
});

// ============================================================================
// 5. CHẤM CÔNG (ATTENDANCES) - CHÍNH CHỦ TẠO, QUẢN LÝ & CHỦ SỞ HỮU KIỂM DUYỆT
// ============================================================================
test('attendances: member creates own check-in, owner and m1 can manage all, others cannot inspect', async () => {
  // Employee e1 checks in
  await assertSucceeds(setDoc(doc(client('e1'), 'stores/s1/attendances/att_e1'), {
    userId: 'e1',
    checkInTime: new Date(),
    status: 'present',
  }));

  // Employee e1 CANNOT check-in for e2
  await assertFails(setDoc(doc(client('e1'), 'stores/s1/attendances/att_e2'), {
    userId: 'e2',
    checkInTime: new Date(),
    status: 'present',
  }));

  // Employee e2 CANNOT read e1's attendance
  await assertFails(getDoc(doc(client('e2'), 'stores/s1/attendances/att_e1')));

  // Manager 1, Manager 2, and Owner CAN read e1's attendance (Active staff view)
  await assertSucceeds(getDoc(doc(client('m1'), 'stores/s1/attendances/att_e1')));
  await assertSucceeds(getDoc(doc(client('m2'), 'stores/s1/attendances/att_e1')));
  await assertSucceeds(getDoc(doc(client('owner1'), 'stores/s1/attendances/att_e1')));

  // Manager 2 and Manager 1 can query active staff in the store
  await assertSucceeds(getDocs(query(collection(client('m2'), 'stores/s1/attendances'), where('checkOut', '==', null))));
  await assertSucceeds(getDocs(query(collection(client('m1'), 'stores/s1/attendances'), where('checkOut', '==', null))));

  // Employee CANNOT query all active staff
  await assertFails(getDocs(query(collection(client('e2'), 'stores/s1/attendances'), where('checkOut', '==', null))));

  // Employee CANNOT delete attendance
  await assertFails(deleteDoc(doc(client('e1'), 'stores/s1/attendances/att_e1')));

  // Manager 2 CANNOT delete attendance
  await assertFails(deleteDoc(doc(client('m2'), 'stores/s1/attendances/att_e1')));

  // Manager 1 CAN delete/edit attendance
  await assertSucceeds(deleteDoc(doc(client('m1'), 'stores/s1/attendances/att_e1')));
});

// ============================================================================
// 6. HIỆU NĂNG TRẠM (PERFORMANCE) - CHỈ CHỦ & QUẢN LÝ ĐƯỢC XEM, NHÂN VIÊN BỊ CHẶN
// ============================================================================
test('performance: only owner, m1, m2 can access performance for their store; employee is blocked', async () => {
  await db.doc('performance_sessions/sess_s1').set({ storeId: 's1', name: 'Phiên đo 1' });
  await db.doc('performance_reports/rep_s1').set({ storeId: 's1', summary: 'Báo cáo hiệu năng' });

  // Owner, Manager 1, Manager 2 CAN read performance sessions & reports
  await assertSucceeds(getDoc(doc(client('owner1'), 'performance_sessions/sess_s1')));
  await assertSucceeds(getDoc(doc(client('m1'), 'performance_sessions/sess_s1')));
  await assertSucceeds(getDoc(doc(client('m2'), 'performance_sessions/sess_s1')));
  await assertSucceeds(getDoc(doc(client('owner1'), 'performance_reports/rep_s1')));
  await assertSucceeds(getDoc(doc(client('m1'), 'performance_reports/rep_s1')));
  await assertSucceeds(getDoc(doc(client('m2'), 'performance_reports/rep_s1')));

  // Employee e1 is STRICTLY DENIED access to performance data
  await assertFails(getDoc(doc(client('e1'), 'performance_sessions/sess_s1')));
  await assertFails(getDoc(doc(client('e1'), 'performance_reports/rep_s1')));
  await assertFails(setDoc(doc(client('e1'), 'performance_sessions/forged'), { storeId: 's1' }));
});

// ============================================================================
// 7. CÔ LẬP DỮ LIỆU GIỮA CÁC CỬA HÀNG (CROSS-STORE ISOLATION)
// ============================================================================
test('cross-store isolation: members of store 1 cannot access store 2 private collections', async () => {
  await db.doc('stores/s2/attendances/att_s2').set({ userId: 's2_emp', checkIn: new Date() });
  await db.doc('stores/s2/schedules/2026-09-14').set({ shifts: {} });
  await db.doc('performance_sessions/sess_s2').set({ storeId: 's2' });

  // Manager 1 and Employee 1 of Store 1 CANNOT read Store 2 attendances, schedules, performance
  await assertFails(getDoc(doc(client('m1'), 'stores/s2/attendances/att_s2')));
  await assertFails(getDoc(doc(client('e1'), 'stores/s2/attendances/att_s2')));
  await assertFails(getDoc(doc(client('m1'), 'stores/s2/schedules/2026-09-14')));
  await assertFails(getDoc(doc(client('e1'), 'stores/s2/schedules/2026-09-14')));
  await assertFails(getDoc(doc(client('m1'), 'performance_sessions/sess_s2')));
  await assertFails(getDoc(doc(client('owner1'), 'performance_sessions/sess_s2')));

  // Store 2 Owner CAN read Store 2 data
  await assertSucceeds(getDoc(doc(client('owner2'), 'stores/s2/attendances/att_s2')));
  await assertSucceeds(getDoc(doc(client('owner2'), 'stores/s2/schedules/2026-09-14')));
  await assertSucceeds(getDoc(doc(client('owner2'), 'performance_sessions/sess_s2')));
});
