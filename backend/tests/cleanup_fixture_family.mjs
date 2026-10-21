// Deliberately destructive only for one locally generated adult fixture account.
// Index is explicit; do not reuse this script with personal/real-family data.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const index=Number(process.argv[2]);assert(process.argv.length===3&&[0,1].includes(index));
const config=JSON.parse(fs.readFileSync('config/supabase.local.json'));
const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json'));
assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');
assert.equal(accounts.length,2);assert(accounts.every(a=>/^adult-[a-f0-9]+@example\.invalid$/.test(a.email)&&/^[a-f0-9-]{36}$/.test(a.id)));
const account=accounts[index];
async function api(route,token,body,grant){
 const r=await fetch(config.SUPABASE_URL+route,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,
  'content-type':'application/json',...(token?{authorization:`Bearer ${token}`} : {}),
  ...(grant?{'x-imagineos-parent-grant':grant}: {})},body:JSON.stringify(body)});
 const value=await r.json().catch(()=>null);return{status:r.status,value,data:value?.contract_version===1?value.data:value};
}
const ok=r=>{assert.equal(r.status,200,'Fixture cleanup status '+r.status);return r.data;};
let token;
try{
 const session=ok(await api('/auth/v1/token?grant_type=password',null,{email:account.email,password:account.password}));
 assert.equal(session.user.id,account.id);assert.equal(session.user.email,account.email);assert.equal(session.user.is_anonymous,false);
 token=session.access_token;
 const grant=ok(await api('/functions/v1/parent-controls',token,{action:'unlock',password:account.password})).grant;
 const family=ok(await api('/functions/v1/parent-controls',token,{action:'privacy_status'},grant)).family_id;
 assert(/^[a-f0-9-]{36}$/.test(family));
 const overview=ok(await api('/functions/v1/parent-controls',token,{action:'overview'},grant));
 let result=ok(await api('/functions/v1/parent-controls',token,overview.deletion_pending?{action:'continue_delete'}:
  {action:'start_delete',password:account.password,confirmation:'DELETE MY FAMILY'},grant));
 for(let batch=0;batch<50&&result.pending===true;batch++)result=ok(await api('/functions/v1/parent-controls',token,{action:'continue_delete'},grant));
 assert.equal(result.deleted,true);assert.equal(result.pending,false);
 assert.notEqual((await api('/auth/v1/token?grant_type=password',null,{email:account.email,password:account.password})).status,200);
 fs.writeFileSync(`build/fixture-${index}-cleanup.json`,JSON.stringify({parent_id:account.id,family_id:family,deleted:true}));
 console.log(`PASS: fixture ${index} erased through Storage-first parent deletion; account sign-in no longer works. Verify database/file counts before removing fixture JSON.`);
}finally{
 if(token)await api('/auth/v1/logout?scope=local',token,{}).catch(()=>{});
}
