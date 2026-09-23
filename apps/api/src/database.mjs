import { DatabaseSync } from 'node:sqlite';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('../../../', import.meta.url));
export const defaultCatalog = resolve(root, 'apps/event_match/assets/data/catalog.jsonl');
export const defaultDatabase = resolve(root, 'apps/api/data/event-match.sqlite');
export function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
  return value;
}
export const hash = value => createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');

export function openDatabase(path = process.env.DB_PATH || defaultDatabase) {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=3000;
    CREATE TABLE IF NOT EXISTS catalog_meta(version TEXT PRIMARY KEY, imported_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS contractors(id TEXT PRIMARY KEY, payload TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS explanation_cache(key TEXT PRIMARY KEY, payload TEXT NOT NULL, created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS ai_usage(day TEXT PRIMARY KEY, calls INTEGER NOT NULL);
    PRAGMA user_version=1;`);
  return db;
}

export function importCatalog(db, path = defaultCatalog) {
  const rows = readFileSync(path, 'utf8').trim().split(/\r?\n/).map(line => JSON.parse(line));
  if (!rows.length || new Set(rows.map(p => p.id)).size !== rows.length) throw Error('Empty catalog or duplicate IDs');
  for (const p of rows) {
    if (typeof p.id !== 'string' || !p.id || typeof p.anon_name !== 'string' || typeof p.city !== 'string' || typeof p.description !== 'string' || !Number.isSafeInteger(p.price_from_kzt) || p.price_from_kzt < 0) throw Error('Invalid catalog profile');
    for (const key of ['categories', 'event_formats', 'languages', 'busy_dates']) if (!Array.isArray(p[key]) || !p[key].every(v => typeof v === 'string')) throw Error('Invalid catalog list');
    for (const key of ['synthetic', 'city_imputed', 'price_imputed']) if (typeof p[key] !== 'boolean') throw Error('Invalid provenance');
    if (p.max_hours !== null && (!Number.isFinite(p.max_hours) || p.max_hours <= 0)) throw Error('Invalid duration');
  }
  rows.sort((a,b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  const version = hash(rows);
  db.exec('BEGIN IMMEDIATE');
  try {
    // Atomic snapshot replacement, no deletion of caches/history from old versions.
    db.exec('DELETE FROM contractors; DELETE FROM catalog_meta;');
    const insert = db.prepare('INSERT INTO contractors VALUES (?, ?)');
    for (const p of rows) insert.run(p.id, JSON.stringify(p));
    db.prepare('INSERT INTO catalog_meta VALUES (?, ?)').run(version, new Date().toISOString());
    db.exec('COMMIT');
  } catch(e) { db.exec('ROLLBACK'); throw e; }
  return { version, count: rows.length };
}
export function readCatalog(db) {
  return db.prepare('SELECT payload FROM contractors ORDER BY id').all().map(row => JSON.parse(row.payload));
}
export function reserveCall(db, maximum, day = new Date().toISOString().slice(0,10)) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const calls = db.prepare('SELECT calls FROM ai_usage WHERE day=?').get(day)?.calls || 0;
    if (calls >= maximum) { db.exec('ROLLBACK'); return false; }
    db.prepare('INSERT INTO ai_usage VALUES (?, 1) ON CONFLICT(day) DO UPDATE SET calls=calls+1').run(day);
    db.exec('COMMIT'); return true;
  } catch(e) { db.exec('ROLLBACK'); throw e; }
}
