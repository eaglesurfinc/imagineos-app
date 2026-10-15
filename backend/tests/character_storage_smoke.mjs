// Dedicated development target and temporary fictional accounts only.
// See backend/README.md for fixture preparation and mandatory file/user cleanup.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { deflateSync } from 'node:zlib';

const config = JSON.parse(fs.readFileSync('config/supabase.local.json', 'utf8'));
assert.equal(config.SUPABASE_URL, 'https://hgsivbqmbcliqbstrkdz.supabase.co');
const accounts = JSON.parse(fs.readFileSync('config/auth-test.local.json', 'utf8'));
assert(accounts.length === 2 && accounts.every(a => a.email.endsWith('@example.invalid')));
const bucket = 'character-originals';
const sessions = [];
async function request(path, token, method = 'GET', body, binary = false, headers = {}) {
  const response = await fetch(config.SUPABASE_URL + path, {
    method, headers: { apikey: config.SUPABASE_PUBLISHABLE_KEY,
      ...(token ? {Authorization: `Bearer ${token}`} : {}),
      'Content-Type': binary ? 'image/png' : 'application/json', Prefer: 'return=representation', ...headers },
    body: body === undefined ? undefined : binary ? body : JSON.stringify(body),
  });
  const bytes = Buffer.from(await response.arrayBuffer());
  let data;
  try { data = bytes.length ? JSON.parse(bytes.toString()) : null; } catch { data = null; }
  return { status: response.status, data, bytes };
}
function png(color) {
  const crc = buffer => {
    let value = 0xffffffff;
    for (const byte of buffer) { value ^= byte; for (let i=0;i<8;i++) value = (value>>>1) ^ ((value&1) ? 0xedb88320 : 0); }
    return (value ^ 0xffffffff) >>> 0;
  };
  const chunk = (name, data) => {
    const type = Buffer.from(name), size = Buffer.alloc(4), checksum = Buffer.alloc(4);
    size.writeUInt32BE(data.length); checksum.writeUInt32BE(crc(Buffer.concat([type,data])));
    return Buffer.concat([size,type,data,checksum]);
  };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(8,0); ihdr.writeUInt32BE(8,4); ihdr[8]=8; ihdr[9]=2;
  const pixels = Buffer.concat(Array.from({length:8}, () => Buffer.from([0,...Array.from({length:8}, () => color).flat()])));
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),chunk('IDAT',deflateSync(pixels)),chunk('IEND',Buffer.alloc(0))]);
}
const original = png([70,40,180]), revised = png([20,140,100]);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const object = path => `/storage/v1/object/${bucket}/${path}`;
const rpc = (name, token, params) => request(`/rest/v1/rpc/${name}`,token,'POST',params);
async function reserve(token, child, name, bytes=original, character=null, id=randomUUID()) {
  return rpc('reserve_original',token,{p_request_id:id,p_child_id:child,p_character_id:character,p_name:name,
    p_mime_type:'image/png',p_byte_size:bytes.length,p_sha256:hash(bytes)});
}
async function upload(token, row, bytes=original) {
  return request(object(row.object_path),token,'POST',bytes,true,{'x-upsert':'false'});
}
function ok(result, status=200) { assert(status === 200 && result.status === 204 || result.status === status, `Unexpected API status ${result.status}: ${result.data?.message ?? result.data?.error ?? 'response'}`); return result.data; }
function denied(result) { assert(result.status >= 400, 'Unexpected authorized response'); }
try {
  for (const account of accounts) sessions.push(ok(await request('/auth/v1/token?grant_type=password',null,'POST',account)));
  const [a,b] = sessions.map(s => s.access_token);
  if (process.argv.includes('--cleanup')) {
    // First reset ONLY these fictional accounts' assets to pending through the
    // authorized SQL cleanup procedure. Published files are otherwise immutable.
    for (const token of [a,b]) {
      const rows = ok(await request('/rest/v1/original_uploads?state=neq.cancelled&select=request_id,object_path,state',token));
      for (const row of rows) {
        assert.equal(row.state,'pending','Privileged fixture reset must precede cleanup');
        ok(await request(`/storage/v1/object/${bucket}`,token,'DELETE',{prefixes:[row.object_path]}));
        ok(await rpc('cancel_original',token,{p_request_id:row.request_id}));
      }
    }
    console.log('PASS: fictional fixture objects removed through Storage API. Delete fixture Auth users next.');
  } else {
    const children=[];
    for (const token of [a,b]) {
      const family=ok(await request('/rest/v1/families?select=id',token))[0];
      children.push(ok(await request('/rest/v1/child_profiles',token,'POST',{family_id:family.id,nickname:'Fictional creator'}),201)[0]);
    }
    const retryKey=randomUUID();
    const reservations=await Promise.all([reserve(a,children[0].id,'Space friend',original,null,retryKey),reserve(a,children[0].id,'Space friend',original,null,retryKey)]);
    const first=ok(reservations[0]); assert.deepEqual(ok(reservations[1]),first);
    assert.equal(first.state,'pending');
    denied(await rpc('finish_original',a,{p_request_id:retryKey}));
    denied(await reserve(a,children[1].id,'Foreign child'));
    denied(await reserve(b,children[1].id,'Foreign character',original,first.character_id));
    denied(await reserve(a,children[0].id,'Changed retry',original,null,retryKey));
    denied(await request(object(first.object_path),b,'POST',original,true));
    denied(await request(object(`${first.family_id}/${randomUUID()}`),a,'POST',original,true));
    ok(await upload(a,first));
    ok(await rpc('finish_original',a,{p_request_id:retryKey}));
    ok(await rpc('finish_original',a,{p_request_id:retryKey}));
    denied(await rpc('cancel_original',a,{p_request_id:retryKey}));
    const saved=ok(await request('/rest/v1/original_uploads?state=eq.ready&select=*',a));
    assert.equal(saved.length,1); assert.equal(saved[0].sha256,hash(original));
    assert.deepEqual((await request(object(first.object_path),a)).bytes,original);
    denied(await request(object(first.object_path),b));
    denied(await request(`/storage/v1/object/public/${bucket}/${first.object_path}`,null));
    denied(await request(`/storage/v1/object/sign/${bucket}/${first.object_path}`,b,'POST',{expiresIn:60}));
    denied(await rpc('finish_original',b,{p_request_id:retryKey}));
    denied(await rpc('cancel_original',b,{p_request_id:retryKey}));
    assert.deepEqual(ok(await request('/rest/v1/original_uploads?select=*',b)),[]);
    denied(await request('/rest/v1/original_uploads?select=*',null));
    denied(await request(`/rest/v1/character_versions?id=eq.${first.version_id}`,a,'PATCH',{name:'Overwrite'}));
    denied(await request(`/rest/v1/original_assets?id=eq.${retryKey}`,a,'DELETE'));
    denied(await request(object(first.object_path),a,'POST',revised,true,{'x-upsert':'true'}));
    await request(`/storage/v1/object/${bucket}`,a,'DELETE',{prefixes:[first.object_path]});
    assert.deepEqual((await request(object(first.object_path),a)).bytes,original,'Published original was deleted');
    const second=ok(await reserve(a,children[0].id,'Space friend updated',revised,first.character_id));
    assert.equal(second.version_number,2); assert.notEqual(second.version_id,first.version_id);
    ok(await upload(a,second,revised)); ok(await rpc('finish_original',a,{p_request_id:second.request_id}));
    assert.deepEqual((await request(object(first.object_path),a)).bytes,original,'Version one changed');
    assert.deepEqual((await request(object(second.object_path),a)).bytes,revised);
    // Crash after upload: a fresh session finds and finishes the pending version.
    const interrupted=ok(await reserve(a,children[0].id,'Recovered original'));
    ok(await upload(a,interrupted));
    const renewed=ok(await request('/auth/v1/token?grant_type=password',null,'POST',accounts[0])); sessions.push(renewed);
    const reopened=ok(await request('/rest/v1/original_uploads?state=eq.pending&select=*',renewed.access_token));
    assert(reopened.some(row=>row.request_id===interrupted.request_id));
    ok(await rpc('finish_original',renewed.access_token,{p_request_id:interrupted.request_id}));
    const abandoned=ok(await reserve(a,children[0].id,'Abandoned drawing'));
    ok(await upload(a,abandoned));
    denied(await rpc('cancel_original',a,{p_request_id:abandoned.request_id}));
    ok(await request(`/storage/v1/object/${bucket}`,a,'DELETE',{prefixes:[abandoned.object_path]}));
    ok(await rpc('cancel_original',a,{p_request_id:abandoned.request_id}));
    ok(await rpc('cancel_original',a,{p_request_id:abandoned.request_id}));
    denied(await upload(a,abandoned));
    denied(await request(object(abandoned.object_path),a));
    const oversize=await rpc('reserve_original',a,{p_request_id:randomUUID(),p_child_id:children[0].id,p_character_id:null,p_name:'Oversize',p_mime_type:'image/png',p_byte_size:5242881,p_sha256:hash(original)});
    denied(oversize);
    const mismatch=ok(await rpc('reserve_original',a,{p_request_id:randomUUID(),p_child_id:children[0].id,p_character_id:null,p_name:'Wrong size',p_mime_type:'image/png',p_byte_size:original.length+1,p_sha256:hash(original)}));
    ok(await upload(a,mismatch)); denied(await rpc('finish_original',a,{p_request_id:mismatch.request_id}));
    fs.writeFileSync('config/stage3-fixture.local.json',JSON.stringify({first,second,original:original.toString('base64'),revised:revised.toString('base64')}));
    console.log('PASS: exact original save/reopen, concurrent idempotency, immutable versions/files, cross-family metadata/download/sign/upload denial, recovered saves, abandoned-file cleanup, size validation.');
  }
} finally {
  for (const session of sessions) await request('/auth/v1/logout?scope=local',session.access_token,'POST');
}
