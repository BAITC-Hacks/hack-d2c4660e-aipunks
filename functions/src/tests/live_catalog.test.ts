import assert from "node:assert/strict";
import { test } from "node:test";
import type { Firestore } from "firebase-admin/firestore";
import { buildTurn } from "../dialogue";
import { dateIsCovered, evaluate, recommend } from "../engine";
import { calendarAvailability, liveDatePolicy, loadLiveCatalog } from "../live_catalog";
import { emptyBrief, type Brief } from "../types";

const now = new Date("2026-09-23T12:00:00Z");
const date = "2026-10-15";
const dayMs = 86_400_000;
const brief = (patch: Partial<Brief> = {}): Brief => ({ ...emptyBrief(), city: "Алматы", category: "Ведущий",
  event_format: "корпоратив", date, budget_kzt: 500_000, ...patch });
const publication = (id: string, patch: Record<string, unknown> = {}) => ({ ownerId: id, published: true, revision: 1,
  profileRevision: 1, updatedAt: now, content: { name: `Профиль ${id}`, city: "Алматы", categories: ["Ведущий"],
    price: 100_000, formats: ["корпоратив"], languages: ["русский"], maxHours: 6,
    description: "Ведущий с индивидуальной программой.", contact: "+7 700 000 00 00", portfolioUrls: ["https://example.com/work"] }, ...patch });
const calendar = (id: string, patch: Record<string, unknown> = {}) => ({ ownerId: id, year: 2026, month: 10,
  busyDays: [], confirmedAt: now, ...patch });

function fakeStore(initial: Record<string, unknown>) {
  const records = new Map(Object.entries(initial));
  const reads: string[] = [];
  const snapshot = (path: string) => ({ id: path.split("/").at(-1), exists: records.has(path), data: () => records.get(path) });
  const db = {
    doc: (path: string) => ({ path }),
    getAll: async (...refs: { path: string }[]) => refs.map(({ path }) => { reads.push(path); return snapshot(path); }),
    collection: (name: string) => ({ where: (key: string, op: string, value: unknown) => {
      assert.deepEqual([name, key, op, value], ["publishedProfiles", "published", "==", true]);
      return { get: async () => ({ docs: [...records.entries()].filter(([path, data]) =>
        path.startsWith("publishedProfiles/") && (data as Record<string, unknown>).published === true).map(([path]) => snapshot(path)) }) };
    } }),
  } as unknown as Firestore;
  return { db, records, reads };
}
function fixture(ids: string[]) {
  return Object.fromEntries(ids.flatMap((id) => [
    [`publishedProfiles/${id}`, publication(id)], [`accounts/${id}`, { status: "active" }],
    [`calendars/${id}/months/2026-10`, calendar(id)],
  ]));
}

test("live date horizon uses Almaty day and includes exactly today through today + 365", () => {
  assert.deepEqual(liveDatePolicy(new Date("2026-09-23T18:59:59Z")), { firstDate: "2026-09-23", lastDate: "2027-09-23" });
  assert.deepEqual(liveDatePolicy(new Date("2026-09-23T19:00:00Z")), { firstDate: "2026-09-24", lastDate: "2027-09-24" });
  assert.throws(() => liveDatePolicy(new Date("invalid")));
});

test("live publication loader exposes only active undeleted public profiles and DTO fields", async () => {
  const store = fakeStore({ ...fixture(["active", "suspended", "deactivated", "deleted", "missing", "draft"]),
    "accounts/suspended": { status: "suspended" }, "accounts/deactivated": { status: "deactivated" },
    "deletedAccounts/deleted": { deletedAt: now }, "publishedProfiles/draft": publication("draft", { published: false }),
    "profiles/active": { privateNotes: "must never appear" },
  });
  store.records.delete("accounts/missing");
  const catalog = await loadLiveCatalog(store.db, now);
  assert.deepEqual(catalog.contractors.map((item) => item.id), ["active"]);
  const item = catalog.contractors[0];
  assert.equal(item.is_live, true);
  assert.equal(item.contact, "+7 700 000 00 00");
  assert.deepEqual(item.portfolio_urls, ["https://example.com/work"]);
  assert.deepEqual(item.busy_dates, []);
  assert.equal(item.synthetic, false);
  assert.ok(!JSON.stringify(item).includes("privateNotes"));
  assert.ok(!store.reads.some((path) => path.startsWith("profiles/")));
});

test("malformed public documents fail closed instead of exposing partially decoded cards", async () => {
  const bad = publication("bad");
  const store = fakeStore({ ...fixture(["bad", "other"]),
    "publishedProfiles/bad": { ...bad, content: { ...bad.content, portfolioUrls: ["javascript:alert(1)"] } },
    "publishedProfiles/other": publication("wrong-owner"),
  });
  assert.deepEqual((await loadLiveCatalog(store.db, now)).contractors, []);
});

test("catalog and profile versions are stable under document order and change with published revision/content", async () => {
  const records = fixture(["b", "a"]);
  const one = await loadLiveCatalog(fakeStore(records).db, now);
  const two = await loadLiveCatalog(fakeStore(Object.fromEntries(Object.entries(records).reverse())).db, now);
  assert.deepEqual(one.contractors.map((item) => item.id), ["a", "b"]);
  assert.equal(one.datasetVersion, two.datasetVersion);
  assert.equal(one.profileVersions?.get("a"), two.profileVersions?.get("a"));
  const updated = publication("a", { revision: 2 });
  const three = await loadLiveCatalog(fakeStore({ ...records, "publishedProfiles/a": updated }).db, now);
  assert.notEqual(one.datasetVersion, three.datasetVersion);
  assert.notEqual(one.profileVersions?.get("a"), three.profileVersions?.get("a"));
  assert.equal(one.profileVersions?.get("b"), three.profileVersions?.get("b"));
});

test("calendar freshness is strict, accepts Firestore timestamps and rejects invalid calendar facts", () => {
  assert.equal(calendarAvailability(calendar("a"), "a", date, now), "available");
  assert.equal(calendarAvailability(calendar("a", { busyDays: [15] }), "a", date, now), "busy");
  assert.equal(calendarAvailability(calendar("a", { confirmedAt: { toMillis: () => now.getTime() - 30 * dayMs + 1 } }), "a", date, now), "available");
  for (const patch of [
    { confirmedAt: new Date(now.getTime() - 30 * dayMs) }, { confirmedAt: new Date(now.getTime() + 1) },
    { confirmedAt: null }, { ownerId: "b" }, { month: 9 }, { busyDays: [32] }, { busyDays: [1, 1] }, { busyDays: ["15"] },
  ]) assert.equal(calendarAvailability(calendar("a", patch), "a", date, now), "unconfirmed");
  assert.equal(calendarAvailability(null, "a", date, now), "unconfirmed");
  assert.equal(calendarAvailability(calendar("a", { month: 2 }), "a", "2026-02-30", now), "unconfirmed");
});

test("live resolver reads only requested month fresh on every call and does not read outside horizon", async () => {
  const store = fakeStore(fixture(["a", "b"]));
  const catalog = await loadLiveCatalog(store.db, now);
  assert.equal((await catalog.resolveAvailability!(date)).get("a"), "available");
  store.records.set("calendars/a/months/2026-10", calendar("a", { busyDays: [15] }));
  assert.equal((await catalog.resolveAvailability!(date)).get("a"), "busy");
  store.records.delete("calendars/b/months/2026-10");
  assert.equal((await catalog.resolveAvailability!(date)).get("b"), "unconfirmed");
  const readCount = store.reads.length;
  assert.deepEqual([...await catalog.resolveAvailability!("2027-10-01")], [["a", "unconfirmed"], ["b", "unconfirmed"]]);
  assert.equal(store.reads.length, readCount);
  assert.ok(store.reads.filter((path) => path.startsWith("calendars/")).every((path) => path.endsWith("/2026-10")));
});

test("only confirmed available live candidates pass; strong semantic scores cannot bypass calendar or hard filters", async () => {
  const store = fakeStore(fixture(["available", "busy", "missing", "expensive"]));
  store.records.set("calendars/busy/months/2026-10", calendar("busy", { busyDays: [15] }));
  store.records.delete("calendars/missing/months/2026-10");
  const costly = publication("expensive");
  store.records.set("publishedProfiles/expensive", { ...costly, content: { ...costly.content, price: 900_000 } });
  const catalog = await loadLiveCatalog(store.db, now);
  const hydrated = { ...catalog, availabilityDate: date, availability: await catalog.resolveAvailability!(date) };
  const evaluation = evaluate(hydrated, brief(), new Map([["busy", 1], ["missing", 1], ["expensive", 1]]));
  assert.deepEqual(evaluation.eligible.map((item) => item.contractor.id), ["available"]);
  assert.deepEqual(evaluation.rejected, { busy: 1, budget: 1, unconfirmed: 1 });
  const result = recommend(hydrated, brief());
  assert.equal(result.preliminary, false);
  assert.match(result.summary, /подтверждена актуальным календарём/);
});

test("an unresolved or different-date availability map cannot imply availability", async () => {
  const catalog = await loadLiveCatalog(fakeStore(fixture(["a"])).db, now);
  assert.equal(recommend(catalog, brief()).outcome, "no_eligible");
  assert.equal(recommend({ ...catalog, availabilityDate: "2026-10-16", availability: new Map([["a", "available"]]) }, brief()).outcome, "no_eligible");
});

test("missing date and dates outside live horizon retain preliminary results without promising availability", async () => {
  const catalog = await loadLiveCatalog(fakeStore(fixture(["a"])).db, now);
  assert.equal(dateIsCovered("2026-09-23", catalog), true);
  assert.equal(dateIsCovered("2027-09-23", catalog), true);
  for (const targetDate of [null, "2026-09-22", "2027-09-24"]) {
    const result = recommend(catalog, brief({ date: targetDate }));
    assert.equal(result.preliminary, true);
    assert.deepEqual(result.recommendations.map((item) => item.contractor.id), ["a"]);
    assert.ok(result.unchecked.some((label) => /Дата/.test(label)));
    assert.ok(!result.summary.includes("подтверждена актуальным календарём"));
  }
});

test("live preferences remain unknown without curated evidence, even when description looks similar", async () => {
  const catalog = await loadLiveCatalog(fakeStore(fixture(["a"])).db, now);
  assert.ok(catalog.featureDefinitions.some((item) => item.key === "personalized_program"));
  assert.deepEqual(catalog.features.get("a"), []);
  const result = recommend({ ...catalog, availabilityDate: date, availability: await catalog.resolveAvailability!(date) }, brief({
    preferences: [{ text: "индивидуальная программа", feature_id: "personalized_program", importance: "required", polarity: "positive" }],
  }));
  assert.equal(result.recommendations[0].evidence[0].status, "unknown");
  assert.equal(result.preliminary, true);
});

test("empty live catalog does not start a pointless questionnaire or imply city/category absence", async () => {
  const catalog = await loadLiveCatalog(fakeStore({}).db, now);
  const turn = buildTurn(catalog, emptyBrief(), { mode: "basic" });
  assert.equal(turn.question_field, null);
  assert.deepEqual(turn.actions, []);
  assert.match(turn.message, /нет опубликованных подрядчиков/);
  assert.match(recommend(catalog, brief()).summary, /нет опубликованных подрядчиков/);
});
