// Configured release at 127.0.0.1:8766; fictional Stage 5 fixtures only.
const {spawn} = require('node:child_process');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const assert = require('node:assert/strict');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

(async () => {
  const accounts = JSON.parse(fs.readFileSync('config/auth-test.local.json', 'utf8'));
  assert(accounts.every(account => account.email.endsWith('@example.invalid')));
  const fixture = JSON.parse(fs.readFileSync('config/stage5-fixture.local.json', 'utf8'));
  const artifacts = path.resolve('build/story-browser'); fs.mkdirSync(artifacts, {recursive:true});
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'imagineos-story-browser-'));
  const browser = spawn(process.env.IMAGINEOS_BROWSER_PATH || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    ['--headless=new', '--remote-debugging-port=9333', `--user-data-dir=${profile}`, '--no-first-run', 'about:blank'],
    {windowsHide:true, stdio:'ignore'});
  let ws;
  try {
    let pages;
    for(let i=0;i<60;i++){try{pages=await(await fetch('http://127.0.0.1:9333/json')).json();break;}catch{await delay(250);}}
    assert(pages, 'Browser did not start');
    ws = new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);
    await new Promise(resolve=>ws.addEventListener('open',resolve,{once:true}));
    const pending = new Map(), errors = [], requests = []; let sequence=0;
    ws.addEventListener('message', event=>{
      const message=JSON.parse(event.data);
      if(message.id){const item=pending.get(message.id);pending.delete(message.id);message.error?item.reject(message.error):item.resolve(message.result);}
      else if(message.method==='Runtime.exceptionThrown')errors.push(message.params);
      else if(message.method==='Network.requestWillBeSent' && message.params.request.url.includes('/functions/v1/illustration-gateway'))requests.push(message.params.request);
    });
    const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
    const evaluate=async expression=>(await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true})).result.value;
    const body=()=>evaluate('document.body.innerText');
    const waitFor=async text=>{for(let i=0;i<100;i++){if((await body()).includes(text))return;await delay(200);}throw Error('Missing UI: '+text+'\n'+await body());};
    const click=async(x,y)=>{await send('Input.dispatchMouseEvent',{type:'mousePressed',x,y,button:'left',clickCount:1});await send('Input.dispatchMouseEvent',{type:'mouseReleased',x,y,button:'left',clickCount:1});await delay(200);};
    const wheel=async deltaY=>{await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:190,y:450,deltaX:0,deltaY});await delay(150);};
    async function locate(expression) {
      await wheel(-15000);
      for(let i=0;i<50;i++){
        const rect=await evaluate(`(()=>{const el=${expression};if(!el)return null;const r=el.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()`);
        if(rect && rect.y>75 && rect.y<710)return rect;
        await wheel(220);
      }
      throw Error('Missing control '+expression+'\n'+await body());
    }
    const button=async label=>{const r=await locate(`Array.from(document.querySelectorAll('[role="button"],button')).find(el=>(el.innerText||el.getAttribute('aria-label')||'').startsWith(${JSON.stringify(label)}))`);await click(r.x,r.y);};
    const fieldExpression=label=>`Array.from(document.querySelectorAll('input,textarea')).find(el=>(el.getAttribute('aria-label')||'').startsWith(${JSON.stringify(label)}))`;
    const fill=async(label,value)=>{const r=await locate(fieldExpression(label));await click(r.x,r.y);
      await send('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
      await send('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
      await send('Input.insertText',{text:value});await delay(300);};
    const semantics=async()=>{await delay(3500);await evaluate("document.querySelector('flt-semantics-placeholder')?.click()");await delay(500);};
    const snapshot=async name=>{const shot=await send('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(artifacts,name+'.png'),Buffer.from(shot.data,'base64'));};
    const deviceDraft=()=>evaluate(`(()=>{const key=Object.keys(localStorage).find(key=>key.endsWith(${JSON.stringify('.story.'+fixture.latest.version_id)}));if(!key)return null;let value=JSON.parse(localStorage.getItem(key));if(typeof value==='string')value=JSON.parse(value);return value;})()`);
    await send('Runtime.enable');await send('Page.enable');await send('Network.enable');
    await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
    await send('Page.navigate',{url:'http://127.0.0.1:8766'});await semantics();
    await click(292,800);await waitFor('Create a parent account');
    await fill('Parent email',accounts[0].email);await fill('Password',accounts[0].password);
    await button('Sign in');await waitFor('Your family is ready.');
    await click(98,800);await waitFor('Save an original');
    await button('Story fixture version two');await waitFor('This saved original stays unchanged.');
    await button('Plan a story page');await waitFor('Your page starts here.');
    const dialogue='  MY Moon says: “GO!” 🌙\n\nKeep  my words.  ';
    const narration='  A quiet night.\n  ';
    await fill('Scene direction','  Jump over the moon.\n  ');
    await fill('Exact dialogue',dialogue);await fill('Exact narration',narration);
    await button('Check illustration availability');await waitFor('Illustration is turned off.');
    const posts=requests.filter(request=>request.method==='POST');assert.equal(posts.length,1);
    const payload=JSON.parse(posts[0].postData);
    assert.equal(payload.character.version_id,fixture.latest.version_id);
    assert.equal(Object.hasOwn(payload,'dialogue'),false);assert.equal(Object.hasOwn(payload,'narration'),false);
    assert.equal(JSON.stringify(payload).includes('Keep  my words'),false);
    const stored=await deviceDraft();assert.equal(stored.dialogue,dialogue);assert.equal(stored.narration,narration);
    await snapshot('story-disabled-phone');
    await send('Page.reload',{ignoreCache:true});await semantics();await waitFor('Save an original');
    await button('Story fixture version two');await button('Plan a story page');await waitFor('Your page starts here.');
    const restored=await deviceDraft();assert.equal(restored.dialogue,dialogue);assert.equal(restored.narration,narration);
    await snapshot('story-restored-phone');
    const checkField=async(label,value)=>{const r=await locate(fieldExpression(label));await click(r.x,r.y);await delay(200);assert.equal(await evaluate('document.activeElement?.value'),value);};
    await checkField('Exact dialogue',dialogue);await checkField('Exact narration',narration);
    await wheel(1200);await waitFor('Illustration is turned off.');
    assert.equal(requests.filter(request=>request.method==='POST').length,1,'disabled result was retried');
    await send('Emulation.setDeviceMetricsOverride',{width:1024,height:768,deviceScaleFactor:1,mobile:false});
    await wheel(2000);await snapshot('story-preview-tablet');
    // Clear account drafts through the actual sign-out flow.
    await click(28,28);await delay(400);await click(28,28);
    await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
    await click(292,800);await waitFor('Sign out');await button('Sign out');await waitFor('Create a parent account');
    const keys=await evaluate("Object.keys(localStorage).filter(key=>key.includes('imagineos.draft.v1.'))");
    assert.deepEqual(keys,[]);
    assert.equal(errors.length,0,'Browser runtime exceptions occurred');
    console.log('PASS: release browser sign-in -> saved-version page draft -> exact text -> hosted disabled result -> reload recovery -> tablet preview -> sign-out draft cleanup; dialogue/narration absent from network payload.');
  } finally {if(ws)ws.close();browser.kill();}
})().catch(error=>{console.error(error);process.exitCode=1;});
