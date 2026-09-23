# Assistant contract v1

Firebase callable `assistantTurn` input: `{brief, message?, action?, history?}`. Exactly one message or action; history has at most 12 `{role: "user"|"assistant", text}` entries. Text max 2000 chars. Brief is revalidated on every call.

`brief`: `{city: string|null, category: string|null, event_format: string|null, date: "YYYY-MM-DD"|null, budget_kzt: number|null, hours: number|null, language: string|null, preferences: Preference[], skipped_fields: string[], excluded_ids: string[], budget_scope: "contractor"|"event"}`. Empty arrays/default contractor for new sessions; no demo defaults. Preference = `{text: string, feature_id: string|null, importance: "required"|"preferred", polarity: "positive"|"negative"}`. Feature IDs defined by versioned evidence artifact. Date outside catalog window is retained but unchecked, never promised available. Event budget is not a contractor budget.

`action`: `{id: string, label: string, type: string, field?: string, value?: JSON}`. Types: `set_field` (city/category/event_format/date/budget_kzt/hours/language), `clear_field`, `skip_field` (date/budget_kzt), `show_results`, `next_category` (value category or null; preserve city/date/event_format, reset other constraints), `reject` (value `{contractor_id, reason}`), `add_preference` (value Preference), `remove_preference` (value index), `reset`. Picker-only UI actions `pick_date`, `pick_budget`, `pick_field` are resolved by client into set_field. Supported reject reasons: price/style/experience/other; reject excludes this ID, asks one follow-up if needed, never silently changes budget.

Output `AssistantTurn`: `{brief, message, actions: Action[], question_field: string|null, result: Result|null, mode: "ai"|"basic", warnings: string[], dataset_version: string, algorithm_version: string}`.

`Result`: `{outcome: "matched"|"category_absent"|"no_eligible", recommendations: Recommendation[], summary: string, preliminary: boolean, unchecked: string[]}`. Up to 3 Recommendations = `{contractor: original JSONL profile, explanation: string, unchecked: string[], evidence: [{feature_id, quote, status}]}`. Status supported/contradicted/unknown; empty quote only for unknown. Do not describe a candidate with unchecked required preferences as fully matching.

`recommendContractors` accepts existing MatchRequest JSON fields (preferences remains free text on that legacy input) and returns Result + dataset_version/algorithm_version/mode. Shared engine, no second rule set.

Fallback: typed controls are supported without an API key. Free text must fail with an actionable AI-unavailable error rather than be falsely presented as understood. Local Dart basic service may implement the same typed workflow, with structural filtering and factual quotes; no semantic claims. Errors preserve brief and offer retry/manual mode. Every displayed action is bound to the current turn.
