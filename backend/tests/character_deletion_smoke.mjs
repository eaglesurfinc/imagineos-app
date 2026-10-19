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
const original = png([70,40,180]);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const object = path => `/storage/v1/object/${bucket}/${path}?cacheBust=${randomUUID()}`;
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
  if (!process.argv.includes('--cleanup')) {
  const [a,b]=sessions.map(s=>s.access_token);
  const children=[];
  for (const token of [a,b]) {
    const family=ok(await request('/rest/v1/families?select=id',token))[0];
    children.push(ok(await request('/rest/v1/child_profiles',token,'POST',{family_id:family.id,nickname:'Deletion test creator'}),201)[0]);
  }
  const create=async(token,child,character=null,name='Fictional delete friend')=>{
    const row=ok(await reserve(token,child,name,original,character));
    ok(await upload(token,row));ok(await rpc('finish_original',token,{p_request_id:row.request_id}));
    return row;
  };
  const begin=(token,row,version=null)=>rpc('begin_character_deletion',token,{p_character_id:row.character_id,p_version_id:version});
  const finish=(token,row,version=null)=>rpc('finish_character_deletion',token,{p_character_id:row.character_id,p_version_id:version});
  const remove=async(token,paths)=>{if(paths.length)ok(await request(`/storage/v1/object/${bucket}`,token,'DELETE',{prefixes:paths}));};
  const one=await create(a,children[0].id);
  const two=await create(a,children[0].id,one.character_id);
  const three=await create(a,children[0].id,one.character_id);
  const keep=await create(a,children[0].id,null,'Keep this character');
  const foreign=await create(b,children[1].id,null,'Other family character');
  denied(await request('/rest/v1/characters?id=eq.'+one.character_id,a,'DELETE'));
  denied(await request('/rest/v1/character_versions?id=eq.'+one.version_id,a,'DELETE'));
  await remove(a,[one.object_path]);
  assert.equal(hash(okBytes(await request(object(one.object_path),a))),hash(original));
  assert.deepEqual(ok(await begin(b,one)),[]);
  ok(await finish(b,one));
  assert.deepEqual(ok(await begin(a,one,foreign.version_id)),[]);
  denied(await begin(null,one));
  denied(await finish(a,one,two.version_id));
  const selectedPaths=ok(await begin(a,one,two.version_id));
  assert.deepEqual(selectedPaths,[two.object_path]);
  denied(await finish(a,one,two.version_id));
  denied(await rpc('finish_original',a,{p_request_id:two.request_id}));
  const fresh=ok(await request('/auth/v1/token?grant_type=password',null,'POST',accounts[0])).access_token;
  const deleting=ok(await request('/rest/v1/original_uploads?state=eq.deleting',fresh));
  assert.equal(deleting.length,1);assert.equal(deleting[0].version_id,two.version_id);
  assert.equal(deleting[0].deleting_character,false);
  await remove(fresh,ok(await begin(fresh,one,two.version_id)));
  ok(await finish(fresh,one,two.version_id));ok(await finish(fresh,one,two.version_id));
  assert.equal(hash(okBytes(await request(object(one.object_path),a))),hash(original));
  assert.equal(hash(okBytes(await request(object(three.object_path),a))),hash(original));
  // Remove latest too; the next number must still be 4, not a reused 2.
  await remove(a,ok(await begin(a,one,three.version_id)));
  ok(await finish(a,one,three.version_id));
  denied(await begin(a,one,one.version_id));
  const four=await create(a,children[0].id,one.character_id);
  assert.equal(four.version_number,4);
  const pending=ok(await reserve(a,children[0].id,'Unfinished drawing',original,one.character_id));
  ok(await upload(a,pending));
  const wholePaths=ok(await begin(a,one));
  assert.deepEqual(new Set(wholePaths),new Set([one.object_path,four.object_path,pending.object_path]));
  denied(await finish(a,one));
  denied(await reserve(a,children[0].id,'No resurrection',original,one.character_id));
  denied(await rpc('finish_original',a,{p_request_id:pending.request_id}));
  await remove(b,wholePaths); // RLS returns no deletions; own files still exist.
  assert.equal(hash(okBytes(await request(object(one.object_path),a))),hash(original));
  await remove(a,[wholePaths[0]]); // Interrupt after one physical file removal.
  await remove(fresh,ok(await begin(fresh,one)));
  ok(await finish(fresh,one));ok(await finish(fresh,one));
  assert.deepEqual(ok(await begin(fresh,one)),[]);
  assert.deepEqual(ok(await request('/rest/v1/original_uploads?character_id=eq.'+one.character_id,a)),[]);
  for(const path of wholePaths) assert((await request(object(path),a)).status>=400);
  denied(await reserve(a,children[0].id,'Fictional delete friend',original,null,one.request_id));
  const remaining=ok(await request('/rest/v1/characters?select=id',a));
  assert.deepEqual(remaining.map(c=>c.id),[keep.character_id]);
  assert.equal(hash(okBytes(await request(object(keep.object_path),a))),hash(original));
  assert.equal(hash(okBytes(await request(object(foreign.object_path),b))),hash(original));
  console.log('PASS: selected-version and whole-character removal, family isolation, physical file cleanup, interrupted/fresh-session retries, last-version guard, monotonic numbers, and stale-upload resurrection prevention.');
  }
} finally {
  for (const session of sessions) {
    const token=session.access_token;
    const rows=ok(await request('/rest/v1/characters?select=id',token));
    for(const row of rows) {
      const params={p_character_id:row.id,p_version_id:null};
      const paths=ok(await rpc('begin_character_deletion',token,params));
      if(paths.length)ok(await request(`/storage/v1/object/${bucket}`,token,'DELETE',{prefixes:paths}));
      ok(await rpc('finish_character_deletion',token,params));
    }
  }
  console.log('Fixture artwork removed through Storage API. Verify zero fixture objects before deleting fixture Auth users.');
}
function okBytes(result) { assert.equal(result.status,200);return result.bytes; }
