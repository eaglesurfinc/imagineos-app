// Fictional adult-created content only. No provider calls or paid operations.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID,createHash} from 'node:crypto';
const config=JSON.parse(fs.readFileSync('config/supabase.local.json','utf8'));
const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json','utf8'));
const fixture=JSON.parse(fs.readFileSync('config/stage5-fixture.local.json','utf8'));
assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');
assert(accounts.every(a=>a.email.endsWith('@example.invalid')));
const sessions=[],children=[];
async function api(path,token,body,extra={}){
 const response=await fetch(config.SUPABASE_URL+path,{method:body?'POST':'GET',headers:{
  apikey:config.SUPABASE_PUBLISHABLE_KEY,'content-type':'application/json',Origin:'http://127.0.0.1:8766',
  ...(token?{authorization:`Bearer ${token}`} : {}),...extra},body:body?JSON.stringify(body):undefined});
 const data=response.headers.get('content-type')?.startsWith('application/octet-stream')
  ? Buffer.from(await response.arrayBuffer()):await response.json().catch(()=>null);
 return{status:response.status,data};
}
const parent=(token,body,grant)=>api('/functions/v1/parent-controls',token,body,grant?{'x-imagineos-parent-grant':grant}:{});
const child=(secret,body)=>api('/functions/v1/child-access',null,body,secret?{'x-imagineos-child-session':secret}:{});
function ok(result){assert.equal(result.status,200,`Unexpected API status ${result.status}: ${result.data?.code??''}`);return result.data?.contract_version===1?result.data.data:result.data;}
async function login(code){const body={action:'login',code,request_id:randomUUID(),secret:randomBytes(32).toString('hex')};
 const data=ok(await child(null,body));children.push(body.secret);return{body,data,secret:body.secret};}
try{
 for(const account of accounts){const result=await api('/auth/v1/token?grant_type=password',null,{email:account.email,password:account.password});
  assert.equal(result.status,200);sessions.push(result.data);}
 const [a,b]=sessions.map(s=>s.access_token);
 const grantA=ok(await parent(a,{action:'unlock',password:accounts[0].password})).grant;
 const grantB=ok(await parent(b,{action:'unlock',password:accounts[1].password})).grant;
 const profiles=ok(await parent(a,{action:'child_list'},grantA)).profiles;
 const creator=profiles.find(p=>p.id===fixture.first.child_profile_id);assert(creator);assert.equal(creator.allow_export,false);
 const sibling=ok(await parent(a,{action:'child_add',nickname:'Fictional sibling'},grantA)).child_id;
 const approve=async(id,minutes=30)=>ok(await parent(a,{action:'child_approve',child_id:id,minutes},grantA)).code;
 assert.equal((await child(null,{action:'library'})).status,401);
 assert.equal((await api('/functions/v1/child-access',a,{action:'library'})).status,401,'Parent JWT bypassed child approval');
 assert.notEqual((await parent(a,{action:'child_approve',child_id:creator.id,minutes:1})).status,200,'Approval without parent unlock');
 assert.notEqual((await parent(b,{action:'child_approve',child_id:creator.id,minutes:1},grantB)).status,200,'Other family approved a child');
 const code=await approve(creator.id),signed=await login(code);
 const replay=ok(await child(null,signed.body));assert.equal(replay.expires_at,signed.data.expires_at,'Retry extended duration');
 assert.equal((await child(null,{...signed.body,secret:randomBytes(32).toString('hex')})).status,401);
 assert.equal((await child(null,{...signed.body,request_id:randomUUID()})).status,401);
 const library=ok(await child(signed.secret,{action:'library'}));
 assert.deepEqual(library.creators.map(c=>c.id),[creator.id]);assert.equal(library.versions.length,2);
 const old=await child(signed.secret,{action:'download',asset_id:fixture.first.request_id});assert.equal(old.status,200);
 assert.equal(createHash('sha256').update(old.data).digest('hex'),fixture.first.sha256);
 assert.equal((await child(signed.secret,{action:'authorize_export'})).status,401);
 const foreign=(await api('/rest/v1/original_uploads?select=request_id',b)).data[0];
 assert.equal((await child(signed.secret,{action:'download',asset_id:foreign.request_id})).status,401);
 const bytes=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGNw09iCFTEMLQkAOOxIgSesf3AAAAAASUVORK5CYII=','base64');
 const save={action:'reserve',request_id:randomUUID(),child_id:creator.id,character_id:null,
  name:'Fictional child upload',mime_type:'image/png',byte_size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')};
 assert.equal((await child(signed.secret,{...save,child_id:sibling})).status,401);
 const row=ok(await child(signed.secret,save));assert.equal(row.child_profile_id,creator.id);
 ok(await child(signed.secret,{action:'upload',asset_id:row.request_id,bytes:bytes.toString('base64')}));
 ok(await child(signed.secret,{action:'upload',asset_id:row.request_id,bytes:bytes.toString('base64')}));
 ok(await child(signed.secret,{action:'finish',asset_id:row.request_id}));
 assert.equal(ok(await child(signed.secret,save)).state,'ready');
 const page={action:'save_page',page_id:randomUUID(),asset_id:fixture.first.request_id,revision:0,
  scene:'  My exact scene.\n ',dialogue:'  My  words 🌈\n ',narration:'  I decide.  '};
 assert.equal(ok(await child(signed.secret,page)),1);assert.equal(ok(await child(signed.secret,page)),1);
 const pages=ok(await child(signed.secret,{action:'pages',asset_id:fixture.first.request_id}));
 assert.equal(pages[0].dialogue,page.dialogue);assert.equal(pages[0].scene,page.scene);
 const story={action:'save_story',id:randomUUID(),child_id:creator.id,revision:0,title:'  My story 🌈  ',format:'comic',
  panels:[{id:randomUUID(),reference:{character_id:fixture.first.character_id,version_id:fixture.first.version_id,
   asset_id:fixture.first.request_id,sha256:fixture.first.sha256},scene:page.scene,dialogue:page.dialogue,narration:page.narration}]};
 assert.equal(ok(await child(signed.secret,story)),1);assert.equal(ok(await child(signed.secret,story)),1);
 const saved=ok(await child(signed.secret,{action:'stories',offset:0}));assert.equal(saved[0].title,story.title);
 assert.equal(saved[0].panels[0].dialogue,page.dialogue);
 const siblingSignIn=await login(await approve(sibling));
 assert.equal((await child(siblingSignIn.secret,{action:'download',asset_id:fixture.first.request_id})).status,401);
 assert.deepEqual(ok(await child(siblingSignIn.secret,{action:'stories',offset:0})),[]);
 assert.equal((await child(siblingSignIn.secret,{...story,revision:1})).status,401);
 assert.notEqual((await api('/rest/v1/rpc/child_access',a,{p_action:'library',p_token_hash:'a'.repeat(64),p_data:{}})).status,200);
 assert.notEqual((await api('/functions/v1/parent-providers',signed.secret,{action:'list'})).status,200);
 assert.notEqual((await api('/rest/v1/child_profiles',signed.secret)).status,200);
 ok(await parent(a,{action:'child_settings',child_id:creator.id,minutes:30,allow_export:true,blocked:false},grantA));
 assert.equal(ok(await child(signed.secret,{action:'authorize_export'})),true);
 ok(await parent(b,{action:'child_end',session_id:signed.data.session_id},grantB));
 assert.equal((await child(signed.secret,{action:'status'})).status,200,'Other family revoked the session');
 ok(await parent(a,{action:'child_end',session_id:signed.data.session_id},grantA));
 assert.equal((await child(signed.secret,{action:'library'})).status,401);
 assert.equal((await child(null,signed.body)).status,401,'Revoked approval replayed');
 const pendingCode=await approve(creator.id);
 ok(await parent(a,{action:'child_settings',child_id:creator.id,minutes:1,allow_export:false,blocked:true},grantA));
 assert.equal((await child(null,{action:'login',code:pendingCode,request_id:randomUUID(),secret:randomBytes(32).toString('hex')})).status,401);
 ok(await parent(a,{action:'child_settings',child_id:creator.id,minutes:1,allow_export:false,blocked:false},grantA));
 assert.equal((await child(null,{action:'login',code:pendingCode,request_id:randomUUID(),secret:randomBytes(32).toString('hex')})).status,401,'Unblocking reused an old approval');
 const timed=await login(await approve(creator.id,1));
 console.log('PASS: hosted parent-only single-use approval, fixed retry deadline, child upload/replay/original bytes, exact stories/pages, sibling/family isolation, provider/admin denial, export permission, revocation and blocked-code reuse. Checking real one-minute expiry…');
 for(let i=0;i<2;i++){
  await new Promise(resolve=>setTimeout(resolve,20000));
  assert.equal(ok(await child(timed.secret,{action:'status'})).expires_at,timed.data.expires_at,'Activity extended the session');
 }
 await new Promise(resolve=>setTimeout(resolve,22000));
 for(const body of [{action:'status'},{action:'library'},{action:'download',asset_id:fixture.first.request_id},
  {...save,request_id:randomUUID()}, {...story,revision:1}])assert.equal((await child(timed.secret,body)).status,401,'Expired approval still authorized data');
 assert.equal((await child(null,timed.body)).status,401,'Expired approval reopened a session');
 fs.writeFileSync('config/child-test.local.json',JSON.stringify({creator:creator.id,sibling,story:story.id}));
 console.log('PASS: real server expiry blocks reads, downloads and writes; keep-alives and identical replay never extend or reopen the approved session. New parent approval is required.');
}finally{
 for(const token of children)await child(token,{action:'logout'});
 for(const session of sessions)await api('/auth/v1/logout?scope=local',session.access_token,{});
}
