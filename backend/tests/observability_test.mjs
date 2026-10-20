import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {requestLog} from '../supabase/functions/_shared/observability.ts';
import {digest} from '../supabase/functions/_shared/http.ts';
import {summarizeLogs} from '../scripts/summarize_logs.mjs';
import {createHandler as providers} from '../supabase/functions/parent-providers/handler.ts';
import {createHandler as parents} from '../supabase/functions/parent-controls/handler.ts';
import {createHandler as children} from '../supabase/functions/child-access/handler.ts';
import {createHandler as illustrations} from '../supabase/functions/illustration-gateway/handler.ts';

const trace = '01f7ecab-0408-4167-91bd-c4e7bbef9238';
test('request events whitelist metadata, emit once and bound untrusted values', () => {
  const lines = []; let time = 10;
  const log = requestLog('parent-controls', 'POST', {sink:line=>lines.push(line),clock:()=>time});
  time = 63; log(503,'PARENT_CONTROLS_UNAVAILABLE',trace); log(200,'OK',trace);
  assert.deepEqual(JSON.parse(lines[0]), {event:'imagineos.request',schema:1,function:'parent-controls',
    method:'POST',status:503,code:'PARENT_CONTROLS_UNAVAILABLE',trace_id:trace,duration_ms:53});
  assert.equal(lines.length,1);
  const poisoned = requestLog('fake private function name','private story', {sink:line=>lines.push(line),clock:()=>NaN});
  poisoned(900,'sk-fictional-private-key','fictional@example.invalid');
  const event = JSON.parse(lines[1]);
  assert.equal(event.function,'unknown'); assert.equal(event.code,'UNKNOWN'); assert.equal(event.method,'UNKNOWN');
  assert.equal(event.status,500); assert.equal(event.duration_ms,0);
  assert.match(event.trace_id,/^[a-f0-9-]{36}$/);
  assert(!lines.join('').includes('private')); assert(!lines.join('').includes('@'));
});

test('each public handler logs failures without request bodies, identities or upstream errors', async () => {
  const body = {action:'connect',provider:'openai',api_key:'sk-fictional-secret-that-must-never-appear',password:'fictional-password'};
  const parent = {id:crypto.randomUUID(),sessionId:crypto.randomUUID(),email:'adult@example.invalid'};
  const cases = [
    [providers, {authenticate:async()=>parent,manage:async()=>true,confirmPassword:async()=>true,
      verifyKey:async()=>{throw Error(JSON.stringify(body));}}, body,503],
    [parents, {authenticate:async()=>parent,manage:async()=>{throw Error('fictional-password');}}, {action:'unlock',password:body.password},503],
    [children, {rpc:async()=>{throw Error(JSON.stringify(body));}}, {action:'status'},503],
    [illustrations, {authenticate:async()=>{throw Error(JSON.stringify(body));}},
      JSON.parse(readFileSync(new URL('./fixtures/illustration_request.json',import.meta.url))),503],
  ];
  for (const [factory,deps,payload,status] of cases) {
    const events=[];
    const response=await factory({...deps,log:line=>events.push(line)})(new Request('https://example.invalid/private-name',{
      method:'POST',headers:{authorization:'Bearer private-session', 'content-type':'application/json',
        'x-imagineos-child-session':'f'.repeat(64),'x-imagineos-parent-grant':'a'.repeat(64)},body:JSON.stringify(payload)}));
    assert.equal(response.status,status); assert.equal(events.length,1);
    const event=JSON.parse(events[0]),result=await response.json();
    assert.equal(event.trace_id,result.trace_id); assert.equal(event.status,status);
    for (const secret of [body.api_key,body.password,parent.id,parent.email,'private-session','private-name',payload.scene_direction]) {
      if(secret) assert(!events[0].includes(secret));
    }
  }
});

test('preflights, authorization refusal and failing log sinks preserve response contracts', async () => {
  const events=[]; const handler=providers({log:line=>events.push(line)});
  assert.equal((await handler(new Request('https://example.invalid',{method:'OPTIONS'}))).status,204);
  assert.equal((await handler(new Request('https://example.invalid',{method:'POST'}))).status,401);
  assert.deepEqual(events.map(line=>JSON.parse(line).code),['PREFLIGHT','AUTH_REQUIRED']);
  const response=await parents({log:()=>{throw Error('unavailable telemetry');}})(new Request('https://example.invalid',{method:'POST'}));
  assert.equal(response.status,401); assert.equal((await response.json()).code,'AUTH_REQUIRED');
});

test('successful child file delivery logs only its result and preserves exact private bytes', async () => {
  const bytes=new TextEncoder().encode('fictional private artwork bytes'),id=crypto.randomUUID(),events=[];
  const asset={path:`${id}/${id}`,mime_type:'image/png',sha256:await digest(bytes),byte_size:bytes.length,state:'ready'};
  const handler=children({log:line=>events.push(line),rpc:async(action)=>action==='asset'?asset:true,download:async()=>bytes});
  const response=await handler(new Request('https://example.invalid',{method:'POST',
    headers:{'content-type':'application/json','x-imagineos-child-session':'b'.repeat(64)},
    body:JSON.stringify({action:'download',asset_id:id})}));
  assert.equal(response.status,200);assert.deepEqual(new Uint8Array(await response.arrayBuffer()),bytes);
  assert.equal(events.length,1);const event=JSON.parse(events[0]);assert.equal(event.code,'OK');
  assert.equal(event.trace_id,response.headers.get('x-trace-id'));
  for(const value of [id,asset.sha256,asset.path,new TextDecoder().decode(bytes)])assert(!events[0].includes(value));
});

test('log summaries aggregate only safe fields and never echo private or malformed input', async () => {
  const lines=[];
  for (const duration of [10,20,60]) requestLog('parent-controls','POST',{
    sink:line=>lines.push(line),clock:(()=>{let n=0;return()=>n++===0?0:duration;})()})(503,'PARENT_CONTROLS_UNAVAILABLE',trace);
  lines.push('private raw error',JSON.stringify({event:'imagineos.request',schema:1,function:'private text',status:500,code:'OK',duration_ms:5}));
  const report=await summarizeLogs(lines);
  assert.equal(report.accepted,3);assert.equal(report.ignored,2);
  assert.deepEqual(report.groups,[{function:'parent-controls',status:503,code:'PARENT_CONTROLS_UNAVAILABLE',count:3,max_ms:60,mean_ms:30}]);
  assert(!JSON.stringify(report).includes(trace));assert(!JSON.stringify(report).includes('private'));
});
