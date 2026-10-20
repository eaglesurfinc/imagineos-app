const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {browserSession}=require('./support/browser_session.cjs');
const {pathToFileURL}=require('node:url');
(async()=>{
 const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json','utf8'));
 const fixture=JSON.parse(fs.readFileSync('config/stage5-fixture.local.json','utf8'));
 assert(accounts.every(a=>a.email.endsWith('@example.invalid')));
 const artifacts=path.resolve('build/story-project-browser',Date.now().toString(36));
 const b=await browserSession(artifacts);
 try {
  await b.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
  await b.send('Page.navigate',{url:'http://127.0.0.1:8766'});await b.semantics();
  await b.waitFor('Parent sign-in');await b.control('Parent sign-in');await b.waitFor('Create a parent account');
  await b.fill('Parent email',accounts[0].email);await b.fill('Password',accounts[0].password);
  await b.control('Sign in');await b.waitFor('Unlock parent settings');
  await b.fill('Parent password',accounts[0].password);await b.control('Unlock parent settings');await b.control('Review family creations');await b.waitFor('Save an original');
  await b.control('My stories');await b.waitFor('Your characters. Your story.');
  await b.control('Start my story');await b.control('Fictional story creator');
  await b.waitFor('You are the creator.');
  const title='  My own “story” 🌈  ',scene='  Jon walks down my street.\n ',dialogue='  My  EXACT words 🌈\n\n<script>keep this text</script>  ',narration='  I choose what comes next.\n ';
  assert.equal(await b.evaluate(`(${b.field('Your story title')})?.value`),'');
  await b.control('Comic pages');await b.fill('Your story title',title);
  await b.control('Next step');await b.control('Add panel');await b.control(fixture.first.name+' — version 1');
  await b.control('Add panel');await b.control(fixture.first.name+' — version 1');
  await b.control('Next step');
  for(const label of ['What happens here?','What is said?','Other words for the reader']){
    const r=await b.locate(b.field(label));await b.click(r.x,r.y);
    assert.equal(await b.evaluate('document.activeElement?.value'),'','Guidance must never supply content');
  }
  await b.fill('What happens here?',scene);await b.fill('What is said?',dialogue);await b.fill('Other words for the reader',narration);
  await b.snapshot('child-words-phone');
  await b.control('Next step');await b.control('Move panel 2 earlier');
  await b.control('Remove panel 1');await b.control('Keep it');
  await b.control('Next step');await b.waitFor('Original-artwork draft.');
  await b.control('Save story');await b.waitFor('Your story is saved. Your words stay exactly yours.');
  await b.control('Download printable story');await b.waitFor('Printable story download requested.');
  let exported;
  for(let i=0;i<40;i++){exported=fs.readdirSync(artifacts).find(n=>n.endsWith('.html'));if(exported)break;await b.delay(200);}
  assert(exported,'No story HTML download');
  const html=fs.readFileSync(path.join(artifacts,exported),'utf8');
  const read=await b.evaluate(`(()=>{const doc=new DOMParser().parseFromString(${JSON.stringify(html)},'text/html');return {title:doc.querySelector('h1').textContent,words:Array.from(doc.querySelectorAll('.words')).map(e=>e.textContent),refs:Array.from(doc.querySelectorAll('.panel')).map(e=>e.dataset.versionId),images:doc.querySelectorAll('img').length};})()`);
  assert.equal(read.title,title);assert.deepEqual(read.words,[dialogue,narration]);
  assert.deepEqual(read.refs,[fixture.first.version_id,fixture.first.version_id]);assert.equal(read.images,2);
  const workspace=async()=>b.evaluate(`(()=>{const key=Object.keys(localStorage).find(k=>k.endsWith('.story-project.workspace'));if(!key)return null;let value=JSON.parse(localStorage.getItem(key));if(typeof value==='string')value=JSON.parse(value);return value.story;})()`);
  let story=await workspace();const id=story.id;
  assert.equal(story.panels[0].dialogue,dialogue);assert.equal(story.panels[1].dialogue,'');
  await b.control('1. Choose a layout');await b.control('Comic strips');await b.control('Save for later');
  await b.waitFor('Your story is saved.');
  story=await workspace();assert.equal(story.format,'strip');assert.equal(story.panels[0].dialogue,dialogue);assert.equal(story.panels[0].scene,scene);
  await b.control('5. Read, save and print');
  await b.send('Emulation.setDeviceMetricsOverride',{width:1024,height:900,deviceScaleFactor:1,mobile:false});
  await b.wheel(420);await b.snapshot('comic-strip-tablet');
  await b.control('1. Choose a layout');await b.control('Illustrated pages');await b.control('Save for later');await b.waitFor('Your story is saved.');
  await b.control('5. Read, save and print');await b.wheel(400);await b.snapshot('illustrated-pages-tablet');
  // Reopen from cloud, with the device working copy explicitly removed by the test.
  await b.evaluate("Object.keys(localStorage).filter(k=>k.endsWith('.story-project.workspace')).forEach(k=>localStorage.removeItem(k))");
  await b.send('Page.reload',{ignoreCache:true});await b.semantics();
  await b.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
  await b.control('Parent sign-in');await b.waitFor('Unlock parent settings');await b.fill('Parent password',accounts[0].password);await b.control('Unlock parent settings');await b.control('Review family creations');await b.waitFor('Save an original');await b.control('My stories');await b.waitFor(title.trim());
  // Read story cards instead of relying on sort order alongside API fixtures.
  const open=await b.locate(`Array.from(document.querySelectorAll('[role="button"],button')).find(el=>(el.innerText||el.getAttribute('aria-label')||'').startsWith('Open story'))`);
  await b.click(open.x,open.y);await b.waitFor('You are the creator.');
  story=await workspace();assert.equal(story.id,id);assert.equal(story.format,'illustrated');
  assert.equal(story.title,title);assert.equal(story.panels[0].dialogue,dialogue);assert.equal(story.panels[0].reference.version_id,fixture.first.version_id);
  await b.control('3. Tell it your way');
  const r=await b.locate(b.field('What is said?'));await b.click(r.x,r.y);assert.equal(await b.evaluate('document.activeElement?.value'),dialogue);
  await b.snapshot('cloud-story-reopened-phone');
  // No generation or external provider request belongs to this independent flow.
  assert.equal(b.requests.filter(r=>/illustration-gateway|api\.openai\.com|api\.anthropic\.com|generativelanguage\.googleapis\.com/.test(r.url)).length,0);
  await b.click(28,28);await b.waitFor('Your characters. Your story.');await b.click(28,28);
  await b.click(28,28);await b.control('Sign out');await b.waitFor('Create a parent account');
  assert.deepEqual(await b.evaluate("Object.keys(localStorage).filter(k=>k.includes('imagineos.draft.v1.'))"),[]);
  await b.send('Emulation.setDeviceMetricsOverride',{width:1024,height:900,deviceScaleFactor:1,mobile:false});
  await b.send('Page.navigate',{url:pathToFileURL(path.join(artifacts,exported)).href});await b.delay(800);
  const standalone=await b.evaluate("({words:Array.from(document.querySelectorAll('.words')).map(e=>e.textContent),images:Array.from(document.images).every(i=>i.complete&&i.naturalWidth>0),fits:document.documentElement.scrollWidth<=innerWidth})");
  assert.deepEqual(standalone.words,[dialogue,narration]);assert(standalone.images);assert(standalone.fits);
  await b.snapshot('standalone-comic-export');
  const print=await b.send('Page.printToPDF',{printBackground:true,preferCSSPageSize:true});
  fs.writeFileSync(path.join(artifacts,'browser-print-verification.pdf'),Buffer.from(print.data,'base64'));
  assert.equal(b.errors.length,0,'Uncaught browser exception');
  console.log('PASS: blank child guidance -> reusable pinned character -> exact words -> explicit reorder/remove cancellation -> all three formats -> cloud save/reopen -> real printable HTML download -> phone/tablet -> sign-out recovery cleanup. Zero provider/gateway requests. Artifacts: '+artifacts);
 } catch(error) {
   await b.snapshot('failure').catch(()=>{});
   fs.writeFileSync(path.join(artifacts,'failure.json'),JSON.stringify({body:await b.body(),errors:b.errors,dom:await b.evaluate('document.body.innerHTML.slice(0,4000)')},null,2));
   throw error;
 } finally {await b.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
