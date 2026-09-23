import assert from "node:assert/strict";
import { test } from "node:test";
import { actionFor, applyAction, digest } from "../actions";
import { loadCatalog } from "../catalog";
import { buildTurn } from "../dialogue";
import { dateIsCovered, evaluate, preferenceEvidence, recommend } from "../engine";
import { type Brief, type Catalog, type Contractor, type Preference, type ProfileFeature, emptyBrief } from "../types";
import { AssistantError } from "../validation";

const complete = (overrides: Partial<Brief> = {}): Brief => ({
  ...emptyBrief(), city: "Алматы", category: "Ведущий", event_format: "корпоратив",
  date: "2026-10-15", budget_kzt: 500_000, ...overrides,
});
const person = (id: string, overrides: Partial<Contractor> = {}): Contractor => ({
  id, anon_name: `Подрядчик ${id}`, city: "Алматы", description: "Спокойное ведение. Живой джаз. Без пошлых конкурсов.",
  categories: ["Ведущий"], event_formats: ["корпоратив", "свадьба"], languages: ["русский"],
  busy_dates: [], price_from_kzt: 100_000, max_hours: 6, synthetic: false, city_imputed: false, price_imputed: false,
  ...overrides,
});
const pref = (feature_id: string | null, overrides: Partial<Preference> = {}): Preference => ({
  text: feature_id ?? "Нестандартное пожелание", feature_id, importance: "preferred", polarity: "positive", ...overrides,
});
const feature = (key: string, polarity: "supports" | "contradicts" = "supports"): ProfileFeature => ({
  key, polarity, quote: "Спокойное ведение",
});
const catalog = (contractors: Contractor[], features: [string, ProfileFeature[]][] = []): Catalog => ({
  contractors, datasetVersion: "test-data-v1", featureVersion: "1", features: new Map(features),
  featureDefinitions: [...new Set(features.flatMap(([, items]) => items.map((item) => item.key)))].map((key) => ({ key, label: key, description: key })),
});
const ids = (c: Catalog, b = complete(), semanticScores?: ReadonlyMap<string, number>) =>
  recommend(c, b, semanticScores).recommendations.map((item) => item.contractor.id);

test("all structural hard filters are enforced before ranking", () => {
  const cases: [Partial<Contractor>, Partial<Brief>][] = [
    [{ city: "Астана" }, {}], [{ categories: ["Фотограф"] }, {}],
    [{ busy_dates: ["2026-10-15"] }, {}], [{ price_from_kzt: 600_000 }, {}],
    [{ event_formats: ["юбилей"] }, {}], [{ languages: ["английский"] }, { language: "русский" }],
    [{ max_hours: 3 }, { hours: 5 }],
  ];
  for (const [contractorOverrides, briefOverrides] of cases) {
    const c = catalog([person("good"), person("bad", contractorOverrides)]);
    assert.deepEqual(ids(c, complete(briefOverrides), new Map([["bad", 1], ["good", -1]])), ["good"]);
  }
});

test("null max_hours is not treated as zero; exact budget and duration pass", () => {
  const c = catalog([person("untimed", { max_hours: null, price_from_kzt: 500_000 }), person("exact", { max_hours: 6 })]);
  assert.deepEqual(ids(c, complete({ hours: 6 })), ["exact", "untimed"]);
  const untimed = recommend(c, complete({ hours: 6 })).recommendations.find((item) => item.contractor.id === "untimed")!;
  assert.ok(untimed.unchecked.includes("Длительность не подтверждена"));
});

test("date coverage is explicit and out-of-window busy entries cannot imply checked availability", () => {
  assert.equal(dateIsCovered("2026-09-23"), true);
  assert.equal(dateIsCovered("2026-12-31"), true);
  assert.equal(dateIsCovered("2027-01-01"), false);
  const result = recommend(catalog([person("a", { busy_dates: ["2027-01-01"] })]), complete({ date: "2027-01-01" }));
  assert.equal(result.preliminary, true);
  assert.equal(result.recommendations.length, 1);
  assert.ok(result.unchecked.includes("Дата за пределами календаря 23.09–31.12.2026"));
  assert.ok(!result.recommendations[0].explanation.includes("Свободен"));
});

test("unknown date and budget yield honest preliminary candidates; event budget does not filter", () => {
  const c = catalog([person("a", { price_from_kzt: 300_000 })]);
  const result = recommend(c, complete({ date: null, budget_kzt: null }));
  assert.equal(result.preliminary, true);
  assert.deepEqual(result.unchecked, ["Дата не проверена", "Бюджет подрядчика не задан"]);
  assert.equal(ids(c, complete({ budget_kzt: 10_000, budget_scope: "event" })).length, 1);
  assert.equal(ids(c, complete({ budget_kzt: 10_000, budget_scope: "contractor" })).length, 0);
});

test("every rejected profile contributes only its first hard failure", () => {
  const c = catalog([person("a", { busy_dates: ["2026-10-15"], price_from_kzt: 800_000 }), person("b", { price_from_kzt: 700_000 })]);
  const result = evaluate(c, complete());
  assert.deepEqual(result.rejected, { busy: 1, budget: 1 });
  assert.equal(Object.values(result.rejected).reduce((a, b) => a + b, 0), 2);
});

test("category absent and no eligible are distinct outcomes", () => {
  const c = catalog([person("a")]);
  assert.equal(recommend(c, complete({ city: "Астана" })).outcome, "category_absent");
  assert.equal(recommend(c, complete({ budget_kzt: 1 })).outcome, "no_eligible");
  assert.equal(recommend(c, complete()).outcome, "matched");
});

test("required preferences retain unknown candidates as preliminary and exclude explicit contradictions", () => {
  const c = catalog([person("supported"), person("contradicted"), person("unknown")], [
    ["supported", [feature("calm")]], ["contradicted", [feature("calm", "contradicts")]],
  ]);
  const result = recommend(c, complete({ preferences: [pref("calm", { text: "Спокойный стиль", importance: "required" })] }));
  assert.deepEqual(result.recommendations.map((item) => item.contractor.id), ["supported", "unknown"]);
  assert.equal(result.preliminary, true);
  assert.deepEqual(result.recommendations[0].evidence[0], { feature_id: "calm", quote: "Спокойное ведение", status: "supported" });
  assert.equal(result.recommendations[1].evidence[0].status, "unknown");
  assert.equal(result.recommendations[1].evidence[0].quote, "");
  assert.ok(result.recommendations[1].unchecked.includes("Не подтверждено: Спокойный стиль"));
  assert.match(result.recommendations[1].explanation, /Обязательное условие нужно подтвердить/);
});

test("negative preferences invert known evidence but never invert unknown into support", () => {
  const c = catalog([person("a"), person("b"), person("c")], [["a", [feature("calm")]], ["b", [feature("calm", "contradicts")]]]);
  const preference = pref("calm", { polarity: "negative" });
  assert.equal(preferenceEvidence(c, c.contractors[0], preference).status, "contradicted");
  assert.equal(preferenceEvidence(c, c.contractors[1], preference).status, "supported");
  assert.equal(preferenceEvidence(c, c.contractors[2], preference).status, "unknown");
});

test("no generic contests evidence is not misrepresented as no contests", () => {
  const c = catalog([person("a")], [["a", [feature("no_generic_contests")]]]);
  const result = recommend(c, complete({ preferences: [pref("no_contests", { importance: "required" })] }));
  assert.equal(result.recommendations[0].evidence[0].status, "unknown");
  assert.equal(result.preliminary, true);
});

test("opposing evidence wins over an attractive supported quotation", () => {
  const c = catalog([person("a")], [["a", [feature("calm"), feature("calm", "contradicts")]]]);
  assert.equal(preferenceEvidence(c, c.contractors[0], pref("calm")).status, "contradicted");
});

test("fewer contradictions rank first even when another profile has many supported preferences", () => {
  const wishes = [pref("calm"), pref("jazz"), pref("experience"), pref("photo")];
  const c = catalog([person("contradicted"), person("unknown")], [["contradicted", [feature("calm", "contradicts"), feature("jazz"), feature("experience"), feature("photo")]]]);
  assert.deepEqual(ids(c, complete({ preferences: wishes })), ["unknown", "contradicted"]);
});

test("total confirmed preference count precedes semantic score and price", () => {
  const c = catalog([person("required", { price_from_kzt: 400_000 }), person("preferred")], [
    ["required", [feature("calm")]], ["preferred", [feature("jazz"), feature("experience")]],
  ]);
  const brief = complete({ preferences: [pref("calm", { importance: "required" }), pref("jazz"), pref("experience")] });
  assert.deepEqual(ids(c, brief, new Map([["required", 1], ["preferred", -1]])), ["preferred", "required"]);
});

test("stable semantic ranking uses rounded cosine, then price, then id", () => {
  const c = catalog([person("b"), person("a"), person("c", { price_from_kzt: 120_000 })]);
  assert.deepEqual(ids(c), ["a", "b", "c"]);
  assert.deepEqual(ids(c, complete(), new Map([["a", 0.1], ["b", 0.2], ["c", 0.8]])), ["c", "b", "a"]);
  assert.deepEqual(ids(c, complete(), new Map([["a", 0.20000001], ["b", 0.20000002], ["c", 0.2]])), ["a", "b", "c"]);
  assert.deepEqual(ids(catalog([...c.contractors].reverse())), ids(c));
  assert.throws(() => ids(c, complete(), new Map([["a", Number.NaN]])), AssistantError);
});

test("plain recommendations contain a distinctive source quotation without repeated filter prose", () => {
  const c = catalog([person("a")], [["a", [{ key: "jazz", polarity: "supports", quote: "Живой джаз" }]]]);
  const explanation = recommend(c, complete()).recommendations[0].explanation;
  assert.equal(explanation, "Из профиля: «Живой джаз».");
  assert.ok(!explanation.includes("Алматы"));
});

test("recommend never exposes an unfiltered catalog for a missing search minimum", () => {
  for (const field of ["city", "category", "event_format"] as const) {
    assert.throws(() => recommend(catalog([person("a")]), complete({ [field]: null })), AssistantError);
  }
});

test("dialogue requires category, city and format even when Show results is requested", () => {
  const c = catalog([person("a")]);
  for (const [brief, expected] of [[emptyBrief(), "category"], [complete({ city: null }), "city"], [complete({ event_format: null }), "event_format"]] as const) {
    const turn = buildTurn(c, brief, { mode: "basic", forceResults: true });
    assert.equal(turn.result, null);
    assert.equal(turn.question_field, expected);
    assert.ok(!turn.actions.some((item) => item.type === "show_results"));
  }
});

test("minimal brief gives preliminary results and asks one missing question; Show results stops followups", () => {
  const c = catalog([person("a")]);
  const brief = complete({ date: null, budget_kzt: null });
  const turn = buildTurn(c, brief, { mode: "basic" });
  assert.equal(turn.result?.preliminary, true);
  assert.equal(turn.question_field, "date");
  assert.ok(turn.actions.some((item) => item.type === "show_results"));
  assert.equal(buildTurn(c, brief, { mode: "basic", forceResults: true }).question_field, null);
});

test("complete brief returns cards without another mandatory style question", () => {
  const c = catalog([person("a"), person("b")], [["a", [feature("calm")]]]);
  const turn = buildTurn(c, complete(), { mode: "ai" });
  assert.equal(turn.question_field, null);
  assert.equal(turn.result?.recommendations.length, 2);
  assert.ok(!turn.message.includes("Важно ли"));
  assert.ok(turn.actions.some((item) => item.type === "add_preference"));
});

test("budget quick replies use actual remaining candidate prices instead of arbitrary thresholds", () => {
  const c = catalog([
    person("a", { price_from_kzt: 120_000 }), person("b", { price_from_kzt: 240_000 }),
    person("c", { price_from_kzt: 360_000 }), person("d", { price_from_kzt: 480_000 }),
    person("busy", { price_from_kzt: 50_000, busy_dates: ["2026-10-15"] }),
    person("elsewhere", { city: "Астана", price_from_kzt: 10_000 }),
  ]);
  const turn = buildTurn(c, complete({ budget_kzt: null }), { mode: "basic" });
  assert.equal(turn.question_field, "budget_kzt");
  assert.deepEqual(turn.actions.filter((item) => item.type === "set_field" && item.field === "budget_kzt")
    .map((item) => item.value), [120_000, 360_000]);
  assert.ok(turn.actions.some((item) => item.type === "pick_budget"));
  assert.ok(turn.actions.some((item) => item.type === "skip_field"));
  assert.ok(turn.actions.some((item) => item.type === "show_results"));
  assert.equal(turn.actions.length, 5);
});

test("skipped date is not asked repeatedly and every picker has a concrete field", () => {
  const c = catalog([person("a")]);
  const turn = buildTurn(c, complete({ date: null, budget_kzt: null, skipped_fields: ["date"] }), { mode: "basic" });
  assert.equal(turn.question_field, "budget_kzt");
  const empty = buildTurn(c, complete({ budget_kzt: 1, language: "русский", hours: 8 }), { mode: "basic" });
  assert.equal(empty.result?.outcome, "no_eligible");
  assert.ok(empty.actions.filter((item) => item.type === "pick_field").every((item) => Boolean(item.field)));
});

test("setting a contractor budget changes budget scope and preserves all other constraints", () => {
  const before = complete({ budget_scope: "event", skipped_fields: ["budget_kzt"] });
  const after = applyAction(before, { id: "manual", label: "Бюджет", type: "set_field", field: "budget_kzt", value: 300_000 });
  assert.equal(after.budget_scope, "contractor");
  assert.equal(after.budget_kzt, 300_000);
  assert.deepEqual(after.skipped_fields, []);
  assert.equal(before.budget_scope, "event");
  assert.equal(before.budget_kzt, 500_000);
});

test("category correction preserves constraints; Next category starts only a new category brief", () => {
  const before = complete({ language: "русский", hours: 4, preferences: [pref("calm")], excluded_ids: ["a"] });
  const corrected = applyAction(before, { id: "manual", label: "Категория", type: "set_field", field: "category", value: "Фотограф" });
  assert.equal(corrected.budget_kzt, before.budget_kzt);
  assert.deepEqual(corrected.preferences, before.preferences);
  const next = applyAction(before, actionFor(before, "Следующий", "next_category", undefined, "Фотограф"));
  assert.deepEqual(next, { ...emptyBrief(), city: before.city, date: before.date, event_format: before.event_format, category: "Фотограф" });
});

test("reject excludes exactly that contractor, leaves budget intact and asks one relevant followup", () => {
  const before = complete();
  const action = actionFor(before, "Слишком дорого", "reject", undefined, { contractor_id: "a", reason: "price" });
  const brief = applyAction(before, action);
  assert.deepEqual(brief.excluded_ids, ["a"]);
  assert.equal(brief.budget_kzt, before.budget_kzt);
  const turn = buildTurn(catalog([person("a"), person("b")]), brief, { mode: "basic", action });
  assert.deepEqual(turn.result?.recommendations.map((item) => item.contractor.id), ["b"]);
  assert.equal(turn.question_field, "budget_kzt");
  assert.match(turn.message, /Оставил прежний бюджет/);
});

test("actions bind to their brief; stale buttons fail without mutation", () => {
  const before = complete();
  const action = actionFor(before, "Пропустить", "skip_field", "date");
  assert.throws(() => applyAction(complete({ city: "Астана" }), action), AssistantError);
  assert.equal(applyAction(before, action).date, null);
  assert.equal(before.date, "2026-10-15");
  assert.equal(digest({ a: 1, b: 2 }), digest({ b: 2, a: 1 }));
});

test("invalid typed edits and reject reasons cannot bypass validation", () => {
  const invalidActions = [
    { type: "set_field", field: "date", value: "2026-02-30" },
    { type: "set_field", field: "budget_kzt", value: -1 },
    { type: "set_field", field: "hours", value: Number.POSITIVE_INFINITY },
    { type: "skip_field", field: "city" },
    { type: "reject", value: { contractor_id: "a", reason: "arbitrary" } },
    { type: "reject", value: { contractor_id: "a", reason: "other", detail: "x".repeat(1001) } },
    { type: "remove_preference", value: 5 },
  ];
  for (const item of invalidActions) assert.throws(() => applyAction(complete(), { id: "manual", label: "Действие", ...item }), AssistantError);
});

test("actual 66-profile catalog obeys hard filters and stable baseline across its cities, categories and formats", () => {
  const c = loadCatalog();
  assert.equal(c.contractors.length, 66);
  let scenarios = 0;
  for (const city of new Set(c.contractors.map((item) => item.city))) {
    for (const category of new Set(c.contractors.flatMap((item) => item.categories))) {
      for (const event_format of ["корпоратив", "свадьба", "конференция"]) {
        for (const budget_kzt of [200_000, 1_000_000]) {
          const brief = complete({ city, category, event_format, budget_kzt, language: "русский", hours: 4 });
          const expected = c.contractors.filter((item) => item.city === city && item.categories.includes(category) &&
            item.event_formats.includes(event_format) && item.price_from_kzt <= budget_kzt && !item.busy_dates.includes(brief.date!) &&
            item.languages.includes("русский") && (item.max_hours === null || item.max_hours >= 4))
            .sort((a, b) => a.price_from_kzt - b.price_from_kzt || a.id.localeCompare(b.id, "en"));
          assert.deepEqual(ids(c, brief), expected.slice(0, 3).map((item) => item.id));
          scenarios++;
        }
      }
    }
  }
  assert.ok(scenarios >= 100);
});
