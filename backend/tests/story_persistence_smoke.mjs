// Hosted family isolation and exact page-draft persistence. Fictional accounts
// and originals from illustration_gateway_smoke.mjs only; no provider calls.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const config=JSON.parse(fs.readFileSync('config/supabase.local.json','utf8'));
const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json','utf8'));
const fixture=JSON.parse(fs.readFileSync('config/stage5-fixture.local.json','utf8'));
assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');
assert(accounts.every(a=>a.email.endsWith('@example.invalid')));
async function api(path,token,body,method=body?'POST':'GET'){
 const response=await fetch(config.SUPABASE_URL+path,{method,
  headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'content-type':'application/json',Prefer:'return=representation',
   ...(token?{authorization:`Bearer ${token}`}:{})},body:body?JSON.stringify(body):undefined});
 const text=await response.text();return{status:response.status,data:text?JSON.parse(text):null};
}
const sessions=[];
try{
 for(const account of accounts){const result=await api('/auth/v1/token?grant_type=password',null,{email:account.email,password:account.password});assert.equal(result.status,200);sessions.push(result.data);}
 const [a,b]=sessions.map(s=>s.access_token),page=randomUUID();
 const words='  My  “exact words” 🌈\n\n<script>Keep this text</script>\nمرحبا  ';
 const input={p_page_id:page,p_source_id:fixture.first.request_id,p_revision:0,p_scene:'  Jump!\n',p_dialogue:words,p_narration:'\n  End.  '};
 assert.equal((await api('/rest/v1/rpc/save_story_draft',a,input)).data,1);
 assert.equal((await api('/rest/v1/rpc/save_story_draft',a,input)).data,1);
 const read=()=>api(`/rest/v1/saved_story_drafts?page_id=eq.${page}`,a);
 let rows=(await read()).data;
 assert.equal(rows.length,1);assert.equal(rows[0].dialogue,words);assert.equal(rows[0].narration,input.p_narration);
 assert.equal(rows[0].source_id,fixture.first.request_id);assert.equal(rows[0].version_id,fixture.first.version_id);
 assert.equal(rows[0].revision,1);
 const changed={...input,p_revision:1,p_dialogue:words+'\nNext line  '};
 assert.equal((await api('/rest/v1/rpc/save_story_draft',a,changed)).data,2);
 const conflict=await api('/rest/v1/rpc/save_story_draft',a,{...input,p_revision:1,p_dialogue:'Overwrite from stale device'});
 assert.equal(conflict.status,400);
 assert.equal((await read()).data[0].dialogue,changed.p_dialogue);
 assert.deepEqual((await api(`/rest/v1/saved_story_drafts?page_id=eq.${page}`,b)).data,[]);
 assert.equal((await api('/rest/v1/rpc/save_story_draft',b,input)).status,403);
 assert.equal((await api('/rest/v1/rpc/save_story_draft',a,{...changed,p_source_id:fixture.latest.request_id,p_revision:2})).status,403);
 assert([401,403].includes((await api('/rest/v1/story_page_drafts',null)).status));
 assert.equal((await api(`/rest/v1/story_page_drafts?page_id=eq.${page}`,a,{dialogue:'bypass'},'PATCH')).status,403);
 assert.equal((await read()).data[0].revision,2);
 console.log('PASS: exact whitespace/Unicode/text, durable original-version pin, idempotent retry, revision conflict, cross-family/anonymous denial and direct-write denial.');
} finally {for(const session of sessions)await api('/auth/v1/logout?scope=local',session.access_token,{},'POST');}
