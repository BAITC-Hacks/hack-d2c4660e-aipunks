import { openDatabase, importCatalog } from './database.mjs';
const db = openDatabase();
try { console.log(JSON.stringify(importCatalog(db))); } finally { db.close(); }
