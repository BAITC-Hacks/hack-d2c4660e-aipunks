import { createServer } from 'node:http';
import OpenAI from 'openai';
import { openDatabase, importCatalog, readCatalog } from './database.mjs';
import { MatchingWorker } from './worker.mjs';
import { createExplainer, modelDefault, catalogFacts } from './explanations.mjs';

const host = process.env.HOST || '127.0.0.1';
const token = process.env.LOCAL_API_TOKEN || '';
if (!['127.0.0.1','localhost','::1'].includes(host) && token.length < 24) throw Error('LAN mode requires LOCAL_API_TOKEN with at least 24 characters');
const origins = new Set((process.env.ALLOWED_ORIGINS || 'http://localhost:5173,http://127.0.0.1:5173').split(','));
const db = openDatabase();
const imported = importCatalog(db);
const catalog = readCatalog(db);
const worker = new MatchingWorker();
await worker.ready;
const client = process.env.OPENAI_API_KEY ? new OpenAI({apiKey:process.env.OPENAI_API_KEY,maxRetries:0,timeout:6000}) : null;
const maxCalls = Number(process.env.MAX_AI_CALLS_PER_DAY || 100);
if (!Number.isSafeInteger(maxCalls) || maxCalls < 0) throw Error('Invalid MAX_AI_CALLS_PER_DAY');
const explain = createExplainer({db,client,model:process.env.OPENAI_MODEL || modelDefault,maxCalls});
let active = 0;
let windowStart = Date.now(), requests = 0;
const server = createServer(async (req,res) => {
  const send = (status,body) => { res.writeHead(status,{'content-type':'application/json; charset=utf-8','cache-control':'no-store'}); res.end(JSON.stringify(body)); };
  const origin = req.headers.origin;
  const localDevOrigin = !process.env.ALLOWED_ORIGINS && ['127.0.0.1','localhost','::1'].includes(host) && /^http:\/\/(localhost|127\.0\.0\.1):\d{1,5}$/.test(origin || '');
  if (origin && !origins.has(origin) && !localDevOrigin) return send(403,{error:'origin-not-allowed'});
  if (origin) {res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Vary','Origin');}
  res.setHeader('Access-Control-Allow-Headers','Content-Type, X-Local-Token');
  res.setHeader('Access-Control-Allow-Methods','GET, POST, OPTIONS');
  if (req.method === 'OPTIONS') return send(204,null);
  if (token && req.headers['x-local-token'] !== token) return send(401,{error:'unauthorized'});
  if (req.url === '/health' && req.method === 'GET') return send(200,{ok:true,ai_configured:!!client,catalog_version:imported.version,profiles:catalog.length});
  if (req.url === '/v1/catalog' && req.method === 'GET') return send(200,{catalog_version:imported.version,profiles:catalog});
  if (!['/v1/explanations','/v1/summaries'].includes(req.url) || req.method !== 'POST') return send(404,{error:'not-found'});
  if (Date.now()-windowStart > 60000) {windowStart=Date.now();requests=0;}
  if (++requests > 30 || active >= 3) return send(429,{error:'rate-limit'});
  if (!(req.headers['content-type']||'').startsWith('application/json')) return send(415,{error:'json-required'});
  active++;
  try {
    const chunks=[]; let bytes=0;
    for await (const chunk of req) { bytes+=chunk.length; if(bytes>16384) { send(413,{error:'body-too-large'});req.destroy();return; } chunks.push(chunk); }
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (req.url === '/v1/summaries') {
      if (body.catalog_version !== imported.version) return send(409,{error:'version-mismatch'});
      if (!Array.isArray(body.ids) || !body.ids.length || body.ids.length>3 || new Set(body.ids).size!==body.ids.length) return send(400,{error:'invalid-ids'});
      const profiles=body.ids.map(id=>catalog.find(p=>p.id===id));
      if (profiles.some(p=>!p)) return send(400,{error:'unknown-id'});
      return send(200,{...await explain(catalogFacts(profiles,imported.version)),catalog_version:imported.version});
    }
    if (body.catalog_version !== imported.version || body.algorithm_version !== 'contrast-v2') return send(409,{error:'version-mismatch'});
    const q = body.request;
    if (!q || !Number.isSafeInteger(q.budget_kzt) || q.budget_kzt<=0 || !/^2026-\d{2}-\d{2}$/.test(q.date) || new Date(q.date).toISOString().slice(0,10)!==q.date || !['city','category','event_format'].every(k=>typeof q[k]==='string'&&q[k].length<=100) || typeof (q.preferences??'')!=='string' || (q.preferences??'').length>1000 || (q.language!=null && (typeof q.language!=='string'||q.language.length>100)) || (q.hours!=null && (!Number.isFinite(q.hours)||q.hours<=0))) return send(400,{error:'invalid-request'});
    // Reuse the exact Dart engine against SQLite; never trust client facts or IDs.
    const result = await worker.match(catalog,q);
    if (result.catalog_version !== imported.version || JSON.stringify(body.ids)!==JSON.stringify(result.cards.map(c=>c.id))) return send(409,{error:'selection-mismatch'});
    return send(200,{...await explain(result),catalog_version:result.catalog_version,algorithm_version:result.algorithm_version});
  } catch { return send(400,{error:'invalid-or-unavailable-request'}); }
  finally { active--; }
});
server.requestTimeout=10000;
server.headersTimeout=10000;
server.listen(Number(process.env.PORT||8787),host,()=>console.log(`Event Match API on ${host}:${server.address().port}; SQLite profiles=${catalog.length}; GPT=${client?'configured':'not configured'}`));
function stop(){server.close(()=>{worker.close();db.close();});server.closeIdleConnections();}
process.on('SIGINT',stop);process.on('SIGTERM',stop);
