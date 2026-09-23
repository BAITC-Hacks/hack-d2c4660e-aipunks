import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { actionFor } from "../actions";
import { type Interpretation, type LanguageModel } from "../openai";
import { AssistantApplication, type EmbeddingIndex } from "../service";
import { MemoryAssistantCache } from "../storage";
import { type AssistantInput, type Brief, type Catalog, type Contractor, emptyBrief } from "../types";
import { AssistantError, briefSchema } from "../validation";

const fullBrief = (patch: Partial<Brief> = {}): Brief => ({ ...emptyBrief(), city: "Алматы", category: "Ведущий",
  event_format: "корпоратив", date: "2026-10-15", budget_kzt: 500_000, ...patch });
const profile = (id: string, patch: Partial<Contractor> = {}): Contractor => ({ id, anon_name: id, city: "Алматы",
  categories: ["Ведущий"], event_formats: ["корпоратив"], languages: ["русский"], busy_dates: [],
  price_from_kzt: 100_000, max_hours: 6, description: "Спокойное ведение с живой музыкой.",
  synthetic: false, city_imputed: false, price_imputed: false, ...patch });
const fixture = (): Catalog => ({ datasetVersion: "test-catalog-v1", featureVersion: "1",
  contractors: [profile("a"), profile("b", { price_from_kzt: 300_000 }), profile("c", { busy_dates: ["2026-10-15"] })],
  featureDefinitions: [{ key: "calm", label: "Спокойное ведение", description: "Спокойный стиль" }],
  features: new Map([["a", [{ key: "calm", polarity: "supports", quote: "Спокойное ведение" }]]]),
});
const interpretation = (brief: Brief): Interpretation => ({ brief: briefSchema.parse(brief), operation: "update", question: null, question_field: null, choices: [] });
class FakeModel implements LanguageModel {
  available = true;
  version = "fake-model:brief-v1";
  extractionInputs: AssistantInput[] = [];
  embeddingInputs: string[] = [];
  constructor(private readonly handler: (input: AssistantInput) => Promise<Interpretation> = async (input) => interpretation(input.brief)) {}
  async extract(input: AssistantInput): Promise<Interpretation> {
    this.extractionInputs.push(structuredClone(input));
    return this.handler(input);
  }
  async embed(text: string, _model: string, dimensions: number): Promise<number[]> {
    this.embeddingInputs.push(text);
    return [1, ...Array<number>(dimensions - 1).fill(0)];
  }
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const tick = () => new Promise<void>((resolve) => setImmediate(resolve));
const hasCode = (code: string) => (error: unknown) => error instanceof AssistantError && error.code === code;

function embeddingIndex(catalog: Catalog): EmbeddingIndex {
  const labels = new Map(catalog.featureDefinitions.map((feature) => [feature.key, feature.label]));
  const inputs = catalog.contractors.map((contractor) => [`Категории: ${contractor.categories.join(", ")}`, contractor.description,
    ...(catalog.features.get(contractor.id) ?? []).map((feature) => `${feature.polarity === "supports" ? "Указано в профиле" : "Профиль противоречит пожеланию"} «${labels.get(feature.key)}»: ${feature.quote}`),
  ].join("\n"));
  return { schemaVersion: 1, datasetVersion: catalog.datasetVersion, featureVersion: catalog.featureVersion,
    model: "text-embedding-3-small", dimensions: 1536,
    inputVersion: `sha256:${createHash("sha256").update(JSON.stringify(inputs)).digest("hex")}`,
    profiles: catalog.contractors.map((contractor, index) => ({ id: contractor.id,
      embedding: [index === 0 ? 1 : 0, index === 0 ? 0 : 1, ...Array<number>(1534).fill(0)] })),
  };
}

test("complete natural-language request yields cards without extra questions", async () => {
  const model = new FakeModel(async () => interpretation(fullBrief()));
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const input = { brief: emptyBrief(), message: "Нужен ведущий на корпоратив в Алматы 15 октября 2026 до 500000 тенге" };
  const turn = await app.turn(input);
  assert.equal(model.extractionInputs.length, 1);
  assert.equal(turn.mode, "ai");
  assert.equal(turn.question_field, null);
  assert.deepEqual(turn.result?.recommendations.map((item) => item.contractor.id), ["a", "b"]);
  assert.deepEqual(input.brief, emptyBrief());
});

test("typed buttons bypass language-model extraction and preserve constraints", async () => {
  const model = new FakeModel(async () => { throw new Error("Typed actions must not call extraction"); });
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const brief = fullBrief();
  const turn = await app.turn({ brief, action: actionFor(brief, "Меньше бюджет", "set_field", "budget_kzt", 200_000) });
  assert.equal(model.extractionInputs.length, 0);
  assert.equal(turn.brief.budget_kzt, 200_000);
  assert.equal(turn.brief.date, brief.date);
  assert.deepEqual(turn.result?.recommendations.map((item) => item.contractor.id), ["a"]);
});

test("canonical parsing cache ignores JSON object key order and returns an immutable result", async () => {
  const model = new FakeModel(async () => interpretation(fullBrief()));
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const brief = emptyBrief();
  const input = { brief, message: "Полный запрос", history: [] };
  const first = await app.turn(input);
  first.brief.city = "Внешняя мутация";
  const reversedBrief = Object.fromEntries(Object.entries(brief).reverse());
  const second = await app.turn({ history: [], message: "Полный запрос", brief: reversedBrief });
  assert.equal(model.extractionInputs.length, 1);
  assert.equal(second.brief.city, "Алматы");
});

test("concurrent identical turns share a single extraction within one instance", async () => {
  const model = new FakeModel(async () => { await tick(); return interpretation(fullBrief()); });
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const input = { brief: emptyBrief(), message: "Полный запрос" };
  const results = await Promise.all(Array.from({ length: 8 }, () => app.turn(input)));
  assert.equal(model.extractionInputs.length, 1);
  results.forEach((turn) => assert.deepEqual(turn, results[0]));
});

test("separate instances return the first committed canonical interpretation", async () => {
  const cache = new MemoryAssistantCache();
  const first = deferred<Interpretation>();
  const second = deferred<Interpretation>();
  const modelA = new FakeModel(() => first.promise);
  const modelB = new FakeModel(() => second.promise);
  const appA = new AssistantApplication(fixture(), cache, modelA, null);
  const appB = new AssistantApplication(fixture(), cache, modelB, null);
  const input = { brief: emptyBrief(), message: "Неоднозначный запрос" };
  const requestA = appA.turn(input);
  const requestB = appB.turn(input);
  await tick();
  second.resolve(interpretation(fullBrief({ budget_kzt: 200_000 })));
  const resultB = await requestB;
  first.resolve(interpretation(fullBrief({ budget_kzt: 500_000 })));
  assert.deepEqual(await requestA, resultB);
  assert.equal(resultB.brief.budget_kzt, 200_000);
});

test("failed extraction clears pending work and does not poison the cache", async () => {
  let calls = 0;
  const model = new FakeModel(async () => {
    calls++;
    if (calls === 1) throw new AssistantError("unavailable", "Повторите");
    return interpretation(fullBrief());
  });
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const input = { brief: emptyBrief(), message: "Запрос" };
  await assert.rejects(app.turn(input), hasCode("unavailable"));
  assert.equal((await app.turn(input)).result?.outcome, "matched");
  assert.equal(calls, 2);
});

test("model and dataset version changes invalidate parsing cache", async () => {
  const cache = new MemoryAssistantCache();
  const model = new FakeModel(async () => interpretation(fullBrief()));
  const input = { brief: emptyBrief(), message: "Запрос" };
  await new AssistantApplication(fixture(), cache, model, null).turn(input);
  model.version = "fake-model:brief-v2";
  await new AssistantApplication(fixture(), cache, model, null).turn(input);
  await new AssistantApplication({ ...fixture(), datasetVersion: "new-data" }, cache, model, null).turn(input);
  assert.equal(model.extractionInputs.length, 3);
});

test("clarification preserves known conditions and offers only the one ambiguous field", async () => {
  const known = fullBrief({ category: null });
  const model = new FakeModel(async () => ({ ...interpretation(known), operation: "clarify",
    question: "Кого подберём сначала?", question_field: "category", choices: ["Ведущий", "Фотограф"] }));
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const turn = await app.turn({ brief: known, message: "Ведущий и фотограф" });
  assert.equal(turn.result, null);
  assert.equal(turn.question_field, "category");
  assert.equal(turn.brief.city, known.city);
  assert.equal(turn.brief.date, known.date);
  assert.equal(turn.brief.budget_kzt, known.budget_kzt);
  const choice = turn.actions.find((action) => action.type === "set_field" && action.value === "Ведущий")!;
  const answered = await app.turn({ brief: turn.brief, action: choice });
  assert.equal(answered.result?.outcome, "matched");
  assert.equal(model.extractionInputs.length, 1);
});

test("clarification cannot erase known scalar fields when extraction leaves them null", async () => {
  const known = fullBrief({ category: null });
  const model = new FakeModel(async () => ({ ...interpretation(emptyBrief()), operation: "clarify",
    question: "Кого подберём сначала?", question_field: "category", choices: ["Ведущий", "Фотограф"] }));
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const turn = await app.turn({ brief: known, message: "Ведущий и фотограф" });
  assert.equal(turn.brief.city, known.city);
  assert.equal(turn.brief.event_format, known.event_format);
  assert.equal(turn.brief.date, known.date);
  assert.equal(turn.brief.budget_kzt, known.budget_kzt);
  assert.equal(turn.brief.category, null);
});

test("clarification keeps the scope of a preserved event budget", async () => {
  const known = fullBrief({ category: null, budget_scope: "event" });
  const model = new FakeModel(async () => ({ ...interpretation(emptyBrief()), operation: "clarify",
    question: "Кого подберём сначала?", question_field: "category", choices: ["Ведущий", "Фотограф"] }));
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const turn = await app.turn({ brief: known, message: "Ведущий и фотограф" });
  assert.equal(turn.brief.budget_kzt, known.budget_kzt);
  assert.equal(turn.brief.budget_scope, "event");
});

test("partial clarification retains required preferences and previously skipped unrelated fields", async () => {
  const preference = { text: "Спокойный обязательно", feature_id: "calm", importance: "required" as const, polarity: "positive" as const };
  const before = fullBrief({ date: null, skipped_fields: ["date"], preferences: [preference] });
  const model = new FakeModel(async () => ({ ...interpretation(emptyBrief()), operation: "clarify",
    question: "Бюджет всего события или специалиста?", question_field: "budget_kzt", choices: [] }));
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const turn = await app.turn({ brief: before, message: "Сумма 500 тысяч" });
  assert.deepEqual(turn.brief.preferences, [preference]);
  assert.deepEqual(turn.brief.skipped_fields, ["date"]);
});

test("input validation rejects invalid, oversized and stale requests before any provider call", async () => {
  const model = new FakeModel();
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const brief = fullBrief();
  const action = actionFor(brief, "Показать", "show_results");
  const inputs = [
    { brief }, { brief, message: "x", action }, { brief, message: "x".repeat(2001) },
    { brief: { ...brief, budget_kzt: -1 }, message: "x" },
    { brief, message: "x", history: Array.from({ length: 13 }, () => ({ role: "user", text: "x" })) },
    { brief: { ...brief, excluded_ids: ["unknown-id"] }, action },
  ];
  for (const input of inputs) await assert.rejects(app.turn(input), hasCode("invalid-argument"));
  await assert.rejects(app.turn({ brief: fullBrief({ city: "Астана" }), action }), hasCode("failed-precondition"));
  assert.equal(model.extractionInputs.length, 0);
});

test("unavailable AI refuses free text while typed manual flow remains usable", async () => {
  const model = new FakeModel();
  model.available = false;
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const brief = fullBrief();
  await assert.rejects(app.turn({ brief, message: "Уменьши бюджет" }), hasCode("failed-precondition"));
  const result = await app.turn({ brief, action: actionFor(brief, "Показать", "show_results") });
  assert.equal(result.mode, "basic");
  assert.equal(result.result?.outcome, "matched");
  assert.ok(result.warnings.length > 0);
  assert.equal(model.extractionInputs.length, 0);
  assert.deepEqual(brief, fullBrief());
});

test("unknown features returned by AI remain unverified; clients cannot invent evidence keys", async () => {
  const model = new FakeModel(async () => interpretation(fullBrief({ preferences: [
    { text: "Очень необычное пожелание", feature_id: "invented", importance: "required", polarity: "positive" },
  ] })));
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const result = await app.turn({ brief: emptyBrief(), message: "Очень необычное пожелание" });
  assert.equal(result.brief.preferences[0].feature_id, null);
  assert.equal(result.result?.preliminary, true);
  assert.ok(result.result?.recommendations.every((item) => item.evidence[0].status === "unknown" && item.evidence[0].quote === ""));
  const brief = fullBrief();
  await assert.rejects(app.turn({ brief, action: { id: "manual", label: "Пожелание", type: "add_preference", value: {
    text: "Выдуманное", feature_id: "invented", importance: "required", polarity: "positive",
  } } }), hasCode("invalid-argument"));
});

test("language model cannot restore previously rejected contractors", async () => {
  const model = new FakeModel(async () => interpretation(fullBrief({ excluded_ids: [] })));
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const turn = await app.turn({ brief: fullBrief({ excluded_ids: ["a"] }), message: "Уточняю условия" });
  assert.deepEqual(turn.brief.excluded_ids, ["a"]);
  assert.deepEqual(turn.result?.recommendations.map((item) => item.contractor.id), ["b"]);
});

test("legacy explicit filters cannot be overridden by model extraction", async () => {
  const model = new FakeModel(async () => interpretation(fullBrief({ city: "Астана", category: "Фотограф",
    date: "2026-10-16", budget_kzt: 2_000_000, language: "английский", hours: 20,
    preferences: [{ text: "Спокойный", feature_id: "calm", importance: "preferred", polarity: "positive" }],
  })));
  const app = new AssistantApplication(fixture(), new MemoryAssistantCache(), model, null);
  const result = await app.recommend({ city: "Алматы", category: "Ведущий", event_format: "корпоратив",
    date: "2026-10-15", budget_kzt: 200_000, language: "русский", hours: 4, preferences: "Спокойный" });
  assert.deepEqual(result.recommendations.map((item) => item.contractor.id), ["a"]);
  assert.equal(result.recommendations[0].evidence[0].status, "supported");
  assert.equal(model.extractionInputs.length, 1);
});

test("semantic vectors are cached and do not create evidence for unverified wishes", async () => {
  const c = fixture();
  const model = new FakeModel();
  const app = new AssistantApplication(c, new MemoryAssistantCache(), model, embeddingIndex(c));
  const brief = fullBrief({ preferences: [{ text: "Тёплая атмосфера", feature_id: null, importance: "preferred", polarity: "positive" }] });
  const input = { brief, action: actionFor(brief, "Показать", "show_results") };
  const first = await app.turn(input);
  const second = await app.turn(input);
  assert.deepEqual(first, second);
  assert.equal(model.extractionInputs.length, 0);
  assert.equal(model.embeddingInputs.length, 1);
  assert.ok(first.result?.recommendations.every((item) => item.evidence[0].status === "unknown"));
});

test("negative-only wishes do not enter embedding query and use verified evidence only", async () => {
  const c = fixture();
  const model = new FakeModel();
  const app = new AssistantApplication(c, new MemoryAssistantCache(), model, embeddingIndex(c));
  const brief = fullBrief({ preferences: [{ text: "Не спокойный", feature_id: "calm", importance: "preferred", polarity: "negative" }] });
  await app.turn({ brief, action: actionFor(brief, "Показать", "show_results") });
  assert.equal(model.embeddingInputs.length, 0);
});

test("a positive no-contests absence feature remains evidence-only", async () => {
  const c = fixture();
  c.featureDefinitions.push({ key: "no_contests", label: "Без конкурсов", description: "Отсутствие конкурсов" });
  const model = new FakeModel();
  const app = new AssistantApplication(c, new MemoryAssistantCache(), model, embeddingIndex(c));
  const brief = fullBrief({ preferences: [{ text: "Без конкурсов", feature_id: "no_contests", importance: "required", polarity: "positive" }] });
  const result = await app.turn({ brief, action: actionFor(brief, "Показать", "show_results") });
  assert.equal(model.embeddingInputs.length, 0);
  assert.ok(result.result?.recommendations.every((item) => item.evidence[0].status === "unknown"));
});

test("real embedding artifact cannot silently fall back to another ordering when provider becomes unavailable", async () => {
  const c = fixture();
  const model = new FakeModel();
  model.available = false;
  const app = new AssistantApplication(c, new MemoryAssistantCache(), model, embeddingIndex(c));
  const brief = fullBrief({ preferences: [{ text: "Тёплая атмосфера", feature_id: null, importance: "preferred", polarity: "positive" }] });
  await assert.rejects(app.turn({ brief, action: actionFor(brief, "Показать", "show_results") }), hasCode("failed-precondition"));
  assert.equal(model.embeddingInputs.length, 0);
});

test("cached semantic query remains usable during provider outage without reranking", async () => {
  const c = fixture();
  const cache = new MemoryAssistantCache();
  const model = new FakeModel();
  const app = new AssistantApplication(c, cache, model, embeddingIndex(c));
  const brief = fullBrief({ preferences: [{ text: "Тёплая атмосфера", feature_id: null, importance: "preferred", polarity: "positive" }] });
  const input = { brief, action: actionFor(brief, "Показать", "show_results") };
  const first = await app.turn(input);
  model.available = false;
  const second = await app.turn(input);
  assert.deepEqual(first.result, second.result);
  assert.equal(model.embeddingInputs.length, 1);
});

test("a stale embedding artifact fails closed instead of mixing versions", () => {
  const c = fixture();
  const index = embeddingIndex(c);
  assert.throws(() => new AssistantApplication(c, new MemoryAssistantCache(), new FakeModel(), { ...index, datasetVersion: "old" }), hasCode("failed-precondition"));
  assert.throws(() => new AssistantApplication(c, new MemoryAssistantCache(), new FakeModel(), { ...index, inputVersion: "old" }), hasCode("failed-precondition"));
});

function liveFixture(patch: Partial<Catalog> = {}): Catalog {
  return { ...fixture(), source: "live", datasetVersion: "live-v1", features: new Map(),
    contractors: fixture().contractors.map((contractor) => ({ ...contractor, is_live: true, contact: "public-contact", portfolio_urls: [] })),
    liveDatePolicy: { firstDate: "2026-09-23", lastDate: "2027-09-23" },
    resolveAvailability: async () => new Map([["a", "available"], ["b", "available"], ["c", "unconfirmed"]]), ...patch };
}

test("live and demo input sources cannot use each other's catalog even through the legacy endpoint", async () => {
  const demo = new AssistantApplication(fixture(), new MemoryAssistantCache(), new FakeModel(), null);
  const live = new AssistantApplication(liveFixture(), new MemoryAssistantCache(), new FakeModel(), undefined, { uid: "u", source: "live" });
  const brief = fullBrief();
  const action = actionFor(brief, "Показать", "show_results");
  await assert.rejects(demo.turn({ source: "live", brief, action }), hasCode("invalid-argument"));
  await assert.rejects(live.turn({ brief, action }), hasCode("invalid-argument"));
  await assert.rejects(demo.turn({ source: "other", brief, action }), hasCode("invalid-argument"));
  const request = { city: brief.city, category: brief.category, event_format: brief.event_format, date: brief.date, budget_kzt: brief.budget_kzt };
  await assert.rejects(live.recommend(request), hasCode("invalid-argument"));
  assert.equal((await live.recommend({ ...request, source: "live" })).outcome, "matched");
});

test("live availability resolves the new extracted date and rereads it on every turn", async () => {
  const resolved: string[] = [];
  let busy = false;
  const catalog = liveFixture({ resolveAvailability: async (date) => {
    resolved.push(date);
    return new Map([["a", busy ? "busy" : "available"], ["b", "available"], ["c", "unconfirmed"]]);
  } });
  const model = new FakeModel(async () => interpretation(fullBrief({ date: "2026-11-03" })));
  const app = new AssistantApplication(catalog, new MemoryAssistantCache(), model, undefined, { uid: "u", source: "live" });
  const input = { source: "live", brief: fullBrief(), message: "Лучше 3 ноября" };
  const first = await app.turn(input);
  assert.deepEqual(first.result?.recommendations.map((item) => item.contractor.id), ["a", "b"]);
  busy = true;
  const second = await app.turn(input);
  assert.deepEqual(second.result?.recommendations.map((item) => item.contractor.id), ["b"]);
  assert.deepEqual(resolved, ["2026-11-03", "2026-11-03"]);
  assert.equal(model.extractionInputs.length, 1);
});

test("outside live horizon keeps the exact date, skips calendar reads and labels preliminary results", async () => {
  let reads = 0;
  const model = new FakeModel();
  model.available = false;
  const app = new AssistantApplication(liveFixture({ resolveAvailability: async () => { reads++; return new Map(); } }),
    new MemoryAssistantCache(), model, undefined, { uid: "u", source: "live" });
  const brief = fullBrief({ date: "2028-02-10" });
  const turn = await app.turn({ source: "live", brief, action: actionFor(brief, "Показать", "show_results") });
  assert.equal(turn.brief.date, "2028-02-10");
  assert.equal(reads, 0);
  assert.equal(turn.result?.preliminary, true);
  assert.ok(turn.result?.recommendations.length);
});

test("live typed flow works without a key and never turns public description into reviewed evidence", async () => {
  const model = new FakeModel();
  model.available = false;
  const app = new AssistantApplication(liveFixture(), new MemoryAssistantCache(), model, undefined, { uid: "u", source: "live" });
  const brief = fullBrief({ preferences: [{ text: "Спокойный", feature_id: "calm", importance: "required", polarity: "positive" }] });
  const turn = await app.turn({ source: "live", brief, action: actionFor(brief, "Показать", "show_results") });
  assert.equal(turn.mode, "basic");
  assert.equal(turn.result?.preliminary, true);
  assert.deepEqual(turn.result?.recommendations.map((item) => item.contractor.id), ["a", "b"]);
  assert.ok(turn.result?.recommendations.every((item) => item.contractor.is_live && item.evidence[0].status === "unknown" && item.evidence[0].quote === ""));
  assert.equal(model.embeddingInputs.length, 0);
  await assert.rejects(app.turn({ source: "live", brief, message: "Измени пожелания" }), hasCode("failed-precondition"));
  await assert.rejects(app.recommend({ source: "live", city: brief.city, category: brief.category,
    event_format: brief.event_format, date: brief.date, budget_kzt: brief.budget_kzt, preferences: "Спокойный" }), hasCode("failed-precondition"));
});

test("private parsing and query embeddings are UID scoped while public profile vectors are shared", async () => {
  class RecordingCache extends MemoryAssistantCache {
    writes: { key: string; ownerUid?: string; value: unknown }[] = [];
    override async putIfAbsent<T>(key: string, value: T, ttl: number, metadata?: { ownerUid?: string }): Promise<T> {
      this.writes.push({ key, value, ...metadata });
      return super.putIfAbsent(key, value, ttl, metadata);
    }
  }
  const cache = new RecordingCache();
  const model = new FakeModel();
  const catalog = liveFixture();
  const brief = fullBrief({ preferences: [{ text: "Спокойный", feature_id: "calm", importance: "preferred", polarity: "positive" }] });
  const input = { source: "live", brief, message: "Оставляем эти условия" };
  for (const uid of ["user-a", "user-a", "user-b"]) {
    await new AssistantApplication(catalog, cache, model, undefined, { uid, source: "live" }).turn(input);
  }
  assert.equal(model.extractionInputs.length, 2);
  assert.equal(model.embeddingInputs.length, 3); // Identical public descriptions share a vector, queries remain private.
  const privateWrites = cache.writes.filter((entry) => entry.key.startsWith("parse:") || entry.key.startsWith("live-query:"));
  assert.deepEqual(new Set(privateWrites.map((entry) => entry.ownerUid)), new Set(["user-a", "user-b"]));
  assert.ok(cache.writes.filter((entry) => entry.key.startsWith("live-profile:")).every((entry) => entry.ownerUid === undefined));
});

test("a withdrawn live exclusion does not block future turns and changed profile content refreshes its vector", async () => {
  const cache = new MemoryAssistantCache();
  const model = new FakeModel();
  const brief = fullBrief({ excluded_ids: ["withdrawn-live-id"], preferences: [{ text: "Спокойный", feature_id: "calm", importance: "preferred", polarity: "positive" }] });
  const input = { source: "live", brief, action: actionFor(brief, "Показать", "show_results") };
  const catalog = liveFixture();
  await new AssistantApplication(catalog, cache, model, undefined, { uid: "u", source: "live" }).turn(input);
  const changed = { ...catalog, contractors: catalog.contractors.map((contractor) => contractor.id === "a" ? { ...contractor, description: "Новая спокойная программа." } : contractor) };
  await new AssistantApplication(changed, cache, model, undefined, { uid: "u", source: "live" }).turn(input);
  assert.equal(model.embeddingInputs.length, 3); // Original query + shared description, then only one changed public vector.
});
