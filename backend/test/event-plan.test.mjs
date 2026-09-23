import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  collection, doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc,
  writeBatch, serverTimestamp, Timestamp, setLogLevel,
} from 'firebase/firestore';

// The existing rules suite clears its project before every test. A separate
// project keeps Node's parallel test-file workers from deleting each other's data.
const projectId = 'demo-event-match-planning';
let env;
setLogLevel('silent');
const oldTime = Timestamp.fromMillis(1700000000000);
const categories = [
  'Ведущий', 'Фотограф', 'Банкетный зал', 'Флорист', 'Декоратор',
  'Подарки и сувениры', 'Ведущий церемонии', 'Фото и видеобудки',
  'Отель', 'Инструменталист',
];
const tasks = ['confirm_scope', 'confirm_final_price', 'confirm_terms'];
const account = (uid, status = 'active') => ({
  uid, name: uid, email: `${uid}@example.com`, status,
  deletionRequested: false, revision: 1, createdAt: oldTime, updatedAt: oldTime,
});
const event = () => ({
  name: 'Свадьба', city: 'Алматы', date: '2026-10-15', format: 'свадьба',
  preferences: '', updatedAt: serverTimestamp(),
});
const plan = (overrides = {}) => ({
  schemaVersion: 1, revision: 1, totalBudgetKzt: null,
  choices: {}, completedTaskIds: [], notes: '', updatedAt: serverTimestamp(),
  ...overrides,
});
const choice = (overrides = {}) => ({
  selectionId: 'selection', contractorId: 'contractor', ...overrides,
});
const db = (uid, verified = true) => env.authenticatedContext(uid, {
  email: `${uid}@example.com`, email_verified: verified,
}).firestore();
const ref = (store, uid = 'client', eventId = 'event') =>
  doc(store, 'accounts', uid, 'eventPlans', eventId);

async function seed(data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const batch = writeBatch(ctx.firestore());
    for (const [path, value] of Object.entries(data)) {
      batch.set(doc(ctx.firestore(), path), value);
    }
    await batch.commit();
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: { rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
  });
});
beforeEach(async () => {
  await env.clearFirestore();
  await seed({
    'accounts/client': account('client'),
    'accounts/other': account('other'),
    'accounts/admin': account('admin'),
    'accounts/moderator': account('moderator'),
    'accounts/suspended': account('suspended', 'suspended'),
    'accounts/deactivated': account('deactivated', 'deactivated'),
    'staffAccess/admin': { role: 'admin', revision: 1, updatedAt: oldTime },
    'staffAccess/moderator': { role: 'moderator', revision: 1, updatedAt: oldTime },
    ...Object.fromEntries(['client', 'other', 'admin', 'moderator', 'suspended', 'deactivated']
      .map((uid) => [`accounts/${uid}/events/event`, { ...event(), updatedAt: oldTime }])),
  });
});
after(async () => { await env?.cleanup(); });

test('verified active owner can read a missing plan, create, list, update and delete it', async () => {
  const store = db('client');
  assert.equal((await assertSucceeds(getDoc(ref(store)))).exists(), false);
  await assertSucceeds(setDoc(ref(store), plan()));
  const saved = (await assertSucceeds(getDoc(ref(store)))).data();
  assert.equal(saved.revision, 1);
  assert.equal(saved.totalBudgetKzt, null);
  assert.ok(saved.updatedAt instanceof Timestamp);
  assert.equal((await assertSucceeds(getDocs(collection(store, 'accounts/client/eventPlans')))).size, 1);
  await assertSucceeds(updateDoc(ref(store), {
    revision: 2, totalBudgetKzt: 300000, notes: 'Проверить состав пакета',
    updatedAt: serverTimestamp(),
  }));
  assert.equal((await getDoc(ref(store))).data().revision, 2);
  await assertSucceeds(deleteDoc(ref(store)));
});

test('plans stay private from other accounts and staff', async () => {
  await seed({ 'accounts/client/eventPlans/event': { ...plan(), updatedAt: oldTime } });
  for (const uid of ['other', 'moderator', 'admin']) {
    const store = db(uid);
    await assertFails(getDoc(ref(store)));
    await assertFails(getDocs(collection(store, 'accounts/client/eventPlans')));
    await assertFails(setDoc(ref(store), plan({ revision: 2, notes: 'Подмена' })));
    await assertFails(deleteDoc(ref(store)));
    await assertFails(setDoc(ref(store, 'client', 'forged'), plan()));
  }
  // A staff role does not prevent an ordinary owner from keeping a private plan.
  await assertSucceeds(setDoc(ref(db('admin'), 'admin'), plan()));
});

test('anonymous, unverified, suspended, deactivated and missing-account users cannot access plans', async () => {
  const contexts = [
    { store: env.unauthenticatedContext().firestore(), uid: 'client' },
    { store: db('client', false), uid: 'client' },
    { store: db('suspended'), uid: 'suspended' },
    { store: db('deactivated'), uid: 'deactivated' },
    { store: db('missing'), uid: 'missing' },
  ];
  for (const { store, uid } of contexts) {
    await assertFails(getDoc(ref(store, uid)));
    await assertFails(getDocs(collection(store, `accounts/${uid}/eventPlans`)));
    await assertFails(setDoc(ref(store, uid), plan()));
    await assertFails(deleteDoc(ref(store, uid)));
  }
});

test('writes require the matching owner event; orphaned plans remain readable and removable', async () => {
  const store = db('client');
  await assertFails(setDoc(ref(store, 'client', 'missing'), plan()));
  await seed({ 'accounts/other/events/other-only': { ...event(), updatedAt: oldTime } });
  await assertFails(setDoc(ref(store, 'client', 'other-only'), plan()));
  await assertSucceeds(setDoc(ref(store), plan()));
  await deleteDoc(doc(store, 'accounts/client/events/event'));
  await assertFails(updateDoc(ref(store), { revision: 2, updatedAt: serverTimestamp() }));
  await assertSucceeds(getDoc(ref(store)));
  await assertSucceeds(deleteDoc(ref(store)));
});

test('an atomic event creation can include its plan but event deletion cannot include a plan write', async () => {
  const store = db('client');
  const create = writeBatch(store);
  create.set(doc(store, 'accounts/client/events/new'), event());
  create.set(ref(store, 'client', 'new'), plan());
  await assertSucceeds(create.commit());
  const remove = writeBatch(store);
  remove.delete(doc(store, 'accounts/client/events/new'));
  remove.update(ref(store, 'client', 'new'), { revision: 2, updatedAt: serverTimestamp() });
  await assertFails(remove.commit());
  assert.equal((await getDoc(doc(store, 'accounts/client/events/new'))).exists(), true);
});

test('maximum supported plan fits rule evaluation limits', async () => {
  const store = db('client');
  const maximum = plan({
    totalBudgetKzt: 1000000000,
    choices: Object.fromEntries(categories.map((category, index) => [category, choice({
      selectionId: `${index}${'s'.repeat(159)}`, contractorId: `${index}${'c'.repeat(159)}`,
    })])),
    completedTaskIds: tasks, notes: 'я'.repeat(2000),
  });
  await assertSucceeds(setDoc(ref(store), maximum));
  const stored = (await getDoc(ref(store))).data();
  assert.equal(Object.keys(stored.choices).length, 10);
  assert.equal(stored.completedTaskIds.length, 3);
});

test('plan shape rejects unknown fields, omitted fields and unsupported schemas', async () => {
  const store = db('client');
  for (const extra of [{ ownerId: 'other' }, { eventId: 'other' }, { role: 'admin' }]) {
    await assertFails(setDoc(ref(store), plan(extra)));
  }
  for (const key of Object.keys(plan())) {
    const missing = plan();
    delete missing[key];
    await assertFails(setDoc(ref(store), missing));
  }
  for (const schemaVersion of [0, 2, 1.5, '1', null]) {
    await assertFails(setDoc(ref(store), plan({ schemaVersion })));
  }
  for (const notes of ['x'.repeat(2001), 123, null]) {
    await assertFails(setDoc(ref(store), plan({ notes })));
  }
  await assertFails(setDoc(ref(store), plan({ updatedAt: oldTime })));
});

test('budget accepts unknown or positive integral tenge within its cap', async () => {
  const store = db('client');
  for (const totalBudgetKzt of [-1, 0, 1000000001, 1.5, '1000']) {
    await assertFails(setDoc(ref(store), plan({ totalBudgetKzt })));
  }
  await assertSucceeds(setDoc(ref(store), plan({ totalBudgetKzt: 1 })));
  await assertSucceeds(updateDoc(ref(store), {
    totalBudgetKzt: null, revision: 2, updatedAt: serverTimestamp(),
  }));
});

test('choices accept known categories and bounded references only', async () => {
  const store = db('client');
  const badChoices = [
    [], null, 'selection', { 'Неизвестная категория': choice() },
    { 'Фотограф': null }, { 'Фотограф': [] },
    { 'Фотограф': { selectionId: 'selection' } },
    { 'Фотограф': { contractorId: 'contractor' } },
    { 'Фотограф': choice({ price: 1 }) },
  ];
  for (const key of ['selectionId', 'contractorId']) {
    for (const value of ['', 'x'.repeat(161), 'nested/document', '.', '..', null, 1]) {
      badChoices.push({ 'Фотограф': choice({ [key]: value }) });
    }
  }
  for (const choices of badChoices) {
    await assertFails(setDoc(ref(store), plan({ choices })));
  }
});

test('completed tasks must come from the checklist without duplicates', async () => {
  const store = db('client');
  for (const completedTaskIds of [
    null, 'confirm_scope', {}, ['unknown'], [1],
    ['confirm_scope', 'confirm_scope'], [...tasks, 'confirm_scope'],
  ]) {
    await assertFails(setDoc(ref(store), plan({ completedTaskIds })));
  }
  await assertSucceeds(setDoc(ref(store), plan({ completedTaskIds: ['confirm_terms'] })));
});

test('revisions reject stale edits and require one-step increments', async () => {
  const store = db('client');
  for (const revision of [0, -1, 2, 1.5, '1']) {
    await assertFails(setDoc(ref(store), plan({ revision })));
  }
  await assertSucceeds(setDoc(ref(store), plan()));
  for (const revision of [0, 1, 3, 2.5, '2']) {
    await assertFails(updateDoc(ref(store), { revision, updatedAt: serverTimestamp() }));
  }
  await assertSucceeds(updateDoc(ref(store), { revision: 2, notes: 'Новое', updatedAt: serverTimestamp() }));
  await assertFails(setDoc(ref(store), plan({ revision: 2, notes: 'Устаревшее' })));
  assert.equal((await getDoc(ref(store))).data().notes, 'Новое');
});

test('two concurrent writes from the same revision cannot both overwrite the plan', async () => {
  const store = db('client');
  await setDoc(ref(store), plan());
  const results = await Promise.allSettled(['Выбор A', 'Выбор B'].map((notes) =>
    setDoc(ref(db('client')), plan({ revision: 2, notes })),
  ));
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(results.filter((result) => result.status === 'rejected').length, 1);
  const saved = (await getDoc(ref(store))).data();
  assert.equal(saved.revision, 2);
  assert.ok(['Выбор A', 'Выбор B'].includes(saved.notes));
});
