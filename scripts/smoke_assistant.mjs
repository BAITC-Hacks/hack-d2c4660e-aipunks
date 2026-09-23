// End-to-end callable/auth smoke; use only against the explicit local emulators.
import assert from 'node:assert/strict';
const project = process.env.GCLOUD_PROJECT || 'demo-event-match-assistant';
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9199';
const functionsHost = process.env.ASSISTANT_FUNCTIONS_EMULATOR_HOST || '127.0.0.1:5002';
for (const host of [authHost, functionsHost]) {
  assert.match(host, /^(127\.0\.0\.1|localhost):\d+$/, 'Smoke tests only call local emulators');
}
const brief = { city: 'Алматы', category: 'Ведущий', event_format: 'свадьба',
  date: null, budget_kzt: null, hours: null, language: null,
  preferences: [], skipped_fields: [], excluded_ids: [], budget_scope: 'contractor' };
const request = { brief, action: { id: 'manual:show', label: 'Показать варианты', type: 'show_results' }, history: [] };

async function callable(name, data, token) {
  const response = await fetch(`http://${functionsHost}/${project}/us-central1/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {}) },
    body: JSON.stringify({data}), signal: AbortSignal.timeout(20_000),
  });
  return response.json();
}
const unauthorized = await callable('assistantTurn', request);
assert.equal(unauthorized.error?.status, 'UNAUTHENTICATED');
const authResponse = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local-demo`, {
  method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({returnSecureToken: true}),
});
assert.equal(authResponse.status, 200);
const {idToken} = await authResponse.json();
assert.equal(typeof idToken, 'string');
const partial = await callable('assistantTurn', request, idToken);
assert.ok(partial.result, 'Authenticated callable should return data');
assert.equal(partial.result.result.preliminary, true);
assert.equal(partial.result.result.recommendations.length, 3);
assert.ok(partial.result.result.unchecked.some(item => item.includes('Дата')));

const full = {...brief, date: '2026-11-14', budget_kzt: 1000000};
const first = await callable('assistantTurn', {...request, brief:full}, idToken);
const second = await callable('assistantTurn', {...request, brief:full}, idToken);
assert.ok(first.result, 'Complete brief should return recommendations');
const profiles = first.result.result.recommendations.map(r => r.contractor);
assert.deepEqual(profiles.map(p => p.id), second.result.result.recommendations.map(r => r.contractor.id));
assert.ok(profiles.every(p => !p.busy_dates.includes(full.date) && p.price_from_kzt <= full.budget_kzt));
const missing = await callable('assistantTurn', {...request, brief:{...brief,city:'Зарубежье',category:'Флорист'}}, idToken);
assert.equal(missing.result.result.outcome, 'category_absent');
const none = await callable('assistantTurn', {...request, brief:{...full,budget_kzt:1}}, idToken);
assert.equal(none.result.result.outcome, 'no_eligible');
const legacy = await callable('recommendContractors', {city:'Алматы', category:'Ведущий', event_format:'свадьба', date:'2026-11-14',budget_kzt:1000000}, idToken);
assert.equal(legacy.result.outcome, 'matched');
assert.deepEqual(legacy.result.recommendations.map(r=>r.contractor.id), profiles.map(p=>p.id));
if (process.env.ASSISTANT_EXPECT_NO_AI_KEY === 'true') {
  const ai = await callable('assistantTurn', {brief, message:'Нет, в Астане',history:[]}, idToken);
  assert.equal(ai.error?.status, 'FAILED_PRECONDITION');
}
console.log('Assistant emulator smoke passed: auth, partial/complete, deterministic order, availability, absent/empty, legacy contract.');
