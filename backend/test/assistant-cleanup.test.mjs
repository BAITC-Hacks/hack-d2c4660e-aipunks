import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const projectId = 'demo-event-match-assistant-privacy';
const runFile = promisify(execFile);
const hash = (uid) => createHash('sha256').update(uid).digest('hex');
let env;
let app;
let store;

before(async () => {
  assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST, 'Auth emulator must be enabled');
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Firestore emulator must be enabled');
  env = await initializeTestEnvironment({ projectId, firestore: { rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
  await env.clearFirestore();
  app = initializeApp({ projectId }, 'assistant-cleanup-test');
  store = getFirestore(app);
});
after(async () => { if (app) await deleteApp(app); await env?.cleanup(); });

test('account deletion previews and removes all private assistant cache pages and only its rate-limit document; retry is safe', async () => {
  const uid = 'assistant-owner';
  const expiresAt = Timestamp.fromMillis(Date.now() + 86_400_000);
  const batch = store.batch();
  batch.set(store.doc(`accounts/${uid}`), { status: 'deactivated', deletionRequested: true });
  // More than one cleanup page catches a partial deletion that small fixtures miss.
  for (let index = 0; index < 251; index++) batch.set(store.doc(`assistant_cache/private-${index}`), {
    ownerUid: uid, value: { privateText: 'Never printed in maintenance preview' }, expiresAt,
  });
  batch.set(store.doc('assistant_cache/another-user'), { ownerUid: 'another-user', value: { privateText: 'Preserve' }, expiresAt });
  batch.set(store.doc('assistant_cache/public-vector'), { value: [0.1, 0.2], expiresAt });
  batch.set(store.doc(`assistant_rate_limits/${hash(uid)}`), { window: 1, count: 2, expiresAt });
  batch.set(store.doc(`assistant_rate_limits/${hash('another-user')}`), { window: 1, count: 2, expiresAt });
  await batch.commit();
  const args = ['scripts/admin.mjs', 'delete-account', '--project', projectId, '--uid', uid, '--reason', 'Confirmed emulator deletion request'];
  const cli = (...extra) => runFile(process.execPath, [...args, ...extra], { cwd: new URL('..', import.meta.url), env: process.env });

  const preview = (await cli()).stdout;
  assert.match(preview, /"assistantCache": 251/);
  assert.match(preview, /"assistantRateLimits": 1/);
  assert.match(preview, /Preview only/);
  assert.ok(!preview.includes('Never printed'));
  assert.equal((await store.doc('assistant_cache/private-0').get()).exists, true);
  assert.equal((await store.doc(`deletedAccounts/${uid}`).get()).exists, false);

  await cli('--execute', '--confirm-project', projectId);
  assert.equal((await store.collection('assistant_cache').where('ownerUid', '==', uid).get()).size, 0);
  assert.equal((await store.doc(`assistant_rate_limits/${hash(uid)}`).get()).exists, false);
  assert.equal((await store.doc('assistant_cache/another-user').get()).exists, true);
  assert.equal((await store.doc('assistant_cache/public-vector').get()).exists, true);
  assert.equal((await store.doc(`assistant_rate_limits/${hash('another-user')}`).get()).exists, true);
  assert.equal((await store.doc(`deletedAccounts/${uid}`).get()).data().completed, true);

  // An interrupted earlier release may leave owned cache after a tombstone.
  await store.doc('assistant_cache/retry-leftover').set({ ownerUid: uid, value: 'retry', expiresAt });
  await cli('--execute', '--confirm-project', projectId);
  assert.equal((await store.doc('assistant_cache/retry-leftover').get()).exists, false);
  assert.equal((await store.doc('assistant_cache/another-user').get()).exists, true);
});
