#!/usr/bin/env node
// Fixtures only for the isolated Dart/Chrome repository smoke test.
// FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9299 FIRESTORE_EMULATOR_HOST=127.0.0.1:8280 \
//   node backend/scripts/seed-communication-smoke.mjs
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const projectId = 'demo-communication-smoke';
for (const [key, value] of Object.entries({
  FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9299',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:8280',
})) {
  if (process.env[key] !== value) throw new Error(`${key} must be ${value}; cloud and preview writes are forbidden.`);
}
if (process.argv.length !== 2) throw new Error('This fixture script accepts no arguments.');

const app = initializeApp({ projectId }, 'communication-smoke-seed');
const auth = getAuth(app);
const store = getFirestore(app);
const password = 'CommunicationSmoke2026!';
const stamp = () => FieldValue.serverTimestamp();
try {
  for (const uid of ['client', 'vendor', 'admin', 'other']) {
    const email = `${uid}@communication.example.com`;
    try {
      const existing = await auth.getUser(uid);
      if (existing.email !== email || !existing.emailVerified) throw new Error(`Unexpected isolated fixture user ${uid}.`);
    } catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
      await auth.createUser({ uid, email, password, displayName: uid, emailVerified: true });
    }
    await store.doc(`accounts/${uid}`).set({
      uid, name: uid, email, status: 'active', deletionRequested: false,
      revision: 1, createdAt: stamp(), updatedAt: stamp(),
    });
  }
  await store.doc('staffAccess/admin').set({ role: 'admin', revision: 1, updatedAt: stamp() });
  const content = {
    name: 'Тестовый ведущий', city: 'Алматы', categories: ['Ведущий'], price: 300000,
    formats: ['свадьба'], languages: ['русский'], maxHours: 8,
    description: 'Ведущий для проверки доставки заявок.', contact: 'vendor@communication.example.com', portfolioUrls: [],
  };
  await store.doc('profiles/vendor').set({
    ownerId: 'vendor', revision: 3, status: 'approved', content, reason: '', updatedAt: stamp(),
  });
  await store.doc('publishedProfiles/vendor').set({
    ownerId: 'vendor', revision: 1, profileRevision: 3, published: true, content, updatedAt: stamp(),
  });
  await store.doc('accounts/client/events/wedding').set({
    name: 'Свадьба для smoke-теста', city: 'Алматы', date: '2026-11-14', format: 'свадьба',
    preferences: '50 гостей, спокойная программа.', updatedAt: stamp(),
  });
  console.log(`Seeded ${projectId}: verified client/vendor/admin/other and published vendor + client wedding.`);
} finally {
  await deleteApp(app);
}
