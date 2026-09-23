import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { initializeApp as initializeAdminApp, deleteApp as deleteAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore as getAdminFirestore } from 'firebase-admin/firestore';
import { collection, doc, getDoc, getDocs, query, where, orderBy, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp, setLogLevel } from 'firebase/firestore';

const projectId = 'demo-event-match-communication'; // No clearFirestore race with account / planner suites.
const oldTime = Timestamp.fromMillis(1700000000000);
const runFile = promisify(execFile);
setLogLevel('silent');
let env;
const db = (uid, verified = true) => env.authenticatedContext(uid, { email: `${uid}@example.com`, email_verified: verified }).firestore();
const account = (uid, status = 'active') => ({ uid, name: uid, email: `${uid}@example.com`, status, deletionRequested: false, revision: 1, createdAt: oldTime, updatedAt: oldTime });
const eventSnapshot = { name: 'Свадьба', city: 'Алматы', date: '2026-10-15', format: 'свадьба', preferences: 'На открытом воздухе' };
const publication = { ownerId: 'vendor', published: true, revision: 1, profileRevision: 3, updatedAt: oldTime, content: { name: 'Фотограф', categories: ['Фотограф'] } };
const message = (senderId, sequence = 1, text = 'Здравствуйте!\nОбсудим мероприятие?') => ({ senderId, sequence, text, createdAt: serverTimestamp() });
const inquiry = (overrides = {}) => ({ kind: 'inquiry', participantIds: ['client', 'vendor'], clientId: 'client', contractorId: 'vendor', clientName: 'client', contractorName: 'Фотограф', eventId: 'event', eventSnapshot, subject: 'Фотограф', status: 'sent', linkedInquiryId: '', assignedAdminId: '', contextTicketId: '', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), lastMessageAt: serverTimestamp(), lastMessageId: 'first', lastSenderId: 'client', messageCount: 1, revision: 1, ...overrides });
const support = (uid = 'client', overrides = {}) => inquiry({ kind: 'support', participantIds: [uid], clientId: uid, clientName: uid, contractorId: '', contractorName: '', eventId: '', eventSnapshot: {}, subject: 'Нужна помощь', status: 'open', lastSenderId: uid, ...overrides });
const audit = (conversationId, actorId, action, revision) => ({ conversationId, actorId, action, revision, createdAt: serverTimestamp() });
const ref = (store, id = 'inquiry') => doc(store, 'conversations', id);
const auditRef = (store, id, revision) => doc(store, 'communicationAudit', `${id}_${revision}`);
async function seed(data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const batch = writeBatch(ctx.firestore());
    for (const [path, value] of Object.entries(data)) batch.set(doc(ctx.firestore(), path), value);
    await batch.commit();
  });
}
function createInquiry(store = db('client'), { id = 'inquiry', data = {}, first = {}, withMessage = true } = {}) {
  const batch = writeBatch(store);
  batch.set(ref(store, id), inquiry(data));
  if (withMessage) batch.set(doc(ref(store, id), 'messages', 'first'), { ...message('client'), ...first });
  return batch;
}
function createSupport(store = db('client'), { id = 'support', uid = 'client', linked = '', inquiryRevision = 1, data = {}, withAudit = true, withContext = true, auditData = {} } = {}) {
  const batch = writeBatch(store);
  batch.set(ref(store, id), support(uid, { linkedInquiryId: linked, ...data }));
  batch.set(doc(ref(store, id), 'messages', 'first'), message(uid));
  if (withAudit) batch.set(auditRef(store, id, 1), { ...audit(id, uid, 'opened', 1), ...auditData });
  if (linked && withContext) batch.update(ref(store, linked), { contextTicketId: id, revision: inquiryRevision + 1, updatedAt: serverTimestamp() });
  return batch;
}
function send(store, uid, { id = 'inquiry', sequence = 2, revision = 2, messageId = 'reply', text, data = {}, messageData = {}, withMessage = true } = {}) {
  const batch = writeBatch(store);
  batch.update(ref(store, id), { messageCount: sequence, revision, lastMessageId: messageId, lastSenderId: uid, lastMessageAt: serverTimestamp(), updatedAt: serverTimestamp(), ...data });
  if (withMessage) batch.set(doc(ref(store, id), 'messages', messageId), { ...message(uid, sequence, text), ...messageData });
  return batch;
}
function status(store, next, { id = 'inquiry', revision = 2, assignedAdminId, withAudit = true, actor = 'admin', auditData = {} } = {}) {
  const batch = writeBatch(store);
  batch.update(ref(store, id), { status: next, revision, updatedAt: serverTimestamp(), ...(assignedAdminId === undefined ? {} : { assignedAdminId }) });
  if (withAudit && ['in_progress', 'resolved'].includes(next)) batch.set(auditRef(store, id, revision), { ...audit(id, actor, next === 'in_progress' ? 'claimed' : 'resolved', revision), ...auditData });
  return batch;
}

before(async () => {
  env = await initializeTestEnvironment({ projectId, firestore: { rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
});
beforeEach(async () => {
  await env.clearFirestore();
  await seed({
    ...Object.fromEntries(['client', 'vendor', 'other', 'admin', 'admin2', 'moderator'].map((uid) => [`accounts/${uid}`, account(uid)])),
    'staffAccess/admin': { role: 'admin', revision: 1, updatedAt: oldTime },
    'staffAccess/admin2': { role: 'admin', revision: 1, updatedAt: oldTime },
    'staffAccess/moderator': { role: 'moderator', revision: 1, updatedAt: oldTime },
    'accounts/client/events/event': { ...eventSnapshot, updatedAt: oldTime },
    'publishedProfiles/vendor': publication,
  });
});
after(async () => { await env?.cleanup(); });

test('real inquiry and first message are atomic; identities and event snapshot are verified', async () => {
  await assertFails(createInquiry(db('client'), { withMessage: false }).commit());
  for (const data of [
    { contractorId: 'anonymous-card', participantIds: ['client', 'anonymous-card'] },
    { contractorId: 'client', participantIds: ['client', 'client'] },
    { clientName: 'Spoofed' }, { contractorName: 'Spoofed' }, { subject: 'Банкетный зал' },
    { participantIds: ['client', 'vendor', 'other'] }, { eventId: 'missing' },
    { eventSnapshot: { ...eventSnapshot, city: 'Астана' } }, { eventSnapshot: { ...eventSnapshot, secret: true } },
    { assignedAdminId: 'admin' }, { contextTicketId: 'support' }, { revision: 2 },
  ]) await assertFails(createInquiry(db('client'), { data }).commit());
  await assertFails(createInquiry(db('other')).commit());
  await assertFails(createInquiry(db('client', false)).commit());
  await assertSucceeds(createInquiry().commit());
  assert.equal((await getDoc(ref(db('vendor')))).data().messageCount, 1);
  assert.equal((await getDoc(doc(ref(db('vendor')), 'messages/first'))).data().senderId, 'client');
});

test('hidden or unavailable contractor cannot receive new inquiries', async () => {
  await seed({ 'publishedProfiles/vendor': { ...publication, published: false } });
  await assertFails(createInquiry().commit());
  await seed({ 'publishedProfiles/vendor': publication, 'accounts/vendor': account('vendor', 'suspended') });
  await assertFails(createInquiry().commit());
  await seed({ 'accounts/vendor': account('vendor'), 'deletedAccounts/vendor': { completed: false } });
  await assertFails(createInquiry().commit());
});

test('members can list their conversations; administrators have no ambient private-chat access', async () => {
  await createInquiry().commit();
  for (const uid of ['client', 'vendor']) {
    await assertSucceeds(getDocs(query(collection(db(uid), 'conversations'), where('participantIds', 'array-contains', uid), orderBy('updatedAt', 'desc'))));
    await assertSucceeds(getDocs(collection(ref(db(uid)), 'messages')));
  }
  for (const uid of ['other', 'admin', 'moderator']) {
    await assertFails(getDoc(ref(db(uid))));
    await assertFails(getDocs(collection(ref(db(uid)), 'messages')));
    await assertFails(getDocs(collection(db(uid), 'conversations')));
  }
  await assertFails(getDoc(ref(env.unauthenticatedContext().firestore())));
  await assertFails(getDoc(ref(db('client', false))));
  assert.equal((await assertSucceeds(getDoc(ref(db('client'), 'new-id')))).exists(), false);
  assert.equal((await assertSucceeds(getDoc(doc(ref(db('client')), 'messages/new-id')))).exists(), false);
});

test('messages require matching new summary, exact sequence, immutable author and server time', async () => {
  await createInquiry().commit();
  await assertFails(send(db('vendor'), 'vendor', { withMessage: false }).commit());
  for (const overrides of [
    { messageData: { senderId: 'client' } }, { data: { lastSenderId: 'client' } },
    { sequence: 4 }, { revision: 4 }, { messageData: { createdAt: oldTime } },
    { messageData: { sequence: 3 } }, { text: ' \n\t ' }, { text: 'a'.repeat(4001) },
    { data: { status: 'discussing' } }, { data: { eventSnapshot: {} } },
  ]) await assertFails(send(db('vendor'), 'vendor', overrides).commit());
  await assertFails(send(db('other'), 'other').commit());
  await assertFails(send(db('admin'), 'admin').commit());
  await assertFails(setDoc(doc(ref(db('vendor')), 'messages/orphan'), message('vendor', 2)));
  await assertSucceeds(send(db('vendor'), 'vendor').commit());
  await assertFails(updateDoc(doc(ref(db('vendor')), 'messages/reply'), { text: 'Edited' }));
  await assertFails(deleteDoc(doc(ref(db('client')), 'messages/reply')));
  await assertFails(send(db('vendor'), 'vendor', { sequence: 3, revision: 3 }).commit());
  await assertFails(updateDoc(ref(db('client')), { clientName: 'New name', revision: 3, updatedAt: serverTimestamp() }));
});

test('simultaneous messages with the same counter cannot both commit', async () => {
  await createInquiry().commit();
  const attempts = await Promise.allSettled([
    send(db('client'), 'client', { messageId: 'a' }).commit(),
    send(db('vendor'), 'vendor', { messageId: 'b' }).commit(),
  ]);
  assert.equal(attempts.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(attempts.filter((r) => r.status === 'rejected').length, 1);
});

test('inquiry transitions are role-bound and terminal conversations cannot reopen or send', async () => {
  await createInquiry().commit();
  await assertFails(status(db('client'), 'discussing').commit());
  await assertFails(status(db('client'), 'declined').commit());
  await assertFails(status(db('vendor'), 'cancelled').commit());
  await assertFails(status(db('vendor'), 'closed').commit());
  await assertFails(status(db('admin'), 'discussing').commit());
  await assertSucceeds(status(db('vendor'), 'discussing').commit());
  await assertSucceeds(status(db('client'), 'closed', { revision: 3 }).commit());
  await assertFails(status(db('vendor'), 'discussing', { revision: 4 }).commit());
  await assertFails(send(db('client'), 'client', { revision: 4 }).commit());
  await assertSucceeds(getDocs(collection(ref(db('client')), 'messages')));
  for (const [id, next, uid] of [['cancel', 'cancelled', 'client'], ['decline', 'declined', 'vendor']]) {
    await createInquiry(db('client'), { id }).commit();
    await assertSucceeds(status(db(uid), next, { id }).commit());
  }
  await createInquiry(db('client'), { id: 'decline-discussion' }).commit();
  await status(db('vendor'), 'discussing', { id: 'decline-discussion' }).commit();
  await assertSucceeds(status(db('vendor'), 'declined', { id: 'decline-discussion', revision: 3 }).commit());
});

test('support needs an immutable coupled opening audit and has a private administrative queue', async () => {
  await assertFails(createSupport(db('client'), { withAudit: false }).commit());
  await assertFails(createSupport(db('client'), { auditData: { actorId: 'admin' } }).commit());
  await assertFails(createSupport(db('client'), { auditData: { createdAt: oldTime } }).commit());
  await assertFails(createSupport(db('client'), { data: { assignedAdminId: 'admin' } }).commit());
  await assertFails(setDoc(auditRef(db('client'), 'orphan', 1), audit('orphan', 'client', 'opened', 1)));
  await assertSucceeds(createSupport().commit());
  for (const uid of ['client', 'admin']) await assertSucceeds(getDocs(query(collection(db(uid), 'communicationAudit'), where('conversationId', '==', 'support'))));
  await assertSucceeds(getDocs(query(collection(db('admin'), 'conversations'), where('kind', '==', 'support'), orderBy('updatedAt', 'desc'))));
  for (const uid of ['vendor', 'moderator', 'other']) {
    await assertFails(getDoc(ref(db(uid), 'support')));
    await assertFails(getDocs(query(collection(db(uid), 'conversations'), where('kind', '==', 'support'))));
    await assertFails(getDoc(auditRef(db(uid), 'support', 1)));
  }
  await assertFails(updateDoc(auditRef(db('admin'), 'support', 1), { actorId: 'admin' }));
  await assertFails(deleteDoc(auditRef(db('admin'), 'support', 1)));
});

test('support context requires participant consent, a new ticket and its opening audit', async () => {
  await createInquiry().commit();
  await assertFails(createSupport(db('client'), { linked: 'inquiry', withContext: false }).commit());
  await assertFails(createSupport(db('client'), { linked: 'inquiry', withAudit: false }).commit());
  await assertFails(createSupport(db('other'), { uid: 'other', linked: 'inquiry' }).commit());
  await assertFails(createSupport(db('admin'), { uid: 'admin', linked: 'inquiry' }).commit());
  await assertFails(updateDoc(ref(db('client')), { contextTicketId: 'arbitrary', revision: 2, updatedAt: serverTimestamp() }));
  await assertSucceeds(createSupport(db('vendor'), { uid: 'vendor', linked: 'inquiry' }).commit());
  await assertFails(getDoc(ref(db('admin')))); // Opening alone does not grant context.
  await assertFails(send(db('admin'), 'admin', { id: 'support' }).commit());
  await assertFails(updateDoc(ref(db('client')), { contextTicketId: 'support', revision: 3, updatedAt: serverTimestamp() }));
});

test('only assigned current administrator can use explicit context; resolving revokes it immediately', async () => {
  await createInquiry().commit();
  await createSupport(db('client'), { linked: 'inquiry' }).commit();
  await assertFails(status(db('moderator'), 'in_progress', { id: 'support', assignedAdminId: 'moderator', actor: 'moderator' }).commit());
  await assertFails(status(db('admin'), 'in_progress', { id: 'support', assignedAdminId: 'admin', withAudit: false }).commit());
  await assertSucceeds(status(db('admin'), 'in_progress', { id: 'support', assignedAdminId: 'admin' }).commit());
  await assertSucceeds(getDoc(ref(db('admin'))));
  await assertSucceeds(getDocs(collection(ref(db('admin')), 'messages')));
  await assertFails(getDoc(ref(db('admin2'))));
  await assertFails(send(db('admin'), 'admin', { revision: 3 }).commit()); // Context is read-only.
  await assertFails(status(db('admin2'), 'in_progress', { id: 'support', revision: 3, assignedAdminId: 'admin2', actor: 'admin2' }).commit());
  await assertFails(send(db('admin2'), 'admin2', { id: 'support', revision: 3 }).commit());
  await assertSucceeds(send(db('admin'), 'admin', { id: 'support', revision: 3 }).commit());
  await assertFails(status(db('admin2'), 'resolved', { id: 'support', revision: 4, actor: 'admin2' }).commit());
  await assertSucceeds(status(db('client'), 'resolved', { id: 'support', revision: 4, actor: 'client' }).commit());
  await assertFails(getDoc(ref(db('admin'))));
  await assertFails(getDocs(collection(ref(db('admin')), 'messages')));
  await assertFails(send(db('client'), 'client', { id: 'support', sequence: 3, revision: 5 }).commit());
  await assertFails(status(db('admin'), 'in_progress', { id: 'support', revision: 5, assignedAdminId: 'admin' }).commit());
  await assertSucceeds(getDoc(ref(db('client'), 'support')));
});

test('requester may resolve an open support ticket but an administrator cannot claim their own ticket', async () => {
  await createSupport().commit();
  await assertSucceeds(status(db('client'), 'resolved', { id: 'support', actor: 'client' }).commit());
  await createSupport(db('admin'), { id: 'self-support', uid: 'admin' }).commit();
  await assertFails(status(db('admin'), 'in_progress', { id: 'self-support', assignedAdminId: 'admin' }).commit());
});

test('revoked or suspended administrators lose context and ability to answer with their old token', async () => {
  await createInquiry().commit();
  await createSupport(db('client'), { linked: 'inquiry' }).commit();
  const store = db('admin');
  await status(store, 'in_progress', { id: 'support', assignedAdminId: 'admin' }).commit();
  await seed({ 'staffAccess/admin': { role: 'none', revision: 2, updatedAt: oldTime } });
  await assertFails(getDoc(ref(store)));
  await assertFails(getDoc(ref(store, 'support')));
  await assertFails(send(store, 'admin', { id: 'support', revision: 3 }).commit());
  await seed({ 'staffAccess/admin': { role: 'admin', revision: 3, updatedAt: oldTime }, 'accounts/admin': account('admin', 'suspended') });
  await assertFails(getDoc(ref(store)));
  await assertFails(send(store, 'admin', { id: 'support', revision: 3 }).commit());
});

test('blocked members cannot read or send; the other member cannot message a blocked or deleted account', async () => {
  await createInquiry().commit();
  await seed({ 'accounts/vendor': account('vendor', 'suspended') });
  await assertFails(getDoc(ref(db('vendor'))));
  await assertFails(send(db('vendor'), 'vendor').commit());
  await assertFails(send(db('client'), 'client').commit());
  await assertFails(status(db('client'), 'cancelled').commit());
  await seed({ 'accounts/vendor': account('vendor'), 'deletedAccounts/vendor': { completed: false } });
  await assertFails(getDoc(ref(db('vendor'))));
  await assertFails(send(db('client'), 'client').commit());
  await assertFails(createSupport(db('client'), { linked: 'inquiry' }).commit());
});

test('support requester suspension stops all replies and blocked requester loses access', async () => {
  await createSupport().commit();
  await status(db('admin'), 'in_progress', { id: 'support', assignedAdminId: 'admin' }).commit();
  await seed({ 'accounts/client': account('client', 'suspended') });
  await assertFails(getDoc(ref(db('client'), 'support')));
  await assertFails(send(db('admin'), 'admin', { id: 'support', revision: 3 }).commit());
});

test('read state is private, monotonic and cannot invent unread sequence counts', async () => {
  await createInquiry().commit();
  const read = (uid) => doc(ref(db(uid)), 'readStates', uid);
  await assertSucceeds(setDoc(read('client'), { lastReadSequence: 1, updatedAt: serverTimestamp() }));
  await assertFails(setDoc(read('client'), { lastReadSequence: 2, updatedAt: serverTimestamp() }));
  await assertFails(setDoc(read('client'), { lastReadSequence: 0, updatedAt: serverTimestamp() }));
  await assertFails(setDoc(read('client'), { lastReadSequence: 1, updatedAt: oldTime }));
  await assertFails(setDoc(doc(ref(db('client')), 'readStates/vendor'), { lastReadSequence: 1, updatedAt: serverTimestamp() }));
  await assertFails(getDoc(doc(ref(db('vendor')), 'readStates/client')));
  await assertFails(setDoc(read('other'), { lastReadSequence: 1, updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(ref(db('client')), 'unknown/arbitrary'), { value: true }));
  await assertFails(deleteDoc(ref(db('client'))));
});

test('forged extra audit or reused audit cannot attach to an ordinary support message', async () => {
  await createSupport().commit();
  const store = db('client');
  const forged = send(store, 'client', { id: 'support' });
  forged.set(auditRef(store, 'support', 2), audit('support', 'client', 'opened', 2));
  await assertFails(forged.commit());
  await seed({ 'communicationAudit/support_2': { ...audit('support', 'admin', 'claimed', 2), createdAt: oldTime } });
  await assertFails(status(db('admin'), 'in_progress', { id: 'support', assignedAdminId: 'admin' }).commit());
});

test('trusted deletion purges conversation descendants, related support and audit and safely retries orphan cleanup', async () => {
  assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST);
  const app = initializeAdminApp({ projectId }, 'communication-maintenance');
  const auth = getAdminAuth(app);
  const adminStore = getAdminFirestore(app);
  try {
    await auth.createUser({ uid: 'vendor', email: 'vendor@example.com', emailVerified: true });
    await createInquiry().commit();
    await createSupport(db('client'), { linked: 'inquiry' }).commit();
    await seed({
      'conversations/inquiry/readStates/client': { lastReadSequence: 1, updatedAt: oldTime },
      'accounts/vendor': { ...account('vendor', 'deactivated'), deletionRequested: true },
      'deletedAccounts/vendor': { completed: false, communicationIds: ['orphan'] },
      'conversations/orphan/messages/leftover': { ...message('vendor'), createdAt: oldTime },
      'communicationAudit/orphan_1': { ...audit('orphan', 'vendor', 'opened', 1), createdAt: oldTime },
    });
    const args = ['scripts/admin.mjs', 'delete-account', '--project', projectId, '--uid', 'vendor', '--reason', 'Confirmed emulator deletion request', '--execute', '--confirm-project', projectId];
    await runFile(process.execPath, args, { cwd: new URL('..', import.meta.url), env: process.env });
    for (const path of ['conversations/inquiry', 'conversations/inquiry/messages/first', 'conversations/inquiry/readStates/client', 'conversations/support', 'conversations/support/messages/first', 'communicationAudit/support_1', 'conversations/orphan/messages/leftover', 'communicationAudit/orphan_1']) {
      assert.equal((await adminStore.doc(path).get()).exists, false, path);
    }
    assert.equal((await adminStore.doc('deletedAccounts/vendor').get()).data().completed, true);
    await runFile(process.execPath, args, { cwd: new URL('..', import.meta.url), env: process.env });
  } finally {
    try { await auth.deleteUser('vendor'); } catch (_) { /* already removed */ }
    await deleteAdminApp(app);
  }
});

test('deletion tombstone also freezes related support while recursive cleanup is running', async () => {
  await createInquiry().commit();
  await createSupport(db('client'), { linked: 'inquiry' }).commit();
  await status(db('admin'), 'in_progress', { id: 'support', assignedAdminId: 'admin' }).commit();
  await seed({ 'deletedAccounts/vendor': { completed: false } });
  await assertFails(send(db('client'), 'client', { id: 'support', revision: 3 }).commit());
  await assertFails(send(db('admin'), 'admin', { id: 'support', revision: 3 }).commit());
  await assertFails(status(db('client'), 'resolved', { id: 'support', actor: 'client', revision: 3 }).commit());
  await assertFails(setDoc(doc(ref(db('client')), 'readStates/client'), { lastReadSequence: 1, updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(ref(db('client'), 'support'), 'readStates/client'), { lastReadSequence: 1, updatedAt: serverTimestamp() }));
  await createSupport(db('other'), { uid: 'other', id: 'separate-support' }).commit();
  await status(db('admin'), 'in_progress', { id: 'separate-support', assignedAdminId: 'admin' }).commit();
  await seed({ 'deletedAccounts/admin': { completed: false } });
  await assertFails(send(db('other'), 'other', { id: 'separate-support', revision: 3 }).commit());
});

test('deleting assigned administrator removes their support and receipts while retaining the participants inquiry', async () => {
  const app = initializeAdminApp({ projectId }, 'communication-admin-maintenance');
  const adminStore = getAdminFirestore(app);
  try {
    await createInquiry().commit();
    await createSupport(db('client'), { linked: 'inquiry' }).commit();
    await status(db('admin'), 'in_progress', { id: 'support', assignedAdminId: 'admin' }).commit();
    await send(db('admin'), 'admin', { id: 'support', revision: 3 }).commit();
    await seed({
      'conversations/inquiry/readStates/admin': { lastReadSequence: 1, updatedAt: oldTime },
      'accounts/admin': { ...account('admin', 'deactivated'), deletionRequested: true },
    });
    const args = ['scripts/admin.mjs', 'delete-account', '--project', projectId, '--uid', 'admin', '--reason', 'Confirmed emulator deletion request', '--execute', '--confirm-project', projectId];
    await runFile(process.execPath, args, { cwd: new URL('..', import.meta.url), env: process.env });
    assert.equal((await adminStore.doc('conversations/inquiry').get()).data().contextTicketId, '');
    assert.equal((await adminStore.doc('conversations/inquiry/messages/first').get()).exists, true);
    for (const path of ['conversations/inquiry/readStates/admin', 'conversations/support', 'conversations/support/messages/reply', 'communicationAudit/support_1', 'communicationAudit/support_2']) {
      assert.equal((await adminStore.doc(path).get()).exists, false, path);
    }
  } finally { await deleteAdminApp(app); }
});
