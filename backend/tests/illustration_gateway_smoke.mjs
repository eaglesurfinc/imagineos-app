// Real Auth/RLS checks on the approved development project, fictional accounts
// only. Always run the documented Storage/API and Auth cleanup afterward.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { fingerprint } from '../supabase/functions/illustration-gateway/handler.ts';

const config = JSON.parse(fs.readFileSync('config/supabase.local.json', 'utf8'));
assert.equal(config.SUPABASE_URL, 'https://hgsivbqmbcliqbstrkdz.supabase.co');
const accounts = JSON.parse(fs.readFileSync('config/auth-test.local.json', 'utf8'));
assert(accounts.length === 2 && accounts.every(a => a.email.endsWith('@example.invalid')));
const sessions = [];
async function api(path, token, method = 'GET', body, extra = {}) {
  const response = await fetch(config.SUPABASE_URL + path, {
    method, headers: { apikey: config.SUPABASE_PUBLISHABLE_KEY,
      ...(token ? { Authorization: `Bearer ${token}` } : {}), 'Content-Type': 'application/json',
      Prefer: 'return=representation', ...extra },
    body: body === undefined ? undefined : body instanceof Buffer ? body : JSON.stringify(body),
  });
  const text = await response.text();
  let data; try { data = JSON.parse(text); } catch { data = null; }
  return { status: response.status, data, headers: response.headers };
}
function ok(result, status = 200) { assert(status === 200 && result.status === 204 || result.status === status, 'Unexpected API status: ' + result.status + ' ' + JSON.stringify(result.data)); return result.data; }
const original = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGNw09iCFTEMLQkAOOxIgSesf3AAAAAASUVORK5CYII=', 'base64');
const sha256 = createHash('sha256').update(original).digest('hex');
try {
  for (const account of accounts) sessions.push(ok(await api('/auth/v1/token?grant_type=password', null, 'POST', account)));
  const [a,b] = sessions.map(s => s.access_token), children = [];
  for (const token of [a,b]) {
    const family = ok(await api('/rest/v1/families?select=id', token))[0];
    children.push(ok(await api('/rest/v1/child_profiles', token, 'POST', { family_id: family.id, nickname: 'Fictional story creator' }), 201)[0]);
  }
  async function save(token, child, character = null, name = 'Story fixture friend') {
    const id = randomUUID();
    const row = ok(await api('/rest/v1/rpc/reserve_original', token, 'POST', {
      p_request_id: id, p_child_id: child, p_character_id: character, p_name: name,
      p_mime_type: 'image/png', p_byte_size: original.length, p_sha256: sha256,
    }));
    ok(await api('/storage/v1/object/character-originals/' + row.object_path, token, 'POST', original, { 'Content-Type': 'image/png', 'x-upsert': 'false' }));
    ok(await api('/rest/v1/rpc/finish_original', token, 'POST', { p_request_id: id }));
    return { ...row, sha256, state: 'ready' };
  }
  const first = await save(a, children[0].id);
  const latest = await save(a, children[0].id, first.character_id, 'Story fixture version two');
  const foreign = await save(b, children[1].id);
  const body = row => ({ contract_version: 1, request_id: randomUUID(), trace_id: randomUUID(), page_id: randomUUID(),
    character: { character_id: row.character_id, version_id: row.version_id, asset_id: row.request_id, sha256 },
    scene_direction: '  A fictional pencil friend jumps over the moon.\n  ', layout: 'portrait' });
  const call = (token, data, headers = {}) => api('/functions/v1/illustration-gateway', token, 'POST', data, { Origin: 'http://127.0.0.1:8766', ...headers });
  const request = body(first);
  const data = ok(await call(a, request));
  assert.equal(data.status, 'disabled'); assert.equal(data.code, 'GENERATION_DISABLED');
  assert.equal(data.request_id, request.request_id); assert.equal(data.trace_id, request.trace_id);
  assert.equal(data.fingerprint, await fingerprint(request)); assert.equal(data.output, null);
  assert.equal(data.cost_micros, 0); assert.equal(data.provider_attempts, 0); assert.equal(data.retryable, false);
  assert.deepEqual(ok(await call(a, request)), data, 'Identical disabled replay changed');
  assert.equal(ok(await call(a, body(latest))).status, 'disabled');
  assert.equal((await call(b, request)).status, 404);
  assert.equal((await call(a, body(foreign))).status, 404);
  const wrongHash = body(first); wrongHash.character.sha256 = 'b'.repeat(64);
  assert.equal((await call(a, wrongHash)).status, 404);
  const wrongLink = body(first); wrongLink.character.version_id = foreign.version_id;
  assert.equal((await call(a, wrongLink)).status, 404);
  assert.equal((await call(null, request)).status, 401);
  assert.equal((await call(a, { ...request, dialogue: 'Must never leave the page draft' })).status, 422);
  assert.equal((await call(a, { ...request, enabled: true })).status, 422);
  assert.equal((await call(a, request, { Origin: 'https://foreign.invalid' })).status, 403);
  const preflight = await api('/functions/v1/illustration-gateway', null, 'OPTIONS', undefined, { Origin: 'http://127.0.0.1:8766', 'Access-Control-Request-Headers': 'authorization,apikey,content-type' });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), 'http://127.0.0.1:8766');
  fs.writeFileSync('config/stage5-fixture.local.json', JSON.stringify({ first, latest }));
  console.log('PASS: hosted disabled checks, replay/hash/correlation, pinned old/new versions, two-family isolation, bad references/overrides, no-session rejection and CORS. Zero provider attempts/cost.');
} finally {
  for (const session of sessions) await api('/auth/v1/logout?scope=local', session.access_token, 'POST');
}
