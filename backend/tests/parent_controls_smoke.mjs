// Fictional adult fixtures only; --delete removes fixture B, never a real family.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const config=JSON.parse(fs.readFileSync('config/supabase.local.json','utf8'));
const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json','utf8'));
assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');
assert.equal(accounts.length,2);
assert(accounts.every(a=>a.email.endsWith('@example.invalid')&&/^[0-9a-f-]{36}$/.test(a.id)));
async function api(path,token,body,method=body?'POST':'GET',grant) {
  const response=await fetch(config.SUPABASE_URL+path,{method,
    headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'content-type':'application/json',
      ...(token?{authorization:`Bearer ${token}`} : {}),...(grant?{'x-imagineos-parent-grant':grant}:{}),
      Origin:'http://127.0.0.1:8766'},body:body?JSON.stringify(body):undefined});
  const raw=await response.text();return{status:response.status,data:raw?JSON.parse(raw):null};
}
const call=(token,body,grant)=>api('/functions/v1/parent-controls',token,body,'POST',grant);
const sessions=[];
try {
  for(const account of accounts){const result=await api('/auth/v1/token?grant_type=password',null,
    {email:account.email,password:account.password});assert.equal(result.status,200);sessions.push(result.data);}
  const [a,b]=sessions.map(s=>s.access_token);
  const beforeA=(await api('/rest/v1/original_uploads?select=request_id,sha256&order=request_id',a)).data;
  assert.equal((await call(a,{action:'overview'})).status,403);
  assert.equal((await call(a,{action:'unlock',password:'wrong-fictional-password'})).status,403);
  const unlock=await call(a,{action:'unlock',password:accounts[0].password});assert.equal(unlock.status,200);
  const grant=unlock.data.data.grant;assert.match(grant,/^[0-9a-f]{64}$/);
  const overview=await call(a,{action:'overview'},grant);assert.equal(overview.status,200);
  assert.equal(overview.data.data.versions,2);assert.equal(overview.data.data.original_files,2);
  assert.equal(overview.data.data.generation_enabled,false);
  assert.equal((await call(b,{action:'overview'},grant)).status,403,'Another family used the grant');
  assert.equal((await call(a,{action:'start_delete',password:accounts[0].password,confirmation:'DELETE'} ,grant)).status,422);
  const direct=await api('/rest/v1/rpc/parent_controls',a,{p_parent_id:accounts[0].id,
    p_session_id:sessions[0].session_id??crypto.randomUUID(),p_action:'unlock',p_token_hash:'a'.repeat(64)});
  assert([401,403,404].includes(direct.status),'Browser called service-only parent RPC');
  assert.equal((await call(a,{action:'lock'},grant)).status,200);
  assert.equal((await call(a,{action:'overview'},grant)).status,403);
  const again=await call(a,{action:'unlock',password:accounts[0].password});assert.equal(again.status,200);
  await api('/auth/v1/logout?scope=local',a,{});
  assert.notEqual((await call(a,{action:'overview'},again.data.data.grant)).status,200,'Revoked session retained parent access');
  if(process.argv.includes('--delete')) {
    const originals=(await api('/rest/v1/original_uploads?select=*',b)).data;
    assert.equal(originals.length,1);
    const original=originals[0], storyId=crypto.randomUUID();
    const saved=await api('/rest/v1/rpc/save_story_project',b,{p_id:storyId,p_child_id:original.child_profile_id,
      p_revision:0,p_title:'Fictional family deletion test',p_format:'comic',p_panels:[{id:crypto.randomUUID(),
        reference:{character_id:original.character_id,version_id:original.version_id,
          asset_id:original.request_id,sha256:original.sha256},scene:'My scene',dialogue:'My exact words',narration:''}]});
    assert.equal(saved.status,200);
    const second=await api('/auth/v1/token?grant_type=password',null,{email:accounts[1].email,password:accounts[1].password});
    assert.equal(second.status,200);sessions.push(second.data);
    const fresh=await call(b,{action:'unlock',password:accounts[1].password});assert.equal(fresh.status,200);
    const token=fresh.data.data.grant;
    assert.equal((await call(b,{action:'start_delete',password:'wrong',confirmation:'DELETE MY FAMILY'},token)).status,403);
    const removed=await call(b,{action:'start_delete',password:accounts[1].password,confirmation:'DELETE MY FAMILY'},token);
    assert.equal(removed.status,200,'Whole-family deletion failed');assert.equal(removed.data.data.deleted,true);
    assert.notEqual((await call(second.data.access_token,{action:'overview'},token)).status,200);
    const oldRows=await api('/rest/v1/story_project_snapshots',second.data.access_token);
    assert(oldRows.status!==200||oldRows.data.length===0,'Old token read deleted family stories');
    assert.notEqual((await api('/storage/v1/object/authenticated/character-originals/'+original.object_path,
      second.data.access_token)).status,200);
    assert.notEqual((await api('/auth/v1/token?grant_type=password',null,
      {email:accounts[1].email,password:accounts[1].password})).status,200);
    // Independent family A remains byte-identical and can still sign in.
    const retained=await api('/auth/v1/token?grant_type=password',null,{email:accounts[0].email,password:accounts[0].password});
    assert.equal(retained.status,200);sessions.push(retained.data);
    assert.deepEqual((await api('/rest/v1/original_uploads?select=request_id,sha256&order=request_id',retained.data.access_token)).data,beforeA);
  }
  console.log('PASS: hosted parent password/grant, lock, current-session revocation, cross-family/direct-RPC denial'+
    (process.argv.includes('--delete')?', Storage-first whole-family/account/session deletion and other-family preservation.':'.'));
} finally {
  for(const session of sessions)await api('/auth/v1/logout?scope=local',session.access_token,{});
}
