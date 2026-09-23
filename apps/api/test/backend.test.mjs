import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openDatabase,importCatalog,readCatalog,reserveCall} from '../src/database.mjs';
import {MatchingWorker} from '../src/worker.mjs';
import {createExplainer,validateCards,validText,catalogFacts} from '../src/explanations.mjs';

const request={city:'Алматы',category:'Ведущий',date:'2026-10-06',event_format:'свадьба',budget_kzt:1000000,hours:null,language:null,preferences:''};
test('SQLite import is idempotent; usage and cache survive reopening',()=>{
  const directory=mkdtempSync(join(tmpdir(),'event-match-test-'));
  const path=join(directory,'test.sqlite');
  try {
    let db=openDatabase(path);
    const first=importCatalog(db);const second=importCatalog(db);
    assert.equal(first.count,500);assert.equal(first.version,second.version);
    assert.equal(readCatalog(db).filter(p=>p.synthetic).length,447);
    assert.equal(reserveCall(db,1,'2026-09-23'),true);
    db.prepare('INSERT INTO explanation_cache VALUES (?,?,?)').run('test','{}','now');
    db.close();db=openDatabase(path);
    assert.equal(reserveCall(db,1,'2026-09-23'),false);
    assert.ok(db.prepare('SELECT * FROM explanation_cache WHERE key=?').get('test'));
    db.close();
  } finally {rmSync(directory,{recursive:true,force:true});}
});
test('shared Dart engine, version parity, real catalog, validated GPT mock, cache',async()=>{
  const db=openDatabase(':memory:');const meta=importCatalog(db);const catalog=readCatalog(db);
  const worker=new MatchingWorker();
  try {
    await worker.ready;
    const result=await worker.match(catalog,request);
    assert.equal(result.catalog_version,meta.version);assert.ok(result.eligible_count>4);
    assert.equal(result.cards.length,3);
    let calls=0;
    const client={responses:{create:async input=>{calls++;assert.equal(input.text.format.schema.properties.cards.items.properties.explanation.type,'string');return {status:'completed',output_text:JSON.stringify({cards:result.cards.map(c=>({id:c.id,explanation:c.template.replace('Цена от','Стоимость от')}))})};}}};
    const explain=createExplainer({db,client});
    const [first,concurrent]=await Promise.all([explain(result),explain(result)]);
    assert.equal(first.cards.length,3);assert.equal(calls,1);assert.deepEqual(first,concurrent);
    assert.equal((await explain(result)).cached,true);assert.equal(calls,1);
    assert.equal(validateCards({cards:[...first.cards].reverse()},result.cards),null);
    const forged={cards:first.cards.map(c=>({...c,explanation:'Отличный выбор за 1 ₸.'}))};
    assert.ok(validateCards(forged,result.cards).every(c=>c.source==='template'));
    const failure=createExplainer({db,client:{responses:{create:async()=>{throw Error('offline');}}},model:'test-other'});
    assert.equal((await failure(result)).reason,'ai-unavailable');
    assert.equal((await createExplainer({db,client:null})(result)).reason,'missing-key');
    assert.equal((await createExplainer({db,client,model:'limit',maxCalls:0})(result)).reason,'daily-limit');
    const alias=await worker.match(catalog,{...request,city:' Almaty ',category:'MC',event_format:'wedding'});
    assert.deepEqual(alias.cards.map(c=>c.id),result.cards.map(c=>c.id));
  } finally {worker.close();db.close();}
});

test('free generation guards and profile facts use server catalog only',()=>{
  assert.equal(validText('Ведёт свадьбы на русском языке. Стоимость от 200 000 ₸.', 'свадьбы русский 200000'),true);
  assert.equal(validText('Ведёт свадьбы на русском языке. Стоимость от 300 000 ₸.', 'свадьбы русский 200000'),false);
  assert.equal(validText('Гарантирует лучший праздник для каждого клиента.', 'праздник'),false);
  assert.equal(validText('Первое предложение. Второе предложение. Третье предложение.', ''),false);
  const db=openDatabase(':memory:');importCatalog(db);
  const facts=catalogFacts(readCatalog(db).slice(0,3),'version');
  assert.equal(facts.mode,'catalog');assert.equal(facts.cards.length,3);
  assert.ok(facts.cards.every(c=>c.main_fact.includes('Описание')&&c.fit_fact.includes('предварительная')));
  db.close();
});
