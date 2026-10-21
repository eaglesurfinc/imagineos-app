import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFile,lstat,readdir} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

const root=path.resolve(fileURLToPath(new URL('../..',import.meta.url)));
const outputs=['index.html','flutter_bootstrap.js','main.dart.js'];
export async function releaseManifest(projectRoot=root) {
  const source=execFileSync('git',['rev-parse','HEAD'],{cwd:projectRoot,encoding:'utf8',windowsHide:true}).trim();
  if(!/^[a-f0-9]{40}$/.test(source))throw Error('Cannot identify release source.');
  const dirty=execFileSync('git',['status','--porcelain','--untracked-files=normal'],
      {cwd:projectRoot,encoding:'utf8',windowsHide:true}).trim().length>0;
  const files=[],web=path.join(projectRoot,'build','web');
  if(!(await lstat(web)).isDirectory())throw Error('Release output missing.');
  async function walk(relative=''){
    for(const entry of await readdir(path.join(web,relative),{withFileTypes:true})){
      const name=relative?`${relative}/${entry.name}`:entry.name;
      if(entry.isSymbolicLink())throw Error('Release contains a link.');
      if(entry.isDirectory()){await walk(name);continue;}
      const location=path.join(web,name),info=await lstat(location);
      if(!info.isFile()||info.nlink!==1||info.size>50*1024*1024||files.length>=2000)throw Error('Release output invalid.');
      files.push({path:`build/web/${name}`,bytes:info.size,sha256:createHash('sha256').update(await readFile(location)).digest('hex')});
    }
  }
  await walk();files.sort((a,b)=>a.path.localeCompare(b.path));
  if(!outputs.every(name=>files.some(f=>f.path===`build/web/${name}`&&f.bytes>0)))throw Error('Required release output missing.');
  return {format:'imagineos-release-manifest',version:1,created_at:new Date().toISOString(),source_commit:source,
    working_tree_dirty:dirty,files,
    // This is an artifact fingerprint, never evidence that tests/deployment ran.
    verification:'artifact_hashes_only'};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  try {process.stdout.write(JSON.stringify(await releaseManifest(),null,2)+'\n');}
  catch {console.error('Release manifest failed. Build web and verify Git before recording a release.');process.exitCode=1;}
}
