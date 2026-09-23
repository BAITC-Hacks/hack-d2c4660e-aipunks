import test from 'node:test';
import assert from 'node:assert/strict';
import { generateCatalog, readProfiles, sourcePath, outputPath } from '../../../scripts/seed_catalog.mjs';
import { auditCatalog } from '../../../scripts/audit_catalog.mjs';

const original = readProfiles(sourcePath);
const catalog = readProfiles(outputPath);
test('seed is reproducible, preserves originals and has no new duplicate identities or descriptions', () => {
  assert.deepEqual(generateCatalog(original), catalog);
  assert.deepEqual(catalog.slice(0, 66), original);
  const audit = auditCatalog(catalog, original);
  assert.equal(audit.profiles, 500);
  assert.equal(audit.added, 434);
  assert.equal(audit.uniqueIds, 500);
  assert.equal(audit.uniqueNames, 500);
  assert.equal(audit.uniqueDescriptions, 500);
  assert.deepEqual(audit.newDuplicatePairs, []);
  assert.deepEqual(audit.newNearDuplicatePairs, []);
  assert.ok(audit.apiCharacters < 2000000);
  for (const category of ['Флорист', 'Декоратор', 'Подарки и сувениры', 'Ведущий церемонии', 'Фото и видеобудки', 'Отель', 'Инструменталист']) assert.equal(audit.categories[category], 3);
});
test('demo calendars respect the 100-day window, seasonal load and December weekends', () => {
  const names = new Set(['Алматы', 'Астана', 'Зарубежье']);
  for (const p of catalog.slice(66)) {
    assert.equal(p.synthetic, true);
    assert.ok(names.has(p.city));
    assert.ok(p.price_from_kzt > 0);
    assert.ok(p.max_hours === null || p.max_hours > 0);
    assert.deepEqual([...new Set(p.busy_dates)].sort(), p.busy_dates);
    assert.ok(p.busy_dates.every(d => d >= '2026-09-23' && d <= '2026-12-31'));
    for (const [month, days] of [['09', 8], ['10', 31], ['11', 30], ['12', 31]]) {
      const load = p.busy_dates.filter(d => d.slice(5, 7) === month).length / days;
      assert.ok(load >= (month === '12' ? .70 : .30));
      assert.ok(load <= (month === '12' ? .80 : .50));
    }
    for (const day of [5, 6, 12, 13, 19, 20, 26, 27]) assert.ok(p.busy_dates.includes(`2026-12-${String(day).padStart(2, '0')}`));
  }
});
test('duplicate audit detects copies even after changing IDs, names, numbers and punctuation', () => {
  const a = catalog[66];
  const copy = { ...a, id: 'DEMO-copy', anon_name: 'Другая студия', description: a.description.replaceAll('.', '!') + ' 123' };
  assert.ok(auditCatalog([a, copy], []).newDuplicatePairs.some(p => p.fields.includes('description')));
});
