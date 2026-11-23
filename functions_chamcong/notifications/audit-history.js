#!/usr/bin/env node
'use strict';
// Offline only. Input is an operator-supplied JSON export, never database credentials.
const fs = require('node:fs');
const { digest } = require('./policy');
function audit(items) {
  const groups = new Map();
  let unverifiableEvents = 0;
  for (const item of items) {
    // A weekStart / advanceId alone is not an event identity: distinct edits must survive.
    const key = item.routeExtra?.birthdayKey || item.routeExtra?.reminderKey || item.eventKey;
    if (!key) { unverifiableEvents++; continue; }
    const identity = digest(item.storeId, key, item.type, item.targetUserId || '', [...(item.targetRoles || [])].sort());
    if (!groups.has(identity)) groups.set(identity, []);
    groups.get(identity).push(item.id);
  }
  return { total: items.length, unverifiableEvents,
    duplicateCandidates: [...groups.values()].filter(ids => ids.length > 1),
    note: 'Chỉ là danh sách cần kiểm tra. Không tự động xóa, nhập hộp thư hoặc gửi lại thông báo.' };
}
if (require.main === module) {
  if (!process.argv[2]) { process.stderr.write('Usage: node notifications/audit-history.js <export.json>\n'); process.exitCode = 1; }
  else {
    const items = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    if (!Array.isArray(items)) throw new Error('Input must be a JSON array');
    process.stdout.write(JSON.stringify(audit(items), null, 2) + '\n');
  }
}
module.exports = { audit };
