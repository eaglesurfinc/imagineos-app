import assert from 'node:assert/strict';
import test from 'node:test';
import {createHandler, runtimeDependencies} from '../supabase/functions/parent-controls/handler.ts';
const parent={id:crypto.randomUUID(),email:'adult@example.invalid',sessionId:crypto.randomUUID()};
const grant='a'.repeat(64), path=`${crypto.randomUUID()}/${crypto.randomUUID()}`;
const summary={child_profiles:2,characters:1,versions:2,original_files:2,page_drafts:1,
  stories:1,provider_connections:0,deletion_pending:false,generation_enabled:false};
function request(body,token=grant,origin='https://imagineos-app.vercel.app') {
  return new Request('https://example.invalid/parent-controls',{method:'POST',
    headers:{origin,authorization:'Bearer fictional','content-type':'application/json',
      'x-imagineos-parent-grant':token},body:JSON.stringify(body)});
}
function fixture(overrides={}) {
  const calls=[];
  const deps={authenticate:async()=>parent,confirmPassword:async()=>true,
    manage:async(p,action,hash)=>{calls.push({p,action,hash});
      if(action==='overview')return summary;
      if(action==='unlock')return {expires_at:new Date(Date.now()+300000).toISOString()};
      if(action==='delete_batch')return [path];
      return true;},
    removeFiles:async(paths)=>calls.push({action:'files',paths}),
    removeAccount:async(p)=>calls.push({action:'account',p}),...overrides};
  return {calls,handler:createHandler(deps)};
}
test('unlock returns a random grant; only its hash reaches storage',async()=>{
  const {handler,calls}=fixture();
  const response=await handler(request({action:'unlock',password:'fictional'}));
  assert.equal(response.status,200);
  const {data}=await response.json();
  assert.match(data.grant,/^[0-9a-f]{64}$/);
  assert.notEqual(calls[1].hash,data.grant);
  assert.equal(calls[1].p.id,parent.id);
  assert.equal(response.headers.get('cache-control'),'no-store');
});
test('overview requires a valid unexpired current-session grant and whitelists safe counts',async()=>{
  const {handler}=fixture({manage:async()=>({...summary,secret:'never return me'})});
  assert.equal((await handler(request({action:'overview'},''))).status,403);
  const result=await handler(request({action:'overview'}));
  assert(!(await result.text()).includes('never return me'));
  const expired=fixture({manage:async()=>null});
  assert.equal((await expired.handler(request({action:'overview'}))).status,403);
});
test('account erasure requires exact scope confirmation, current password, and file cleanup first',async()=>{
  const {handler,calls}=fixture();
  const body={action:'start_delete',password:'fictional',confirmation:'DELETE MY FAMILY'};
  assert.equal((await handler(request({...body,confirmation:'delete'}))).status,422);
  assert.equal(calls.length,0);
  const result=await handler(request(body));
  assert.equal(result.status,200);
  assert.equal((await result.json()).data.deleted,true);
  assert.deepEqual(calls.map(c=>c.action),['overview','attempt','delete_begin','delete_batch','files','delete_ready','account']);
});
test('failed files never remove Auth; batches and interrupted cleanup can be continued',async()=>{
  const fail=fixture({removeFiles:async()=>{throw Error('sensitive');}});
  assert.equal((await fail.handler(request({action:'start_delete',password:'p',confirmation:'DELETE MY FAMILY'}))).status,503);
  assert(!fail.calls.some(c=>c.action==='account'));
  let ready=false;
  const {handler,calls}=fixture({manage:async(_p,action)=>{
    if(action==='overview')return {...summary,deletion_pending:true};
    if(action==='delete_batch')return [path];
    if(action==='delete_ready')return ready;
    return true;
  }});
  assert.equal((await (await handler(request({action:'continue_delete'}))).json()).data.pending,true);
  assert(!calls.some(c=>c.action==='account'));
  ready=true;
  assert.equal((await (await handler(request({action:'continue_delete'}))).json()).data.deleted,true);
});
test('no deletion from auth failure, bad parent password, no pending request, bad origin or caller ownership',async()=>{
  for(const [overrides,expected] of [[{authenticate:async()=>null},401],
    [{confirmPassword:async()=>false},403]]){
    const {handler,calls}=fixture(overrides);
    assert.equal((await handler(request({action:'start_delete',password:'bad',confirmation:'DELETE MY FAMILY'}))).status,expected);
    assert(!calls.some(c=>c.action==='delete_begin'||c.action==='account'));
  }
  const {handler,calls}=fixture();
  assert.equal((await handler(request({action:'continue_delete'}))).status,409);
  assert.equal((await handler(request({action:'overview'},grant,'https://evil.example'))).status,403);
  assert.equal((await handler(request({action:'overview',family_id:crypto.randomUUID()}))).status,422);
  assert(!calls.some(c=>c.action==='account'));
});
test('runtime uses only server-side fixed Storage/Auth endpoints and hard deletion',async()=>{
  const calls=[];
  const deps=runtimeDependencies('https://example.invalid','public','private',async(url,init)=>{
    calls.push({url,init});return new Response('{}');});
  await deps.removeFiles([path]);await deps.removeAccount(parent);
  assert.equal(calls[0].url,'https://example.invalid/storage/v1/object/character-originals');
  assert.deepEqual(JSON.parse(calls[0].init.body),{prefixes:[path]});
  assert.equal(calls[1].url,`https://example.invalid/auth/v1/admin/users/${parent.id}`);
  assert.deepEqual(JSON.parse(calls[1].init.body),{should_soft_delete:false});
  assert(calls.every(c=>c.init.method==='DELETE'&&c.init.redirect==='error'));
});

test('child approval binds the confirmed parent grant and returns a single-use code, storing only its hash',async()=>{
  const calls=[];
  const {handler}=fixture({manageChildren:async(p,action,hash,data)=>{
    calls.push({p,action,hash,data});return{minutes:30,redeem_before:new Date().toISOString()};
  }});
  const response=await handler(request({action:'child_approve',child_id:parent.id,minutes:30}));
  assert.equal(response.status,200);const data=(await response.json()).data;
  assert.match(data.code,/^[a-f0-9]{32}$/);
  assert.equal(calls[0].p.id,parent.id);assert.equal(calls[0].action,'child_approve');
  assert.match(calls[0].hash,/^[a-f0-9]{64}$/);assert.match(calls[0].data.code_hash,/^[a-f0-9]{64}$/);
  assert(!JSON.stringify(calls).includes(data.code));
});
test('child management rejects missing unlocks, invalid durations and caller-owned scope overrides',async()=>{
  let calls=0;const {handler}=fixture({manageChildren:async()=>{calls++;return{};}});
  assert.equal((await handler(request({action:'child_list'},''))).status,403);
  for(const body of [{action:'child_approve',child_id:parent.id,minutes:0},
    {action:'child_approve',child_id:parent.id,minutes:481},
    {action:'child_list',family_id:parent.id},
    {action:'child_settings',child_id:parent.id,minutes:30,allow_export:true,blocked:'false'}])
    assert.equal((await handler(request(body))).status,422);
  assert.equal(calls,0);
});
