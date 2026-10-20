// Fictional adult fixtures on the approved development target only.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
const config=JSON.parse(fs.readFileSync('config/supabase.local.json'));
const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json'));
const fixture=JSON.parse(fs.readFileSync('config/stage5-fixture.local.json'));
assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');
assert(accounts.length===2&&accounts.every(a=>/^adult-.*@example\.invalid$/.test(a.email)));
async function api(path,token,body,grant,child){const r=await fetch(config.SUPABASE_URL+path,{method:body?'POST':'GET',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,
  'content-type':'application/json',...(token?{authorization:`Bearer ${token}`} : {}),...(grant?{'x-imagineos-parent-grant':grant}:{}),...(child?{'x-imagineos-child-session':child}:{})},body:body?JSON.stringify(body):undefined});
 const data=await r.json().catch(()=>null);return{status:r.status,data:data?.contract_version===1?data.data:data};}
function ok(r){assert.equal(r.status,200,'API status '+r.status);return r.data;}
const sessions=[],childSecrets=[];
try{
 for(const a of accounts)sessions.push(ok(await api('/auth/v1/token?grant_type=password',null,{email:a.email,password:a.password})));
 const[a,b]=sessions.map(s=>s.access_token);
 const grants=[];for(let i=0;i<2;i++)grants.push(ok(await api('/functions/v1/parent-controls',sessions[i].access_token,{action:'unlock',password:accounts[i].password})).grant);
 const call=(index,body)=>api('/functions/v1/parent-controls',sessions[index].access_token,body,grants[index]);
 const status=ok(await call(0,{action:'privacy_status'}));assert.equal(status.pilot_enabled,false);assert.equal(status.consent_status,'not_configured');assert.equal(status.retention_status,'not_configured');
 assert.equal((await api('/functions/v1/parent-controls',a,{action:'recovery_snapshot'})).status,403);
 assert.equal((await api('/functions/v1/parent-controls',b,{action:'recovery_snapshot'},grants[0])).status,403);
 assert.equal((await api('/functions/v1/parent-controls',null,{action:'privacy_pause',paused:true},grants[0])).status,401);
 for(const token of [null,a,b])assert([401,403].includes((await api('/rest/v1/rpc/parent_privacy',token,{p_parent:accounts[0].id,p_session:randomUUID(),p_grant_hash:'a'.repeat(64),p_action:'recovery_snapshot'})).status));
 const before=ok(await call(0,{action:'recovery_snapshot'}));assert.equal(before.originals.length,2);assert.equal(before.children.length,1);
 const childId=before.children[0].id, source=before.originals.find(v=>v.request_id===fixture.first.request_id);
 assert(source);
 const reference={character_id:source.character_id,version_id:source.version_id,asset_id:source.request_id,sha256:source.sha256};
 const words='  Fictional exact recovery words 🌈\n\n  ';
 const storyId=randomUUID(),pageId=randomUUID();
 ok(await api('/rest/v1/rpc/save_story_project',a,{p_id:storyId,p_child_id:childId,p_revision:0,p_title:'  Exact backup title  ',p_format:'comic',p_panels:[{id:randomUUID(),reference,scene:'walk',dialogue:words,narration:'\n End  '}]}));
 ok(await api('/rest/v1/rpc/save_story_draft',a,{p_page_id:pageId,p_source_id:source.request_id,p_revision:0,p_scene:'walk',p_dialogue:words,p_narration:'\n End  '}));
 async function approved(index,id){const code=ok(await call(index,{action:'child_approve',child_id:id,minutes:5})).code;
  const secret=randomBytes(32).toString('hex');ok(await api('/functions/v1/child-access',null,{action:'login',code,request_id:randomUUID(),secret}));childSecrets.push(secret);return{code,secret};}
 const active=await approved(0,childId);
 const unused=ok(await call(0,{action:'child_approve',child_id:childId,minutes:5})).code;
 const bSnapshot=ok(await call(1,{action:'recovery_snapshot'}));const independent=await approved(1,bSnapshot.children[0].id);
 ok(await call(0,{action:'privacy_pause',paused:true}));
 assert.equal((await api('/functions/v1/child-access',null,{action:'status'},null,active.secret)).status,401);
 assert.equal((await api('/functions/v1/child-access',null,{action:'login',code:unused,request_id:randomUUID(),secret:randomBytes(32).toString('hex')})).status,401);
 assert.equal((await call(0,{action:'child_approve',child_id:childId,minutes:5})).status,409);
 ok(await api('/functions/v1/child-access',null,{action:'status'},null,independent.secret));
 const newChild=ok(await call(0,{action:'child_add',nickname:'Fictional recovery creator'})).child_id;
 assert.equal((await call(0,{action:'child_approve',child_id:newChild,minutes:5})).status,409);
 ok(await call(0,{action:'privacy_pause',paused:false}));
 assert.equal((await api('/functions/v1/child-access',null,{action:'status'},null,active.secret)).status,401);
 assert.equal((await api('/functions/v1/child-access',null,{action:'login',code:unused,request_id:randomUUID(),secret:randomBytes(32).toString('hex')})).status,401);
 await approved(0,childId);
 const snapshot=ok(await call(0,{action:'recovery_snapshot'}));
 assert.equal(snapshot.stories.length,1);assert.equal(snapshot.stories[0].panels[0].dialogue,words);assert.equal(snapshot.pages[0].dialogue,words);
 assert.equal(snapshot.stories[0].panels[0].reference.version_id,source.version_id);assert(snapshot.originals.every(v=>v.object_path.startsWith(status.family_id+'/')));
 for(const key of ['password','grant','secret','provider_connections','token_hash'])assert(!Object.hasOwn(snapshot,key));
 assert.equal((await api('/functions/v1/parent-controls',null,{action:'recovery_snapshot'},null,active.secret)).status,401);
 assert.deepEqual(ok(await call(1,{action:'recovery_snapshot'})),bSnapshot);
 fs.writeFileSync('config/privacy-test.local.json',JSON.stringify({family:snapshot.family_id,creator:childId,target:newChild,storyId,pageId,words,reference}));
 ok(await call(0,{action:'lock'}));assert.equal((await call(0,{action:'recovery_snapshot'})).status,403);
 console.log('PASS: private parent-only complete snapshot, exact story/page text and old-version pins; family pause revokes active and unused approvals, blocks new profiles, resumes only fresh approvals and preserves the other family. Pilot/consent/retention stay unconfigured.');
}finally{
 for(const secret of childSecrets)await api('/functions/v1/child-access',null,{action:'logout'},null,secret);
 for(const s of sessions)await api('/auth/v1/logout?scope=local',s.access_token,{});
}
