import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {root} from '../src/database.mjs';
import {MatchingWorker} from '../src/worker.mjs';

test('HTTP catalog, CORS, version checks, forged selection and missing-key fallback',async()=>{
  const directory=mkdtempSync(join(tmpdir(),'event-match-http-'));
  const child=spawn(process.execPath,['src/server.mjs'],{
    cwd:join(root,'apps/api'),windowsHide:true,
    env:{...process.env,PORT:'0',HOST:'127.0.0.1',DB_PATH:join(directory,'test.sqlite'),OPENAI_API_KEY:'',LOCAL_API_TOKEN:'',ALLOWED_ORIGINS:'http://localhost:5173'},
    stdio:['ignore','pipe','pipe'],
  });
  try {
    const port=await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(Error('Startup timeout')),15000);
      child.on('error',error=>{clearTimeout(timer);reject(error);});
      child.stdout.on('data',chunk=>{const match=chunk.toString().match(/on 127\.0\.0\.1:(\d+)/);if(match){clearTimeout(timer);resolve(match[1]);}});
    });
    const url=`http://127.0.0.1:${port}`;
    const response=await fetch(`${url}/v1/catalog`);const catalog=await response.json();
    assert.equal(catalog.profiles.length,500);
    assert.equal((await fetch(`${url}/health`,{headers:{Origin:'https://untrusted.example'}})).status,403);
    const request={city:'Алматы',category:'Ведущий',event_format:'свадьба',date:'2026-10-06',budget_kzt:1000000};
    const worker=new MatchingWorker();
    let ids;
    try { await worker.ready; ids=(await worker.match(catalog.profiles,request)).cards.map(c=>c.id); }
    finally { worker.close(); }
    assert.equal(ids.length,3);
    const body={request,catalog_version:catalog.catalog_version,algorithm_version:'evidence-v3',ids};
    const post=payload=>fetch(`${url}/v1/explanations`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
    assert.equal((await post({...body,catalog_version:'stale'})).status,409);
    assert.equal((await post({...body,ids:['forged']})).status,409);
    assert.equal((await post({...body,request:{...request,date:'2026-02-30'}})).status,400);
    const fallbackResponse=await post(body);
    assert.equal(fallbackResponse.status,200);
    const fallback=await fallbackResponse.json();
    assert.equal(fallback.reason,'missing-key');assert.ok(fallback.cards.every(c=>c.source==='template'));
    const summarize=payload=>fetch(`${url}/v1/summaries`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
    const summaryBody={catalog_version:catalog.catalog_version,ids:catalog.profiles.slice(0,3).map(p=>p.id)};
    const summary=await (await summarize(summaryBody)).json();
    assert.equal(summary.reason,'missing-key');assert.equal(summary.cards.length,3);
    assert.equal((await summarize({...summaryBody,ids:['unknown']})).status,400);
    assert.equal((await summarize({...summaryBody,ids:Array(4).fill(summaryBody.ids[0])})).status,400);
    assert.equal((await summarize({...summaryBody,catalog_version:'stale'})).status,409);
    const api=(path,payload,session)=>fetch(`${url}/v1/${path}`,{method:'POST',headers:{'Content-Type':'application/json',...(session?{Authorization:`Bearer ${session}`}:{})},body:JSON.stringify(payload)});
    const registered=await api('auth',{op:'register',name:'HTTP test',email:'http@example.test',password:'local-password-test'});
    assert.equal(registered.status,200);const account=(await registered.json()).data;
    assert.equal((await api('workspace',{op:'account'},account.token)).status,200);
    assert.equal((await api('workspace',{op:'listAccounts'},account.token)).status,403);
    assert.equal((await api('workspace',{op:'listEvents',uid:'foreign'},account.token)).status,403);
    assert.equal((await api('messages',{op:'list'})).status,401);
    assert.deepEqual((await (await api('messages',{op:'list'},account.token)).json()).data,[]);
    const brief={city:null,category:null,event_format:null,date:null,budget_kzt:null,hours:null,language:null,preferences:[],skipped_fields:[],excluded_ids:[],budget_scope:'contractor'};
    const turn=await api('assistant',{brief,action:{id:'manual',label:'Фотограф',type:'set_field',field:'category',value:'Фотограф'}});
    assert.equal(turn.status,200);const answer=await turn.json();assert.equal(answer.brief.category,'Фотограф');assert.ok(answer.actions.length>0);
    assert.equal((await api('assistant',{brief,message:'Кого посоветуете?'})).status,503);
    await api('auth',{op:'logout'},account.token);
    assert.equal((await api('workspace',{op:'account'},account.token)).status,401);
  } finally {
    const exited=new Promise(resolve=>child.once('exit',resolve));child.kill();await exited;
    rmSync(directory,{recursive:true,force:true});
  }
});
