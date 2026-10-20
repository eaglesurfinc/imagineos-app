// Dedicated development target; fictional adult accounts only. No AI calls.
// Run prepare_auth_fixtures.py and apply its create SQL first. After this test,
// verify encrypted SQL storage independently, then clean up fixture accounts.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const config=JSON.parse(fs.readFileSync('config/supabase.local.json','utf8'));
const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json','utf8'));
assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');
assert(accounts.every(a=>a.email.endsWith('@example.invalid')));
const sessions=[];
async function call(path,token,body) {
  const result=await fetch(config.SUPABASE_URL+path,{method:body?'POST':'GET',
    headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'content-type':'application/json',
      ...(token?{authorization:`Bearer ${token}`}:{})},body:body?JSON.stringify(body):undefined});
  const text=await result.text();return {status:result.status,data:text?JSON.parse(text):null};
}
try {
  for(const a of accounts){
    const result=await call('/auth/v1/token?grant_type=password',null,{email:a.email,password:a.password});
    assert.equal(result.status,200);sessions.push(result.data);
  }
  const [a,b]=sessions.map(s=>s.access_token);
  for(const token of [a,b]) {
    const list=await call('/functions/v1/parent-providers',token,{action:'list'});
    assert.equal(list.status,200);
    assert.deepEqual(list.data.data.connections,[]);
    assert.equal(list.data.data.providers.length,3);
    assert.equal(list.data.data.generation_enabled,false);
  }
  const noAuth=await call('/functions/v1/parent-providers',null,{action:'list'});
  assert([401,403].includes(noAuth.status));
  const forged=await call('/functions/v1/parent-providers',a,{action:'list',parent_id:accounts[1].id});
  assert.equal(forged.status,422);
  const denied=await call('/rest/v1/rpc/manage_parent_provider',a,{
    p_parent_id:accounts[1].id,p_session_id:crypto.randomUUID(),p_action:'list'});
  assert([401,403,404].includes(denied.status));
  const wrongPassword=await call('/functions/v1/parent-providers',a,{
    action:'disconnect',provider:'openai',password:'intentionally-wrong'});
  assert.equal(wrongPassword.status,403);
  assert.equal(wrongPassword.data.code,'PARENT_CONFIRMATION_REQUIRED');
  const disconnect=await call('/functions/v1/parent-providers',a,{
    action:'disconnect',provider:'openai',password:accounts[0].password});
  assert.equal(disconnect.status,200);
  // SQL verification uses only fixture identity/session IDs, never provider keys.
  const ids=sessions.map(s=>({id:s.user.id,sessionId:JSON.parse(Buffer.from(s.access_token.split('.')[1],'base64url')).session_id}));
  fs.writeFileSync('config/provider-test.local.json',JSON.stringify(ids));
  console.log('PASS: hosted catalog, no live generation, anonymous/caller ownership/RPC denial, password confirmation and disconnect. No AI provider call.');
} catch(error) {
  // Do not dump request bodies, passwords or Auth response objects.
  console.error(error.message);process.exitCode=1;
} finally {
  // Keep sessions for the follow-up SQL ownership/encryption/revocation checks.
  // Fixture cleanup cascades sessions and credentials after those checks.
}
