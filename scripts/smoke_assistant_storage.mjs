// Real Admin SDK transaction checks, restricted to the isolated local emulator.
// Run via firebase emulators:exec with firebase.assistant.json, never production.
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';

const host = process.env.FIRESTORE_EMULATOR_HOST;
assert.match(host ?? '', /^(127\.0\.0\.1|localhost):8180$/, 'Use the isolated Firestore emulator on 8180');
const projectId = process.env.GCLOUD_PROJECT || 'demo-event-match-assistant';
assert.equal(projectId, 'demo-event-match-assistant', 'Use the dedicated demo project');
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { FirestoreAssistantCache } = require('./lib/storage.js');
const app = initializeApp({ projectId }, `assistant-storage-smoke-${randomUUID()}`);
const db = getFirestore(app);
const hash = value => createHash('sha256').update(value).digest('hex');
const unique = randomUUID();
const key = `cache-smoke:${unique}:catalog-v1`;
const nextVersion = `cache-smoke:${unique}:catalog-v2`;
const uid = `storage-smoke-${unique}`;
const otherUid = `storage-smoke-other-${unique}`;
const paths = [
  `assistant_cache/${hash(key)}`, `assistant_cache/${hash(nextVersion)}`,
  `assistant_rate_limits/${hash(uid)}`, `assistant_rate_limits/${hash(otherUid)}`,
];
let now = Math.floor(Date.now() / 60_000) * 60_000 + 1_000;
const cacheA = new FirestoreAssistantCache(db, () => now);
const cacheB = new FirestoreAssistantCache(db, () => now);

try {
  const results = await Promise.all(Array.from({ length: 12 }, (_, index) =>
    (index % 2 ? cacheA : cacheB).putIfAbsent(key, { winner: index, sample: ['source evidence'] }, 30)));
  const winner = results[0].winner;
  assert.equal(new Set(results.map(result => result.winner)).size, 1, 'Separate cache instances must return one committed winner');
  const stored = (await db.doc(paths[0]).get()).data();
  assert.equal(stored.value.winner, winner);
  assert.equal(stored.expiresAt.toMillis(), now + 30_000);
  assert.equal(stored.expiresAtMs, now + 30_000);
  assert.equal((await cacheA.get(key)).winner, winner);
  assert.equal((await cacheB.putIfAbsent(key, { winner: -1 }, 900)).winner, winner);
  assert.equal((await db.doc(paths[0]).get()).data().expiresAtMs, stored.expiresAtMs, 'A cache hit must not extend the original expiry');
  assert.deepEqual(await cacheA.putIfAbsent(nextVersion, { winner: 'new-version' }, 30), { winner: 'new-version' });

  now += 30_000;
  assert.equal(await cacheB.get(key), null, 'Expiry must work before a Firestore TTL cleanup deletes the document');
  assert.deepEqual(await cacheB.putIfAbsent(key, { winner: 999 }, 30), { winner: 999 });

  const admitted = await Promise.all(Array.from({ length: 12 }, (_, index) =>
    (index % 2 ? cacheA : cacheB).rateLimit(uid, 5)));
  assert.equal(admitted.filter(Boolean).length, 5, 'A distributed UID budget must admit exactly its configured allowance');
  assert.equal((await db.doc(paths[2]).get()).data().count, 5);
  assert.equal(await cacheA.rateLimit(uid, 5), false);
  assert.equal(await cacheB.rateLimit(otherUid, 5), true, 'Different users have separate budgets');
  now = (Math.floor(now / 60_000) + 1) * 60_000;
  assert.equal(await cacheB.rateLimit(uid, 5), true, 'The next minute gets a new request window');
  assert.equal((await db.doc(paths[2]).get()).data().count, 1);
  console.log('Assistant storage emulator smoke passed: concurrent canonical cache winner, version separation, real Timestamp/expiry, distributed UID budget and window reset.');
} finally {
  await Promise.all(paths.map(path => db.doc(path).delete()));
  await deleteApp(app);
}
