// Explicit manual live test. At most one generation; repeat only after success.
import {MatchingWorker} from './worker.mjs';
const base=`http://127.0.0.1:${process.env.PORT||8787}`;
const headers={'Content-Type':'application/json',...(process.env.LOCAL_API_TOKEN?{'X-Local-Token':process.env.LOCAL_API_TOKEN}:{})};
const catalogResponse=await fetch(`${base}/v1/catalog`,{headers});
if(!catalogResponse.ok) throw Error(`Catalog HTTP ${catalogResponse.status}`);
const catalog=await catalogResponse.json();
const worker=new MatchingWorker();
try {
  await worker.ready;
  const request={city:'Алматы',category:'Ведущий',date:'2026-10-06',event_format:'свадьба',budget_kzt:1000000,hours:null,language:null,preferences:''};
  const local=await worker.match(catalog.profiles,request);
  const body=JSON.stringify({request,catalog_version:catalog.catalog_version,algorithm_version:local.algorithm_version,ids:local.cards.map(c=>c.id)});
  const start=performance.now();
  const response=await fetch(`${base}/v1/explanations`,{method:'POST',headers,body});
  const first=await response.json();
  console.log(JSON.stringify({stage:'first',http:response.status,reason:first.reason,error:first.error,sources:first.cards?.map(c=>c.source),ms:Math.round(performance.now()-start)}));
  if(first.cards?.some(c=>c.source==='llm')) {
    const again=await (await fetch(`${base}/v1/explanations`,{method:'POST',headers,body})).json();
    console.log(JSON.stringify({stage:'repeat',cached:again.cached,identical:JSON.stringify(first.cards)===JSON.stringify(again.cards)}));
  }
} finally {worker.close();}
