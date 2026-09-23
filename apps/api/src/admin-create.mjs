import {openDatabase,defaultDatabase} from './database.mjs';
import {createWorkspace} from './workspace.mjs';
import {bootstrapAdmin} from './bootstrap-admin.mjs';

const dbPath=process.env.DB_PATH || defaultDatabase;
const db=openDatabase(dbPath);
try {
  const admin=await bootstrapAdmin(createWorkspace(db),{dbPath});
  console.log(admin.created ? `Initial administrator created: ${admin.email}` : `Administrator already exists: ${admin.email}`);
  if(admin.credentialsPath)console.log(`Credentials saved to ${admin.credentialsPath}`);
  else if(admin.created)console.log('Password from ADMIN_PASSWORD.');
} finally {
  db.close();
}
