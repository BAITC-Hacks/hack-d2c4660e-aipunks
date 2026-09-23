import assert from 'node:assert/strict';
import {test} from 'node:test';
import {openDatabase} from '../src/database.mjs';
import {createWorkspace,WorkspaceError} from '../src/workspace.mjs';
const content={name:'Фотограф Анна',city:'Алматы',categories:['Фотограф'],price:150000,formats:['свадьба'],languages:['русский'],maxHours:6,description:'Спокойная репортажная съёмка.',contact:'Контакт через Event Match',portfolioUrls:[]};
async function setup(t){const db=openDatabase(':memory:');t.after(()=>db.close());const api=createWorkspace(db);const users={};for(const name of ['client','contractor','stranger','admin'])users[name]=await api.auth({op:'register',email:`${name}@example.test`,password:'testing-password-456',name});const admin=users.admin.identity.uid;db.prepare("INSERT INTO workspace VALUES('staff',?,?,?)").run(admin,admin,JSON.stringify({role:'admin',revision:1}));const call=(who,op,data={})=>api.rpc({op,...data},users[who].token);return {db,api,users,call};}
function denied(fn,status){assert.throws(fn,e=>e instanceof WorkspaceError&&e.status===status);}
function publish(s){const uid=s.users.contractor.identity.uid;s.call('contractor','saveProfile',{content});s.call('contractor','submitProfile');s.call('admin','moderateProfile',{uid,approve:true,reason:'Проверено',expectedRevision:2});return uid;}
test('password sessions, private ownership and server-only staff access',async t=>{
  const s=await setup(t),uid=s.users.client.identity.uid;
  assert.equal(s.users.client.identity.emailVerified,false);
  const stored=s.db.prepare('SELECT * FROM users WHERE uid=?').get(uid);assert.notEqual(stored.password_hash,'testing-password-456');
  assert.equal(s.db.prepare('SELECT * FROM sessions').all().some(r=>r.token_hash===s.users.client.token),false);
  await assert.rejects(s.api.auth({op:'login',email:'client@example.test',password:'wrong-password'}),e=>e.status===401);
  denied(()=>s.call('client','listAccounts'),403);
  denied(()=>s.call('admin','deactivateAccount'),403);
  denied(()=>s.call('client','setModerator',{uid,enabled:true,reason:'spoof',actorId:s.users.admin.identity.uid}),403);
  denied(()=>s.call('stranger','listEvents',{uid}),403);
  const logged=await s.api.auth({op:'login',email:'client@example.test',password:'testing-password-456'});assert.equal(logged.identity.uid,uid);
  await s.api.auth({op:'logout'},logged.token);denied(()=>s.api.rpc({op:'account'},logged.token),401);
});
test('moderation rejection is a visible request for corrections, not a draft',async t=>{
  const s=await setup(t),uid=s.users.contractor.identity.uid;
  s.call('contractor','saveProfile',{content});s.call('contractor','submitProfile');
  s.call('admin','moderateProfile',{uid,approve:false,reason:'Уточните услуги',expectedRevision:2});
  const p=s.call('contractor','getProfile');assert.equal(p.status,'changes_requested');assert.equal(p.reason,'Уточните услуги');
  assert.equal(s.api.rpc({op:'listPublished'},'').length,0);
});
test('draft, review, revisions, calendar and suspension preserve publication integrity',async t=>{
  const s=await setup(t),uid=s.users.contractor.identity.uid;
  s.call('contractor','saveProfile',{content});assert.deepEqual(s.api.rpc({op:'listPublished'},''),[]);
  denied(()=>s.call('client','getProfile',{uid}),403);
  s.call('contractor','submitProfile');denied(()=>s.call('contractor','saveProfile',{content}),409);
  denied(()=>s.call('admin','moderateProfile',{uid,approve:true,reason:'ok',expectedRevision:1}),409);
  s.call('admin','moderateProfile',{uid,approve:true,reason:'ok',expectedRevision:2});
  assert.equal(s.api.rpc({op:'listPublished'},'').length,1);
  s.call('contractor','saveCalendar',{calendar:{year:2026,month:11,busyDays:[2,4]}});
  const calendar=s.api.rpc({op:'getCalendar',uid,key:'2026-11'},'');assert.ok(calendar.confirmedAt);assert.deepEqual(calendar.busyDays,[2,4]);
  denied(()=>s.call('contractor','saveCalendar',{calendar:{year:2026,month:2,busyDays:[30]}}),400);
  s.call('admin','setAccountStatus',{uid,suspended:true,reason:'Проверка'});
  assert.deepEqual(s.api.rpc({op:'listPublished'},''),[]);denied(()=>s.call('contractor','saveProfile',{content}),403);
  assert.ok(s.call('admin','listAudit').length>=3);
});
test('private event plans use optimistic revisions and do not accept foreign selections',async t=>{
  const s=await setup(t),contractor=publish(s);
  const day=new Date(Date.now()+2*86400000).toISOString().slice(0,10);
  const event=s.call('client','saveEvent',{event:{name:'Свадьба',city:'Алматы',format:'свадьба',date:day,preferences:''}});
  const request={city:'Алматы',category:'Фотограф',event_format:'свадьба',date:day,budget_kzt:200000,hours:null,language:null,preferences:''};
  const selection=s.call('client','saveSelection',{selection:{eventId:event,name:'Команда',request,entries:[{contractor:{id:contractor,price_from_kzt:1},explanation:'Данные анкеты'}]}});
  assert.equal(s.call('client','listSelections')[0].entries[0].contractor.price_from_kzt,150000);
  const plan={schemaVersion:1,revision:0,totalBudgetKzt:500000,choices:{'Фотограф':{selectionId:selection,contractorId:contractor}},completedTaskIds:[],notes:'Уточнить условия'};
  assert.equal(s.call('client','savePlan',{eventId:event,plan}).revision,1);
  denied(()=>s.call('client','savePlan',{eventId:event,plan}),409);
  denied(()=>s.call('stranger','savePlan',{eventId:event,plan}),404);
  denied(()=>s.call('client','deleteEvent',{id:event}),409);
  s.call('client','deleteSelection',{id:selection});s.call('client','deleteEvent',{id:event});assert.equal(s.call('client','getPlan',{eventId:event}),null);
});
test('two-sided messaging is private, idempotent and unavailable to demo profiles',async t=>{
  const s=await setup(t),contractor=publish(s),m=(who,op,data={})=>s.api.messaging({op,...data},s.users[who].token);
  denied(()=>m('client','open',{contractorId:'DEMO-0001'}),404);
  denied(()=>m('contractor','open',{contractorId:contractor}),400);
  const thread=m('client','open',{contractorId:contractor});assert.equal(m('client','open',{contractorId:contractor}).id,thread.id);
  m('client','send',{threadId:thread.id,text:'Свободны на нашу дату?',nonce:'first'});
  m('client','send',{threadId:thread.id,text:'Свободны на нашу дату?',nonce:'first'});
  assert.equal(m('contractor','read',{threadId:thread.id}).length,1);
  m('contractor','send',{threadId:thread.id,text:'Уточните время.',nonce:'reply'});
  assert.equal(m('client','read',{threadId:thread.id}).length,2);
  assert.equal(m('contractor','list').length,1);assert.equal(m('stranger','list').length,0);
  denied(()=>m('stranger','read',{threadId:thread.id}),404);denied(()=>m('admin','read',{threadId:thread.id}),404);
  denied(()=>m('stranger','send',{threadId:thread.id,text:'spoof',nonce:'hack'}),404);
  s.call('admin','setAccountStatus',{uid:contractor,suspended:true,reason:'Приостановлен'});
  denied(()=>m('contractor','read',{threadId:thread.id}),403);denied(()=>m('client','send',{threadId:thread.id,text:'hi',nonce:'blocked'}),403);
});

test('registration stores account type across login and rejects privileged roles',async t=>{
  const db=openDatabase(':memory:');t.after(()=>db.close());const api=createWorkspace(db);
  for(const accountType of ['client','contractor']) {
    const input={op:'register',email:`${accountType}@type.test`,password:'testing-password-456',name:'Test',accountType};
    const registered=await api.auth(input);
    assert.equal(registered.identity.accountType,accountType);
    assert.equal(api.rpc({op:'account'},registered.token).accountType,accountType);
    await api.auth({op:'logout'},registered.token);
    const logged=await api.auth({...input,op:'login'});
    assert.equal(logged.identity.accountType,accountType);
    denied(()=>api.rpc({op:'listAccounts'},logged.token),403);
  }
  await assert.rejects(api.auth({op:'register',email:'admin@type.test',password:'testing-password-456',name:'Test',accountType:'admin'}),e=>e.status===400);
});
