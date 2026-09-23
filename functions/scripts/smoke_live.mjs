#!/usr/bin/env node
/** Actual callable/Firestore smoke, confined to the isolated demo emulators.
 * Run with firebase.assistant.json and --project demo-event-match-assistant.
 * All requests are typed actions: this script never calls OpenAI.
 */
import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const projectId = 'demo-event-match-assistant';
assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^(127\.0\.0\.1|localhost):8180$/);
assert.match(process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '', /^(127\.0\.0\.1|localhost):9199$/);
if (process.env.GCLOUD_PROJECT) assert.equal(process.env.GCLOUD_PROJECT, projectId);
const app = initializeApp({ projectId }, `live-smoke-${randomUUID()}`);
const db = getFirestore(app);
const auth = getAuth(app);
const prefix = `live-smoke-${randomUUID()}`;
const ids = [`${prefix}-a`, `${prefix}-b`];
const ownedDocuments = [];
let uid;
let token;
let calls = 0;

async function write(path, value) {
  ownedDocuments.push(path);
  await db.doc(path).set(value);
}
async function call(data, name = 'assistantTurn', status = 200) {
  const response = await fetch(`http://127.0.0.1:5002/${projectId}/us-central1/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ data }), signal: AbortSignal.timeout(25_000),
  });
  calls++;
  const body = await response.json();
  assert.equal(response.status, status, `Callable HTTP status ${response.status}; expected ${status}`);
  return body.result ?? body;
}
function show(brief, source = 'live') {
  return { source, brief, action: { id: 'smoke-manual', type: 'show_results', label: 'Показать варианты' } };
}

try {
  const signUp = await fetch(`http://127.0.0.1:9199/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnSecureToken: true }),
  });
  assert.equal(signUp.status, 200);
  const signed = await signUp.json();
  uid = signed.localId;
  token = signed.idToken;
  assert.ok(uid && token);
  const now = new Date();
  const date = new Date(now.getTime() + 5 * 3_600_000).toISOString().slice(0, 10);
  const [year, month, day] = date.split('-').map(Number);
  const monthKey = date.slice(0, 7);
  const calendar = { year, month, busyDays: [], confirmedAt: Timestamp.fromDate(now) };
  for (const [index, id] of ids.entries()) {
    await write(`accounts/${id}`, { status: 'active' });
    await write(`publishedProfiles/${id}`, { ownerId: id, published: true, revision: 1, profileRevision: 1,
      content: { name: `Live smoke ${index}`, city: 'Алматы', categories: ['Ведущий'], price: (index + 1) * 100_000,
        formats: ['корпоратив'], languages: ['русский'], maxHours: 6,
        description: 'Тестовый опубликованный профиль для локальной проверки.', contact: 'test@example.invalid', portfolioUrls: [] },
      updatedAt: Timestamp.fromDate(now),
    });
    await write(`calendars/${id}/months/${monthKey}`, { ...calendar, ownerId: id });
  }
  const brief = { city: 'Алматы', category: 'Ведущий', event_format: 'корпоратив', date, budget_kzt: 500_000,
    hours: 4, language: 'русский', preferences: [], skipped_fields: [], excluded_ids: [], budget_scope: 'contractor' };
  const actualIds = (turn) => turn.result?.recommendations.map((entry) => entry.contractor.id) ?? [];
  const first = await call(show(brief));
  assert.deepEqual(actualIds(first), ids);
  assert.ok(first.result.recommendations.every((entry) => entry.contractor.is_live && entry.contractor.contact === 'test@example.invalid'));
  assert.equal(first.result.preliminary, false);

  await db.doc(`calendars/${ids[0]}/months/${monthKey}`).update({ busyDays: [day] });
  assert.deepEqual(actualIds(await call(show(brief))), [ids[1]]);

  await db.doc(`calendars/${ids[1]}/months/${monthKey}`).update({ confirmedAt: Timestamp.fromMillis(now.getTime() - 31 * 86_400_000) });
  assert.deepEqual(actualIds(await call(show(brief))), []);
  const undated = await call(show({ ...brief, date: null, skipped_fields: ['date'] }));
  assert.deepEqual(actualIds(undated), ids);
  assert.equal(undated.result.preliminary, true);

  await db.doc(`publishedProfiles/${ids[1]}`).update({ published: false, revision: 2 });
  assert.deepEqual(actualIds(await call(show({ ...brief, date: null, skipped_fields: ['date'] }))), [ids[0]]);
  await db.doc(`accounts/${ids[0]}`).update({ status: 'suspended' });
  assert.deepEqual(actualIds(await call(show({ ...brief, date: null, skipped_fields: ['date'] }))), []);
  await db.doc(`accounts/${ids[0]}`).update({ status: 'active' });
  await write(`deletedAccounts/${ids[0]}`, { completed: true });
  assert.deepEqual(actualIds(await call(show({ ...brief, date: null, skipped_fields: ['date'] }))), []);

  const demoInput = show({ ...brief, date: null });
  delete demoInput.source;
  const demo = await call(demoInput);
  assert.ok(actualIds(demo).length > 0);
  assert.ok(demo.result.recommendations.every((entry) => !entry.contractor.is_live && entry.contractor.id.startsWith('HK-')));
  assert.equal((await call(show(brief, 'invalid'), 'assistantTurn', 400)).error.status, 'INVALID_ARGUMENT');

  await write(`deletedAccounts/${uid}`, { completed: true });
  assert.equal((await call(show(brief), 'assistantTurn', 403)).error.status, 'PERMISSION_DENIED');
  console.log(JSON.stringify({ status: 'passed', callableCalls: calls, checks: ['live DTO', 'busy date', 'calendar freshness', 'preliminary unknown date',
    'publication withdrawal', 'suspension', 'contractor deletion', 'legacy demo separation', 'invalid source', 'caller deletion'] }));
} finally {
  await Promise.all([...new Set(ownedDocuments)].map((path) => db.doc(path).delete()));
  if (uid) {
    await db.doc(`assistant_rate_limits/${createHash('sha256').update(uid).digest('hex')}`).delete();
    const cache = await db.collection('assistant_cache').where('ownerUid', '==', uid).get();
    await Promise.all(cache.docs.map((document) => document.ref.delete()));
    await auth.deleteUser(uid).catch(() => undefined);
  }
  await deleteApp(app);
}
