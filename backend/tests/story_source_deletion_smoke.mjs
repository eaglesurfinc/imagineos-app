// Run after story browser checks. Deletes only the fictional older source.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const config=JSON.parse(fs.readFileSync('config/supabase.local.json','utf8'));
const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json','utf8'));
const fixture=JSON.parse(fs.readFileSync('config/stage5-fixture.local.json','utf8'));
assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');
assert(accounts.every(a=>a.email.endsWith('@example.invalid')));
async function api(path,token,body,method=body?'POST':'GET') {
 const response=await fetch(config.SUPABASE_URL+path,{method,
  headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},
  body:body?JSON.stringify(body):undefined});
 const text=await response.text();return{status:response.status,data:text?JSON.parse(text):null};
}
const session=await api('/auth/v1/token?grant_type=password',null,{email:accounts[0].email,password:accounts[0].password});
assert.equal(session.status,200);const token=session.data.access_token;
try {
 const before=(await api('/rest/v1/story_project_snapshots?order=id',token)).data;
 assert(before.some(s=>s.panels.some(p=>p.reference.asset_id===fixture.first.request_id)));
 const params={p_character_id:fixture.first.character_id,p_version_id:fixture.first.version_id};
 const begin=await api('/rest/v1/rpc/begin_character_deletion',token,params);
 assert.equal(begin.status,200);assert.deepEqual(begin.data,[fixture.first.object_path]);
 assert.equal((await api('/storage/v1/object/character-originals',token,{prefixes:begin.data},'DELETE')).status,200);
 const finish=await api('/rest/v1/rpc/finish_character_deletion',token,params);
 assert([200,204].includes(finish.status));
 const after=(await api('/rest/v1/story_project_snapshots?order=id',token)).data;
 const withoutFlags=rows=>rows.map(s=>({...s,panels:s.panels.map(({source_available,...p})=>p)}));
 assert.deepEqual(withoutFlags(after),withoutFlags(before),'Original deletion cannot remove story words, order or historical references');
 for(const s of after)for(const p of s.panels)if(p.reference.asset_id===fixture.first.request_id)assert.equal(p.source_available,false);
 const story=after.find(s=>s.panels.some(p=>!p.source_available));
 const payload={p_id:story.id,p_child_id:story.child_id,p_revision:story.revision,p_title:story.title,p_format:story.format,
  p_panels:story.panels.map(p=>({id:p.id,reference:p.reference,scene:p.scene,dialogue:p.dialogue,narration:p.narration}))};
 assert.equal((await api('/rest/v1/rpc/save_story_project',token,payload)).data,story.revision);
 payload.p_panels[0].narration+='\n  Only the creator edits this.  ';
 assert.equal((await api('/rest/v1/rpc/save_story_project',token,payload)).data,story.revision+1);
 console.log('PASS: deliberate fictional source deletion removes its Storage object while preserving every story word, reading order and pinned reference; missing artwork is explicit and remaining text can still be saved.');
} finally {await api('/auth/v1/logout?scope=local',token,{},'POST');}
