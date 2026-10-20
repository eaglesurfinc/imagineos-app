import test from 'node:test';
import assert from 'node:assert/strict';
import {createHandler,ChildDenied} from '../supabase/functions/child-access/handler.ts';
import {digest} from '../supabase/functions/_shared/http.ts';
const secret='b'.repeat(64),code='c'.repeat(32),id=crypto.randomUUID();
const req=(body,token=secret,origin='https://imagineos-app.vercel.app')=>new Request('https://example.invalid',{method:'POST',
 headers:{'content-type':'application/json','x-imagineos-child-session':token,origin},body:JSON.stringify(body)});
function fixture(overrides={}){const calls=[];return{calls,handler:createHandler({
 rpc:async(action,hash,data)=>{calls.push({action,hash,data});return{child_id:id,ai_enabled:false};},
 download:async()=>new Uint8Array(),upload:async()=>{},...overrides})};}
test('login accepts only a fresh approval/request/secret shape; only hashes reach SQL',async()=>{
 const {handler,calls}=fixture();const result=await handler(req({action:'login',code,request_id:id,secret},''));
 assert.equal(result.status,200);assert.equal(result.headers.get('cache-control'),'no-store');
 assert.equal(calls[0].hash,await digest(secret));assert.equal(calls[0].data.code_hash,await digest(code));
 assert(!JSON.stringify(calls).includes(secret));assert(!JSON.stringify(calls).includes(code));
});
test('a parent JWT alone, unknown actions and caller family/provider overrides never authorize children',async()=>{
 const {handler,calls}=fixture();
 assert.equal((await handler(req({action:'library'},''))).status,401);
 for(const body of [{action:'delete_character',id},{action:'child_approve',child_id:id},
   {action:'library',family_id:id},{action:'library',provider:'openai'},
   {action:'login',code,request_id:id,secret,minutes:480},
   {action:'download',asset_id:'../../foreign-object'}])assert.equal((await handler(req(body))).status,422);
 assert.equal(calls.length,0);
});
test('expired, used, revoked or blocked approvals are denied without secrets or upstream detail',async()=>{
 const {handler}=fixture({rpc:async()=>{throw new ChildDenied(secret);}});
 const result=await handler(req({action:'status'}));assert.equal(result.status,401);
 const raw=await result.text();assert(!raw.includes(secret));assert(raw.includes('CHILD_APPROVAL_REQUIRED'));
});
test('file delivery rechecks approval after reading bytes; expired files never reach the client',async()=>{
 const bytes=Uint8Array.from([137,80,78,71,13,10,26,10]),asset={path:`${id}/${id}`,mime_type:'image/png',
  sha256:await digest(bytes),byte_size:bytes.length,state:'ready'};
 const {handler,calls}=fixture({rpc:async(action)=>{calls.push(action);if(action==='status')throw new ChildDenied();return asset;},
  download:async()=>bytes});
 const result=await handler(req({action:'download',asset_id:id}));assert.equal(result.status,401);
 assert.deepEqual(calls,['asset','status']);
});
test('bad image bytes cannot be published; uploads never accept caller paths',async()=>{
 let uploads=0;
 const {handler}=fixture({rpc:async()=>({path:`${id}/${id}`,mime_type:'image/png',
  sha256:await digest(new Uint8Array([1,2,3])),byte_size:3,state:'pending'}),upload:async()=>{uploads++;}});
 assert.equal((await handler(req({action:'upload',asset_id:id,bytes:'AQID'}))).status,422);
 assert.equal((await handler(req({action:'upload',asset_id:id,bytes:'AQID',path:'foreign'}))).status,422);
 assert.equal(uploads,0);
});
test('foreign origins and oversized bodies fail before touching storage or SQL',async()=>{
 const {handler,calls}=fixture();assert.equal((await handler(req({action:'library'},secret,'https://evil.example'))).status,403);
 assert.equal((await handler(req({action:'upload',asset_id:id,bytes:'a'.repeat(8*1024*1024)}))).status,422);
 assert.equal(calls.length,0);
});
