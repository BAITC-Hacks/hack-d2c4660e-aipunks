import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync,mkdtempSync,readFileSync,rmSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openDatabase,root} from '../src/database.mjs';
import {createWorkspace} from '../src/workspace.mjs';
import {bootstrapAdmin} from '../src/bootstrap-admin.mjs';

function setup(t) {
  const directory=mkdtempSync(join(tmpdir(),'event-match-admin-'));
  const dbPath=join(directory,'test.sqlite');
  const db=openDatabase(dbPath);
  t.after(()=>{db.close();rmSync(directory,{recursive:true,force:true});});
  return {directory,dbPath,db,workspace:createWorkspace(db),credentialsPath:`${dbPath}.admin-credentials.json`};
}

test('initial admin gets a generated password, hashed storage and administrator access',async t=>{
  const s=setup(t);
  const result=await bootstrapAdmin(s.workspace,{dbPath:s.dbPath,env:{}});
  assert.deepEqual(result,{created:true,email:'admin@eventmatch.local',credentialsPath:s.credentialsPath});
  const credentials=JSON.parse(readFileSync(s.credentialsPath,'utf8'));
  assert.equal(credentials.name,'Администратор');
  assert.ok(credentials.password.length>=32);
  const stored=s.db.prepare('SELECT * FROM users').get();
  assert.notEqual(stored.password_hash,credentials.password);
  assert.equal(stored.password_hash.length,128);
  assert.equal(s.db.prepare('SELECT count(*) AS n FROM sessions').get().n,0);
  const login=await s.workspace.auth({op:'login',...credentials});
  assert.deepEqual(s.workspace.rpc({op:'staff'},login.token),{role:'admin',revision:1});
  assert.equal(s.workspace.rpc({op:'account'},login.token).status,'active');
  assert.equal(s.workspace.rpc({op:'listAccounts'},login.token).length,1);
  await assert.rejects(s.workspace.auth({op:'login',email:credentials.email,password:'wrong-password'}),e=>e.status===401);
});

test('a reopened database preserves the account and password even when configuration changes',async t=>{
  const s=setup(t);
  await bootstrapAdmin(s.workspace,{dbPath:s.dbPath,env:{}});
  const before=s.db.prepare('SELECT * FROM users').all();
  const file=readFileSync(s.credentialsPath,'utf8');
  const reopened=openDatabase(s.dbPath);
  try {
    const workspace=createWorkspace(reopened);
    const result=await bootstrapAdmin(workspace,{dbPath:s.dbPath,env:{ADMIN_EMAIL:'another@example.test',ADMIN_PASSWORD:'different-password'}});
    assert.deepEqual(result,{created:false,email:'admin@eventmatch.local'});
    assert.deepEqual(reopened.prepare('SELECT * FROM users').all(),before);
    assert.equal(readFileSync(s.credentialsPath,'utf8'),file);
    const login=await workspace.auth({op:'login',...JSON.parse(file)});
    assert.equal(workspace.rpc({op:'staff'},login.token).role,'admin');
  } finally {reopened.close();}
});

test('configured credentials are normalized, usable and not written to a file',async t=>{
  const s=setup(t);
  const env={ADMIN_EMAIL:' Owner@Example.test ',ADMIN_NAME:' Owner ',ADMIN_PASSWORD:'configured-password'};
  assert.deepEqual(await bootstrapAdmin(s.workspace,{dbPath:s.dbPath,env}),{created:true,email:'owner@example.test'});
  assert.equal(existsSync(s.credentialsPath),false);
  const login=await s.workspace.auth({op:'login',email:'owner@example.test',password:env.ADMIN_PASSWORD});
  assert.equal(login.identity.name,'Owner');
  assert.equal(s.workspace.rpc({op:'staff'},login.token).role,'admin');
});

test('an existing administrator is preserved without creating another account',async t=>{
  const s=setup(t);
  const existing=await s.workspace.auth({op:'register',email:'existing@example.test',name:'Existing admin',password:'existing-password'});
  const uid=existing.identity.uid;
  s.db.prepare("INSERT INTO workspace VALUES('staff',?,?,?)").run(uid,uid,JSON.stringify({role:'admin',revision:7}));
  assert.deepEqual(await bootstrapAdmin(s.workspace,{dbPath:s.dbPath,env:{}}),{created:false,email:'existing@example.test'});
  assert.equal(s.db.prepare('SELECT count(*) AS n FROM users').get().n,1);
  assert.deepEqual(s.workspace.rpc({op:'staff'},existing.token),{role:'admin',revision:7});
  assert.equal(existsSync(s.credentialsPath),false);
});

test('a normal user at the configured email is not silently promoted or overwritten',async t=>{
  const s=setup(t);
  const user=await s.workspace.auth({op:'register',email:'admin@eventmatch.local',name:'Ordinary user',password:'ordinary-password'});
  await assert.rejects(bootstrapAdmin(s.workspace,{dbPath:s.dbPath,env:{}}),/already registered/);
  assert.equal(s.workspace.rpc({op:'staff'},user.token).role,'none');
  assert.equal(s.db.prepare('SELECT count(*) AS n FROM users').get().n,1);
  assert.equal(existsSync(s.credentialsPath),false);
  await assert.rejects(s.workspace.auth({op:'ensureInitialAdmin',role:'admin'},user.token),e=>e.status===400);
  assert.throws(()=>s.workspace.rpc({op:'ensureInitialAdmin',role:'admin'},user.token),e=>e.status===400);
});

test('concurrent bootstrap attempts create exactly one administrator',async t=>{
  const s=setup(t);
  const results=await Promise.all(Array.from({length:2},()=>bootstrapAdmin(s.workspace,{dbPath:s.dbPath,env:{}})));
  assert.equal(results.filter(r=>r.created).length,1);
  assert.equal(s.db.prepare('SELECT count(*) AS n FROM users').get().n,1);
  const credentials=JSON.parse(readFileSync(s.credentialsPath,'utf8'));
  const login=await s.workspace.auth({op:'login',...credentials});
  assert.equal(s.workspace.rpc({op:'staff'},login.token).role,'admin');
});

test('invalid environment credentials fail without persisting accounts or secrets',async t=>{
  const s=setup(t);
  for(const env of [{ADMIN_EMAIL:'invalid-email'},{ADMIN_PASSWORD:'short'},{ADMIN_PASSWORD:'x'.repeat(129)},{ADMIN_NAME:'  '}]) {
    await assert.rejects(bootstrapAdmin(s.workspace,{dbPath:s.dbPath,env}),/Invalid initial admin configuration/);
  }
  assert.equal(s.db.prepare('SELECT count(*) AS n FROM users').get().n,0);
  assert.equal(existsSync(s.credentialsPath),false);
});

test('a credential write failure rolls back the user, account and role together',async t=>{
  const s=setup(t);
  await assert.rejects(bootstrapAdmin(s.workspace,{dbPath:join(s.directory,'missing','test.sqlite'),env:{}}),e=>e.code==='ENOENT');
  assert.equal(s.db.prepare('SELECT count(*) AS n FROM users').get().n,0);
  assert.equal(s.db.prepare('SELECT count(*) AS n FROM workspace').get().n,0);
});

test('saved credentials can recover an interrupted bootstrap and are never overwritten',async t=>{
  const s=setup(t);
  const saved={email:'admin@eventmatch.local',password:'saved-random-password',name:'Администратор'};
  const contents=JSON.stringify(saved);
  writeFileSync(s.credentialsPath,contents);
  await bootstrapAdmin(s.workspace,{dbPath:s.dbPath,env:{}});
  assert.equal(readFileSync(s.credentialsPath,'utf8'),contents);
  const login=await s.workspace.auth({op:'login',...saved});
  assert.equal(s.workspace.rpc({op:'staff'},login.token).role,'admin');
});

test('malformed saved credentials fail without disclosing their contents',async t=>{
  const s=setup(t);
  writeFileSync(s.credentialsPath,'{"password":"private-saved-secret"');
  await assert.rejects(bootstrapAdmin(s.workspace,{dbPath:s.dbPath,env:{}}),error=>{
    assert.match(error.message,/Invalid initial admin credentials file/);
    assert.equal(error.message.includes('private-saved-secret'),false);
    return true;
  });
  assert.equal(s.db.prepare('SELECT count(*) AS n FROM users').get().n,0);
});

test('standalone creation script works without Dart and is safe to rerun',async t=>{
  const s=setup(t);
  const env={...process.env,DB_PATH:s.dbPath,ADMIN_EMAIL:'',ADMIN_NAME:'',ADMIN_PASSWORD:'',DART_BIN:'missing-dart-executable'};
  const run=()=>spawnSync(process.execPath,['src/admin-create.mjs'],{cwd:join(root,'apps/api'),env,windowsHide:true,encoding:'utf8'});
  const first=run();
  assert.equal(first.status,0,first.stderr);
  assert.match(first.stdout,/Initial administrator created/);
  const credentials=JSON.parse(readFileSync(s.credentialsPath,'utf8'));
  assert.equal(first.stdout.includes(credentials.password),false);
  const second=run();
  assert.equal(second.status,0,second.stderr);
  assert.match(second.stdout,/Administrator already exists/);
  assert.equal(s.db.prepare('SELECT count(*) AS n FROM users').get().n,1);
  const login=await s.workspace.auth({op:'login',...credentials});
  assert.equal(s.workspace.rpc({op:'staff'},login.token).role,'admin');
});
