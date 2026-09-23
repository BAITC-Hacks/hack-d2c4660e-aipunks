import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { initializeApp as initializeAdminApp, deleteApp as deleteAdminApp } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore as getAdminFirestore } from 'firebase-admin/firestore';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, where, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp, setLogLevel } from 'firebase/firestore';

let env;
const runFile = promisify(execFile);
setLogLevel('silent'); // Expected denials are asserted; print only actual failures.
const oldTime = Timestamp.fromMillis(1700000000000);
const content = {
  name: 'Фотограф', city: 'Алматы', categories: ['Фотограф'], price: 100000,
  formats: ['свадьба'], languages: ['русский'], maxHours: 6,
  description: 'Съёмка мероприятий', contact: '+7 700 000 0000', portfolioUrls: ['https://example.com/portfolio'],
};
const account = (uid, status = 'active') => ({ uid, name: uid, email: `${uid}@example.com`, status, deletionRequested: false, revision: 1, createdAt: oldTime, updatedAt: oldTime });
const profile = (uid = 'vendor', status = 'pending', revision = 2) => ({ ownerId: uid, revision, status, content, reason: '', updatedAt: oldTime });
const pub = (uid = 'vendor', revision = 1) => ({ ownerId: uid, revision, profileRevision: 3, published: true, content, updatedAt: oldTime });
const db = (uid, verified = true) => env.authenticatedContext(uid, { email: `${uid}@example.com`, email_verified: verified }).firestore();
const audit = (actorId, resourceType, resourceId, revision, action, reason = 'Проверено') => ({ actorId, resourceType, resourceId, revision, action, reason, createdAt: serverTimestamp() });
const auditRef = (store, kind, uid, rev) => doc(store, 'audit', `${kind}_${uid}_${rev}`);
const snapshot = {
  id: 'vendor', anon_name: content.name, city: content.city, categories: content.categories, price_from_kzt: content.price,
  event_formats: content.formats, languages: content.languages, busy_dates: [], description: content.description,
  max_hours: 6, synthetic: false, city_imputed: false, price_imputed: false, is_live: true,
  contact: content.contact, portfolio_urls: content.portfolioUrls,
};
const event = () => ({ name: 'Свадьба', city: 'Алматы', date: '2026-10-15', format: 'Свадьба', preferences: '', updatedAt: serverTimestamp() });
const selection = () => ({ eventId: 'event', name: 'Фотографы', request: { city: 'Алматы', date: '2026-10-15', event_format: 'Свадьба', category: 'Фотограф', budget_kzt: 200000, hours: null, language: null, preferences: '' }, entries: [{ contractor: snapshot, explanation: 'Подходит по параметрам' }], savedAt: serverTimestamp() });

async function seed(data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const batch = writeBatch(ctx.firestore());
    for (const [path, value] of Object.entries(data)) batch.set(doc(ctx.firestore(), path), value);
    await batch.commit();
  });
}
function approval(store, { actor = 'moderator', oldRevision = 2, pubRevision = 1, contents = content, withAudit = true, withPublication = true } = {}) {
  const batch = writeBatch(store);
  batch.update(doc(store, 'profiles/vendor'), { revision: oldRevision + 1, status: 'approved', reason: '', updatedAt: serverTimestamp() });
  if (withPublication) batch.set(doc(store, 'publishedProfiles/vendor'), { ownerId: 'vendor', revision: pubRevision, profileRevision: oldRevision + 1, published: true, content: contents, updatedAt: serverTimestamp() });
  if (withAudit) batch.set(auditRef(store, 'profile', 'vendor', oldRevision + 1), audit(actor, 'profile', 'vendor', oldRevision + 1, 'approved', ''));
  return batch;
}
function suspend(store, { hide = true, publicationAudit = true, status = 'suspended', actor = 'admin' } = {}) {
  const batch = writeBatch(store);
  batch.update(doc(store, 'accounts/vendor'), { revision: 2, status, updatedAt: serverTimestamp() });
  batch.set(auditRef(store, 'account', 'vendor', 2), audit(actor, 'account', 'vendor', 2, status));
  if (hide) {
    batch.update(doc(store, 'publishedProfiles/vendor'), { revision: 2, published: false, updatedAt: serverTimestamp() });
    if (publicationAudit) batch.set(auditRef(store, 'publication', 'vendor', 2), audit(actor, 'publication', 'vendor', 2, 'unpublished'));
  }
  return batch;
}

before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-event-match', firestore: { rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
});
beforeEach(async () => {
  await env.clearFirestore();
  await seed({
    'accounts/client': account('client'), 'accounts/other': account('other'), 'accounts/vendor': account('vendor'),
    'accounts/admin': account('admin'), 'accounts/moderator': account('moderator'),
    'staffAccess/admin': { role: 'admin', revision: 1, updatedAt: oldTime },
    'staffAccess/moderator': { role: 'moderator', revision: 1, updatedAt: oldTime },
  });
});
after(async () => { await env?.cleanup(); });

test('registration allows unverified email only for its own safe account', async () => {
  const store = db('new', false);
  await assertSucceeds(setDoc(doc(store, 'accounts/new'), { ...account('new'), createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertSucceeds(getDoc(doc(store, 'accounts/new')));
  await assertFails(setDoc(doc(store, 'accounts/new/events/event'), event()));
  await assertFails(setDoc(doc(db('fake', false), 'accounts/fake'), { ...account('fake'), status: 'suspended', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db('intruder'), 'accounts/someone'), { ...account('someone'), createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
});

test('client events and collections are private even from staff', async () => {
  const store = db('client');
  await assertSucceeds(setDoc(doc(store, 'accounts/client/events/event'), event()));
  await assertSucceeds(setDoc(doc(store, 'accounts/client/selections/selection'), selection()));
  await assertSucceeds(setDoc(doc(store, 'accounts/client/favorites/vendor'), { contractor: snapshot, savedAt: serverTimestamp() }));
  for (const uid of ['other', 'moderator', 'admin']) {
    for (const name of ['events', 'selections', 'favorites']) await assertFails(getDocs(collection(db(uid), `accounts/client/${name}`)));
    await assertFails(setDoc(doc(db(uid), 'accounts/client/events/forged'), event()));
  }
  assert.equal((await getDoc(doc(store, 'accounts/client/selections/selection'))).data().entries.length, 1);
});

test('client snapshots require a live card, own existing event and at most three results', async () => {
  const store = db('client');
  await assertFails(setDoc(doc(store, 'accounts/client/selections/missing-event'), selection()));
  await setDoc(doc(store, 'accounts/client/events/event'), event());
  await assertFails(setDoc(doc(store, 'accounts/client/selections/too-many'), { ...selection(), entries: Array(4).fill(selection().entries[0]) }));
  await assertFails(setDoc(doc(store, 'accounts/client/favorites/vendor'), { contractor: { ...snapshot, is_live: false }, savedAt: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(store, 'accounts/client/selections/three'), { ...selection(), entries: ['vendor', 'other', 'client'].map((id) => ({ contractor: { ...snapshot, id, portfolio_urls: Array(5).fill('https://example.com/portfolio') }, explanation: 'Совпадает с запросом' })) }));
});

test('owner cannot create staff or elevate privileges in an account', async () => {
  await assertFails(setDoc(doc(db('client'), 'staffAccess/client'), { role: 'admin', revision: 1, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db('client'), 'accounts/client'), { role: 'admin', revision: 2, updatedAt: serverTimestamp() }));
  await assertFails(getDocs(collection(db('client'), 'accounts')));
  await assertSucceeds(getDocs(collection(db('admin'), 'accounts')));
  const store = db('client');
  const fakeRestoration = writeBatch(store);
  fakeRestoration.update(doc(store, 'accounts/client'), { name: 'Changed name', revision: 2, updatedAt: serverTimestamp() });
  fakeRestoration.set(auditRef(store, 'account', 'client', 2), audit('client', 'account', 'client', 2, 'active', 'Forged restoration'));
  await assertFails(fakeRestoration.commit());
});

test('owner profile drafts require verification and monotonically increasing revisions', async () => {
  const draft = { ...profile('vendor', 'draft', 1), updatedAt: serverTimestamp() };
  await assertFails(setDoc(doc(db('vendor', false), 'profiles/vendor'), draft));
  await assertSucceeds(setDoc(doc(db('vendor'), 'profiles/vendor'), draft));
  await assertFails(updateDoc(doc(db('vendor'), 'profiles/vendor'), { revision: 1, status: 'pending', updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(db('vendor'), 'profiles/vendor'), { revision: 2, status: 'pending', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db('other'), 'profiles/vendor'), { revision: 3, status: 'draft', updatedAt: serverTimestamp() }));
});

test('pending content is frozen; owner must withdraw before editing', async () => {
  await seed({ 'profiles/vendor': profile() });
  const store = db('vendor');
  await assertFails(updateDoc(doc(store, 'profiles/vendor'), { revision: 3, 'content.price': 200000, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(store, 'profiles/vendor'), { revision: 3, status: 'draft', 'content.price': 200000, updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(store, 'profiles/vendor'), { revision: 3, status: 'draft', updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(store, 'profiles/vendor'), { revision: 4, 'content.price': 200000, updatedAt: serverTimestamp() }));
});

test('staff cannot append a fake moderation audit to their ordinary draft edit', async () => {
  await seed({ 'profiles/moderator': profile('moderator', 'draft', 1) });
  const store = db('moderator');
  const batch = writeBatch(store);
  batch.update(doc(store, 'profiles/moderator'), { revision: 2, 'content.price': 200000, updatedAt: serverTimestamp() });
  batch.set(auditRef(store, 'profile', 'moderator', 2), audit('moderator', 'profile', 'moderator', 2, 'draft', ''));
  await assertFails(batch.commit());
});

test('owner cannot self-publish and moderator cannot alter submitted content', async () => {
  await seed({ 'profiles/vendor': profile() });
  await assertFails(approval(db('vendor'), { actor: 'vendor' }).commit());
  const moderator = db('moderator');
  const changed = approval(moderator);
  changed.update(doc(moderator, 'profiles/vendor'), { 'content.price': 1 });
  await assertFails(changed.commit());
  await seed({ 'staffAccess/vendor': { role: 'admin', revision: 1, updatedAt: oldTime } });
  await assertFails(approval(db('vendor'), { actor: 'vendor' }).commit());
});

test('approval atomically publishes the reviewed version and creates immutable audit', async () => {
  await seed({ 'profiles/vendor': profile() });
  const store = db('moderator');
  await assertFails(approval(store, { withAudit: false }).commit());
  await assertFails(approval(store, { withPublication: false }).commit());
  await assertFails(approval(store, { contents: { ...content, price: 1 } }).commit());
  await assertSucceeds(approval(store).commit());
  const guest = env.unauthenticatedContext().firestore();
  assert.equal((await getDoc(doc(guest, 'publishedProfiles/vendor'))).data().content.price, 100000);
  await assertFails(updateDoc(auditRef(store, 'profile', 'vendor', 3), { reason: 'altered' }));
  await assertFails(deleteDoc(auditRef(db('admin'), 'profile', 'vendor', 3)));
});

test('maximum supported profile lists remain within Firestore evaluation budget', async () => {
  const maximum = { ...content, categories: Array(10).fill('Фотограф'), formats: Array(6).fill('свадьба'), languages: Array(3).fill('русский'), portfolioUrls: Array(5).fill('https://example.com/portfolio') };
  await seed({ 'profiles/vendor': { ...profile('vendor', 'draft', 1), content: maximum } });
  await assertSucceeds(updateDoc(doc(db('vendor'), 'profiles/vendor'), { revision: 2, status: 'pending', updatedAt: serverTimestamp() }));
  await assertSucceeds(approval(db('moderator'), { contents: maximum }).commit());
});

test('forged actor and timestamps fail, and audit entries cannot be reused', async () => {
  await seed({ 'profiles/vendor': profile() });
  const store = db('moderator');
  await assertFails(approval(store, { actor: 'admin' }).commit());
  const old = approval(store);
  old.set(auditRef(store, 'profile', 'vendor', 3), { ...audit('moderator', 'profile', 'vendor', 3, 'approved', ''), createdAt: oldTime });
  await assertFails(old.commit());
  await seed({ 'audit/profile_vendor_3': { ...audit('moderator', 'profile', 'vendor', 3, 'approved', ''), createdAt: oldTime } });
  await assertFails(approval(store).commit());
});

test('two simultaneous review decisions cannot both commit', async () => {
  await seed({ 'profiles/vendor': profile() });
  const results = await Promise.allSettled([approval(db('moderator')).commit(), approval(db('admin'), { actor: 'admin' }).commit()]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(results.filter((r) => r.status === 'rejected').length, 1);
});

test('return for changes requires explanation and audit; old publication remains visible', async () => {
  await seed({ 'profiles/vendor': profile('vendor', 'pending', 4), 'publishedProfiles/vendor': pub() });
  const store = db('moderator');
  const batch = writeBatch(store);
  batch.update(doc(store, 'profiles/vendor'), { revision: 5, status: 'changes_requested', reason: 'Добавьте описание', updatedAt: serverTimestamp() });
  batch.set(auditRef(store, 'profile', 'vendor', 5), audit('moderator', 'profile', 'vendor', 5, 'changes_requested', 'Добавьте описание'));
  await assertSucceeds(batch.commit());
  assert.equal((await getDoc(doc(env.unauthenticatedContext().firestore(), 'publishedProfiles/vendor'))).data().published, true);
});

test('public queries can see only published profiles, not private drafts', async () => {
  await seed({ 'profiles/vendor': profile(), 'publishedProfiles/vendor': pub(), 'publishedProfiles/other': { ...pub('other'), published: false } });
  const guest = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDocs(query(collection(guest, 'publishedProfiles'), where('published', '==', true))));
  await assertFails(getDocs(collection(guest, 'publishedProfiles')));
  await assertFails(getDoc(doc(guest, 'profiles/vendor')));
  await assertFails(getDoc(doc(guest, 'publishedProfiles/other')));
  await assertFails(getDoc(doc(guest, 'accounts/vendor')));
});

test('calendar confirmation uses server time and real month days independently of moderation', async () => {
  await seed({ 'profiles/vendor': profile(), 'publishedProfiles/vendor': pub() });
  const store = db('vendor');
  const calendar = { ownerId: 'vendor', year: 2027, month: 2, busyDays: [1, 28], confirmedAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(store, 'calendars/vendor/months/2027-02'), calendar));
  await assertFails(setDoc(doc(store, 'calendars/vendor/months/2027-02'), { ...calendar, busyDays: [29] }));
  await assertFails(setDoc(doc(store, 'calendars/vendor/months/2027-02'), { ...calendar, busyDays: [1, 1] }));
  await assertFails(setDoc(doc(store, 'calendars/vendor/months/2027-03'), calendar));
  await assertFails(setDoc(doc(store, 'calendars/vendor/months/2027-02'), { ...calendar, confirmedAt: oldTime }));
  await assertFails(setDoc(doc(db('other'), 'calendars/vendor/months/2027-02'), calendar));
  await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), 'calendars/vendor/months/2027-02')));
  await assertSucceeds(approval(db('moderator'), { pubRevision: 2 }).commit());
  assert.deepEqual((await getDoc(doc(store, 'calendars/vendor/months/2027-02'))).data().busyDays, [1, 28]);
});

test('suspension requires atomic unpublication and both audits; blocks subsequent access', async () => {
  await seed({ 'profiles/vendor': profile(), 'publishedProfiles/vendor': pub(), 'accounts/vendor/events/private': { ...event(), updatedAt: oldTime } });
  const store = db('admin');
  await assertFails(suspend(store, { hide: false }).commit());
  await assertFails(suspend(store, { publicationAudit: false }).commit());
  await assertSucceeds(suspend(store).commit());
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'publishedProfiles/vendor')));
  await assertFails(getDoc(doc(db('vendor'), 'accounts/vendor/events/private')));
  await assertFails(updateDoc(doc(db('vendor'), 'profiles/vendor'), { revision: 3, status: 'draft', updatedAt: serverTimestamp() }));
  await assertSucceeds(getDoc(doc(db('vendor'), 'accounts/vendor')));
});

test('a single batch cannot approve and suspend the same contractor', async () => {
  await seed({ 'profiles/vendor': profile() });
  const store = db('admin');
  const batch = approval(store, { actor: 'admin' });
  batch.update(doc(store, 'accounts/vendor'), { revision: 2, status: 'suspended', updatedAt: serverTimestamp() });
  batch.set(auditRef(store, 'account', 'vendor', 2), audit('admin', 'account', 'vendor', 2, 'suspended'));
  await assertFails(batch.commit());
});

test('restoring an account does not republish its profile', async () => {
  await seed({ 'accounts/vendor': { ...account('vendor', 'suspended'), revision: 2 }, 'publishedProfiles/vendor': { ...pub(), published: false } });
  const store = db('admin');
  const batch = writeBatch(store);
  batch.update(doc(store, 'accounts/vendor'), { status: 'active', revision: 3, updatedAt: serverTimestamp() });
  batch.set(auditRef(store, 'account', 'vendor', 3), audit('admin', 'account', 'vendor', 3, 'active'));
  await assertSucceeds(batch.commit());
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'publishedProfiles/vendor')));
});

test('deactivation is owner-audited and cannot be reversed or deleted by client', async () => {
  await seed({ 'profiles/vendor': profile(), 'publishedProfiles/vendor': pub() });
  await assertSucceeds(suspend(db('vendor'), { status: 'deactivated', actor: 'vendor' }).commit());
  await assertFails(updateDoc(doc(db('vendor'), 'accounts/vendor'), { status: 'active', revision: 3, updatedAt: serverTimestamp() }));
  await assertFails(deleteDoc(doc(db('vendor'), 'accounts/vendor')));
});

test('admin accounts cannot be suspended or deactivated through the client', async () => {
  await seed({ 'staffAccess/vendor': { role: 'admin', revision: 1, updatedAt: oldTime }, 'publishedProfiles/vendor': pub() });
  await assertFails(suspend(db('admin')).commit());
  await assertFails(suspend(db('vendor'), { status: 'deactivated', actor: 'vendor' }).commit());
  // Protected account administrators can still edit their ordinary display name.
  await assertSucceeds(updateDoc(doc(db('vendor'), 'accounts/vendor'), { name: 'Новое имя', revision: 2, updatedAt: serverTimestamp() }));
});

test('moderator assignments are audited; admin roles and existing admins are protected', async () => {
  const store = db('admin');
  await assertFails(setDoc(doc(store, 'staffAccess/client'), { role: 'moderator', revision: 1, updatedAt: serverTimestamp() }));
  const assign = (role, revision = 1, target = 'client') => {
    const batch = writeBatch(store);
    batch.set(doc(store, 'staffAccess', target), { role, revision, updatedAt: serverTimestamp() });
    batch.set(auditRef(store, 'staff', target, revision), audit('admin', 'staff', target, revision, role));
    return batch;
  };
  await assertFails(assign('admin').commit());
  await assertFails(assign('none', 2, 'admin').commit());
  await assertSucceeds(assign('moderator').commit());
  await assertFails(assign('moderator', 2).commit());
  await assertSucceeds(getDocs(collection(db('client'), 'profiles')));
});

test('revoked moderator fails immediately even with unchanged authentication token', async () => {
  await seed({ 'profiles/vendor': profile() });
  const moderator = db('moderator');
  const store = db('admin');
  const batch = writeBatch(store);
  batch.update(doc(store, 'staffAccess/moderator'), { role: 'none', revision: 2, updatedAt: serverTimestamp() });
  batch.set(auditRef(store, 'staff', 'moderator', 2), audit('admin', 'staff', 'moderator', 2, 'none'));
  await assertSucceeds(batch.commit());
  await assertFails(approval(moderator).commit());
  await assertFails(getDocs(collection(moderator, 'profiles')));
});

test('admin can revoke inactive moderators but cannot grant them a role', async () => {
  const store = db('admin');
  for (const status of ['suspended', 'deactivated']) {
    const target = `moderator-${status}`;
    await seed({
      [`accounts/${target}`]: account(target, status),
      [`staffAccess/${target}`]: { role: 'moderator', revision: 1, updatedAt: oldTime },
    });
    const changeRole = (role, revision, withAudit = true) => {
      const batch = writeBatch(store);
      batch.update(doc(store, 'staffAccess', target), { role, revision, updatedAt: serverTimestamp() });
      if (withAudit) batch.set(auditRef(store, 'staff', target, revision), audit('admin', 'staff', target, revision, role));
      return batch;
    };
    await assertFails(changeRole('none', 2, false).commit());
    await assertSucceeds(changeRole('none', 2).commit());
    assert.equal((await getDoc(doc(store, 'staffAccess', target))).data().role, 'none');
    await assertFails(changeRole('moderator', 3).commit());
    if (status === 'suspended') {
      const restore = writeBatch(store);
      restore.update(doc(store, 'accounts', target), { status: 'active', revision: 2, updatedAt: serverTimestamp() });
      restore.set(auditRef(store, 'account', target, 2), audit('admin', 'account', target, 2, 'active'));
      await assertSucceeds(restore.commit());
      await assertFails(getDocs(collection(db(target), 'profiles')));
    }
  }
});

test('a role grant cannot be combined with suspending its target', async () => {
  const store = db('admin');
  const batch = writeBatch(store);
  batch.update(doc(store, 'accounts/client'), { status: 'suspended', revision: 2, updatedAt: serverTimestamp() });
  batch.set(auditRef(store, 'account', 'client', 2), audit('admin', 'account', 'client', 2, 'suspended'));
  batch.set(doc(store, 'staffAccess/client'), { role: 'moderator', revision: 1, updatedAt: serverTimestamp() });
  batch.set(auditRef(store, 'staff', 'client', 1), audit('admin', 'staff', 'client', 1, 'moderator'));
  await assertFails(batch.commit());
});

test('unknown collections and server-only assistant state deny client access', async () => {
  for (const path of ['unknown/doc', 'assistant_cache/doc', 'assistant_rate_limits/doc']) {
    await assertFails(setDoc(doc(db('admin'), path), { value: 1 }));
    await assertFails(getDoc(doc(db('admin'), path)));
  }
});

test('missing optional documents can be read by their owner and staff', async () => {
  for (const path of ['profiles/client', 'publishedProfiles/client', 'staffAccess/client']) {
    assert.equal((await assertSucceeds(getDoc(doc(db('client'), path)))).exists(), false);
  }
  assert.equal((await assertSucceeds(getDoc(doc(db('moderator'), 'publishedProfiles/client')))).exists(), false);
  assert.equal((await assertSucceeds(getDoc(doc(db('admin'), 'publishedProfiles/client')))).exists(), false);
});

test('deletion tombstone prevents old tokens recreating accounts or contractor snapshots', async () => {
  await seed({ 'deletedAccounts/deleted': { completed: true }, 'deletedAccounts/vendor': { completed: true } });
  await assertFails(setDoc(doc(db('deleted'), 'accounts/deleted'), { ...account('deleted'), createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db('client'), 'accounts/client/favorites/vendor'), { contractor: snapshot, savedAt: serverTimestamp() }));
  await assertFails(deleteDoc(doc(db('admin'), 'deletedAccounts/vendor')));
});

test('trusted CLI previews, grants admin, then fully deletes only a requested account', async () => {
  assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST, 'Auth emulator must be enabled');
  const app = initializeAdminApp({ projectId: 'demo-event-match' }, 'maintenance-test');
  const auth = getAdminAuth(app);
  const adminStore = getAdminFirestore(app);
  const cli = (...args) => runFile(process.execPath, ['scripts/admin.mjs', ...args], { cwd: new URL('..', import.meta.url), env: process.env });
  try {
    await auth.createUser({ uid: 'maintenance', email: 'maintenance@example.com', emailVerified: true });
    await seed({ 'accounts/maintenance': account('maintenance') });
    const args = ['grant-admin', '--project', 'demo-event-match', '--uid', 'maintenance', '--reason', 'Emulator test'];
    assert.match((await cli(...args)).stdout, /Preview only/);
    assert.equal((await adminStore.doc('staffAccess/maintenance').get()).exists, false);
    await cli(...args, '--execute', '--confirm-project', 'demo-event-match');
    assert.equal((await adminStore.doc('staffAccess/maintenance').get()).data().role, 'admin');
    const revoke = ['revoke-admin', '--project', 'demo-event-match', '--uid', 'maintenance', '--reason', 'Transfer administration'];
    await assert.rejects(cli(...revoke, '--execute', '--confirm-project', 'demo-event-match'), /last verified active administrator/);
    await auth.createUser({ uid: 'admin', email: 'admin@example.com', emailVerified: true });
    assert.match((await cli(...revoke)).stdout, /Preview only/);
    assert.equal((await adminStore.doc('staffAccess/maintenance').get()).data().role, 'admin');
    await cli(...revoke, '--execute', '--confirm-project', 'demo-event-match');
    assert.equal((await adminStore.doc('staffAccess/maintenance').get()).data().role, 'none');
    await assert.rejects(cli('delete-account', '--project', 'demo-event-match', '--uid', 'maintenance', '--reason', 'No request'), /recorded request/);
    await seed({
      'accounts/maintenance': { ...account('maintenance', 'deactivated'), deletionRequested: true },
      'accounts/maintenance/events/event': { ...event(), updatedAt: oldTime },
      'profiles/maintenance': profile('maintenance'),
      'publishedProfiles/maintenance': { ...pub('maintenance'), published: false },
      'calendars/maintenance/months/2026-10': { ownerId: 'maintenance', year: 2026, month: 10, busyDays: [], confirmedAt: oldTime },
      'accounts/client/favorites/maintenance': { contractor: { ...snapshot, id: 'maintenance' }, savedAt: oldTime },
      'accounts/client/selections/selection': { ...selection(), entries: [{ contractor: { ...snapshot, id: 'maintenance' }, explanation: 'Historic' }], savedAt: oldTime },
      'audit/profile_vendor_7': { ...audit('maintenance', 'profile', 'vendor', 7, 'approved', ''), createdAt: oldTime },
    });
    const deletion = ['delete-account', '--project', 'demo-event-match', '--uid', 'maintenance', '--reason', 'Confirmed user request', '--execute', '--confirm-project', 'demo-event-match'];
    await cli(...deletion);
    for (const path of ['accounts/maintenance', 'accounts/maintenance/events/event', 'profiles/maintenance', 'publishedProfiles/maintenance', 'calendars/maintenance/months/2026-10', 'staffAccess/maintenance', 'accounts/client/favorites/maintenance', 'audit/staff_maintenance_1']) {
      assert.equal((await adminStore.doc(path).get()).exists, false, path);
    }
    assert.deepEqual((await adminStore.doc('accounts/client/selections/selection').get()).data().entries, []);
    assert.equal((await adminStore.doc('audit/profile_vendor_7').get()).data().actorId, 'deleted-user');
    assert.equal((await adminStore.doc('deletedAccounts/maintenance').get()).data().completed, true);
    await assert.rejects(auth.getUser('maintenance'), { code: 'auth/user-not-found' });
    await cli(...deletion); // retries after partial/complete cleanup are safe
  } finally {
    try { await auth.deleteUser('maintenance'); } catch (_) { /* already removed */ }
    try { await auth.deleteUser('admin'); } catch (_) { /* already removed */ }
    await deleteAdminApp(app);
  }
});
