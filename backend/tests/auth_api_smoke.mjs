// Uses preprovisioned fictional accounts only; sends no email and prints no tokens.
// Run from repository root after authorized fixture setup. Cleanup is server-side.
import fs from 'node:fs';
import assert from 'node:assert/strict';

const config = JSON.parse(fs.readFileSync('config/supabase.local.json', 'utf8'));
const accounts = JSON.parse(fs.readFileSync('config/auth-test.local.json', 'utf8'));
assert.equal(accounts.length, 2);
assert(accounts.every(account => account.email.endsWith('@example.invalid')));
const url = config.SUPABASE_URL;
const key = config.SUPABASE_PUBLISHABLE_KEY;
async function request(path, token, method = 'GET', body) {
  const response = await fetch(url + path, {
    method,
    headers: { apikey: key, 'Content-Type': 'application/json', Prefer: 'return=representation', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, data: text ? JSON.parse(text) : null };
}
const settings = await request('/auth/v1/settings');
assert.equal(settings.status, 200);
assert.equal(settings.data.mailer_autoconfirm, false);
const invalid = await request('/auth/v1/token?grant_type=password', null, 'POST', { email: accounts[0].email, password: 'intentionally-wrong' });
assert.equal(invalid.status, 400);
const sessions = [];
try {
  for (const account of accounts) {
    const result = await request('/auth/v1/token?grant_type=password', null, 'POST', account);
    assert.equal(result.status, 200, 'Fictional account sign-in failed');
    sessions.push(result.data);
  }
  const [a, b] = sessions.map(session => session.access_token);
  const families = await Promise.all([a, b].map(token => request('/rest/v1/families?select=id,parent_user_id', token)));
  for (let i = 0; i < 2; i++) {
    assert.equal(families[i].status, 200);
    assert.equal(families[i].data.length, 1);
    assert.equal(families[i].data[0].parent_user_id, accounts[i].id);
  }
  const familyA = families[0].data[0].id;
  const familyB = families[1].data[0].id;
  assert.notEqual(familyA, familyB);
  const child = await request('/rest/v1/child_profiles', a, 'POST', {family_id: familyA, nickname: 'Fictional API creator'});
  assert.equal(child.status, 201);
  const childId = child.data[0].id;
  assert.deepEqual((await request(`/rest/v1/child_profiles?id=eq.${childId}&select=id`, b)).data, []);
  assert.deepEqual((await request(`/rest/v1/child_profiles?id=eq.${childId}`, b, 'PATCH', {nickname: 'Intruder'})).data, []);
  const linkedInsert = await request('/rest/v1/child_profiles', a, 'POST', {family_id: familyB, nickname: 'Intruder'});
  assert.equal(linkedInsert.status, 403);
  const reassign = await request(`/rest/v1/child_profiles?id=eq.${childId}`, a, 'PATCH', {family_id: familyB});
  assert.equal(reassign.status, 403);
  const owner = await request(`/rest/v1/families?id=eq.${familyA}`, a, 'PATCH', {parent_user_id: accounts[1].id});
  assert.equal(owner.status, 403);
  const metadata = await request('/auth/v1/user', a, 'PUT', {data: {role: 'admin', family_id: familyB}});
  assert.equal(metadata.status, 200);
  const refreshed = await request('/auth/v1/token?grant_type=refresh_token', null, 'POST', {refresh_token: sessions[0].refresh_token});
  assert.equal(refreshed.status, 200);
  sessions[0] = refreshed.data;
  const forged = await request(`/rest/v1/families?id=eq.${familyB}&select=id`, sessions[0].access_token);
  assert.deepEqual(forged.data, []);
  const unauthenticated = await request('/rest/v1/families?select=id');
  assert([401, 403].includes(unauthenticated.status));
  const logout = await request('/auth/v1/logout?scope=global', sessions[1].access_token, 'POST');
  assert.equal(logout.status, 204);
  const afterLogout = await request('/auth/v1/token?grant_type=refresh_token', null, 'POST', {refresh_token: sessions[1].refresh_token});
  assert.equal(afterLogout.status, 400);
  console.log('PASS: real password sign-in, refresh, signout, family/child REST isolation, ownership and metadata attacks, anonymous denial.');
} finally {
  for (const session of sessions) await request('/auth/v1/logout?scope=global', session.access_token, 'POST');
}
