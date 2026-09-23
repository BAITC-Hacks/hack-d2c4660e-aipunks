import {openDatabase} from './database.mjs';
const email=process.argv[2]?.trim().toLowerCase();
if(!email)throw Error('Usage: npm run admin:grant -- account@example.com');
const db=openDatabase();
try {
  const user=db.prepare('SELECT uid FROM users WHERE email=?').get(email);
  if(!user)throw Error('Register the account in the local application first.');
  const old=db.prepare("SELECT payload FROM workspace WHERE kind='staff' AND owner=? AND id=?").get(user.uid,user.uid);
  const payload=JSON.stringify({role:'admin',revision:(old?JSON.parse(old.payload).revision:0)+1});
  db.prepare("INSERT INTO workspace VALUES('staff',?,?,?) ON CONFLICT(kind,owner,id) DO UPDATE SET payload=excluded.payload").run(user.uid,user.uid,payload);
  console.log('Local administrator access granted. Sign in again.');
} finally {db.close();}
