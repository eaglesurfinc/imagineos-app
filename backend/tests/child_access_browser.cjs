const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {browserSession}=require('./support/browser_session.cjs');
(async()=>{
 const config=JSON.parse(fs.readFileSync('config/supabase.local.json','utf8'));
 const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json','utf8'));
 const fixture=JSON.parse(fs.readFileSync('config/stage5-fixture.local.json','utf8'));
 const childFixture=JSON.parse(fs.readFileSync('config/child-test.local.json','utf8'));
 assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');assert(accounts.every(a=>a.email.endsWith('@example.invalid')));
 async function api(route,token,body,grant){const r=await fetch(config.SUPABASE_URL+route,{method:body?'POST':'GET',
  headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'content-type':'application/json',...(token?{authorization:`Bearer ${token}`} : {}),
    ...(grant?{'x-imagineos-parent-grant':grant}:{})},body:body?JSON.stringify(body):undefined});
  const data=await r.json().catch(()=>null);assert([200,204].includes(r.status),`API status ${r.status}: ${data?.code??''}`);return data?.contract_version===1?data.data:data;}
 const adult=await api('/auth/v1/token?grant_type=password',null,{email:accounts[0].email,password:accounts[0].password});
 const grant=(await api('/functions/v1/parent-controls',adult.access_token,{action:'unlock',password:accounts[0].password})).grant;
 const manage=body=>api('/functions/v1/parent-controls',adult.access_token,body,grant);
 const artifacts=path.resolve('build/child-access-browser',Date.now().toString(36)),b=await browserSession(artifacts);
 try{
  await b.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
  await b.send('Page.navigate',{url:'http://127.0.0.1:8766'});await b.semantics();await b.waitFor('Child sign-in');
  await b.snapshot('separate-entry-phone');
  if(!process.argv.includes('--timed-only')){
  await b.control('Parent sign-in');await b.waitFor('Create a parent account');
  await b.fill('Parent email',accounts[0].email);await b.fill('Password',accounts[0].password);
  await b.control('Sign in');await b.waitFor('Unlock parent settings');
  await b.fill('Parent password',accounts[0].password);await b.control('Unlock parent settings');
  await b.control('Children and sign-in approvals');await b.waitFor('Approve next sign-in for Fictional story creator');
  await b.fill('Allowed minutes for Fictional story creator','5');
  // Leave the native numeric input before scrolling to the approval control.
  await b.click(180,28);
  await b.control('Approve next sign-in for Fictional story creator');await b.waitFor('Start child session on this device');
  const issued=b.requests.filter(r=>r.url.includes('parent-controls')&&r.postData).map(r=>{try{return JSON.parse(r.postData);}catch{return null;}}).find(v=>v?.action==='child_approve');
  assert.equal(issued?.minutes,5,'Parent-selected duration changed before approval');
  await b.snapshot('parent-approval-phone');await b.control('Start child session on this device');
  await b.waitFor('Fictional story creator’s studio');await b.waitFor('Save an original');
  assert(!(await b.body()).includes('Fictional sibling'));assert(!(await b.body()).includes('Add another creator'));
  assert(!(await b.body()).includes('AI provider accounts'));
  assert.equal(await b.evaluate(`Object.values(localStorage).some(v=>v.includes(${JSON.stringify(accounts[0].email)}))`),false,'Parent session remained on child device');
  await b.snapshot('child-library-phone');
  await b.control(fixture.latest.name);await b.waitFor('This saved original stays unchanged.');
  assert(!(await b.body()).includes('Delete character'));assert(!(await b.body()).includes('Delete selected version'));
  await b.click(28,28);await b.waitFor('Save an original');
  await b.control('My stories');await b.waitFor('Your characters. Your story.');
  assert(!(await b.body()).includes('Delete story'));
  await b.control('Open story');await b.waitFor('You are the creator.');
  const exact='  My browser words 🌈\n  ';
  await b.control('3. Tell it your way');await b.fill('What is said?',exact);
  await b.control('Save for later');await b.waitFor('Your story is saved.');
  const saved=await api('/rest/v1/story_project_snapshots?id=eq.'+childFixture.story,adult.access_token);
  assert.equal(saved[0].panels[0].dialogue,exact);
  await b.click(28,28);await b.waitFor('Your characters. Your story.');await b.click(28,28);await b.waitFor('Save an original');
  const active=(await manage({action:'child_list'})).sessions.find(s=>s.child_id===childFixture.creator);
  assert(active);await manage({action:'child_end',session_id:active.id});
  await b.waitFor('Parent approval code');assert(!(await b.body()).includes('Save an original'));
  console.log('PASS: shared-device parent approval/handoff clears parent credentials; child-only library, protected deletion/export and exact cloud story save; remote parent revocation closes the workspace.');
  }else{await b.control('Child sign-in');await b.waitFor('Parent approval code');}
  const timed=await manage({action:'child_approve',child_id:childFixture.creator,minutes:1});
  const started=Date.now();
  await b.fill('Parent approval code',timed.code);await b.control('Enter my studio');await b.waitFor('Fictional story creator’s studio');
  await b.control('Draw a character');await b.waitFor('Drawing studio');
  const exportDisabled=await b.evaluate(`(()=>{const e=Array.from(document.querySelectorAll('[role="button"],button')).find(e=>(e.innerText||e.getAttribute('aria-label')||'').startsWith('Save to device'));return !!e&&(e.getAttribute('aria-disabled')==='true'||e.disabled===true);})()`);
  assert(exportDisabled,'Child export permission was bypassed');
  await b.wheel(-20000);
  let rect;
  for(let i=0;i<30&&!rect;i++){
    rect=await b.evaluate(`(()=>{const e=Array.from(document.querySelectorAll('flt-semantics')).find(e=>e.firstElementChild?.tagName==='SPAN'&&e.textContent.startsWith('Drawing canvas.'));const r=e?.getBoundingClientRect();return r&&r.width>0&&r.height>0?{x:r.x+r.width*.4,y:r.y+r.height*.4}:null;})()`);
    if(!rect)await b.delay(100);
  }
  assert(rect,'Drawing input surface missing');
  await b.send('Input.dispatchMouseEvent',{type:'mousePressed',x:rect.x,y:rect.y,button:'left',clickCount:1});
  await b.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:rect.x+20,y:rect.y+20,button:'left',buttons:1});
  await b.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:rect.x+20,y:rect.y+20,button:'left',clickCount:1});
  await b.waitFor('Draft kept on this device.');await b.snapshot('timed-child-drawing-phone');
  console.log('Waiting for the approved one-minute browser session to end; private drawing route must close.');
  for(let i=0;i<5;i++){if((await b.body()).includes('Parent approval code'))break;await b.delay(15000);}
  await b.waitFor('Parent approval code');
  assert(Date.now()-started>=45000&&Date.now()-started<110000,'Browser did not end around the approved one-minute deadline');
  assert(!(await b.body()).includes('Drawing studio'));
  await b.send('Emulation.setDeviceMetricsOverride',{width:1024,height:900,deviceScaleFactor:1,mobile:false});
  await b.snapshot('expired-session-tablet');
  await b.fill('Parent approval code',timed.code);await b.control('Enter my studio');
  await b.waitFor('Ask your parent for a new code.');assert(!(await b.body()).includes('Save an original'));
  const next=await manage({action:'child_approve',child_id:childFixture.creator,minutes:1});
  await b.fill('Parent approval code',next.code);await b.control('Enter my studio');await b.waitFor('Save an original');
  await b.control('Draw a character');await b.waitFor('Device draft restored.');
  await b.snapshot('approved-again-draft-restored-tablet');await b.click(28,28);await b.waitFor('Save an original');
  const finish=await b.evaluate(`(()=>{const e=Array.from(document.querySelectorAll('[role="button"],button')).find(e=>(e.innerText||e.getAttribute('aria-label')||'').trim()==='Finish session');const r=e?.getBoundingClientRect();return r?{x:r.x+r.width/2,y:r.y+r.height/2}:null;})()`);
  assert(finish,'Finish session action missing');await b.click(finish.x,finish.y);await b.waitFor('Parent approval code');
  assert.deepEqual(b.errors,[]);
  assert.equal(b.requests.filter(r=>/api\.openai\.com|api\.anthropic\.com|generativelanguage\.googleapis\.com|illustration-gateway/.test(r.url)).length,0);
  console.log('PASS: separate-device one-minute approval expires automatically, closes private routes, rejects reuse and requires new parent approval; the child-scoped device drawing is recovered. '+artifacts);
 }finally{await b.close();await api('/auth/v1/logout?scope=local',adult.access_token,{});}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
