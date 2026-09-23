import {randomBytes} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {z} from 'zod';

const credentialsSchema=z.object({
  email:z.string().trim().email().max(254).transform(value=>value.toLowerCase()),
  password:z.string().min(8).max(128),
  name:z.string().trim().min(1).max(120),
});

/** Provision one administrator before accepting HTTP requests. Never reset existing accounts. */
export async function bootstrapAdmin(workspace,{dbPath,env=process.env}) {
  let credentialsPath;
  const result=await workspace.ensureInitialAdmin(()=>{
    const configured={
      email:env.ADMIN_EMAIL || 'admin@eventmatch.local',
      name:env.ADMIN_NAME || 'Администратор',
      password:env.ADMIN_PASSWORD || randomBytes(24).toString('base64url'),
    };
    let saveCredentials=false;
    if(!env.ADMIN_PASSWORD) {
      if(dbPath===':memory:')throw Error('Set ADMIN_PASSWORD when using DB_PATH=:memory:.');
      credentialsPath=`${resolve(dbPath)}.admin-credentials.json`;
      // Reuse a saved secret after a failed/interrupted bootstrap or a DB restore.
      try {
        const contents=readFileSync(credentialsPath,'utf8');
        let saved;
        try { saved=JSON.parse(contents); }
        catch { throw Error('Invalid initial admin credentials file. Restore it or set ADMIN_PASSWORD explicitly.'); }
        if(saved?.email!==configured.email.trim().toLowerCase()) {
          throw Error('Saved initial admin email differs from ADMIN_EMAIL. Set ADMIN_PASSWORD explicitly.');
        }
        configured.password=saved.password;
      } catch(error) {
        if(error.code!=='ENOENT')throw error;
        saveCredentials=true;
      }
    }
    const parsed=credentialsSchema.safeParse(configured);
    if(!parsed.success)throw Error('Invalid initial admin configuration: check ADMIN_EMAIL, ADMIN_NAME and ADMIN_PASSWORD (8–128 characters).');
    return {...parsed.data,persist:()=>{
      if(saveCredentials)writeFileSync(credentialsPath,`${JSON.stringify(parsed.data,null,2)}\n`,{flag:'wx',mode:0o600});
    }};
  });
  return {...result,...(result.created && credentialsPath ? {credentialsPath} : {})};
}
