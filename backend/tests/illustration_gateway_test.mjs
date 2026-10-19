import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { createHandler, fingerprint, runtimeDependencies } from '../supabase/functions/illustration-gateway/handler.ts';

const fixture = JSON.parse(readFileSync(new URL('./fixtures/illustration_request.json', import.meta.url)));
const hash = readFileSync(new URL('./fixtures/illustration_fingerprint.txt', import.meta.url), 'utf8').trim();
const valid = () => structuredClone(fixture);
const request = (body = valid(), { method = 'POST', origin = 'http://localhost:8766', auth = 'Bearer fictional-token' } = {}) => new Request('https://example.invalid', {
  method, headers: { 'content-type': 'application/json', ...(origin ? { origin } : {}), ...(auth ? { authorization: auth } : {}) },
  ...(method === 'POST' ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}),
});

test('canonical hash matches the shared Dart fixture; correlation IDs do not change it', async () => {
  assert.equal(await fingerprint(fixture), hash);
  const replay = valid(); replay.request_id = crypto.randomUUID(); replay.trace_id = crypto.randomUUID();
  assert.equal(await fingerprint(replay), hash);
  replay.scene_direction += ' ';
  assert.notEqual(await fingerprint(replay), hash);
});

test('valid and repeated checks are disabled, zero-cost, and never call a provider', async () => {
  const calls = [];
  const handler = createHandler({
    authenticate: async (auth) => { calls.push(auth); return true; },
    ownsReadyReference: async (auth, body) => { assert.deepEqual(body, fixture); calls.push(auth); return true; },
  });
  const previous = globalThis.fetch;
  globalThis.fetch = () => { throw Error('No network/provider permitted in handler test'); };
  try {
    const first = await handler(request()), second = await handler(request());
    const data = await first.json();
    assert.equal(first.status, 200);
    assert.deepEqual(data, await second.json());
    assert.deepEqual(data, { contract_version: 1, request_id: fixture.request_id, trace_id: fixture.trace_id,
      fingerprint: hash, status: 'disabled', code: 'GENERATION_DISABLED', retryable: false,
      output: null, cost_micros: 0, provider_attempts: 0 });
    assert.equal(first.headers.get('cache-control'), 'no-store');
    assert.equal(first.headers.get('x-trace-id'), fixture.trace_id);
    assert.equal(calls.length, 4);
  } finally { globalThis.fetch = previous; }
});

test('rejects dialogue, narration, override flags, unknown versions and malformed/oversized bodies', async () => {
  let authCalls = 0;
  const handler = createHandler({ authenticate: async () => { authCalls++; return true; }, ownsReadyReference: async () => true });
  for (const bad of [
    { ...valid(), dialogue: 'Do not rewrite me' }, { ...valid(), narration: 'Exact' },
    { ...valid(), enabled: true }, { ...valid(), provider: 'anything' },
    { ...valid(), contract_version: 2 }, { ...valid(), scene_direction: '  \n ' },
    { ...valid(), scene_direction: 'x'.repeat(2001) },
    { ...valid(), character: { ...fixture.character, family_id: crypto.randomUUID() } },
    { ...valid(), character: { ...fixture.character, version_id: 'latest' } },
    '{invalid', ' '.repeat(16385),
  ]) {
    const response = await handler(request(bad));
    assert.equal(response.status, 422);
    assert.equal((await response.json()).code, 'INVALID_REQUEST');
  }
  assert.equal(authCalls, 0);
});

test('anonymous, foreign or unavailable references are rejected; upstream failures are sanitized and retryable', async () => {
  let reads = 0;
  const noAuth = createHandler({ authenticate: async () => false, ownsReadyReference: async () => { reads++; return true; } });
  assert.equal((await noAuth(request())).status, 401);
  assert.equal((await noAuth(request(valid(), { auth: '' }))).status, 401);
  assert.equal(reads, 0);
  const noRef = createHandler({ authenticate: async () => true, ownsReadyReference: async () => false });
  assert.equal((await noRef(request())).status, 404);
  const failed = createHandler({ authenticate: async () => { throw Error('private token, text, SQL'); }, ownsReadyReference: async () => true });
  const response = await failed(request());
  assert.equal(response.status, 503);
  const text = await response.text();
  assert.equal(text.includes('private'), false);
  assert.equal(JSON.parse(text).retryable, true);
});

test('CORS is restricted; preflight does not require an authenticated session', async () => {
  const handler = createHandler({ authenticate: async () => { throw Error('must not authenticate'); }, ownsReadyReference: async () => false });
  const preflight = await handler(request(null, { method: 'OPTIONS', auth: '' }));
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), 'http://localhost:8766');
  assert.equal((await handler(request(valid(), { origin: 'https://foreign.invalid' }))).status, 403);
  assert.equal((await handler(request(null, { method: 'GET', origin: '' }))).status, 405);
});

test('runtime uses only caller-scoped GETs and public key; requires an actual ready, matching source', async () => {
  const calls = [];
  let user = { id: 'authenticated-id', is_anonymous: false, user_metadata: { family_id: 'forged' } };
  let row = { ...fixture.character, sha256: fixture.character.sha256, state: 'ready', deleting_character: false };
  const deps = runtimeDependencies('https://project.invalid', 'sb_publishable_test', async (url, options) => {
    calls.push({ url, options });
    return Response.json(url.includes('/auth/') ? user : [row]);
  });
  assert.equal(await deps.authenticate('Bearer caller'), true);
  assert.equal(await deps.ownsReadyReference('Bearer caller', fixture), true);
  for (const change of [{ state: 'pending' }, { deleting_character: true }, { sha256: 'b'.repeat(64) }]) {
    const original = row; row = { ...row, ...change };
    assert.equal(await deps.ownsReadyReference('Bearer caller', fixture), false);
    row = original;
  }
  user = { ...user, is_anonymous: true };
  assert.equal(await deps.authenticate('Bearer caller'), false);
  assert.equal(calls.every(({ options }) => !options.method && !options.body && options.headers.Authorization === 'Bearer caller' &&
    options.headers.apikey === 'sb_publishable_test' && options.signal instanceof AbortSignal), true);
  assert.match(calls[1].url, /version_id=eq\./);
  assert.equal(calls.some(({ url }) => /storage|provider|admin/.test(url)), false);
});
