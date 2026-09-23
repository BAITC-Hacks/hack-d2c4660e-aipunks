import {randomBytes, randomUUID, createHash, scrypt as scryptCallback, timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';
import {z} from 'zod';
const scrypt=promisify(scryptCallback);
const hash=v=>createHash('sha256').update(v).digest('hex');
const now=()=>new Date().toISOString();
export class WorkspaceError extends Error {
  constructor(status,message,details={}) {super(message);this.status=status;this.details=details;}
}
const fail=(status,message,details)=>{throw new WorkspaceError(status,message,details);};
const id=z.string().min(1).max(160).regex(/^[^/\\]+$/);
const cities=['Алматы','Астана','Зарубежье'];
const categories=['Ведущий','Фотограф','Банкетный зал','Флорист','Декоратор','Подарки и сувениры','Ведущий церемонии','Фото и видеобудки','Отель','Инструменталист'];
const formats=['свадьба','той','корпоратив','конференция','юбилей','день рождения'];
const languages=['русский','казахский','английский'];
const date=z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(s=>Number.isFinite(Date.parse(s))&&new Date(s).toISOString().slice(0,10)===s);
const short=z.string().trim().min(1).max(120);
const profileSchema=z.object({name:z.string().max(120),city:z.enum(cities),categories:z.array(z.enum(categories)).max(10),price:z.number().int().min(0).max(1e9),formats:z.array(z.enum(formats)).max(6),languages:z.array(z.enum(languages)).max(3),maxHours:z.number().positive().max(48).nullable(),description:z.string().max(6000),contact:z.string().max(1000),portfolioUrls:z.array(z.string().url().max(2000).startsWith('https://')).max(5)}).strict();
const eventSchema=z.object({name:short,city:z.enum(cities),date,format:z.enum(formats),preferences:z.string().max(1000)}).strict();
const requestSchema=z.object({city:z.enum(cities),date,event_format:z.enum(formats),category:z.enum(categories),budget_kzt:z.number().int().positive().max(1e9),hours:z.number().positive().max(48).nullable(),language:z.enum(languages).nullable(),preferences:z.string().max(1000)}).strict();
const planSchema=z.object({schemaVersion:z.literal(1),revision:z.number().int().nonnegative(),totalBudgetKzt:z.number().int().positive().max(1e9).nullable(),choices:z.record(z.enum(categories),z.object({selectionId:id,contractorId:id}).strict()),completedTaskIds:z.array(z.enum(['confirm_scope','confirm_final_price','confirm_terms'])).max(3),notes:z.string().max(2000)}).strict();
const parse=(schema,value)=>{const r=schema.safeParse(value);if(!r.success) fail(400,'Проверьте заполненные поля.');return r.data;};
function liveDate(value){const today=new Date(Date.now()+5*3600000).toISOString().slice(0,10);const end=new Date(Date.parse(today)+365*86400000).toISOString().slice(0,10);if(value<today||value>end)fail(400,'Выберите дату в ближайшие 365 дней.');}

/** Single-machine backend. Identity and permissions are always resolved here, never from request actorId. */
export function createWorkspace(db) {
  db.exec(`CREATE TABLE IF NOT EXISTS users(uid TEXT PRIMARY KEY,email TEXT UNIQUE NOT NULL,salt TEXT NOT NULL,password_hash TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY,uid TEXT NOT NULL,expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS workspace(kind TEXT NOT NULL,owner TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(kind,owner,id));
    CREATE TABLE IF NOT EXISTS threads(id TEXT PRIMARY KEY,client_uid TEXT NOT NULL,contractor_uid TEXT NOT NULL,created_at TEXT NOT NULL,UNIQUE(client_uid,contractor_uid));
    CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,thread_id TEXT NOT NULL,sender_uid TEXT NOT NULL,body TEXT NOT NULL,created_at TEXT NOT NULL,nonce TEXT NOT NULL,UNIQUE(thread_id,sender_uid,nonce));
    CREATE INDEX IF NOT EXISTS messages_thread ON messages(thread_id,created_at);`);
  const get=(kind,owner,key=owner)=>{const r=db.prepare('SELECT payload FROM workspace WHERE kind=? AND owner=? AND id=?').get(kind,owner,key);return r?JSON.parse(r.payload):null;};
  const put=(kind,owner,key,data)=>db.prepare('INSERT INTO workspace VALUES(?,?,?,?) ON CONFLICT(kind,owner,id) DO UPDATE SET payload=excluded.payload').run(kind,owner,key,JSON.stringify(data));
  const list=(kind,owner)=>db.prepare(`SELECT id,payload FROM workspace WHERE kind=?${owner===undefined?'':' AND owner=?'} ORDER BY rowid DESC`).all(...(owner===undefined?[kind]:[kind,owner])).map(r=>({...JSON.parse(r.payload),id:r.id}));
  const remove=(kind,owner,key)=>db.prepare('DELETE FROM workspace WHERE kind=? AND owner=? AND id=?').run(kind,owner,key);
  const tx=fn=>{db.exec('BEGIN IMMEDIATE');try{const r=fn();db.exec('COMMIT');return r;}catch(e){db.exec('ROLLBACK');throw e;}};
  const audit=(actorId,resourceType,resourceId,revision,action,reason)=>put('audit','system',randomUUID(),{actorId,resourceType,resourceId,revision,action,reason,createdAt:now()});
  const account=uid=>get('account',uid);
  const role=uid=>get('staff',uid)?.role??'none';
  const hide=(uid,actor,reason)=>{const p=get('published',uid);if(p?.published){p.published=false;p.revision++;p.updatedAt=now();put('published',uid,uid,p);audit(actor,'publication',uid,p.revision,'unpublished',reason);}};
  const identity=uid=>{const a=account(uid);return {uid,email:a.email,name:a.name,emailVerified:false,accountType:a.accountType??'client'};};
  const requireSession=token=>{
    if(typeof token!=='string'||token.length>256)fail(401,'Войдите в аккаунт.');
    const row=db.prepare('SELECT uid FROM sessions WHERE token_hash=? AND expires>?').get(hash(token),Date.now());
    if(!row)fail(401,'Сеанс истёк. Войдите снова.');return row.uid;
  };
  const requireActive=uid=>{if(account(uid)?.status!=='active')fail(403,'Доступ к аккаунту ограничен.');};
  const requireStaff=(uid,admin=false)=>{requireActive(uid);if(!(admin?role(uid)==='admin':['admin','moderator'].includes(role(uid))))fail(403,'Недостаточно прав.');};
  const requireOwner=(uid,target)=>{if(uid!==target)fail(403,'Нет доступа к чужим данным.');};
  const issue=uid=>{const token=randomBytes(32).toString('base64url');db.prepare('DELETE FROM sessions WHERE expires<=?').run(Date.now());db.prepare('INSERT INTO sessions VALUES(?,?,?)').run(hash(token),uid,Date.now()+12*3600000);return {token,identity:identity(uid)};};
  async function prepareAccount(email,password,name,accountType='client') {
    const uid=randomUUID(),salt=randomBytes(16).toString('hex');
    const digest=(await scrypt(password,salt,64)).toString('hex');
    return {uid,email,name,salt,digest,accountType};
  }
  function insertAccount({uid,email,name,salt,digest,accountType}) {
    db.prepare('INSERT INTO users VALUES(?,?,?,?)').run(uid,email,salt,digest);
    put('account',uid,uid,{uid,name,email,accountType,status:'active',deletionRequested:false,revision:1});
  }
  // Server startup only: this method is never dispatched by auth() or rpc().
  // Resolve credentials lazily so an existing administrator is left untouched.
  async function ensureInitialAdmin(configure) {
    const existingAdmin=()=>db.prepare(`SELECT u.email FROM users u
      JOIN workspace s ON s.kind='staff' AND s.owner=u.uid AND s.id=u.uid
      WHERE json_extract(s.payload,'$.role')='admin' LIMIT 1`).get();
    const existing=existingAdmin();
    if(existing)return {created:false,email:existing.email};
    const {email,password,name,persist=()=>{}}=configure();
    const record=await prepareAccount(email,password,name);
    return tx(()=>{
      const existing=existingAdmin();
      if(existing)return {created:false,email:existing.email};
      if(db.prepare('SELECT uid FROM users WHERE email=?').get(email)) {
        throw Error('Initial admin email is already registered. Choose another ADMIN_EMAIL or use npm run admin:grant -- <email> locally.');
      }
      insertAccount(record);
      put('staff',record.uid,record.uid,{role:'admin',revision:1});
      // Fail the transaction if generated credentials cannot be saved locally.
      persist();
      return {created:true,email};
    });
  }
  async function auth(body,token) {
    if(body.op==='register'||body.op==='login') {
      const email=parse(z.string().trim().email().max(254),body.email).toLowerCase();
      const password=parse(z.string().min(8).max(128),body.password);
      const old=db.prepare('SELECT * FROM users WHERE email=?').get(email);
      if(body.op==='register') {
        const name=parse(short,body.name);
        const accountType=parse(z.enum(['client','contractor']).default('client'),body.accountType);
        if(old)fail(409,'Этот адрес уже зарегистрирован.');
        const record=await prepareAccount(email,password,name,accountType);
        tx(()=>insertAccount(record));
        return issue(record.uid);
      }
      // Constant-cost check also for unknown emails; no user enumeration on login.
      const digest=await scrypt(password,old?.salt??'missing-account',64);
      if(!old||!timingSafeEqual(digest,Buffer.from(old.password_hash,'hex')))fail(401,'Неверный email или пароль.');
      return issue(old.uid);
    }
    const uid=requireSession(token);
    if(body.op==='session')return {identity:identity(uid)};
    if(body.op==='logout'){db.prepare('DELETE FROM sessions WHERE token_hash=?').run(hash(token));return null;}
    fail(400,'Неизвестная операция входа.');
  }
  function rpc(body,token) {
    const op=body.op;
    // Only moderated publications and calendars attached to them are public.
    if(op==='listPublished') return list('published').filter(p=>p.published&&account(p.ownerId)?.status==='active');
    if(op==='getPublished') {const p=get('published',parse(id,body.uid));if(p?.published&&account(body.uid)?.status==='active')return p;}
    let uid;
    if(op==='getCalendar' && get('published',body.uid)?.published && account(body.uid)?.status==='active') {
      return get('calendar',parse(id,body.uid),parse(z.string().regex(/^\d{4}-\d{2}$/),body.key));
    }
    uid=requireSession(token);
    const target=body.uid??uid;
    if(op==='account'){requireOwner(uid,target);return account(uid);}
    if(op==='staff'){requireOwner(uid,target);return get('staff',uid)??{role:'none',revision:0};}
    if(op==='ensureAccount'){requireOwner(uid,target);return null;}
    requireActive(uid);
    if(['listProfiles','moderateProfile','unpublish','listAudit'].includes(op))requireStaff(uid);
    if(['listAccounts','listStaff','setAccountStatus','setModerator'].includes(op))requireStaff(uid,true);
    if(op==='listAccounts')return list('account');
    if(op==='listStaff')return Object.fromEntries(list('staff').map(s=>[s.id,{role:s.role,revision:s.revision}]));
    if(op==='listProfiles')return list('profile');
    if(op==='listAudit')return list('audit','system').slice(0,500);
    if(op==='moderateProfile')return tx(()=>{
      const p=get('profile',parse(id,target));
      if(!p||p.status!=='pending'||p.revision!==body.expectedRevision)fail(409,'Профиль изменился. Обновите список.');
      requireActive(target);
      if(typeof body.approve!=='boolean')fail(400,'Выберите решение.');
      const reason=parse(z.string().trim().max(1000),body.reason);
      if(!body.approve&&!reason)fail(400,'Укажите причину отказа.');
      p.status=body.approve?'approved':'changes_requested';p.reason=reason;p.revision++;p.updatedAt=now();put('profile',target,target,p);
      audit(uid,'profile',target,p.revision,p.status,reason);
      if(body.approve){const old=get('published',target);const pub={ownerId:target,content:p.content,revision:(old?.revision??0)+1,profileRevision:p.revision,published:true,updatedAt:now()};put('published',target,target,pub);audit(uid,'publication',target,pub.revision,'published',reason);}
      return null;
    });
    if(op==='unpublish')return tx(()=>{hide(parse(id,target),uid,parse(z.string().trim().min(1).max(1000),body.reason));return null;});
    if(op==='setModerator'||op==='setAccountStatus')return tx(()=>{
      if(uid===target||role(target)==='admin')fail(403,'Нельзя изменять собственный доступ или администратора.');
      const a=account(parse(id,target));if(!a)fail(404,'Аккаунт не найден.');
      const reason=parse(z.string().trim().min(1).max(1000),body.reason);
      if(op==='setModerator'){const r={role:parse(z.boolean(),body.enabled)?'moderator':'none',revision:(get('staff',target)?.revision??0)+1};put('staff',target,target,r);audit(uid,'staff',target,r.revision,r.role,reason);}
      else {a.status=parse(z.boolean(),body.suspended)?'suspended':'active';a.revision++;put('account',target,target,a);audit(uid,'account',target,a.revision,a.status,reason);if(a.status!=='active')hide(target,uid,reason);}
      return null;
    });
    requireOwner(uid,target);
    if(op==='updateName'){const a=account(uid);a.name=parse(short,body.name);a.revision++;put('account',uid,uid,a);return null;}
    if(op==='deactivateAccount')return tx(()=>{if(role(uid)==='admin')fail(403,'Сначала передайте права администратора.');const a=account(uid);a.status='deactivated';a.deletionRequested=body.requestDeletion===true;a.revision++;put('account',uid,uid,a);hide(uid,uid,'Деактивация владельцем');audit(uid,'account',uid,a.revision,'deactivated','Запрос владельца');return null;});
    if(op==='getProfile')return get('profile',uid);
    if(op==='getPublished')return get('published',uid);
    if(op==='saveProfile')return tx(()=>{const old=get('profile',uid);if(old?.status==='pending')fail(409,'Сначала отзовите профиль с проверки.');put('profile',uid,uid,{ownerId:uid,content:parse(profileSchema,body.content),revision:(old?.revision??0)+1,status:'draft',reason:'',updatedAt:now()});return null;});
    if(op==='submitProfile'||op==='withdrawProfile')return tx(()=>{
      const p=get('profile',uid);if(!p)fail(404,'Сначала сохраните профиль.');
      if(op==='submitProfile') {const c=p.content;if(p.status==='pending')fail(409,'Профиль уже на проверке.');if(!c.name.trim()||!c.description.trim()||!c.contact.trim()||!c.categories.length||!c.formats.length||!c.languages.length||c.price<=0)fail(400,'Заполните профиль перед отправкой.');}
      else if(p.status!=='pending')fail(409,'Профиль больше не на проверке.');
      p.status=op==='submitProfile'?'pending':'draft';p.reason='';p.revision++;p.updatedAt=now();put('profile',uid,uid,p);return null;
    });
    if(op==='getCalendar')return get('calendar',uid,parse(id,body.key));
    if(op==='saveCalendar'){
      const c=parse(z.object({year:z.number().int().min(2020).max(2200),month:z.number().int().min(1).max(12),busyDays:z.array(z.number().int().min(1).max(31)).max(31)}).strict(),body.calendar);
      if(c.busyDays.some(d=>d>new Date(c.year,c.month,0).getDate()))fail(400,'Некорректный день месяца.');
      const key=`${c.year}-${String(c.month).padStart(2,'0')}`;put('calendar',uid,key,{...c,ownerId:uid,confirmedAt:now()});return null;
    }
    if(op==='listEvents')return list('event',uid);
    if(op==='saveEvent'){const event=parse(eventSchema,body.event);liveDate(event.date);const key=body.id?parse(id,body.id):randomUUID();put('event',uid,key,{...event,updatedAt:now()});return key;}
    if(op==='deleteEvent')return tx(()=>{const key=parse(id,body.id);if(list('selection',uid).some(s=>s.eventId===key))fail(409,'Сначала удалите подборки мероприятия.');remove('plan',uid,key);remove('event',uid,key);return null;});
    if(op==='listSelections')return list('selection',uid);
    if(op==='saveSelection'){
      const s=body.selection;if(!s||!get('event',uid,parse(id,s.eventId)))fail(404,'Мероприятие не найдено.');
      const request=parse(requestSchema,s.request);liveDate(request.date);
      if(!Array.isArray(s.entries)||s.entries.length>3)fail(400,'До трёх карточек в подборке.');
      const entries=s.entries.map(e=>{const p=get('published',e.contractor?.id);if(!p?.published)fail(400,'Подрядчик не опубликован.');return {contractor:snapshot(p),explanation:parse(z.string().max(2000),e.explanation)};});
      const key=body.id?parse(id,body.id):randomUUID();put('selection',uid,key,{eventId:s.eventId,name:parse(short,s.name),request,entries,savedAt:now()});return key;
    }
    if(op==='deleteSelection'){remove('selection',uid,parse(id,body.id));return null;}
    if(op==='listFavorites')return list('favorite',uid).map(f=>f.contractor);
    if(op==='setFavorite'){const key=parse(id,body.contractorId);if(body.favorite===false){remove('favorite',uid,key);return null;}const p=get('published',key);if(!p?.published)fail(400,'Подрядчик не опубликован.');put('favorite',uid,key,{contractor:snapshot(p),savedAt:now()});return null;}
    if(op==='getPlan'){const key=parse(id,body.eventId);return get('plan',uid,key);}
    if(op==='savePlan')return tx(()=>{
      const key=parse(id,body.eventId),plan=parse(planSchema,body.plan);
      if(!get('event',uid,key))fail(404,'Мероприятие удалено.');
      const revision=get('plan',uid,key)?.revision??0;if(revision!==plan.revision)fail(409,'План изменён в другом окне.',{actualRevision:revision});
      const ids=new Set();for(const [category,choice] of Object.entries(plan.choices)) {const selection=get('selection',uid,choice.selectionId);if(!selection||selection.eventId!==key||selection.request.category!==category||!selection.entries.some(e=>e.contractor.id===choice.contractorId)||ids.has(choice.contractorId))fail(400,'Проверьте выбранные подборки.');ids.add(choice.contractorId);}
      plan.revision++;put('plan',uid,key,plan);return plan;
    });
    fail(400,'Неизвестная операция кабинета.');
  }
  function messaging(body,token) {
    const uid=requireSession(token);requireActive(uid);
    const describe=t=>{const peer=t.client_uid===uid?t.contractor_uid:t.client_uid;const last=db.prepare('SELECT body,created_at FROM messages WHERE thread_id=? ORDER BY rowid DESC LIMIT 1').get(t.id);return {id:t.id,peerId:peer,peerName:account(peer)?.name??'Участник',lastMessage:last?.body??'',updatedAt:last?.created_at??t.created_at};};
    if(body.op==='list')return db.prepare('SELECT * FROM threads WHERE client_uid=? OR contractor_uid=? ORDER BY created_at DESC').all(uid,uid).map(describe).sort((a,b)=>b.updatedAt.localeCompare(a.updatedAt));
    if(body.op==='open') {
      const contractor=parse(id,body.contractorId);if(contractor===uid)fail(400,'Нельзя написать самому себе.');
      if(!get('published',contractor)?.published)fail(404,'Этот профиль не принимает сообщения.');requireActive(contractor);
      db.prepare('INSERT OR IGNORE INTO threads VALUES(?,?,?,?)').run(randomUUID(),uid,contractor,now());
      return describe(db.prepare('SELECT * FROM threads WHERE client_uid=? AND contractor_uid=?').get(uid,contractor));
    }
    const t=db.prepare('SELECT * FROM threads WHERE id=?').get(parse(id,body.threadId));
    if(!t||![t.client_uid,t.contractor_uid].includes(uid))fail(404,'Переписка не найдена.');
    if(body.op==='read')return db.prepare('SELECT id,sender_uid AS senderId,body AS text,created_at AS createdAt FROM messages WHERE thread_id=? ORDER BY rowid DESC LIMIT 200').all(t.id).reverse();
    if(body.op==='send') {
      requireActive(t.client_uid===uid?t.contractor_uid:t.client_uid);
      const text=parse(z.string().trim().min(1).max(4000),body.text),nonce=parse(id,body.nonce);
      db.prepare('INSERT OR IGNORE INTO messages VALUES(?,?,?,?,?,?)').run(randomUUID(),t.id,uid,text,now(),nonce);
      return {sent:true};
    }
    fail(400,'Неизвестная операция переписки.');
  }
  return {auth,rpc,messaging,ensureInitialAdmin};
}
function snapshot(p) {const c=p.content;return {id:p.ownerId,anon_name:c.name,city:c.city,categories:c.categories,price_from_kzt:c.price,event_formats:c.formats,languages:c.languages,max_hours:c.maxHours,busy_dates:[],description:c.description,synthetic:false,city_imputed:false,price_imputed:false,is_live:true,contact:c.contact,portfolio_urls:c.portfolioUrls};}
