'use strict';
const { createHash } = require('node:crypto');
const digest = (...parts) => createHash('sha256').update(JSON.stringify(parts)).digest('hex');
const roleOf = role => ({ owner: 'owner', manager: 'manager1', legacyManager: 'manager1', manager1: 'manager1', manager_1: 'manager1', manager2: 'manager2', manager_2: 'manager2', employee: 'employee' })[role] || null;
const canManage = role => ['owner', 'manager1'].includes(roleOf(role));
function allowedScopes(member, store) {
  if (!member || member.status !== 'active' || !store || store.status === 'deleted') return [];
  const role = roleOf(member.role);
  if (!role) return [];
  return ['member', ...(canManage(role) ? ['approver', 'attendance'] : []), ...(role === 'owner' ? ['owner'] : [])];
}
function canReceive(plan, member, store) {
  return plan.scope === 'account' || (allowedScopes(member, store).includes(plan.scope) && (plan.scope !== 'owner' || store.ownerId === plan.uid));
}
const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
function normalizedDays(value = {}) {
  return days.map(day => [...new Set(Array.isArray(value[day]) ? value[day] : value[day] ? [value[day]] : [])].sort());
}
function changedUsers(before = {}, after = {}) {
  return [...new Set([...Object.keys(before), ...Object.keys(after)])]
    .filter(uid => JSON.stringify(normalizedDays(before[uid])) !== JSON.stringify(normalizedDays(after[uid])));
}
function plan(uid, scope, type, title, body, routePath, routeExtra = {}) {
  return { uid, scope, type, title, body, routePath, routeExtra };
}
function managers(members, scope, actor, type, title, body, routePath, extra) {
  return Object.entries(members).filter(([uid, m]) => uid !== actor && m.status === 'active' && canManage(m.role))
    .map(([uid]) => plan(uid, scope, type, title, body, routePath, extra));
}
function schedulePlans(before, after, members, scheduleId) {
  if (!after) return [];
  const changed = changedUsers(before?.shifts, after.shifts);
  if (!changed.length) return [];
  const actor = after.updatedBy;
  const weekStart = after.weekStart || scheduleId;
  // Only an explicitly recorded self-registration is routed to approvers.
  if (after.notificationAction === 'self_registration' && changed.length === 1 && changed[0] === actor) {
    if (members[actor]?.status !== 'active') return [];
    return managers(members, 'approver', actor, 'schedule_changed', 'Đăng ký lịch làm mới',
      `${members[actor].name || 'Thành viên'} đã cập nhật đăng ký tuần ${weekStart}.`, '/schedule-manager', { weekStart, userId: actor });
  }
  return changed.filter(uid => uid !== actor && members[uid]?.status === 'active')
    .map(uid => plan(uid, 'member', 'schedule_changed', 'Lịch làm việc của bạn đã cập nhật',
      `Lịch tuần ${weekStart} của bạn đã thay đổi. Mở để xem ca làm việc.`, '/schedule', { weekStart }));
}
function advancePlans(before, after, members, store, advanceId) {
  if (!after) return [];
  const extra = { advanceId, userId: after.userId };
  if (!before && after.status === 'pending') {
    return store.ownerId ? [plan(store.ownerId, 'owner', 'advance_request', 'Yêu cầu ứng lương mới',
      `${members[after.userId]?.name || 'Thành viên'} đã gửi yêu cầu ứng lương. Mở để xem và duyệt.`, '/manage-advances', extra)] : [];
  }
  if (before?.status === 'pending' && ['approved', 'rejected'].includes(after.status)) {
    const approved = after.status === 'approved';
    return [plan(after.userId, 'member', approved ? 'advance_approved' : 'advance_rejected',
      approved ? 'Yêu cầu ứng lương đã được duyệt' : 'Yêu cầu ứng lương bị từ chối',
      'Mở mục lương cá nhân để xem kết quả yêu cầu.', '/salary', extra)];
  }
  return [];
}
function membershipPlans(before, after, members, uid) {
  if (!after || before?.status === after.status) return [];
  if (after.status === 'pending') return managers(members, 'approver', uid, 'join_request',
    'Yêu cầu gia nhập mới', `${after.name || 'Thành viên'} đã gửi yêu cầu tham gia cửa hàng.`, '/pending-members', { memberId: uid });
  if (before?.status === 'pending' && after.status === 'active') return [plan(uid, 'account', 'join_approved',
    'Yêu cầu gia nhập đã được duyệt', 'Bạn đã được duyệt tham gia cửa hàng.', '/splash')];
  if (after.status === 'kicked') {
    if (!before || ['account_deleted_firebase_auth', 'account_deleted'].includes(after.kickedReason)) return [];
    if (['member_left', 'owner_left'].includes(after.kickedReason)) return managers(members, 'approver', uid,
      'member_left', 'Thành viên đã rời cửa hàng', `${after.name || 'Thành viên'} đã rời cửa hàng.`, null, { memberId: uid });
    const rejected = before.status === 'pending';
    return [plan(uid, 'account', rejected ? 'join_rejected' : 'member_kicked',
      rejected ? 'Yêu cầu gia nhập bị từ chối' : 'Tư cách thành viên đã kết thúc',
      rejected ? 'Yêu cầu tham gia cửa hàng của bạn chưa được chấp nhận.' : 'Bạn không còn là thành viên của cửa hàng này.', null)];
  }
  return [];
}
function attendancePlans(before, after, members, attendanceId) {
  if (!after || after.isEdited || after.checkInMethod === 'manual') return [];
  const checkedIn = !before && after.checkIn;
  const checkedOut = before && !before.checkOut && after.checkOut;
  if (!checkedIn && !checkedOut) return [];
  return managers(members, 'attendance', after.userId, checkedIn ? 'check_in' : 'check_out',
    checkedIn ? 'Thành viên vào ca' : 'Thành viên kết thúc ca',
    `${members[after.userId]?.name || 'Thành viên'} ${checkedIn ? 'đã vào ca' : 'đã kết thúc ca'}.`,
    '/attendance-table', { attendanceId, userId: after.userId, date: after.date });
}
module.exports = { digest, roleOf, allowedScopes, canReceive, changedUsers, plan, schedulePlans, advancePlans, membershipPlans, attendancePlans, days };
