import assert from 'node:assert/strict';
import {test} from 'node:test';
import {openDatabase,importCatalog,readCatalog} from '../src/database.mjs';
import {createAssistant} from '../src/assistant/runtime.mjs';
import {emptyBrief} from '../src/assistant/types.mjs';
test('500-profile runtime uses SQLite, zero-cost buttons, budget and persistent cache',async t=>{
  const db=openDatabase(':memory:');t.after(()=>db.close());const imported=importCatalog(db),catalog=readCatalog(db);
  let calls=0;
  const brief={...emptyBrief(),city:'Алматы',category:'Фотограф',event_format:'свадьба',date:'2026-10-10',budget_kzt:300000};
  const config={db,catalog,version:imported.version,apiKey:'test-key',model:'fake-model',maxCalls:1,fetchImpl:async()=>{
    calls++;return new Response(JSON.stringify({status:'completed',usage:{input_tokens:10,output_tokens:20},output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({brief,operation:'update',question:null,question_field:null,choices:[]})}]}]}));
  }};
  const api=createAssistant(config);
  const response=await api.turn({brief:emptyBrief(),message:'Подберите фотографа'});
  assert.equal(response.dataset_version,imported.version);assert.equal(catalog.length,500);
  await api.turn({brief:response.brief,action:{id:'test',label:'Показать',type:'show_results'}});assert.equal(calls,1);
  await createAssistant(config).turn({brief:emptyBrief(),message:'Подберите фотографа'});assert.equal(calls,1);
  await assert.rejects(api.turn({brief:emptyBrief(),message:'Другой запрос'}));assert.equal(calls,1);
  const usage=db.prepare('SELECT * FROM assistant_usage').get();assert.equal(usage.input_tokens,10);assert.equal(usage.output_tokens,20);
  for(const r of response.result.recommendations){const p=catalog.find(p=>p.id===r.contractor.id);assert.ok(p);assert.ok(p.price_from_kzt<=brief.budget_kzt);assert.ok(!p.busy_dates.includes(brief.date));}
});
