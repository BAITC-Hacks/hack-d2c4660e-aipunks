import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const normalize = value => value.normalize('NFKC').toLowerCase().replaceAll('ё', 'е').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
const content = p => normalize(p.description.replace(/Форматы работы:.*$/u, '').replace(/\d+/g, ''));
const shingles = value => {
  const words = value.split(' ');
  return new Set(words.slice(0, -2).map((_, i) => words.slice(i, i + 3).join(' ')));
};
export function auditCatalog(profiles, original) {
  const newIds = new Set(profiles.filter(p => p.id.startsWith('DEMO-')).map(p => p.id));
  const prepared = profiles.map(p => ({ p, name: normalize(p.anon_name), description: content(p), shingles: shingles(content(p)) }));
  const duplicatePairs = [], nearDuplicatePairs = [];
  for (let i = 0; i < prepared.length; i++) {
    for (let j = i + 1; j < prepared.length; j++) {
      const a = prepared[i], b = prepared[j];
      const fields = [];
      if (a.p.id === b.p.id) fields.push('id');
      if (a.name === b.name) fields.push('name');
      if (a.description === b.description) fields.push('description');
      if (fields.length) duplicatePairs.push({ ids: [a.p.id, b.p.id], fields });
      const overlap = [...a.shingles].filter(s => b.shingles.has(s)).length;
      const similarity = overlap / (a.shingles.size + b.shingles.size - overlap || 1);
      if (similarity >= .80 && a.description !== b.description) nearDuplicatePairs.push({ ids: [a.p.id, b.p.id], similarity: Number(similarity.toFixed(3)) });
    }
  }
  const hasNew = pair => pair.ids.some(id => newIds.has(id));
  const categories = {};
  for (const p of profiles) for (const category of p.categories) categories[category] = (categories[category] || 0) + 1;
  return {
    profiles: profiles.length, added: newIds.size,
    synthetic: profiles.filter(p => p.synthetic).length,
    originalPreserved: original.every(p => JSON.stringify(p) === JSON.stringify(profiles.find(row => row.id === p.id))),
    uniqueIds: new Set(profiles.map(p => p.id)).size,
    uniqueNames: new Set(prepared.map(p => p.name)).size,
    uniqueDescriptions: new Set(prepared.map(p => p.description)).size,
    apiCharacters: JSON.stringify({ catalog_version: '0'.repeat(64), profiles }).length,
    apiBytes: Buffer.byteLength(JSON.stringify({ catalog_version: '0'.repeat(64), profiles })),
    categories,
    newDuplicatePairs: duplicatePairs.filter(hasNew),
    newNearDuplicatePairs: nearDuplicatePairs.filter(hasNew),
    originalDuplicatePairs: duplicatePairs.filter(p => !hasNew(p)),
    originalNearDuplicatePairs: nearDuplicatePairs.filter(p => !hasNew(p)),
  };
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const read = path => readFileSync(new URL(path, import.meta.url), 'utf8').trim().split(/\r?\n/).map(JSON.parse);
  const audit = auditCatalog(read('../apps/event_match/assets/data/catalog.jsonl'), read('../data/catalog.original.jsonl'));
  console.log(JSON.stringify(audit, null, 2));
  if (audit.newDuplicatePairs.length || audit.newNearDuplicatePairs.length || !audit.originalPreserved || audit.uniqueIds !== audit.profiles) process.exitCode = 1;
}
