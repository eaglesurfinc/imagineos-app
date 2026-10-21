import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,readFile,rm,link} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {verifyBackup} from '../scripts/verify_backup.mjs';
import {releaseManifest} from '../scripts/release_manifest.mjs';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
async function fixture(action){
  const base=await mkdtemp(path.join(tmpdir(),'imagineos-ops-test-'));
  try{return await action(base);}finally{
    assert(path.resolve(base).startsWith(path.join(path.resolve(tmpdir()),'imagineos-ops-test-')));
    await rm(base,{recursive:true,force:true});
  }
}
async function backup(base){
  const root=path.join(base,'backup');await mkdir(path.join(root,'database'),{recursive:true});
  const manifest={format:'imagineos-operator-backup',version:1,source_project:'hgsivbqmbcliqbstrkdz',
    captured_at:'2026-10-20T00:00:00Z',snapshot_label:'fictional_fixture',database:{},storage:[]};
  for(const role of ['roles','schema','data']){
    const relative=`database/${role}.sql`,bytes=Buffer.from(`-- fictional ${role}; never execute this dump\n`);
    await writeFile(path.join(root,relative),bytes);manifest.database[role]={path:relative,bytes:bytes.length,sha256:hash(bytes)};
  }
  const object_path=`${randomUUID()}/${randomUUID()}`,relative=`objects/character-originals/${object_path}`,bytes=Buffer.from('fictional artwork bytes');
  await mkdir(path.dirname(path.join(root,relative)),{recursive:true});await writeFile(path.join(root,relative),bytes);
  manifest.storage.push({bucket:'character-originals',object_path,path:relative,bytes:bytes.length,sha256:hash(bytes)});
  const save=()=>writeFile(path.join(root,'operator-backup.json'),JSON.stringify(manifest));await save();
  return{root,manifest,save};
}
test('paired backup verification hashes all three database parts and every object without executing or echoing private content',()=>fixture(async base=>{
  const {root,manifest}=await backup(base),result=await verifyBackup(root);
  assert.equal(result.database_parts,3);assert.equal(result.storage_objects,1);
  assert.equal(result.verification,'file_integrity_only');assert.equal(result.restore_verified,false);
  assert.equal(result.manifest_sha256,hash(await readFile(path.join(root,'operator-backup.json'))));
  assert(!JSON.stringify(result).includes(manifest.storage[0].object_path));
  assert(!JSON.stringify(result).includes('fictional artwork'));
}));
test('corrupt, omitted and extra backup files fail without exposing their contents or paths',()=>fixture(async base=>{
  const {root,manifest,save}=await backup(base),file=path.join(root,manifest.storage[0].path);
  await writeFile(file,'private corrupt bytes');await assert.rejects(verifyBackup(root),/Backup verification failed/);
  manifest.storage[0].bytes=21;manifest.storage[0].sha256=hash('private corrupt bytes');await save();
  await writeFile(path.join(root,'unexpected-private.sql'),'private data');
  await assert.rejects(verifyBackup(root),error=>!error.message.includes('unexpected-private'));
  await rm(path.join(root,'unexpected-private.sql'));manifest.storage=[];await save();
  await assert.rejects(verifyBackup(root),/Backup verification failed/);
}));
test('backup paths, hard links, foreign targets and manifest tampering are refused',()=>fixture(async base=>{
  const {root,manifest,save}=await backup(base);
  const roles=manifest.database.roles;
  for(const value of ['../private.sql','C:/private.sql','database/../private.sql','database\\roles.sql']){
    manifest.database.roles={...roles,path:value};await save();await assert.rejects(verifyBackup(root),/Backup verification failed/);
  }
  manifest.database.roles=roles;manifest.source_project='foreign-project';await save();await assert.rejects(verifyBackup(root));
  manifest.source_project='hgsivbqmbcliqbstrkdz';await save();
  await link(path.join(root,'database/roles.sql'),path.join(base,'linked.sql'));await assert.rejects(verifyBackup(root));
}));
test('release fingerprints include assets, identify dirty source and make no test/deployment claim',()=>fixture(async base=>{
  const git=args=>execFileSync('git',args,{cwd:base,windowsHide:true,stdio:'pipe'});
  git(['init','-q']);await writeFile(path.join(base,'README.md'),'fictional source');git(['add','README.md']);
  git(['-c','user.name=Fictional Test','-c','user.email=adult@example.invalid','commit','-qm','Fictional baseline']);
  const web=path.join(base,'build','web');await mkdir(path.join(web,'assets'),{recursive:true});
  for(const name of ['index.html','flutter_bootstrap.js','main.dart.js','assets/font.ttf'])await writeFile(path.join(web,name),'fictional '+name);
  const before=await releaseManifest(base);assert.equal(before.files.length,4);assert(before.working_tree_dirty);
  assert.equal(before.verification,'artifact_hashes_only');assert.equal(before.source_commit,git(['rev-parse','HEAD']).toString().trim());
  const original=before.files.find(f=>f.path.endsWith('main.dart.js')).sha256;
  await writeFile(path.join(web,'main.dart.js'),'changed output');
  const after=await releaseManifest(base);assert.notEqual(after.files.find(f=>f.path.endsWith('main.dart.js')).sha256,original);
  await rm(path.join(web,'index.html'));await assert.rejects(releaseManifest(base),/Required release output missing/);
}));
