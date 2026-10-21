// Fictional accounts only, approved development target. Run after the existing
// illustration/privacy fixture setup. Mandatory Storage-first family cleanup.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
const config=JSON.parse(fs.readFileSync('config/supabase.local.json'));
const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json'));
const prior=JSON.parse(fs.readFileSync('config/privacy-test.local.json'));
assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');
assert.equal(accounts.length,2);assert(accounts.every(a=>/^adult-.*@example\.invalid$/.test(a.email)));
const sessions=[];
async function api(route,token,body,grant,method=body===undefined?'GET':'POST'){
 const r=await fetch(config.SUPABASE_URL+route,{method,headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,
  ...(token?{authorization:`Bearer ${token}`} : {}),...(grant?{'x-imagineos-parent-grant':grant}:{}),
  'content-type':body instanceof Buffer?'image/png':'application/json'},
  body:body===undefined?undefined:body instanceof Buffer?body:JSON.stringify(body)});
 const value=await r.json().catch(()=>null);return{status:r.status,code:value?.code,data:value?.contract_version===1?value.data:value};
}
const ok=result=>{assert([200,204].includes(result.status),'API status '+result.status);return result.data;};
try {
 for(const a of accounts)sessions.push(ok(await api('/auth/v1/token?grant_type=password',null,{email:a.email,password:a.password})));
 const [a,b]=sessions.map(s=>s.access_token),grants=[];
 for(let i=0;i<2;i++)grants.push(ok(await api('/functions/v1/parent-controls',sessions[i].access_token,
  {action:'unlock',password:accounts[i].password})).grant);
 const parent=(index,body,grant=grants[index])=>api('/functions/v1/parent-controls',sessions[index].access_token,body,grant);
 const image=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGNw09iCFTEMLQkAOOxIgSesf3AAAAAASUVORK5CYII=','base64');
 const sha=createHash('sha256').update(image).digest('hex'),asset=randomUUID();
 const source=ok(await api('/rest/v1/rpc/reserve_original',a,{p_request_id:asset,p_child_id:prior.creator,p_character_id:null,
  p_name:'Fictional artwork to delete',p_mime_type:'image/png',p_byte_size:image.length,p_sha256:sha}));
 ok(await api('/storage/v1/object/character-originals/'+source.object_path,a,image));
 ok(await api('/rest/v1/rpc/finish_original',a,{p_request_id:asset}));
 const missingRef={character_id:source.character_id,version_id:source.version_id,asset_id:asset,sha256:sha};
 const storyId=randomUUID(),title='  Missing artwork recovery 🌈  ',words='  Exact missing-art story words 🌈\n<script>text only</script>  ';
 const panels=[{id:randomUUID(),reference:missingRef,scene:'  Walking\n',dialogue:words,narration:'\n  The child chose this.  '},
  {id:randomUUID(),reference:prior.reference,scene:'',dialogue:'',narration:'  Exact second panel  '}];
 ok(await api('/rest/v1/rpc/save_story_project',a,{p_id:storyId,p_child_id:prior.creator,p_revision:0,p_title:title,p_format:'strip',p_panels:panels}));
 const paths=ok(await api('/rest/v1/rpc/begin_character_deletion',a,{p_character_id:source.character_id,p_version_id:null}));
 assert(paths.length===1);assert(paths[0].object_path===source.object_path||paths[0]===source.object_path);
 ok(await api('/storage/v1/object/character-originals',a,{prefixes:[source.object_path]},undefined,'DELETE'));
 ok(await api('/rest/v1/rpc/finish_character_deletion',a,{p_character_id:source.character_id,p_version_id:null}));
 const snapshot=ok(await parent(0,{action:'recovery_snapshot'})),story=snapshot.stories.find(s=>s.id===storyId);
 assert(story);assert.deepEqual(story.panels.map(p=>p.source_available),[false,true]);
 assert.equal(story.panels[0].dialogue,words);assert(!snapshot.originals.some(v=>v.request_id===asset));
 const copy={...story,id:randomUUID(),revision:0,panels:story.panels.map(p=>({...p,id:randomUUID(),
  reference:p.source_available?p.reference:{...p.reference,character_id:randomUUID(),version_id:randomUUID(),asset_id:randomUUID()}}))};
 assert.equal((await parent(0,{action:'recover_story',story:copy},'')).status,403);
 assert.equal((await parent(1,{action:'recover_story',story:copy})).status,403);
 assert.equal((await api('/functions/v1/parent-controls',null,{action:'recover_story',story:copy},grants[0])).status,401);
 for(const token of [null,a,b])assert([401,403].includes((await api('/rest/v1/rpc/recover_story_copy',token,
  {p_parent:accounts[0].id,p_session:randomUUID(),p_grant_hash:'a'.repeat(64),p_story:copy})).status));
 const result=ok(await parent(0,{action:'recover_story',story:copy}));assert.equal(result.revision,1);
 assert.deepEqual(ok(await parent(0,{action:'recover_story',story:copy})),result);
 const changed=await parent(0,{action:'recover_story',story:{...copy,title:'Changed retry'}});
 assert.equal(changed.status,409);assert.equal(changed.code,'RECOVERY_CONFLICT');
 const rows=ok(await api('/rest/v1/story_project_snapshots?id=eq.'+copy.id,a));
 assert.equal(rows.length,1);assert.equal(rows[0].panels[0].dialogue,words);assert(!rows[0].panels[0].source_available);
 assert.equal(rows[0].panels[1].reference.asset_id,prior.reference.asset_id);
 ok(await api('/rest/v1/rpc/delete_story_project',a,{p_id:copy.id,p_revision:1}));
 assert.equal((await parent(0,{action:'recover_story',story:copy})).status,409);
 fs.writeFileSync('config/story-recovery-test.local.json',JSON.stringify({storyId,title,words,creator:prior.creator,target:prior.target,missingRef}));
 console.log('PASS: actual source deletion -> complete missing-art snapshot -> protected server recovery -> exact mixed references/words -> idempotent replay and changed/deleted-copy conflicts; direct API and other-family denial.');
} finally {
 for(const s of sessions)await api('/auth/v1/logout?scope=local',s.access_token,{});
}
