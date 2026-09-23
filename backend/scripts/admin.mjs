#!/usr/bin/env node
/** Trusted, local maintenance only. Never ship these credentials to Flutter. */
import { parseArgs } from 'node:util';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    project: { type: 'string' }, uid: { type: 'string' }, reason: { type: 'string' },
    execute: { type: 'boolean', default: false }, 'confirm-project': { type: 'string' },
    help: { type: 'boolean', default: false },
  },
});
const command = positionals[0];
const help = `Usage: npm run admin -- <grant-admin|revoke-admin|delete-account> --project PROJECT --uid UID --reason REASON [--execute --confirm-project PROJECT]

Default is a read-only preview. Uses Application Default Credentials, or Auth and
Firestore emulator hosts together for a demo-* project. grant-admin requires an
existing, verified active account. revoke-admin requires another verified active
administrator to remain. delete-account requires a recorded deletion
request (deactivated + deletionRequested), or an existing deletion tombstone on retry.
Never place a service-account key in this repository.`;
if (values.help) { console.log(help); process.exit(0); }
if (!['grant-admin', 'revoke-admin', 'delete-account'].includes(command) || !values.project || !values.uid || !values.reason?.trim()) {
  console.error(help); process.exit(2);
}
if (values.uid.includes('/') || values.uid.length > 128 || values.reason.length > 1000) throw new Error('Invalid UID or reason');
if (values.execute && values['confirm-project'] !== values.project) throw new Error('--confirm-project must exactly match --project when executing');
const emulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST);
if (emulator && (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST || !values.project.startsWith('demo-'))) {
  throw new Error('Set BOTH emulator hosts and use a demo-* project; partial emulator configuration is forbidden');
}
initializeApp({ projectId: values.project, ...(emulator ? {} : { credential: applicationDefault() }) });
const store = getFirestore();
const auth = getAuth();
const uid = values.uid;
const accountRef = store.doc(`accounts/${uid}`);
const lockRef = store.doc(`deletedAccounts/${uid}`);
const [accountDoc, lockDoc] = await Promise.all([accountRef.get(), lockRef.get()]);
const account = accountDoc.data();
const actorId = 'trusted-maintenance';
const auditDoc = (kind, revision) => store.doc(`audit/${kind}_${uid}_${revision}`);
const auditData = (kind, revision, action) => ({ actorId, resourceType: kind, resourceId: uid, revision, action, reason: values.reason.trim(), createdAt: FieldValue.serverTimestamp() });

async function grantAdmin() {
  if (lockDoc.exists || account?.status !== 'active') throw new Error('An existing active account is required');
  const user = await auth.getUser(uid);
  if (!user.emailVerified || user.disabled) throw new Error('The Firebase Auth account must be verified and enabled');
  const roleRef = store.doc(`staffAccess/${uid}`);
  const previous = await roleRef.get();
  console.log(JSON.stringify({ project: values.project, command, uid, previousRole: previous.data()?.role ?? 'none', nextRole: 'admin', execute: values.execute }, null, 2));
  if (!values.execute) return;
  await store.runTransaction(async (tx) => {
    const [currentRole, currentAccount, currentLock] = await Promise.all([tx.get(roleRef), tx.get(accountRef), tx.get(lockRef)]);
    if (currentLock.exists || currentAccount.data()?.status !== 'active') throw new Error('Account state changed; refusing grant');
    const revision = (currentRole.data()?.revision ?? 0) + 1;
    tx.set(roleRef, { role: 'admin', revision, updatedAt: FieldValue.serverTimestamp() });
    tx.create(auditDoc('staff', revision), auditData('staff', revision, 'admin'));
  });
}

async function revokeAdmin() {
  const adminsQuery = store.collection('staffAccess').where('role', '==', 'admin');
  const check = async (tx) => {
    const admins = tx ? await tx.get(adminsQuery) : await adminsQuery.get();
    const target = admins.docs.find((d) => d.id === uid);
    if (!target) throw new Error('Target does not currently hold the admin role');
    const candidates = admins.docs.filter((d) => d.id !== uid);
    const accountDocs = await Promise.all(candidates.map((d) => tx ? tx.get(store.doc(`accounts/${d.id}`)) : store.doc(`accounts/${d.id}`).get()));
    for (const candidate of accountDocs) {
      if (candidate.data()?.status !== 'active') continue;
      try {
        const user = await auth.getUser(candidate.id);
        if (user.emailVerified && !user.disabled) return target;
      } catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
    }
    throw new Error('Cannot revoke the last verified active administrator; grant another administrator first');
  };
  const target = await check();
  console.log(JSON.stringify({ project: values.project, command, uid, previousRole: 'admin', nextRole: 'none', execute: values.execute }, null, 2));
  if (!values.execute) return;
  await store.runTransaction(async (tx) => {
    // Reading the entire admin query prevents two concurrent revocations from
    // independently treating each other's soon-to-be-revoked role as the backup.
    const current = await check(tx);
    const revision = current.data().revision + 1;
    tx.update(target.ref, { role: 'none', revision, updatedAt: FieldValue.serverTimestamp() });
    tx.create(auditDoc('staff', revision), auditData('staff', revision, 'none'));
  });
}

async function deleteAccount() {
  if (!lockDoc.exists && (account?.status !== 'deactivated' || account.deletionRequested !== true)) {
    throw new Error('Requires the owner’s recorded request: status=deactivated and deletionRequested=true');
  }
  const [events, selections, favorites, calendars] = await Promise.all([
    accountRef.collection('events').get(), accountRef.collection('selections').get(),
    accountRef.collection('favorites').get(), store.collection(`calendars/${uid}/months`).get(),
  ]);
  console.log(JSON.stringify({ project: values.project, command, uid, execute: values.execute, resuming: lockDoc.exists,
    ownDocuments: { events: events.size, selections: selections.size, favorites: favorites.size, calendarMonths: calendars.size },
    additionalCleanup: 'contractor snapshots in other accounts, profile, publication, staff role, audit identifiers, Firebase Auth',
  }, null, 2));
  if (!values.execute) return;

  // This lock is deliberately retained: pre-deletion ID tokens must not recreate
  // accounts before they expire. It contains no email, name, contact or profile.
  await store.runTransaction(async (tx) => {
    const [currentAccount, currentLock, publication] = await Promise.all([
      tx.get(accountRef), tx.get(lockRef), tx.get(store.doc(`publishedProfiles/${uid}`)),
    ]);
    if (!currentLock.exists && (currentAccount.data()?.status !== 'deactivated' || currentAccount.data()?.deletionRequested !== true)) throw new Error('Deletion request changed');
    if (!currentLock.exists) tx.create(lockRef, { requestedAt: FieldValue.serverTimestamp(), completed: false });
    if (publication.data()?.published === true) tx.update(publication.ref, { published: false, revision: publication.data().revision + 1, updatedAt: FieldValue.serverTimestamp() });
  });
  try {
    await auth.updateUser(uid, { disabled: true });
    await auth.revokeRefreshTokens(uid);
  } catch (error) { if (error.code !== 'auth/user-not-found') throw error; }

  // Historical selections are private snapshots, so remove this contractor's
  // copied public content as well. All other entries and event metadata survive.
  const otherFavorites = await store.collectionGroup('favorites').where('contractor.id', '==', uid).get();
  for (const favorite of otherFavorites.docs) await favorite.ref.delete();
  const allSelections = await store.collectionGroup('selections').get();
  for (const selection of allSelections.docs) {
    if (Array.isArray(selection.data().entries) && selection.data().entries.some((e) => e?.contractor?.id === uid)) {
      await store.runTransaction(async (tx) => {
        const latest = await tx.get(selection.ref);
        const entries = latest.data()?.entries;
        if (Array.isArray(entries)) tx.update(selection.ref, { entries: entries.filter((e) => e?.contractor?.id !== uid) });
      });
    }
  }
  const targetAudit = await store.collection('audit').where('resourceId', '==', uid).get();
  for (const row of targetAudit.docs) await row.ref.delete();
  const actorAudit = await store.collection('audit').where('actorId', '==', uid).get();
  for (const row of actorAudit.docs) await row.ref.update({ actorId: 'deleted-user' });
  await store.recursiveDelete(accountRef);
  await store.recursiveDelete(store.doc(`calendars/${uid}`));
  for (const collection of ['profiles', 'publishedProfiles', 'staffAccess']) await store.doc(`${collection}/${uid}`).delete();
  try { await auth.deleteUser(uid); } catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
  await lockRef.set({ completed: true, completedAt: FieldValue.serverTimestamp() }, { merge: true });
}

try {
  if (command === 'grant-admin') await grantAdmin();
  else if (command === 'revoke-admin') await revokeAdmin();
  else await deleteAccount();
  console.log(values.execute ? 'Completed.' : 'Preview only: no data changed.');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
