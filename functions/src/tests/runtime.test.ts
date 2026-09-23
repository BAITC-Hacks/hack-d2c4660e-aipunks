import test from "node:test";
import assert from "node:assert/strict";
import type { Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import {
  assertAssistantAccess, assertEmulatorConfiguration, configuredRateLimit, createCallableHandler, runtimeConfiguration, safeCallableError,
  type AccountState, type RuntimeAuth,
} from "../index";
import { FirestoreAssistantCache, MemoryAssistantCache, type AssistantCache } from "../storage";
import { AssistantError } from "../validation";

type Data = Record<string, unknown>;
interface Reference { path: string; get(): Promise<{ data(): Data | undefined }> }
interface Transaction {
  get(reference: Reference): Promise<{ data(): Data | undefined }>;
  set(reference: Reference, value: Data): void;
}

/** Serial transactions reproduce the first committed writer rule without a
 * remote service. Production concurrency relies on Firestore's transaction API. */
function transactionStore() {
  const documents = new Map<string, Data>();
  let previous = Promise.resolve();
  const fake = {
    collection: (name: string) => ({ doc: (id: string): Reference => {
      const path = `${name}/${id}`;
      return { path, get: async () => ({ data: () => structuredClone(documents.get(path)) }) };
    } }),
    runTransaction: async <T>(callback: (transaction: Transaction) => Promise<T>): Promise<T> => {
      const ready = previous;
      let release!: () => void;
      previous = new Promise<void>((resolve) => { release = resolve; });
      await ready;
      try {
        return await callback({
          get: (reference) => reference.get(),
          set: (reference, value) => { documents.set(reference.path, structuredClone(value)); },
        });
      } finally { release(); }
    },
  };
  return { db: fake as unknown as Firestore, documents };
}

for (const implementation of ["memory", "firestore"] as const) {
  test(`${implementation} cache has one concurrent winner and replaces only expired entries`, async () => {
    let now = 1000;
    const store = transactionStore();
    const cache: AssistantCache = implementation === "memory"
      ? new MemoryAssistantCache(() => now) : new FirestoreAssistantCache(store.db, () => now);
    const results = await Promise.all(Array.from({ length: 25 }, (_, number) =>
      cache.putIfAbsent("same-versioned-query", { winner: number }, 2)));
    assert.equal(new Set(results.map((item) => item.winner)).size, 1);
    const winner = results[0].winner;
    assert.deepEqual(await cache.get("same-versioned-query"), { winner });
    results[0].winner = -1;
    assert.deepEqual(await cache.get("same-versioned-query"), { winner });
    now = 2999;
    assert.deepEqual(await cache.putIfAbsent("same-versioned-query", { winner: 100 }, 2), { winner });
    now = 3000;
    assert.equal(await cache.get("same-versioned-query"), null);
    assert.deepEqual(await cache.putIfAbsent("same-versioned-query", { winner: 100 }, 2), { winner: 100 });
    if (implementation === "firestore") {
      assert.ok([...store.documents.keys()].every((key) => /^assistant_cache\/[a-f0-9]{64}$/.test(key)));
      assert.ok([...store.documents.values()].every((value) => "expiresAt" in value));
    }
  });

  test(`${implementation} rate limit is shared atomically per UID and resets next minute`, async () => {
    let now = 59_999;
    const store = transactionStore();
    const cache: AssistantCache = implementation === "memory"
      ? new MemoryAssistantCache(() => now) : new FirestoreAssistantCache(store.db, () => now);
    const admitted = await Promise.all(Array.from({ length: 30 }, () => cache.rateLimit("private-user-id", 20)));
    assert.equal(admitted.filter(Boolean).length, 20);
    assert.equal(await cache.rateLimit("another-user", 20), true);
    assert.equal(await cache.rateLimit("private-user-id", 20), false);
    now = 60_000;
    assert.equal(await cache.rateLimit("private-user-id", 20), true);
    if (implementation === "firestore") {
      assert.ok([...store.documents.keys()].every((key) => /^assistant_rate_limits\/[a-f0-9]{64}$/.test(key)));
    }
  });
}

test("invalid cache TTL and request limits never disable protection", async () => {
  const cache = new MemoryAssistantCache();
  for (const ttl of [0, -1, Infinity, NaN]) await assert.rejects(cache.putIfAbsent("key", "value", ttl));
  for (const limit of [0, -1, 0.5, Infinity, NaN]) await assert.rejects(cache.rateLimit("uid", limit));
  assert.equal(configuredRateLimit(undefined), 20);
  assert.equal(configuredRateLimit("12"), 12);
  for (const value of ["0", "-1", "no-limit", "Infinity", "1001", "1.5"]) assert.equal(configuredRateLimit(value), 20);
});

test("private Firestore cache entries retain ownerUid for account erasure; public vectors do not", async () => {
  const store = transactionStore();
  const cache = new FirestoreAssistantCache(store.db, () => 1000);
  await cache.putIfAbsent("parse:private", { preferences: ["Частное пожелание"] }, 60, { ownerUid: "account-a" });
  await cache.putIfAbsent("profile:public", [1, 0, 0], 60);
  const rows = [...store.documents.values()];
  assert.equal(rows.filter((row) => row.ownerUid === "account-a").length, 1);
  assert.equal(rows.filter((row) => !("ownerUid" in row)).length, 1);
  assert.ok(rows.every((row) => "expiresAt" in row));
});

test("a deletion tombstone prevents in-flight requests from recreating private cache or rate records", async () => {
  const store = transactionStore();
  const cache = new FirestoreAssistantCache(store.db, () => 1000);
  store.documents.set("deletedAccounts/removed", { completed: true });
  for (const work of [
    () => cache.putIfAbsent("parse:removed", { preferences: ["Частное пожелание"] }, 60, { ownerUid: "removed" }),
    () => cache.rateLimit("removed", 20),
  ]) await assert.rejects(work(), (error: unknown) => error instanceof AssistantError && error.code === "permission-denied");
  assert.deepEqual([...store.documents.keys()], ["deletedAccounts/removed"]);
});

test("an isolated Functions emulator cannot fall through to production account reads", () => {
  assert.doesNotThrow(() => assertEmulatorConfiguration(false, undefined));
  assert.doesNotThrow(() => assertEmulatorConfiguration(true, "127.0.0.1:8080"));
  assert.throws(() => assertEmulatorConfiguration(true, undefined), (error: unknown) =>
    error instanceof HttpsError && error.code === "failed-precondition");
});

test("documented environment options configure region, App Check, budget and emulator storage", () => {
  assert.deepEqual(runtimeConfiguration({}), {
    emulator: false, region: "us-central1", enforceAppCheck: false, requestsPerMinute: 20, storage: "firestore",
  });
  assert.deepEqual(runtimeConfiguration({
    FUNCTIONS_EMULATOR: "true", ASSISTANT_REGION: "europe-west1", ASSISTANT_ENFORCE_APP_CHECK: "true",
    ASSISTANT_RATE_LIMIT_PER_MINUTE: "7", ASSISTANT_STORAGE: "firestore",
  }), { emulator: true, region: "europe-west1", enforceAppCheck: true, requestsPerMinute: 7, storage: "firestore" });
  assert.equal(runtimeConfiguration({ FUNCTIONS_EMULATOR: "true" }).storage, "memory");
  assert.equal(runtimeConfiguration({ FUNCTIONS_EMULATOR: "true", ASSISTANT_STORAGE: "memory" }).storage, "memory");
  // A deployed instance cannot silently replace distributed limits with memory.
  assert.equal(runtimeConfiguration({ ASSISTANT_STORAGE: "memory" }).storage, "firestore");
});

const guest: RuntimeAuth = { uid: "guest", token: { firebase: { sign_in_provider: "anonymous" } } };
const member: RuntimeAuth = { uid: "member", token: { firebase: { sign_in_provider: "password" } } };
const noAccount: AccountState = { exists: false, status: null, deleted: false };
const hasCode = (code: string) => (error: unknown): boolean => error instanceof HttpsError && error.code === code;

test("auth UID is required, while guest and registered no-account sessions can use the independent assistant", async () => {
  let reads = 0;
  await assert.rejects(assertAssistantAccess(undefined, async () => { reads++; return noAccount; }), hasCode("unauthenticated"));
  assert.equal(reads, 0);
  assert.equal(await assertAssistantAccess(guest, async () => noAccount), "guest");
  assert.equal(await assertAssistantAccess(member, async () => noAccount), "member");
  assert.equal(await assertAssistantAccess(member, async () => ({ exists: true, status: "active", deleted: false })), "member");
});

test("deleted or restricted accounts are blocked for every provider including anonymous", async () => {
  for (const auth of [guest, member]) {
    for (const state of [
      { ...noAccount, deleted: true },
      { exists: true, status: "active", deleted: true },
      { exists: true, status: "suspended", deleted: false },
      { exists: true, status: "deactivated", deleted: false },
    ]) await assert.rejects(assertAssistantAccess(auth, async () => state), hasCode("permission-denied"));
  }
});

test("both callable methods recheck access before rate budget and before invoking the application", async () => {
  const calls: string[] = [];
  const cache = new MemoryAssistantCache();
  let restricted = false;
  const dependencies = {
    cache,
    requestsPerMinute: 1,
    readAccount: async () => {
      calls.push("account");
      return { exists: true, status: restricted ? "suspended" : "active", deleted: false };
    },
    application: () => {
      calls.push("application");
      return { turn: async (value: unknown) => ({ method: "turn", value }), recommend: async (value: unknown) => ({ method: "recommend", value }) };
    },
  };
  const turn = createCallableHandler("turn", dependencies);
  const recommend = createCallableHandler("recommend", dependencies);
  const payload = { city: "Алматы" };
  assert.deepEqual(await turn({ auth: member, data: payload }), { method: "turn", value: payload });
  assert.deepEqual(calls, ["account", "application"]);
  // The two endpoints share a rate budget, including when their result is cached.
  await assert.rejects(recommend({ auth: member, data: payload }), hasCode("resource-exhausted"));
  assert.deepEqual(calls, ["account", "application", "account"]);
  restricted = true;
  await assert.rejects(turn({ auth: member, data: payload }), hasCode("permission-denied"));
  assert.deepEqual(calls, ["account", "application", "account", "account"]);
  restricted = false;
  assert.deepEqual(await recommend({ auth: guest, data: payload }), { method: "recommend", value: payload });
});

test("callable selects a verified source and passes authenticated UID to its fresh application", async () => {
  const contexts: { uid: string; source: "live" | "demo" }[] = [];
  const handler = createCallableHandler("turn", {
    cache: new MemoryAssistantCache(), readAccount: async () => noAccount,
    application: async (context) => {
      contexts.push(context);
      return { turn: async () => context.source, recommend: async () => null };
    },
  });
  assert.equal(await handler({ auth: member, data: { source: "live" } }), "live");
  assert.equal(await handler({ auth: guest, data: {} }), "demo");
  await assert.rejects(handler({ auth: member, data: { source: "invalid" } }), hasCode("invalid-argument"));
  assert.deepEqual(contexts, [{ uid: "member", source: "live" }, { uid: "guest", source: "demo" }]);
});

test("callable errors contain static public messages and never raw model, transport or validation secrets", async () => {
  const secret = "fake-sensitive-api-credential";
  for (const error of [
    new Error(`Network request failed with Authorization: Bearer ${secret}`),
    new AssistantError("invalid-argument", secret, { input: secret }),
    new HttpsError("internal", secret, { key: secret }),
  ]) {
    const safe = safeCallableError(error);
    assert.equal(safe.message.includes(secret), false);
    assert.equal(JSON.stringify(safe).includes(secret), false);
  }
  const handler = createCallableHandler("turn", {
    cache: new MemoryAssistantCache(), readAccount: async () => noAccount,
    application: () => ({
      turn: async () => { throw new Error(secret); }, recommend: async () => null,
    }),
  });
  await assert.rejects(handler({ auth: guest, data: {} }), (error: unknown) => {
    assert.ok(error instanceof HttpsError);
    assert.equal(error.code, "unavailable");
    assert.equal(error.message.includes(secret), false);
    return true;
  });
});
