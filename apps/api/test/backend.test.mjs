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
test('shared Dart engine, version parity, real catalog and canonical aliases',async()=>{
  const db=openDatabase(':memory:');const meta=importCatalog(db);const catalog=readCatalog(db);
  const worker=new MatchingWorker();
  try {
    await worker.ready;
    const result=await worker.match(catalog,request);
    assert.equal(result.catalog_version,meta.version);assert.ok(result.eligible_count>4);
    assert.equal(result.cards.length,3);
    for (const card of result.cards) {
      assert.equal(typeof card.template,'string');
      if (card.explanation_options) {
        assert.ok(card.explanation_options.length >= 1 && card.explanation_options.length <= 3);
        assert.ok(card.explanation_options.every(option=>typeof option==='string' && option.length > 0));
      }
    }
    const alias=await worker.match(catalog,{...request,city:' Almaty ',category:'MC',event_format:'wedding'});
    assert.deepEqual(alias.cards.map(c=>c.id),result.cards.map(c=>c.id));
  } finally {worker.close();db.close();}
});

const matchFixture = () => ({
  request,catalog_version:'verified-catalog',algorithm_version:'reviewed-wording-v1',
  cards:[
    {
      id:'a',equivalent:false,main_fact:'Ведёт свадьбы. Максимум 6 часов. Про отсутствие конкурсов сведений нет.',
      fit_fact:'Цена от 150000 ₸, итоговую стоимость нужно уточнить.',
      template:'Подходит по формату свадьбы; длительность — до 6 часов. Цена от 150000 ₸, итоговую стоимость нужно уточнить.',
      explanation_options:[
        'Подходит по формату свадьбы; длительность — до 6 часов. Цена от 150000 ₸, итоговую стоимость нужно уточнить.',
        'Для вашей свадьбы: в профиле указан этот формат и длительность до 6 часов. Цена от 150000 ₸; итоговая стоимость требует уточнения.',
      ],
    },
    {
      id:'b',equivalent:false,main_fact:'Ведёт свадьбы на русском языке.',fit_fact:'Цена от 200000 ₸, дата не проверена.',
      template:'В профиле указаны свадьбы и русский язык. Цена от 200000 ₸; дату и итоговую стоимость нужно уточнить.',
      explanation_options:[
        'В профиле указаны свадьбы и русский язык. Цена от 200000 ₸; дату и итоговую стоимость нужно уточнить.',
        'Подходит по формату свадьбы и русскому языку. Подбор предварительный: дату и итоговую стоимость от 200000 ₸ нужно уточнить.',
      ],
    },
  ],
});
const completed = cards => ({status:'completed',output_text:JSON.stringify({cards})});
const choose = (result, index=1) => result.cards.map(card=>({id:card.id,explanation:card.explanation_options?.[index] ?? card.template}));

test('match schema binds each explanation enum to its own card; completed choices are cached and concurrent calls deduplicated',async()=>{
  const db=openDatabase(':memory:');
  const result=matchFixture();
  let calls=0;
  const client={responses:{create:async input=>{
    calls++;
    const payload=JSON.parse(input.input);
    assert.equal(payload.mode,'match');
    assert.deepEqual(payload.request,result.request);
    assert.ok(input.instructions.includes('дословно'));
    assert.equal(input.store,false);
    const schemas=input.text.format.schema.properties.cards.items.anyOf;
    assert.equal(input.text.format.schema.properties.cards.minItems,result.cards.length);
    assert.equal(input.text.format.schema.properties.cards.maxItems,result.cards.length);
    assert.equal(schemas.length,result.cards.length);
    schemas.forEach((schema,index)=>{
      assert.deepEqual(schema.properties.id.enum,[result.cards[index].id]);
      assert.deepEqual(schema.properties.explanation.enum,result.cards[index].explanation_options);
      assert.equal(schema.additionalProperties,false);
    });
    return completed(choose(result));
  }}};
  try {
    const explain=createExplainer({db,client});
    const [first,concurrent]=await Promise.all([explain(result),explain(result)]);
    assert.equal(calls,1);
    assert.deepEqual(first,concurrent);
    assert.deepEqual(first.cards.map(card=>card.source),['llm','llm']);
    assert.deepEqual(first.cards.map(card=>card.explanation),choose(result).map(card=>card.explanation));
    assert.equal(first.reason,'ok');
    assert.equal((await explain(result)).cached,true);
    assert.equal(calls,1);
  } finally {db.close();}
});

test('match validation rejects changed duration meaning, negation and from-price even when all numbers pass the catalog sanity check',()=>{
  const result=matchFixture();
  const expected=result.cards[0];
  const unsafe=[
    'Ведёт свадьбы не менее 6 часов. Цена от 150000 ₸, итоговую стоимость нужно уточнить.',
    'Ведёт свадьбы без конкурсов до 6 часов. Цена от 150000 ₸, итоговую стоимость нужно уточнить.',
    'Подходит по формату свадьбы; длительность — до 6 часов. Итоговая стоимость 150000 ₸.',
  ];
  for (const explanation of unsafe) {
    assert.equal(validText(explanation,`${expected.main_fact} ${expected.fit_fact}`),true);
    const validated=validateCards({cards:[{id:expected.id,explanation}]},[expected]);
    assert.deepEqual(validated,[{id:expected.id,explanation:expected.template,source:'template'}]);
  }
  // Exact means exact: neither a card swap nor a whitespace rewrite is accepted.
  assert.equal(validateCards({cards:[{id:'a',explanation:result.cards[1].explanation_options[1]}]},[expected])[0].source,'template');
  assert.equal(validateCards({cards:[{id:'a',explanation:` ${expected.explanation_options[1]}`} ]},[expected])[0].source,'template');
});

test('mixed valid and invalid match choices fall back individually and only accepted model choices receive llm source',async()=>{
  const db=openDatabase(':memory:');
  const result=matchFixture();
  const output=choose(result);
  output[1].explanation='Ведёт свадьбы на русском языке и свободен на вашу дату за 200000 ₸.';
  try {
    const explain=createExplainer({db,client:{responses:{create:async()=>completed(output)}}});
    const response=await explain(result);
    assert.equal(response.reason,'validation-fallback');
    assert.deepEqual(response.cards.map(card=>card.source),['llm','template']);
    assert.equal(response.cards[0].explanation,result.cards[0].explanation_options[1]);
    assert.equal(response.cards[1].explanation,result.cards[1].template);
    assert.deepEqual((await explain(result)).cards,response.cards);
    assert.equal((await explain(result)).cached,true);
  } finally {db.close();}
});

test('single-option and equivalent cards remain template-sourced inside a mixed actual model call',async()=>{
  for (const unchanged of [
    card=>({...card,explanation_options:[card.template]}),
    card=>({...card,equivalent:true}),
  ]) {
    const db=openDatabase(':memory:');
    const result=matchFixture();
    result.cards[1]=unchanged(result.cards[1]);
    let calls=0;
    try {
      const response=await createExplainer({db,client:{responses:{create:async()=>{
        calls++;
        return completed(result.cards.map(card=>({id:card.id,explanation:card.explanation_options.at(-1)})));
      }}}})(result);
      assert.equal(calls,1);
      assert.deepEqual(response.cards.map(card=>card.source),['llm','template']);
      assert.equal(response.cards[1].explanation,result.cards[1].template);
      assert.equal(response.reason,'validation-fallback');
    } finally {db.close();}
  }
});

test('wrong order, duplicates, missing cards and malformed entries reject the complete model response',async()=>{
  const result=matchFixture();
  for (const cards of [[...choose(result)].reverse(),[choose(result)[0],choose(result)[0]],[choose(result)[0]],[null,choose(result)[1]]]) {
    assert.equal(validateCards({cards},result.cards),null);
  }
  const db=openDatabase(':memory:');
  try {
    const response=await createExplainer({db,client:{responses:{create:async()=>completed([...choose(result)].reverse())}}})(result);
    assert.equal(response.reason,'invalid-response');
    assert.ok(response.cards.every(card=>card.source==='template'));
  } finally {db.close();}
});

test('legacy and single-option workers skip AI without pretending that a model generated the facts',async()=>{
  const db=openDatabase(':memory:');
  let calls=0;
  const client={responses:{create:async()=>{calls++;throw Error('must not be called');}}};
  try {
    for (const cards of [
      matchFixture().cards.map(({explanation_options,...card})=>card),
      matchFixture().cards.map(card=>({...card,explanation_options:[card.template]})),
    ]) {
      const response=await createExplainer({db,client})({...matchFixture(),cards});
      assert.equal(response.reason,'verified-facts');
      assert.ok(response.cards.every(card=>card.source==='template'));
      assert.deepEqual(response.cards.map(card=>card.explanation),cards.map(card=>card.template));
    }
    assert.equal(calls,0);
    const legacy={...matchFixture().cards[0]};delete legacy.explanation_options;
    assert.equal(validateCards({cards:[{id:legacy.id,explanation:legacy.template}]},[legacy])[0].source,'template');
    assert.equal(validateCards({cards:[{id:legacy.id,explanation:matchFixture().cards[0].explanation_options[1]}]},[legacy])[0].source,'template');
  } finally {db.close();}
});

test('invalid, incomplete and unavailable model responses never claim llm generation and remain retryable',async()=>{
  const db=openDatabase(':memory:');
  const result=matchFixture();
  try {
    assert.equal((await createExplainer({db,client:null})(result)).reason,'missing-key');
    assert.equal((await createExplainer({db,client:{},maxCalls:0})(result)).reason,'daily-limit');
    const cases=[
      [async()=>({status:'incomplete',output_text:JSON.stringify({cards:choose(result)})}),'invalid-response'],
      [async()=>completed(result.cards.map(card=>({id:card.id,explanation:'Ведёт свадьбы без конкурсов до 6 часов за 150000 ₸.'}))),'validation-fallback'],
      [async()=>{throw Object.assign(Error('secret must not escape'),{status:401});},'invalid-key'],
      [async()=>{throw Object.assign(Error('secret must not escape'),{status:429});},'quota-or-rate-limit'],
      [async()=>{throw Error('offline');},'ai-unavailable'],
    ];
    for (const [create,reason] of cases) {
      let calls=0;
      const explain=createExplainer({db,model:reason,client:{responses:{create:async()=>{calls++;return create();}}}});
      for (let retry=0;retry<2;retry++) {
        const response=await explain(result);
        assert.equal(response.reason,reason);
        assert.ok(response.cards.every(card=>card.source==='template'));
        assert.equal(response.cached,false);
      }
      assert.equal(calls,2);
    }
  } finally {db.close();}
});

test('changing reviewed options invalidates the match cache; catalog summaries retain their separate free-generation contract',async()=>{
  const db=openDatabase(':memory:');
  const result=matchFixture();
  let calls=0;
  const client={responses:{create:async input=>{
    calls++;
    const payload=JSON.parse(input.input);
    if(payload.mode==='catalog') {
      assert.equal(input.text.format.schema.properties.cards.items.properties.explanation.type,'string');
      assert.equal(input.text.format.schema.properties.cards.items.anyOf,undefined);
      return completed(payload.cards.map(card=>({id:card.id,explanation:'Ведёт свадьбы на русском языке. Стоимость от 200000 ₸.'})));
    }
    return completed(payload.cards.map(card=>({id:card.id,explanation:card.explanation_options[1]})));
  }}};
  try {
    const explain=createExplainer({db,client});
    await explain(result);
    const updated=structuredClone(result);
    updated.cards[0].explanation_options[1]='Для свадьбы подходит заявленная длительность до 6 часов. Цена от 150000 ₸; итоговую стоимость нужно уточнить.';
    assert.equal((await explain(updated)).cached,false);
    assert.equal(calls,2);
    assert.equal((await explain(updated)).cached,true);
    const card={...result.cards[1],main_fact:'Ведёт свадьбы на русском языке.',fit_fact:'Цена от 200000 ₸, предварительная.'};
    const summary=await explain({...result,mode:'catalog',request:null,cards:[card]});
    assert.equal(summary.cards[0].source,'llm');
    assert.equal(summary.cards[0].explanation,'Ведёт свадьбы на русском языке. Стоимость от 200000 ₸.');
    assert.equal(calls,3);
    // The same free rewrite remains forbidden when no mode is supplied.
    assert.equal(validateCards({cards:summary.cards},[card])[0].source,'template');
  } finally {db.close();}
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
