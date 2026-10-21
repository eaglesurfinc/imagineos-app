const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{createHash}=require('node:crypto');
const {browserSession}=require('./support/browser_session.cjs');
const ordered=v=>Array.isArray(v)?v.map(ordered):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,ordered(v[k])])):v;
(async()=>{
 const config=JSON.parse(fs.readFileSync('config/supabase.local.json')),accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json'));
 const fixture=JSON.parse(fs.readFileSync('config/privacy-test.local.json'));
 const missing=process.argv.includes('--missing-artwork')?JSON.parse(fs.readFileSync('config/story-recovery-test.local.json')):null;
 assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');assert(accounts.every(a=>/^adult-.*@example\.invalid$/.test(a.email)));
 async function api(route,token,body,grant){const r=await fetch(config.SUPABASE_URL+route,{method:body?'POST':'GET',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'content-type':'application/json',...(token?{authorization:`Bearer ${token}`} : {}),...(grant?{'x-imagineos-parent-grant':grant}:{})},body:body?JSON.stringify(body):undefined});const v=await r.json().catch(()=>null);assert([200,204].includes(r.status),'API status '+r.status);return v?.contract_version===1?v.data:v;}
 const adult=await api('/auth/v1/token?grant_type=password',null,{email:accounts[0].email,password:accounts[0].password});
 const beforeRows=await api('/rest/v1/original_uploads',adult.access_token),beforeStories=await api('/rest/v1/story_project_snapshots',adult.access_token);
 const previousAssets=new Set(beforeRows.map(v=>v.request_id)),previousStories=new Set(beforeStories.map(s=>s.id));
 const artifacts=path.resolve('build/privacy-recovery-browser',Date.now().toString(36)),b=await browserSession(artifacts);
 try{
  await b.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
  await b.send('Page.navigate',{url:'http://127.0.0.1:8766'});await b.semantics();await b.control('Parent sign-in');await b.waitFor('Create a parent account');
  await b.fill('Parent email',accounts[0].email);await b.fill('Password',accounts[0].password);await b.control('Sign in');await b.waitFor('Unlock parent settings');
  await b.fill('Parent password',accounts[0].password);await b.control('Unlock parent settings');await b.control('Privacy and recovery');await b.waitFor('USA pilot is not available yet.');await b.waitFor('Fresh parent approvals are required');
  await b.snapshot('privacy-status-phone');
  async function clearDrafts(){
    await b.evaluate(`localStorage.setItem('imagineos.draft.v1.fictional-privacy-check',JSON.stringify('fictional unsaved work'));localStorage.setItem('imagineos.privacy-test.keep','unrelated setting');`);
    await b.control('Clear device working drafts');await b.waitFor('Clear working drafts on this browser?');await b.control('Cancel');
    assert.equal(await b.evaluate(`localStorage.getItem('imagineos.draft.v1.fictional-privacy-check')!==null`),true);
    await b.control('Clear device working drafts');await b.waitFor('Clear working drafts on this browser?');await b.control('Clear device drafts');await b.wheel(20000);await b.waitFor('ImagineOS device drafts cleared.');
    assert.deepEqual(await b.evaluate(`Object.keys(localStorage).filter(k=>k.startsWith('imagineos.draft.v1.'))`),[]);
    assert.equal(await b.evaluate(`localStorage.getItem('imagineos.privacy-test.keep')`),'unrelated setting');
    assert.equal(await b.evaluate(`Object.values(localStorage).some(v=>v.includes(${JSON.stringify(accounts[0].email)}))`),true,'Clearing drafts signed the parent out');
    await b.snapshot('device-drafts-cleared-phone');
  }
  if(process.argv.includes('--drafts-only')){await clearDrafts();assert.deepEqual(b.errors,[]);console.log('PASS: parent-confirmed device-draft removal, cancellation, unrelated storage/Auth preservation. '+artifacts);return;}
  await b.control('Pause all child access');await b.waitFor('Pause all child access?');await b.control('Cancel');await b.waitFor('Fresh parent approvals are required');
  await b.control('Pause all child access');await b.waitFor('Pause all child access?');await b.control('Pause child access');await b.waitFor('Child access is paused. Saved work has been kept.');
  await b.snapshot('parent-paused-phone');await b.control('Allow new parent approvals');await b.control('Allow new approvals');await b.waitFor('Every sign-in still needs a fresh code.');
  await b.control('Download family backup');await b.control('Download backup');await b.waitFor('Backup download requested.');
  let download;for(let i=0;i<60;i++){download=fs.readdirSync(artifacts).find(n=>n.endsWith('.imagineos.json'));if(download)break;await b.delay(200);}
  assert(download,'Portable backup was not downloaded');const file=path.join(artifacts,download),document=JSON.parse(fs.readFileSync(file));
  const {sha256,...payload}=document;assert.equal(sha256,createHash('sha256').update(JSON.stringify(ordered(payload))).digest('hex'));
  assert.equal(document.snapshot.family_id,fixture.family);assert.equal(document.snapshot.originals.length,beforeRows.length);
  assert.equal(document.snapshot.stories.find(s=>s.id===fixture.storyId).panels[0].dialogue,fixture.words);assert.equal(document.snapshot.pages.find(p=>p.page_id===fixture.pageId).dialogue,fixture.words);
  for(const original of document.snapshot.originals){const bytes=Buffer.from(document.files[original.request_id],'base64');assert.equal(createHash('sha256').update(bytes).digest('hex'),original.sha256);}
  assert(!fs.readFileSync(file,'utf8').includes(adult.access_token));
  const corrupt=path.join(artifacts,'corrupt.imagineos.json');fs.writeFileSync(corrupt,JSON.stringify({...document,sha256:'0'.repeat(64)}));
  await b.chooseFile('Review backup',corrupt);await b.waitFor('This backup is incomplete or invalid.');assert(!(await b.body()).includes('Recover saved copies'));
  await b.chooseFile('Review backup',file);await b.waitFor('Verified backup from');
  await b.send('Emulation.setDeviceMetricsOverride',{width:1024,height:900,deviceScaleFactor:1,mobile:false});
  async function choose(label,value){
    const r=await b.locate(`Array.from(document.querySelectorAll('[role="button"],[role="combobox"]')).find(e=>(e.innerText||e.getAttribute('aria-label')||'').includes(${JSON.stringify(label)}))`);await b.click(r.x,r.y);
    let option;for(let i=0;i<30&&!option;i++){option=await b.evaluate(`(()=>{const e=Array.from(document.querySelectorAll('[role="option"],[role="menuitem"],[role="button"],flt-semantics')).find(e=>[e.textContent,e.getAttribute('aria-label')].some(t=>(t||'').trim().startsWith(${JSON.stringify(value)})) && e.getBoundingClientRect().height>0);const r=e?.getBoundingClientRect();return r?{x:r.x+r.width/2,y:r.y+r.height/2}:null;})()`);if(!option)await b.delay(100);}
    assert(option,'Missing creator choice '+value);await b.click(option.x,option.y);
  }
  await choose('Creator in backup','Fictional story creator');await choose('Recover into this creator','Fictional recovery creator');
  await b.snapshot('verified-backup-tablet');await b.control('Recover saved copies');
  if(missing)await b.waitFor('unavailable artwork');
  await b.control('Cancel');
  assert.equal((await api('/rest/v1/original_uploads',adult.access_token)).length,beforeRows.length,'Cancellation imported data');
  await b.control('Recover saved copies');await b.control('Recover copies');await b.wheel(20000);await b.waitFor('Recovery finished. Review the copies in Family creations.');
  const count=beforeRows.filter(v=>v.child_profile_id===fixture.creator).length;
  let rows=await api('/rest/v1/original_uploads',adult.access_token);assert.equal(rows.length,beforeRows.length+count);
  const copied=rows.filter(r=>!previousAssets.has(r.request_id));assert.equal(copied.length,count);assert(copied.every(v=>v.child_profile_id===fixture.target));
  for(const row of beforeRows)assert.equal(rows.find(v=>v.request_id===row.request_id).sha256,row.sha256,'Existing drawing changed');
  const stories=await api('/rest/v1/story_project_snapshots',adult.access_token),saved=stories.find(s=>!previousStories.has(s.id)&&s.child_id===fixture.target&&s.title==='  Exact backup title  ');
  assert(saved);assert.equal(saved.title,'  Exact backup title  ');assert.equal(saved.panels[0].dialogue,fixture.words);
  assert.notEqual(saved.panels[0].reference.version_id,fixture.reference.version_id);
  assert(copied.some(v=>v.version_id===saved.panels[0].reference.version_id&&v.sha256===fixture.reference.sha256));
  const pages=await api('/rest/v1/saved_story_drafts',adult.access_token),copiedPage=pages.find(p=>copied.some(v=>v.request_id===p.source_id));assert(copiedPage);assert.equal(copiedPage.dialogue,fixture.words);
  const missingCopy=missing?stories.find(s=>!previousStories.has(s.id)&&s.child_id===fixture.target&&s.title===missing.title):null;
  if(missing){
    assert(missingCopy);assert.deepEqual(missingCopy.panels.map(p=>p.source_available),[false,true]);
    assert.equal(missingCopy.panels[0].dialogue,missing.words);assert.equal(missingCopy.panels[0].reference.sha256,missing.missingRef.sha256);
    assert(!rows.some(v=>v.request_id===missingCopy.panels[0].reference.asset_id));
    assert(copied.some(v=>v.request_id===missingCopy.panels[1].reference.asset_id));
  }
  await b.control('Recover saved copies');await b.control('Recover copies');await b.wheel(20000);await b.waitFor('Recovery finished. Review the copies in Family creations.');
  rows=await api('/rest/v1/original_uploads',adult.access_token);assert.equal(rows.length,beforeRows.length+count,'Retry duplicated originals');
  const storyCount=document.snapshot.stories.filter(s=>s.child_id===fixture.creator).length;
  assert.equal((await api('/rest/v1/story_project_snapshots',adult.access_token)).length,beforeStories.length+storyCount,'Retry duplicated stories');
  await b.snapshot('recovery-finished-tablet');
  await clearDrafts();
  await b.send('Page.reload',{ignoreCache:true});await b.semantics();await b.control('Parent sign-in');await b.waitFor('Unlock parent settings');
  assert(!(await b.body()).includes('Verified backup from'));
  if(missing){
    await b.fill('Parent password',accounts[0].password);await b.control('Unlock parent settings');
    await b.control('Review family creations');await b.waitFor('Save an original');await b.control('My stories');await b.waitFor(missing.title.trim());
    const orderedStories=await api('/rest/v1/story_project_snapshots?order=updated_at.desc,id.asc',adult.access_token);
    const index=orderedStories.findIndex(s=>s.id===missingCopy.id);assert(index>=0&&index<20);
    const open=await b.locate(`Array.from(document.querySelectorAll('[role="button"],button')).filter(el=>(el.innerText||el.getAttribute('aria-label')||'').trim().startsWith('Open story'))[${index}]`);
    await b.click(open.x,open.y);await b.waitFor('You are the creator.');await b.control('5. Read, save and print');
    await b.waitFor('Drawing unavailable. Your scene and words are kept.');
    await b.control('Download printable story');await b.waitFor('Download with unavailable drawings?');await b.control('Cancel');
    assert(!fs.readdirSync(artifacts).some(n=>n.endsWith('.html')),'Cancellation downloaded a story');
    await b.control('Download printable story');await b.control('Download with placeholders');await b.waitFor('Printable story download requested.');
    let htmlFile;for(let i=0;i<60;i++){htmlFile=fs.readdirSync(artifacts).find(n=>n.endsWith('.html'));if(htmlFile)break;await b.delay(200);}
    assert(htmlFile);const html=fs.readFileSync(path.join(artifacts,htmlFile),'utf8');
    const result=await b.evaluate(`(()=>{const d=new DOMParser().parseFromString(${JSON.stringify(html)},'text/html');return {title:d.querySelector('h1').textContent,dialogue:Array.from(d.querySelectorAll('.dialogue')).map(e=>e.textContent),narration:Array.from(d.querySelectorAll('.narration')).map(e=>e.textContent),refs:Array.from(d.querySelectorAll('.panel')).map(e=>e.dataset.assetId),images:d.images.length,missing:d.querySelectorAll('.missing-art').length};})()`);
    assert.equal(result.title,missing.title);assert.deepEqual(result.dialogue,[missing.words]);
    assert.deepEqual(result.narration,missingCopy.panels.map(p=>p.narration));
    assert.deepEqual(result.refs,missingCopy.panels.map(p=>p.reference.asset_id));assert.equal(result.images,1);assert.equal(result.missing,1);
    await b.snapshot('recovered-missing-art-story-tablet');
  }
  assert.deepEqual(b.errors,[]);assert.equal(b.requests.filter(r=>/illustration-gateway|api\.openai\.com|api\.anthropic\.com|generativelanguage\.googleapis\.com/.test(r.url)).length,0);
  console.log('PASS: phone/tablet privacy pause/cancel/resume, real JSON backup download and image hashes, corrupt-file refusal, explicit creator mapping/cancellation, full original/story/page recovery and retry without duplicates, reload relocking. '+artifacts);
 }catch(e){await b.snapshot('failure');throw e;}finally{await b.close();await api('/auth/v1/logout?scope=local',adult.access_token,{});}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
