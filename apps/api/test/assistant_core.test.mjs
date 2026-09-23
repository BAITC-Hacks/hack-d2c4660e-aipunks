import assert from "node:assert/strict";
import { test } from "node:test";
import { actionFor, applyAction, digest } from "../src/assistant/actions.mjs";
import { loadCatalog } from "../src/assistant/catalog.mjs";
import { buildTurn } from "../src/assistant/dialogue.mjs";
import { dateIsCovered, evaluate, preferenceEvidence, recommend } from "../src/assistant/engine.mjs";
import { emptyBrief } from "../src/assistant/types.mjs";
import { AssistantError } from "../src/assistant/validation.mjs";
const complete = (overrides = {})=>({
        ...emptyBrief(),
        city: "Алматы",
        category: "Ведущий",
        event_format: "корпоратив",
        date: "2026-10-15",
        budget_kzt: 500_000,
        ...overrides
    });
const person = (id, overrides = {})=>({
        id,
        anon_name: `Подрядчик ${id}`,
        city: "Алматы",
        description: "Спокойное ведение. Живой джаз. Без пошлых конкурсов.",
        categories: [
            "Ведущий"
        ],
        event_formats: [
            "корпоратив",
            "свадьба"
        ],
        languages: [
            "русский"
        ],
        busy_dates: [],
        price_from_kzt: 100_000,
        max_hours: 6,
        synthetic: false,
        city_imputed: false,
        price_imputed: false,
        ...overrides
    });
const pref = (feature_id, overrides = {})=>({
        text: feature_id ?? "Нестандартное пожелание",
        feature_id,
        importance: "preferred",
        polarity: "positive",
        ...overrides
    });
const feature = (key, polarity = "supports")=>({
        key,
        polarity,
        quote: "Спокойное ведение"
    });
const catalog = (contractors, features = [])=>({
        contractors,
        datasetVersion: "test-data-v1",
        featureVersion: "1",
        features: new Map(features),
        featureDefinitions: [
            ...new Set(features.flatMap(([, items])=>items.map((item)=>item.key)))
        ].map((key)=>({
                key,
                label: key,
                description: key
            }))
    });
const ids = (c, b = complete(), semanticScores)=>recommend(c, b, semanticScores).recommendations.map((item)=>item.contractor.id);
test("all structural hard filters are enforced before ranking", ()=>{
    const cases = [
        [
            {
                city: "Астана"
            },
            {}
        ],
        [
            {
                categories: [
                    "Фотограф"
                ]
            },
            {}
        ],
        [
            {
                busy_dates: [
                    "2026-10-15"
                ]
            },
            {}
        ],
        [
            {
                price_from_kzt: 600_000
            },
            {}
        ],
        [
            {
                event_formats: [
                    "юбилей"
                ]
            },
            {}
        ],
        [
            {
                languages: [
                    "английский"
                ]
            },
            {
                language: "русский"
            }
        ],
        [
            {
                max_hours: 3
            },
            {
                hours: 5
            }
        ]
    ];
    for (const [contractorOverrides, briefOverrides] of cases){
        const c = catalog([
            person("good"),
            person("bad", contractorOverrides)
        ]);
        assert.deepEqual(ids(c, complete(briefOverrides), new Map([
            [
                "bad",
                1
            ],
            [
                "good",
                -1
            ]
        ])), [
            "good"
        ]);
    }
});
test("null max_hours is not treated as zero; exact budget and duration pass", ()=>{
    const c = catalog([
        person("untimed", {
            max_hours: null,
            price_from_kzt: 500_000
        }),
        person("exact", {
            max_hours: 6
        })
    ]);
    assert.deepEqual(ids(c, complete({
        hours: 6
    })), [
        "exact",
        "untimed"
    ]);
    const untimed = recommend(c, complete({
        hours: 6
    })).recommendations.find((item)=>item.contractor.id === "untimed");
    assert.ok(!untimed.unchecked.includes("Длительность не подтверждена"));
    assert.match(untimed.explanation, /не привязана к длительности присутствия/);
});
test("date coverage is explicit and out-of-window busy entries cannot imply checked availability", ()=>{
    assert.equal(dateIsCovered("2026-09-23"), true);
    assert.equal(dateIsCovered("2026-12-31"), true);
    assert.equal(dateIsCovered("2027-01-01"), false);
    const result = recommend(catalog([
        person("a", {
            busy_dates: [
                "2027-01-01"
            ]
        })
    ]), complete({
        date: "2027-01-01"
    }));
    assert.equal(result.preliminary, true);
    assert.equal(result.recommendations.length, 1);
    assert.ok(result.unchecked.includes("Дата за пределами календаря 23.09–31.12.2026"));
    assert.ok(!result.recommendations[0].explanation.includes("Свободен"));
});
test("unknown date and budget yield honest preliminary candidates; event budget does not filter", ()=>{
    const c = catalog([
        person("a", {
            price_from_kzt: 300_000
        })
    ]);
    const result = recommend(c, complete({
        date: null,
        budget_kzt: null
    }));
    assert.equal(result.preliminary, true);
    assert.deepEqual(result.unchecked, [
        "Дата не проверена",
        "Бюджет подрядчика не задан"
    ]);
    assert.equal(ids(c, complete({
        budget_kzt: 10_000,
        budget_scope: "event"
    })).length, 1);
    assert.equal(ids(c, complete({
        budget_kzt: 10_000,
        budget_scope: "contractor"
    })).length, 0);
});
test("every rejected profile contributes only its first hard failure", ()=>{
    const c = catalog([
        person("a", {
            busy_dates: [
                "2026-10-15"
            ],
            price_from_kzt: 800_000
        }),
        person("b", {
            price_from_kzt: 700_000
        })
    ]);
    const result = evaluate(c, complete());
    assert.deepEqual(result.rejected, {
        busy: 1,
        budget: 1
    });
    assert.equal(Object.values(result.rejected).reduce((a, b)=>a + b, 0), 2);
});
test("category absent and no eligible are distinct outcomes", ()=>{
    const c = catalog([
        person("a")
    ]);
    assert.equal(recommend(c, complete({
        city: "Астана"
    })).outcome, "category_absent");
    assert.equal(recommend(c, complete({
        budget_kzt: 1
    })).outcome, "no_eligible");
    assert.equal(recommend(c, complete()).outcome, "matched");
});
test("required preferences retain unknown candidates as preliminary and exclude explicit contradictions", ()=>{
    const c = catalog([
        person("supported"),
        person("contradicted"),
        person("unknown")
    ], [
        [
            "supported",
            [
                feature("calm")
            ]
        ],
        [
            "contradicted",
            [
                feature("calm", "contradicts")
            ]
        ]
    ]);
    const result = recommend(c, complete({
        preferences: [
            pref("calm", {
                text: "Спокойный стиль",
                importance: "required"
            })
        ]
    }));
    assert.deepEqual(result.recommendations.map((item)=>item.contractor.id), [
        "supported",
        "unknown"
    ]);
    assert.equal(result.preliminary, true);
    assert.deepEqual(result.recommendations[0].evidence[0], {
        feature_id: "calm",
        quote: "Спокойное ведение.",
        status: "supported"
    });
    assert.equal(result.recommendations[1].evidence[0].status, "unknown");
    assert.equal(result.recommendations[1].evidence[0].quote, "");
    assert.ok(result.recommendations[1].unchecked.includes("Не подтверждено: Спокойный стиль"));
    assert.ok(!result.recommendations[1].explanation.includes("Спокойный стиль» подтверждено"));
});
test("negative preferences invert known evidence but never invert unknown into support", ()=>{
    const c = catalog([
        person("a"),
        person("b"),
        person("c")
    ], [
        [
            "a",
            [
                feature("calm")
            ]
        ],
        [
            "b",
            [
                feature("calm", "contradicts")
            ]
        ]
    ]);
    const preference = pref("calm", {
        polarity: "negative"
    });
    assert.equal(preferenceEvidence(c, c.contractors[0], preference).status, "contradicted");
    assert.equal(preferenceEvidence(c, c.contractors[1], preference).status, "supported");
    assert.equal(preferenceEvidence(c, c.contractors[2], preference).status, "unknown");
});
test("no generic contests evidence is not misrepresented as no contests", ()=>{
    const c = catalog([
        person("a")
    ], [
        [
            "a",
            [
                feature("no_generic_contests")
            ]
        ]
    ]);
    const result = recommend(c, complete({
        preferences: [
            pref("no_contests", {
                importance: "required"
            })
        ]
    }));
    assert.equal(result.recommendations[0].evidence[0].status, "unknown");
    assert.equal(result.preliminary, true);
});
test("opposing evidence wins over an attractive supported quotation", ()=>{
    const c = catalog([
        person("a")
    ], [
        [
            "a",
            [
                feature("calm"),
                feature("calm", "contradicts")
            ]
        ]
    ]);
    assert.equal(preferenceEvidence(c, c.contractors[0], pref("calm")).status, "contradicted");
});
test("fewer contradictions rank first even when another profile has many supported preferences", ()=>{
    const wishes = [
        pref("calm"),
        pref("jazz"),
        pref("experience"),
        pref("photo")
    ];
    const c = catalog([
        person("contradicted"),
        person("unknown")
    ], [
        [
            "contradicted",
            [
                feature("calm", "contradicts"),
                feature("jazz"),
                feature("experience"),
                feature("photo")
            ]
        ]
    ]);
    assert.deepEqual(ids(c, complete({
        preferences: wishes
    })), [
        "unknown",
        "contradicted"
    ]);
});
test("total confirmed preference count precedes semantic score and price", ()=>{
    const c = catalog([
        person("required", {
            price_from_kzt: 400_000
        }),
        person("preferred")
    ], [
        [
            "required",
            [
                feature("calm")
            ]
        ],
        [
            "preferred",
            [
                feature("jazz"),
                feature("experience")
            ]
        ]
    ]);
    const brief = complete({
        preferences: [
            pref("calm", {
                importance: "required"
            }),
            pref("jazz"),
            pref("experience")
        ]
    });
    assert.deepEqual(ids(c, brief, new Map([
        [
            "required",
            1
        ],
        [
            "preferred",
            -1
        ]
    ])), [
        "preferred",
        "required"
    ]);
});
test("stable semantic ranking uses rounded cosine, then price, then id", ()=>{
    const c = catalog([
        person("b"),
        person("a"),
        person("c", {
            price_from_kzt: 120_000
        })
    ]);
    assert.deepEqual(ids(c), [
        "a",
        "b",
        "c"
    ]);
    assert.deepEqual(ids(c, complete(), new Map([
        [
            "a",
            0.1
        ],
        [
            "b",
            0.2
        ],
        [
            "c",
            0.8
        ]
    ])), [
        "c",
        "b",
        "a"
    ]);
    assert.deepEqual(ids(c, complete(), new Map([
        [
            "a",
            0.20000001
        ],
        [
            "b",
            0.20000002
        ],
        [
            "c",
            0.2
        ]
    ])), [
        "a",
        "b",
        "c"
    ]);
    assert.deepEqual(ids(catalog([
        ...c.contractors
    ].reverse())), ids(c));
    assert.throws(()=>ids(c, complete(), new Map([
            [
                "a",
                Number.NaN
            ]
        ])), AssistantError);
});
test("plain recommendations explain requested constraints instead of an unrelated profile quote", ()=>{
    const c = catalog([
        person("a")
    ], [
        [
            "a",
            [
                {
                    key: "jazz",
                    polarity: "supports",
                    quote: "Живой джаз"
                }
            ]
        ]
    ]);
    const explanation = recommend(c, complete()).recommendations[0].explanation;
    assert.match(explanation, /формат «корпоратив»/);
    assert.match(explanation, /Начальная цена/);
    assert.ok(!explanation.includes("Живой джаз"));
    assert.ok(!explanation.includes("Из профиля"));
});
test("recommend never exposes an unfiltered catalog for a missing search minimum", ()=>{
    for (const field of [
        "city",
        "category",
        "event_format"
    ]){
        assert.throws(()=>recommend(catalog([
                person("a")
            ]), complete({
                [field]: null
            })), AssistantError);
    }
});
test("dialogue requires category, city and format even when Show results is requested", ()=>{
    const c = catalog([
        person("a")
    ]);
    for (const [brief, expected] of [
        [
            emptyBrief(),
            "category"
        ],
        [
            complete({
                city: null
            }),
            "city"
        ],
        [
            complete({
                event_format: null
            }),
            "event_format"
        ]
    ]){
        const turn = buildTurn(c, brief, {
            mode: "basic",
            forceResults: true
        });
        assert.equal(turn.result, null);
        assert.equal(turn.question_field, expected);
        assert.ok(!turn.actions.some((item)=>item.type === "show_results"));
    }
});
test("minimal brief gives preliminary results and asks one missing question; Show results stops followups", ()=>{
    const c = catalog([
        person("a")
    ]);
    const brief = complete({
        date: null,
        budget_kzt: null
    });
    const turn = buildTurn(c, brief, {
        mode: "basic"
    });
    assert.equal(turn.result?.preliminary, true);
    assert.equal(turn.question_field, "date");
    assert.ok(turn.actions.some((item)=>item.type === "show_results"));
    assert.equal(buildTurn(c, brief, {
        mode: "basic",
        forceResults: true
    }).question_field, null);
});
test("complete brief returns cards without another mandatory style question", ()=>{
    const c = catalog([
        person("a"),
        person("b")
    ], [
        [
            "a",
            [
                feature("calm")
            ]
        ]
    ]);
    const turn = buildTurn(c, complete(), {
        mode: "ai"
    });
    assert.equal(turn.question_field, null);
    assert.equal(turn.result?.recommendations.length, 2);
    assert.ok(!turn.message.includes("Важно ли"));
    assert.ok(turn.actions.some((item)=>item.type === "add_preference"));
});
test("budget quick replies use actual remaining candidate prices instead of arbitrary thresholds", ()=>{
    const c = catalog([
        person("a", {
            price_from_kzt: 120_000
        }),
        person("b", {
            price_from_kzt: 240_000
        }),
        person("c", {
            price_from_kzt: 360_000
        }),
        person("d", {
            price_from_kzt: 480_000
        }),
        person("busy", {
            price_from_kzt: 50_000,
            busy_dates: [
                "2026-10-15"
            ]
        }),
        person("elsewhere", {
            city: "Астана",
            price_from_kzt: 10_000
        })
    ]);
    const turn = buildTurn(c, complete({
        budget_kzt: null
    }), {
        mode: "basic"
    });
    assert.equal(turn.question_field, "budget_kzt");
    assert.deepEqual(turn.actions.filter((item)=>item.type === "set_field" && item.field === "budget_kzt").map((item)=>item.value), [
        120_000,
        360_000
    ]);
    assert.ok(turn.actions.some((item)=>item.type === "pick_budget"));
    assert.ok(turn.actions.some((item)=>item.type === "skip_field"));
    assert.ok(turn.actions.some((item)=>item.type === "show_results"));
    assert.equal(turn.actions.length, 5);
});
test("skipped date is not asked repeatedly and every picker has a concrete field", ()=>{
    const c = catalog([
        person("a")
    ]);
    const turn = buildTurn(c, complete({
        date: null,
        budget_kzt: null,
        skipped_fields: [
            "date"
        ]
    }), {
        mode: "basic"
    });
    assert.equal(turn.question_field, "budget_kzt");
    const empty = buildTurn(c, complete({
        budget_kzt: 1,
        language: "русский",
        hours: 8
    }), {
        mode: "basic"
    });
    assert.equal(empty.result?.outcome, "no_eligible");
    assert.ok(empty.actions.filter((item)=>item.type === "pick_field").every((item)=>Boolean(item.field)));
});
test("setting a contractor budget changes budget scope and preserves all other constraints", ()=>{
    const before = complete({
        budget_scope: "event",
        skipped_fields: [
            "budget_kzt"
        ]
    });
    const after = applyAction(before, {
        id: "manual",
        label: "Бюджет",
        type: "set_field",
        field: "budget_kzt",
        value: 300_000
    });
    assert.equal(after.budget_scope, "contractor");
    assert.equal(after.budget_kzt, 300_000);
    assert.deepEqual(after.skipped_fields, []);
    assert.equal(before.budget_scope, "event");
    assert.equal(before.budget_kzt, 500_000);
});
test("category correction preserves constraints; Next category starts only a new category brief", ()=>{
    const before = complete({
        language: "русский",
        hours: 4,
        preferences: [
            pref("calm")
        ],
        excluded_ids: [
            "a"
        ]
    });
    const corrected = applyAction(before, {
        id: "manual",
        label: "Категория",
        type: "set_field",
        field: "category",
        value: "Фотограф"
    });
    assert.equal(corrected.budget_kzt, before.budget_kzt);
    assert.deepEqual(corrected.preferences, before.preferences);
    const next = applyAction(before, actionFor(before, "Следующий", "next_category", undefined, "Фотограф"));
    assert.deepEqual(next, {
        ...emptyBrief(),
        city: before.city,
        date: before.date,
        event_format: before.event_format,
        category: "Фотограф"
    });
});
test("reject excludes exactly that contractor, leaves budget intact and asks one relevant followup", ()=>{
    const before = complete();
    const action = actionFor(before, "Слишком дорого", "reject", undefined, {
        contractor_id: "a",
        reason: "price"
    });
    const brief = applyAction(before, action);
    assert.deepEqual(brief.excluded_ids, [
        "a"
    ]);
    assert.equal(brief.budget_kzt, before.budget_kzt);
    const turn = buildTurn(catalog([
        person("a"),
        person("b")
    ]), brief, {
        mode: "basic",
        action
    });
    assert.deepEqual(turn.result?.recommendations.map((item)=>item.contractor.id), [
        "b"
    ]);
    assert.equal(turn.question_field, "budget_kzt");
    assert.match(turn.message, /Оставил прежний бюджет/);
});
test("actions bind to their brief; stale buttons fail without mutation", ()=>{
    const before = complete();
    const action = actionFor(before, "Пропустить", "skip_field", "date");
    assert.throws(()=>applyAction(complete({
            city: "Астана"
        }), action), AssistantError);
    assert.equal(applyAction(before, action).date, null);
    assert.equal(before.date, "2026-10-15");
    assert.equal(digest({
        a: 1,
        b: 2
    }), digest({
        b: 2,
        a: 1
    }));
});
test("invalid typed edits and reject reasons cannot bypass validation", ()=>{
    const invalidActions = [
        {
            type: "set_field",
            field: "date",
            value: "2026-02-30"
        },
        {
            type: "set_field",
            field: "budget_kzt",
            value: -1
        },
        {
            type: "set_field",
            field: "hours",
            value: Number.POSITIVE_INFINITY
        },
        {
            type: "skip_field",
            field: "city"
        },
        {
            type: "reject",
            value: {
                contractor_id: "a",
                reason: "arbitrary"
            }
        },
        {
            type: "reject",
            value: {
                contractor_id: "a",
                reason: "other",
                detail: "x".repeat(1001)
            }
        },
        {
            type: "remove_preference",
            value: 5
        }
    ];
    for (const item of invalidActions)assert.throws(()=>applyAction(complete(), {
            id: "manual",
            label: "Действие",
            ...item
        }), AssistantError);
});
test("actual 66-profile catalog obeys hard filters and stable baseline across its cities, categories and formats", ()=>{
    const c = loadCatalog();
    assert.equal(c.contractors.length, 66);
    let scenarios = 0;
    for (const city of new Set(c.contractors.map((item)=>item.city))){
        for (const category of new Set(c.contractors.flatMap((item)=>item.categories))){
            for (const event_format of [
                "корпоратив",
                "свадьба",
                "конференция"
            ]){
                for (const budget_kzt of [
                    200_000,
                    1_000_000
                ]){
                    const brief = complete({
                        city,
                        category,
                        event_format,
                        budget_kzt,
                        language: "русский",
                        hours: 4
                    });
                    const expected = c.contractors.filter((item)=>item.city === city && item.categories.includes(category) && item.event_formats.includes(event_format) && item.price_from_kzt <= budget_kzt && !item.busy_dates.includes(brief.date) && item.languages.includes("русский") && (item.max_hours === null || item.max_hours >= 4)).sort((a, b)=>a.price_from_kzt - b.price_from_kzt || a.id.localeCompare(b.id, "en"));
                    assert.deepEqual(ids(c, brief), expected.slice(0, 3).map((item)=>item.id));
                    scenarios++;
                }
            }
        }
    }
    assert.ok(scenarios >= 100);
});

test("explanation uses the starting event price and the requested language, format and duration", ()=>{
    const result = recommend(catalog([person("a")]), complete({ language: "русский", hours: 4 }));
    const text = result.recommendations[0].explanation.replace(/\s/gu, " ");
    assert.match(text, /от 100 000 ₸ за мероприятие/);
    assert.match(text, /лимите 500 000 ₸/);
    assert.match(text, /итоговую стоимость нужно согласовать/);
    assert.match(text, /формат «корпоратив»/);
    assert.match(text, /запрошенный язык «русский»/);
    assert.match(text, /предел 6 ч при запросе на 4 ч/);
    assert.ok(!/эконом|остаток бюджета|гарантирован/iu.test(text));
    assert.equal([...new Intl.Segmenter("ru", { granularity: "sentence" }).segment(text)].length, 2);
});

test("an estimated price stays qualified and an event budget is never described as a contractor limit", ()=>{
    const profile = person("a", { price_imputed: true });
    const result = recommend(catalog([profile]), complete({ budget_scope: "event", budget_kzt: 10_000 }));
    const card = result.recommendations[0];
    assert.match(card.explanation, /Оценочная начальная цена/);
    assert.ok(!card.explanation.includes("лимит"));
    assert.ok(!card.explanation.includes("10\u00a0000"));
    assert.ok(card.unchecked.includes("Указан общий бюджет; бюджет подрядчика не задан"));
});

test("a requested semantic match uses its complete source sentence and wins over structural fallback", ()=>{
    const description = "Спокойная подача без навязчивых шуток. Также есть музыкальная программа.";
    const c = catalog([person("a", { description })], [["a", [{ key: "calm", polarity: "supports", quote: "Спокойная подача" }]]]);
    const brief = complete({ language: "русский", hours: 4, preferences: [pref("calm", { text: "Спокойный стиль" })] });
    const text = recommend(c, brief).recommendations[0].explanation;
    assert.match(text, /Пожелание «Спокойный стиль» подтверждено описанием/);
    assert.ok(text.includes("«Спокойная подача без навязчивых шуток.»"));
    assert.ok(!text.includes("музыкальная программа"));
    assert.ok(!text.includes("предел 6 ч"));
    assert.equal([...new Intl.Segmenter("ru", { granularity: "sentence" }).segment(text)].length, 2);
});

test("preferred contradiction remains visible and a long quotation never loses its final negation", ()=>{
    const description = `Для события мы учитываем ${"предпочтения гостей и особенности программы, ".repeat(8)}но программу совсем без конкурсов не предлагаем.`;
    assert.ok(description.length > 200);
    const c = catalog([person("a", { description })], [["a", [
        { key: "custom", polarity: "supports", quote: "учитываем" },
        { key: "no_contests", polarity: "contradicts", quote: "программу совсем без конкурсов" },
    ]]]);
    const result = recommend(c, complete({ preferences: [pref("custom"), pref("no_contests", { text: "Совсем без конкурсов" })] }));
    const card = result.recommendations[0];
    assert.equal(result.outcome, "matched");
    assert.match(card.explanation, /Описание противоречит пожеланию «Совсем без конкурсов»/);
    assert.ok(!card.explanation.includes(description));
    assert.ok(card.explanation.length < 300);
    assert.equal([...new Intl.Segmenter("ru", { granularity: "sentence" }).segment(card.explanation)].length, 2);
    assert.equal(card.evidence[1].quote, description);
    assert.ok(card.evidence[1].quote.endsWith("не предлагаем."));
    assert.deepEqual(card.evidence.map((item)=>item.status), ["supported", "contradicted"]);
    assert.ok(!card.unchecked.some((item)=>item.includes("Совсем без конкурсов")));
});

test("evidence spanning sentences keeps its complete source outside the compact explanation", ()=>{
    for (const polarity of ["supports", "contradicts"]) {
        const description = polarity === "supports"
            ? "Работаем спокойно и деликатно. Громкие игры и конкурсы не проводим."
            : "Раньше проводили программу без конкурсов. Теперь такой формат не предлагаем.";
        const sourceQuote = description.slice(10, -8);
        const c = catalog([person("a", { description })], [["a", [
            { key: "no_contests", polarity, quote: sourceQuote },
        ]]]);
        const card = recommend(c, complete({ preferences: [pref("no_contests", { text: "Совсем без конкурсов" })] })).recommendations[0];
        assert.equal(card.evidence[0].quote, description);
        assert.equal(card.evidence[0].status, polarity === "supports" ? "supported" : "contradicted");
        assert.ok(!card.explanation.includes(description));
        assert.ok(card.explanation.length < 300);
        assert.equal([...new Intl.Segmenter("ru", { granularity: "sentence" }).segment(card.explanation)].length, 2);
        assert.match(card.explanation, polarity === "supports" ? /подтверждено описанием/ : /Описание противоречит/);
        assert.ok(!card.unchecked.some((item)=>item.includes("Совсем без конкурсов")));
    }
});

test("short evidence retains an earlier negation when expanded to its source sentence", ()=>{
    const description = "Больше не предлагаем программу совсем без конкурсов.";
    const c = catalog([person("a", { description })], [["a", [
        { key: "no_contests", polarity: "contradicts", quote: "предлагаем программу совсем без конкурсов" },
    ]]]);
    const card = recommend(c, complete({ preferences: [pref("no_contests", { text: "Совсем без конкурсов" })] })).recommendations[0];
    assert.equal(card.evidence[0].quote, description);
    assert.ok(card.explanation.includes(`«${description}»`));
    assert.match(card.explanation, /Описание противоречит/);
    assert.equal([...new Intl.Segmenter("ru", { granularity: "sentence" }).segment(card.explanation)].length, 2);
});

test("long or multi-sentence wish text is referenced intact by its position instead of truncating a negation", ()=>{
    for (const text of [
        `Мне подходит ${"спокойная и деликатная подача, ".repeat(6)}но конкурсы не нужны`,
        "Спокойная подача. Конкурсы не нужны!",
    ]) {
        const description = "Спокойная подача без конкурсов.";
        const c = catalog([person("a", { description })], [["a", [
            { key: "calm", polarity: "supports", quote: description },
        ]]]);
        const card = recommend(c, complete({ preferences: [pref(null), pref("calm", { text })] })).recommendations[0];
        assert.match(card.explanation, /Пожелание №2 подтверждено описанием/);
        assert.ok(!card.explanation.includes(text));
        assert.equal(card.evidence[1].quote, description);
        assert.equal(card.evidence[1].status, "supported");
        assert.ok(!card.unchecked.some((item)=>item.includes(text)));
        assert.ok(card.explanation.length < 300);
        assert.equal([...new Intl.Segmenter("ru", { granularity: "sentence" }).segment(card.explanation)].length, 2);
    }
});

test("multi-sentence structural field names cannot add extra explanation sentences", ()=>{
    const format = "Встреча. Конкурсы не нужны!";
    const language = "Русский. Английский не нужен!";
    const c = catalog([person("a", { event_formats: [format], languages: [language] })]);
    const card = recommend(c, complete({ event_format: format, language, hours: 4 })).recommendations[0];
    assert.match(card.explanation, /запрошенный формат, запрошенный язык/);
    assert.match(card.explanation, /предел 6 ч при запросе на 4 ч/);
    assert.equal([...new Intl.Segmenter("ru", { granularity: "sentence" }).segment(card.explanation)].length, 2);
});

test("unknown wishes stay separate from the explanation and are never replaced by another profile claim", ()=>{
    const c = catalog([person("a")], [["a", [{ key: "jazz", polarity: "supports", quote: "Живой джаз" }]]]);
    const result = recommend(c, complete({ date: null, preferences: [pref("no_contests", { text: "Совсем без конкурсов", importance: "required" })] }));
    const card = result.recommendations[0];
    assert.ok(card.unchecked.includes("Не подтверждено: Совсем без конкурсов"));
    assert.ok(card.unchecked.includes("Дата не проверена"));
    assert.equal(card.evidence[0].status, "unknown");
    assert.equal(result.preliminary, true);
    assert.match(card.explanation, /формат «корпоратив»/);
    assert.ok(!card.explanation.includes("Живой джаз"));
    assert.ok(!card.explanation.includes("без конкурсов» подтверждено"));
    assert.ok(!card.explanation.includes("Дата"));
    assert.match(result.summary, /Дата не задана; занятость не проверена/);
});

test("demo null duration is not an unknown condition, while live null duration is", ()=>{
    for (const live of [false, true]) {
        const c = catalog([person("a", { is_live: live, max_hours: null })]);
        const result = recommend(c, complete({ hours: 8 }));
        const card = result.recommendations[0];
        assert.equal(card.unchecked.includes("Длительность не подтверждена"), live);
        assert.equal(result.preliminary, live);
        assert.equal(card.explanation.includes("не привязана к длительности присутствия"), !live);
        assert.ok(!card.explanation.includes("без ограничения часов"));
        assert.equal(card.contractor.id, "a");
    }
    const liveSource = { ...catalog([person("a", { max_hours: null })]), source: "live" };
    assert.equal(recommend(liveSource, complete({ hours: 8 })).preliminary, true);
});

test("summary identifies the checked date and explains why fewer than three profiles remain", ()=>{
    const c = catalog([
        person("available"),
        person("busy", { busy_dates: ["2026-10-15"] }),
        person("expensive", { price_from_kzt: 600_000 }),
    ]);
    const result = recommend(c, complete());
    assert.deepEqual(result.recommendations.map((item)=>item.contractor.id), ["available"]);
    assert.match(result.summary, /Меньше трёх вариантов: остальные исключены/);
    assert.match(result.summary, /заняты на дату/);
    assert.match(result.summary, /выше бюджета/);
    assert.match(result.summary, /Проверена занятость на 15\.10\.2026/);
    assert.match(result.summary, /дата не отмечена занятой/);
    const smallPool = recommend(catalog([person("only")]), complete());
    assert.match(smallPool.summary, /других анкет этой категории в городе нет/);
    const outside = recommend(catalog([person("only")]), complete({ date: "2027-01-15" }));
    assert.match(outside.summary, /Занятость на 15\.01\.2027 не проверена/);
    assert.ok(!outside.summary.includes("Проверена занятость"));
});

test("three-outcome contract and result cap survive the explanation changes", ()=>{
    const c = catalog([person("a"), person("b"), person("c"), person("d")]);
    assert.equal(recommend(c, complete()).recommendations.length, 3);
    const absent = recommend(c, complete({ city: "Астана" }));
    assert.equal(absent.outcome, "category_absent");
    assert.equal(absent.recommendations.length, 0);
    assert.ok(!absent.summary.includes("Проверена занятость"));
    const none = recommend(c, complete({ budget_kzt: 1 }));
    assert.equal(none.outcome, "no_eligible");
    assert.equal(none.recommendations.length, 0);
    assert.match(none.summary, /выше бюджета/);
});
