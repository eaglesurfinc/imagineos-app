import assert from 'node:assert/strict';
import test from 'node:test';
import { createHandler, providers, runtimeDependencies } from '../supabase/functions/parent-providers/handler.ts';

const parent = { id: crypto.randomUUID(), email: 'adult@example.invalid', sessionId: crypto.randomUUID() };
const fakeKey = 'sk-fictional-test-key-not-a-real-provider-credential';
const req = (body, origin = 'http://localhost:8766') => new Request('https://example.invalid', {
  method: 'POST', headers: { origin, authorization: 'Bearer fictional', 'content-type': 'application/json' },
  body: JSON.stringify(body),
});
function fixture(overrides = {}) {
  const calls = [];
  const deps = {
    authenticate: async () => parent,
    manage: async (_parent, action, provider, secret) => {
      calls.push({ action, provider, secret });
      return action === 'list' ? [] : true;
    },
    confirmPassword: async () => true,
    verifyKey: async () => true,
    ...overrides,
  };
  return { calls, handler: createHandler(deps) };
}
test('three providers accurately expose capabilities and no fake login or live generation', async () => {
  assert.deepEqual(providers.map(p => p.id), ['openai', 'claude', 'gemini']);
  assert(providers.every(p => p.login_available === false));
  assert.equal(providers.find(p => p.id === 'claude').image_generation, false);
  const {handler} = fixture({manage: async () => [{provider:'openai',connected_at:'2026-10-19',secret:'DO NOT RETURN'}]});
  const result = await handler(req({action:'list'}));
  const text = await result.text();
  assert(!text.includes('DO NOT RETURN'));
  assert.equal(JSON.parse(text).data.generation_enabled, false);
  assert.equal(result.headers.get('cache-control'), 'no-store');
});
test('connect confirms the parent before checking a key; failed key leaves prior connection', async () => {
  let confirmed = false;
  const {calls,handler} = fixture({confirmPassword:async()=>{confirmed=true;return true;},
    verifyKey:async()=>{assert(confirmed);return false;}});
  const result = await handler(req({action:'connect',provider:'openai',api_key:fakeKey,password:'fictional-password'}));
  assert.equal(result.status,422);
  assert.equal((await result.json()).code,'PROVIDER_CREDENTIAL_REJECTED');
  assert.deepEqual(calls.map(c=>c.action),['attempt']);
});
test('save and disconnect are owner-bound, password confirmed, and never return a key', async () => {
  const {calls,handler}=fixture();
  const result=await handler(req({action:'connect',provider:'openai',api_key:fakeKey,password:'fictional-password'}));
  assert.equal(result.status,200);
  assert(!(await result.text()).includes(fakeKey));
  assert.deepEqual(calls.map(c=>c.action),['attempt','save']);
  assert.equal(calls[1].secret,fakeKey);
  assert.equal((await handler(req({action:'disconnect',provider:'openai',password:'fictional-password'}))).status,200);
  assert.equal(calls.at(-1).action,'disconnect');
});
test('unauthenticated, unconfirmed, rate-limited and foreign-origin operations cannot save', async () => {
  for(const [override,status] of [
    [{authenticate:async()=>null},401], [{confirmPassword:async()=>false},403],
    [{manage:async()=>false},429],
  ]) {
    const {calls,handler}=fixture(override);
    assert.equal((await handler(req({action:'connect',provider:'openai',api_key:fakeKey,password:'bad'}))).status,status);
    assert(!calls.some(c=>c.action==='save'));
  }
  const {calls,handler}=fixture();
  assert.equal((await handler(req({action:'list'},'https://evil.example'))).status,403);
  assert.equal(calls.length,0);
});
test('rejects caller ownership, billing, endpoint overrides, bad keys and oversized bodies',async()=>{
  const {calls,handler}=fixture();
  for(const invalid of [
    {action:'list',parent_id:parent.id}, {action:'list',family_id:crypto.randomUUID()},
    {action:'connect',provider:'openai',api_key:fakeKey,password:'p',endpoint:'https://evil.example'},
    {action:'connect',provider:'openai',api_key:'sk-\nheader-injection-not-allowed',password:'p'},
    {action:'connect',provider:'unknown',api_key:fakeKey,password:'p'},
    {action:'connect',provider:'openai',api_key:fakeKey,password:'x'.repeat(9000)},
    {action:'oauth',provider:'openai'},
  ]) assert.equal((await handler(req(invalid))).status,422);
  assert.equal(calls.length,0);
});
test('provider failures redact credentials and all upstream errors',async()=>{
  const {handler}=fixture({verifyKey:async()=>{throw Error(fakeKey);}});
  const result=await handler(req({action:'connect',provider:'openai',api_key:fakeKey,password:'p'}));
  assert.equal(result.status,503);
  assert(!(await result.text()).includes(fakeKey));
});
test('runtime model discovery only calls fixed provider hosts, never generation or URL credentials',async()=>{
  const calls=[];
  const deps=runtimeDependencies('https://example.invalid','public','server',async(url,init)=>{
    calls.push({url,init});return new Response('{}');
  });
  for(const p of providers) assert(await deps.verifyKey(p.id,fakeKey));
  assert.deepEqual(calls.map(c=>new URL(c.url).hostname),[
    'api.openai.com','api.anthropic.com','generativelanguage.googleapis.com']);
  assert(calls.every(c=>new URL(c.url).pathname.endsWith('/models') && !c.init.body && c.init.redirect==='error'));
  assert(calls.every(c=>!c.url.includes(fakeKey)));
});
test('password confirmation verifies the current parent and revokes its temporary session',async()=>{
  const calls=[];
  const deps=runtimeDependencies('https://example.invalid','public','server',async(url,init)=>{
    calls.push({url,init});
    return url.includes('/token?') ? Response.json({access_token:'temporary',user:{id:parent.id}}) : new Response(null,{status:204});
  });
  assert(await deps.confirmPassword(parent,'fictional-password'));
  assert.equal(calls.length,2);
  assert(calls[1].url.endsWith('/logout?scope=local'));
  assert.equal(calls[1].init.headers.authorization,'Bearer temporary');
});
