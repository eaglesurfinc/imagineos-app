import assert from 'node:assert/strict';
import test from 'node:test';
import {createHandler, runtimeDependencies, PrivacyError} from '../supabase/functions/parent-controls/handler.ts';
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

test('privacy and complete backup actions require parent auth and grant, with no caller family override',async()=>{
  const calls=[];
  const {handler}=fixture({privacy:async(p,action,hash,paused)=>{calls.push({p,action,hash,paused});return{pilot_enabled:false,consent_status:'not_configured'};}});
  for(const action of ['privacy_status','recovery_snapshot']){
    assert.equal((await handler(request({action},''))).status,403);
    assert.equal((await handler(request({action,family_id:parent.id}))).status,422);
    const r=await handler(request({action}));assert.equal(r.status,200);assert.equal((await r.json()).data.pilot_enabled,false);
  }
  assert.equal((await handler(request({action:'privacy_pause',paused:'yes'}))).status,422);
  assert.equal((await handler(request({action:'privacy_pause',paused:true}))).status,200);
  assert.equal(calls.length,3);assert.notEqual(calls[0].hash,grant);assert.equal(calls[2].paused,true);
  const anonymous=fixture({authenticate:async()=>null,privacy:async()=>{throw Error('must not run');}});
  assert.equal((await anonymous.handler(request({action:'recovery_snapshot'}))).status,401);
});
test('backup size and expired-grant errors are actionable without leaking private content',async()=>{
  for(const [status,code] of [[413,'BACKUP_TOO_LARGE'],[403,'PARENT_LOCKED']]){
    const {handler}=fixture({privacy:async()=>{throw new PrivacyError(status,code);}});
    const r=await handler(request({action:'recovery_snapshot'}));assert.equal(r.status,status);assert.equal((await r.json()).code,code);
  }
  const {handler}=fixture({privacy:async()=>{throw Error('fictional sensitive upstream words');}});
  const r=await handler(request({action:'recovery_snapshot'}));assert.equal(r.status,503);assert(!(await r.text()).includes('sensitive'));
});

test('story-copy recovery requires the authenticated parent and unlock hash, never caller ownership',async()=>{
  const calls=[],events=[],story={id:crypto.randomUUID(),child_id:crypto.randomUUID(),panels:[]};
  const {handler}=fixture({log:line=>events.push(line),recoverStory:async(p,hash,value)=>{
    calls.push({p,hash,value});return{revision:1};}});
  assert.equal((await handler(request({action:'recover_story',story},''))).status,403);
  assert.equal((await handler(request({action:'recover_story',story,family_id:parent.id}))).status,422);
  assert.equal((await handler(request({action:'recover_story',story:[]}))).status,422);
  const result=await handler(request({action:'recover_story',story}));assert.equal(result.status,200);
  assert.equal((await result.json()).data.revision,1);assert.equal(calls.length,1);
  assert.equal(calls[0].p,parent);assert.notEqual(calls[0].hash,grant);assert.deepEqual(calls[0].value,story);
  assert(!events.join('').includes(story.id));assert(!events.join('').includes(story.child_id));
  const anonymous=fixture({authenticate:async()=>null,recoverStory:async()=>{throw Error('must not run');}});
  assert.equal((await anonymous.handler(request({action:'recover_story',story}))).status,401);
});

test('recovery runtime uses a fixed service-only RPC, maps conflicts and redacts upstream errors',async()=>{
  for(const [code,status,resultCode] of [['42501',403,'PARENT_LOCKED'],['P0002',409,'RECOVERY_CONFLICT'],
      ['23505',409,'RECOVERY_CONFLICT'],['22023',422,'INVALID_REQUEST'],['22P02',422,'INVALID_REQUEST']]){
    const deps=runtimeDependencies('https://example.invalid','public','server-secret',async(url,init)=>{
      assert.equal(url,'https://example.invalid/rest/v1/rpc/recover_story_copy');assert.equal(init.redirect,'error');
      const body=JSON.parse(init.body);assert.equal(body.p_parent,parent.id);assert.equal(body.p_session,parent.sessionId);
      assert.equal(init.headers.authorization,'Bearer server-secret');
      return new Response(JSON.stringify({code,message:'private upstream story words'}),{status:400});
    });
    await assert.rejects(deps.recoverStory(parent,'f'.repeat(64),{title:'exact child title'}),error=>{
      assert(error instanceof PrivacyError);assert.equal(error.status,status);assert.equal(error.code,resultCode);
      assert(!error.message.includes('private'));return true;
    });
  }
});
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
