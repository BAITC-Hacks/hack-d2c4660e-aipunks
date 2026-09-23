import { readFileSync } from 'node:fs';
import { makeCatalog } from './catalog.mjs';
import { AssistantApplication } from './service.mjs';
import { OpenAILanguageModel } from './openai.mjs';
import { AssistantError } from './validation.mjs';
import { reserveCall } from '../database.mjs';

export function createAssistant({db, catalog, version, apiKey, model, maxCalls=100, fetchImpl=fetch}) {
  db.exec(`CREATE TABLE IF NOT EXISTS assistant_cache(key TEXT PRIMARY KEY,payload TEXT NOT NULL,expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS assistant_usage(id INTEGER PRIMARY KEY,model TEXT,input_tokens INTEGER,output_tokens INTEGER,created_at TEXT);`);
  const artifact = JSON.parse(readFileSync(new URL('../../data/assistant_catalog.json',import.meta.url),'utf8'));
  // An annotation is usable only for its exact source text. All 500 profiles remain searchable.
  artifact.profiles = artifact.profiles.filter(p => catalog.some(c => c.id === p.id));
  artifact.datasetVersion = version;
  const cache = {
    async get(key) {
      const row=db.prepare('SELECT payload FROM assistant_cache WHERE key=? AND expires>?').get(key,Date.now());
      return row ? JSON.parse(row.payload) : null;
    },
    async putIfAbsent(key,value,ttl) {
      db.prepare('DELETE FROM assistant_cache WHERE expires<=?').run(Date.now());
      db.prepare('INSERT OR IGNORE INTO assistant_cache VALUES(?,?,?)').run(key,JSON.stringify(value),Date.now()+ttl*1000);
      return this.get(key);
    },
  };
  const meteredFetch = async (url, options) => {
    if (!reserveCall(db,maxCalls)) throw new AssistantError('resource-exhausted','Лимит AI на сегодня исчерпан. Продолжите кнопками.');
    const response=await fetchImpl(url,options);
    if(response.ok) {
      const data=await response.clone().json();
      db.prepare('INSERT INTO assistant_usage(model,input_tokens,output_tokens,created_at) VALUES(?,?,?,?)')
        .run(model,data.usage?.input_tokens ?? 0,data.usage?.output_tokens ?? 0,new Date().toISOString());
    }
    return response;
  };
  return new AssistantApplication(makeCatalog(catalog,artifact),cache,
    new OpenAILanguageModel(apiKey,model,meteredFetch),null);
}
