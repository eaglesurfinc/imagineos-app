import {createHash} from 'node:crypto';
import {createReadStream} from 'node:fs';
import {lstat,readdir,readFile,realpath} from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const project='hgsivbqmbcliqbstrkdz',limit=2*1024*1024*1024;
const uuid='[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}';
const objectPath=new RegExp(`^${uuid}/${uuid}$`);
const fail=()=>{throw Error('Backup verification failed. Keep the source files and review the private manifest.');};
function keys(value,names){
  if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==names.length||!names.every(k=>Object.hasOwn(value,k)))fail();
}
async function ordinaryFile(root,relative){
  if(typeof relative!=='string'||relative.includes('\\')||relative.includes(':')||relative.split('/').some(p=>!p||p==='.'||p==='..'))fail();
  const segments=relative.split('/');let current=root;
  for(let i=0;i<segments.length;i++){
    current=path.join(current,segments[i]);const info=await lstat(current);
    if(info.isSymbolicLink()||i<segments.length-1&&!info.isDirectory()||i===segments.length-1&&(!info.isFile()||info.nlink!==1))fail();
  }
  const resolved=await realpath(current),inside=path.relative(root,resolved);
  if(inside.startsWith('..'+path.sep)||inside==='..'||path.isAbsolute(inside))fail();
  return current;
}
async function fingerprint(location){
  const hash=createHash('sha256');let bytes=0;
  for await(const chunk of createReadStream(location)){bytes+=chunk.length;if(bytes>limit)fail();hash.update(chunk);}
  return{bytes,sha256:hash.digest('hex')};
}
export async function verifyBackup(directory){
  try {
    const initial=await lstat(directory);if(!initial.isDirectory()||initial.isSymbolicLink())fail();
    const root=await realpath(directory),manifestPath=await ordinaryFile(root,'operator-backup.json');
    if((await lstat(manifestPath)).size>16*1024*1024)fail();
    const manifestBytes=await readFile(manifestPath),manifestHash=createHash('sha256').update(manifestBytes).digest('hex');
    const manifest=JSON.parse(manifestBytes.toString('utf8'));
    keys(manifest,['format','version','source_project','captured_at','snapshot_label','database','storage']);
    if(manifest.format!=='imagineos-operator-backup'||manifest.version!==1||manifest.source_project!==project||
        typeof manifest.captured_at!=='string'||!Number.isFinite(Date.parse(manifest.captured_at))||
        typeof manifest.snapshot_label!=='string'||!/^[a-zA-Z0-9_-]{1,80}$/.test(manifest.snapshot_label))fail();
    keys(manifest.database,['roles','schema','data']);
    if(!Array.isArray(manifest.storage)||manifest.storage.length>50000)fail();
    const files=new Map();
    for(const role of ['roles','schema','data']){
      const entry=manifest.database[role];keys(entry,['path','bytes','sha256']);
      if(entry.path!==`database/${role}.sql`)fail();files.set(entry.path,entry);
    }
    for(const entry of manifest.storage){
      keys(entry,['bucket','object_path','path','bytes','sha256']);
      if(entry.bucket!=='character-originals'||typeof entry.object_path!=='string'||!objectPath.test(entry.object_path)||
          entry.path!==`objects/character-originals/${entry.object_path}`||files.has(entry.path))fail();
      files.set(entry.path,entry);
    }
    let total=0;
    for(const [relative,expected] of files){
      if(!Number.isSafeInteger(expected.bytes)||expected.bytes<1||expected.bytes>limit||
          typeof expected.sha256!=='string'||!/^[a-f0-9]{64}$/.test(expected.sha256))fail();
      const location=await ordinaryFile(root,relative),info=await lstat(location);
      if(info.size!==expected.bytes)fail();const actual=await fingerprint(location);
      if(actual.bytes!==expected.bytes||actual.sha256!==expected.sha256)fail();total+=actual.bytes;
    }
    // Refuse omitted/extra object bytes and links; never execute a dump or SQL.
    const expected=new Set(['operator-backup.json',...files.keys()]);let entries=0;
    async function walk(relative=''){
      for(const entry of await readdir(path.join(root,relative),{withFileTypes:true})){
        if(++entries>100100)fail();const next=relative?`${relative}/${entry.name}`:entry.name;
        if(entry.isSymbolicLink())fail();
        if(entry.isDirectory()){
          if(next!=='database'&&next!=='objects'&&!next.startsWith('objects/'))fail();
          await walk(next);
        }else if(!entry.isFile()||!expected.delete(next))fail();
      }
    }
    await walk();if(expected.size)fail();
    if(createHash('sha256').update(await readFile(manifestPath)).digest('hex')!==manifestHash)fail();
    return{format:'imagineos-backup-check',version:1,source_project:project,database_parts:3,storage_objects:manifest.storage.length,
      total_bytes:total,manifest_sha256:manifestHash,
      verification:'file_integrity_only',restore_verified:false};
  }catch{fail();}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  try{if(process.argv.length!==3)fail();console.log(JSON.stringify(await verifyBackup(process.argv[2]),null,2));}
  catch{console.error('Backup verification failed. No data was restored, copied or uploaded.');process.exitCode=1;}
}
