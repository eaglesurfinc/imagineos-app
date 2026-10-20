// Hosted development only. Fictional adult-created art; no AI/provider calls.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const config=JSON.parse(fs.readFileSync('config/supabase.local.json','utf8'));
const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json','utf8'));
const fixture=JSON.parse(fs.readFileSync('config/stage5-fixture.local.json','utf8'));
assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');
assert(accounts.every(a=>a.email.endsWith('@example.invalid')));
async function api(path,token,body,method=body?'POST':'GET') {
 const response=await fetch(config.SUPABASE_URL+path,{method,
  headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'content-type':'application/json',Prefer:'return=representation',...(token?{authorization:`Bearer ${token}`}:{})},
  body:body?JSON.stringify(body):undefined});
 const text=await response.text(); return {status:response.status,data:text?JSON.parse(text):null};
}
const sessions=[];
try {
 for(const account of accounts){const response=await api('/auth/v1/token?grant_type=password',null,{email:account.email,password:account.password});assert.equal(response.status,200);sessions.push(response.data);}
 const [a,b]=sessions.map(s=>s.access_token),id=randomUUID();
 const words='  MY exact “words” 🌈\n\n<script>Keep this, too</script>\nمرحبا  ';
 const ref=v=>({character_id:v.character_id,version_id:v.version_id,asset_id:v.request_id,sha256:v.sha256});
 const panel=(v)=>({id:randomUUID(),reference:ref(v),scene:'  Walking.\n ',dialogue:words,narration:'\n End.  '});
 const input={p_id:id,p_child_id:fixture.first.child_profile_id,p_revision:0,p_title:'  My  title\n',p_format:'comic',p_panels:[panel(fixture.first),panel(fixture.first),panel(fixture.latest)]};
 const save=data=>api('/rest/v1/rpc/save_story_project',a,data);
 let response=await save(input);assert.equal(response.status,200,JSON.stringify(response.data));assert.equal(response.data,1);
 assert.equal((await save(input)).data,1);
 const read=()=>api(`/rest/v1/story_project_snapshots?id=eq.${id}`,a);
 let story=(await read()).data[0];
 assert.equal(story.title,input.p_title);assert.equal(story.panels.length,3);
 assert.equal(story.panels[0].dialogue,words);assert.equal(story.panels[0].reference.version_id,fixture.first.version_id);
 const reordered={...input,p_revision:1,p_format:'strip',p_panels:[...input.p_panels].reverse()};
 assert.equal((await save(reordered)).data,2);assert.equal((await save(reordered)).data,2);
 story=(await read()).data[0];assert.deepEqual(story.panels.map(p=>p.id),reordered.p_panels.map(p=>p.id));
 assert(story.panels.every(p=>p.dialogue===words&&p.scene==='  Walking.\n '&&p.narration==='\n End.  '));
 assert.equal((await save({...input,p_revision:1,p_title:'Stale overwrite'})).status,400);
 assert.equal((await read()).data[0].title,input.p_title);
 assert.deepEqual((await api(`/rest/v1/story_project_snapshots?id=eq.${id}`,b)).data,[]);
 assert.deepEqual((await api(`/rest/v1/story_panels?story_id=eq.${id}`,b)).data,[]);
 assert.equal((await api('/rest/v1/rpc/save_story_project',b,input)).status,403);
 assert([401,403].includes((await api('/rest/v1/story_project_snapshots',null)).status));
 assert.equal((await api('/rest/v1/rpc/save_story_project',null,input)).status,401);
 assert.equal((await api(`/rest/v1/story_projects?id=eq.${id}`,a,{title:'bypass'},'PATCH')).status,403);
 assert.equal((await api(`/rest/v1/story_panels?story_id=eq.${id}`,a,{},'DELETE')).status,403);
 assert.equal((await save({...input,p_id:randomUUID()})).status,403,'Panel IDs cannot move to another story');
 const foreign=(await api('/rest/v1/original_uploads?state=eq.ready',b)).data[0];
 assert(foreign);
 assert.equal((await save({...input,p_id:randomUUID(),p_panels:[panel(foreign)]})).status,403);
 assert.equal((await save({...input,p_id:randomUUID(),p_child_id:foreign.child_profile_id,p_panels:[]})).status,403);
 const retarget={...reordered,p_revision:2,p_panels:reordered.p_panels.map((p,i)=>i===1?{...p,reference:ref(fixture.latest)}:p)};
 assert.equal((await save(retarget)).status,403,'Existing panels cannot silently retarget a newer version');
 assert.equal((await save({...reordered,p_revision:2,p_panels:[reordered.p_panels[0],reordered.p_panels[0]]})).status,400);
 assert.equal((await save({...reordered,p_revision:2,p_panels:[{...reordered.p_panels[0],reference:{...ref(fixture.latest),character_id:null}}]})).status,400);
 assert.equal((await save({...reordered,p_revision:2,p_panels:[{...reordered.p_panels[0],family_id:fixture.first.family_id}]})).status,400);
 assert.equal((await save({...reordered,p_revision:2,p_panels:Array.from({length:25},()=>panel(fixture.first))})).status,400);
 assert.equal((await save({...reordered,p_revision:2,p_title:'x'.repeat(161)})).status,400);
 const remove={...reordered,p_revision:2,p_panels:reordered.p_panels.slice(1)};
 assert.equal((await save(remove)).data,3);
 assert.equal((await read()).data[0].panels.length,2);
 // A distinct disposable story verifies deletion without affecting browser fixtures.
 const disposable={...input,p_id:randomUUID(),p_panels:[panel(fixture.latest)]};
 assert.equal((await save(disposable)).data,1);
 assert.equal((await api('/rest/v1/rpc/delete_story_project',b,{p_id:disposable.p_id,p_revision:1})).status,403);
 assert.equal((await api('/rest/v1/rpc/delete_story_project',a,{p_id:disposable.p_id,p_revision:0})).status,400);
 assert.equal((await api('/rest/v1/rpc/delete_story_project',a,{p_id:disposable.p_id,p_revision:1})).status,204);
 assert.equal((await api('/rest/v1/rpc/delete_story_project',a,{p_id:disposable.p_id,p_revision:1})).status,204);
 assert.equal((await save(disposable)).status,400,'A lost create retry cannot resurrect a deleted story');
 assert.deepEqual((await api(`/rest/v1/story_project_snapshots?id=eq.${disposable.p_id}`,a)).data,[]);
 // Revoking the Auth session must stop sensitive writes even with an unexpired JWT.
 assert.equal((await api('/auth/v1/logout?scope=local',b,{})).status,204);
 assert.equal((await api('/rest/v1/rpc/save_story_project',b,{...input,p_id:randomUUID(),p_child_id:foreign.child_profile_id,p_panels:[]})).status,403);
 fs.writeFileSync('config/story-project-test.local.json',JSON.stringify({id,words,revision:3}));
 console.log('PASS: exact words/title/scene, comic/strip reorder, pinned reusable versions, save replay/conflicts, family/anonymous/direct-write/session denial, input bounds, confirmed deletion and resurrection protection. Zero provider calls.');
} finally {for(const session of sessions)await api('/auth/v1/logout?scope=local',session.access_token,{},'POST');}
