const {spawn} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const assert = require('node:assert/strict');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

// Isolated browser; no personal cookies/profile, no visible interactive window.
async function browserSession(artifacts, port = 9334) {
  fs.mkdirSync(artifacts, {recursive: true});
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'imagineos-guided-browser-'));
  const browser = spawn(process.env.IMAGINEOS_BROWSER_PATH || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--no-first-run', 'about:blank'],
    {windowsHide: true, stdio: 'ignore'});
  let ws;
  async function close() {
    if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify({id:2147483600,method:'Browser.close'}));
    if (browser.exitCode === null) {
      const exited = new Promise(resolve => browser.once('exit', resolve));
      await Promise.race([exited, delay(5000)]);
      if (browser.exitCode === null) { browser.kill(); await Promise.race([exited,delay(2000)]); }
    }
    ws?.close();
    // Validate the absolute generated target before recursive cleanup.
    const target = path.resolve(profile), tempRoot = path.resolve(os.tmpdir());
    assert.equal(path.dirname(target), tempRoot);
    assert(path.basename(target).startsWith('imagineos-guided-browser-'));
    try { fs.rmSync(target, {recursive: true, force: true, maxRetries: 4, retryDelay: 200}); } catch {}
  }
  try {
    let pages;
    for (let i=0; i<60; i++) {
      try { pages=await(await fetch(`http://127.0.0.1:${port}/json`)).json(); break; }
      catch { await delay(250); }
    }
    assert(pages, 'Browser did not start');
    ws = new WebSocket(pages.find(p => p.type==='page').webSocketDebuggerUrl);
    await new Promise(resolve => ws.addEventListener('open', resolve, {once:true}));
    const pending = new Map(), errors = [], requests = []; let sequence=0;
    ws.addEventListener('message', event => {
      const message=JSON.parse(event.data);
      if (message.id) {
        const item=pending.get(message.id); pending.delete(message.id);
        if (!item) return;
        message.error ? item.reject(message.error) : item.resolve(message.result);
      } else if (message.method==='Runtime.exceptionThrown') errors.push(message.params);
      else if (message.method==='Network.requestWillBeSent') requests.push(message.params.request);
    });
    const send=(method,params={})=>new Promise((resolve,reject)=>{
      const id=++sequence; pending.set(id,{resolve,reject}); ws.send(JSON.stringify({id,method,params}));
    });
    const evaluate=async expression=>(await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true})).result.value;
    const body=()=>evaluate("document.body.innerText+'\\n'+Array.from(document.querySelectorAll('[aria-label]')).map(e=>e.getAttribute('aria-label')).join('\\n')");
    const waitFor=async text=>{
      for(let i=0;i<100;i++){if((await body()).includes(text))return;await delay(200);}
      throw Error('Missing UI: '+text+'\n'+await body());
    };
    const click=async(x,y)=>{
      await send('Input.dispatchMouseEvent',{type:'mouseMoved',x,y});
      await send('Input.dispatchMouseEvent',{type:'mousePressed',x,y,button:'left',clickCount:1});
      await send('Input.dispatchMouseEvent',{type:'mouseReleased',x,y,button:'left',clickCount:1});await delay(220);
    };
    const wheel=async deltaY=>{await send('Input.dispatchMouseEvent',{type:'mouseMoved',x:190,y:450});await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:190,y:450,deltaX:0,deltaY});await delay(250);};
    async function locate(expression) {
      await wheel(-20000);
      for(let i=0;i<65;i++){
        const rect=await evaluate(`(()=>{const el=${expression};if(!el)return null;const r=el.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()`);
        const bottom=await evaluate("Math.min(innerHeight-16,...Array.from(document.querySelectorAll('[role=tablist]')).map(el=>{const r=el.getBoundingClientRect();return r.height&&r.y>0?r.y:innerHeight}))");
        if(rect&&rect.y>65&&rect.y<bottom-8)return rect;
        await wheel(220);
      }
      throw Error('Missing control '+expression+'\n'+await body());
    }
    const control=async label=>{
      const quoted=JSON.stringify(label);
      const r=await locate(`Array.from(document.querySelectorAll('[role="button"],button,[role="radio"],[role="switch"],[role="checkbox"]')).find(el=>[el.innerText,el.getAttribute('aria-label')].some(text=>(text||'').trim().startsWith(${quoted})))`);
      await click(r.x,r.y);
    };
    const field=label=>`Array.from(document.querySelectorAll('input,textarea')).find(el=>(el.getAttribute('aria-label')||'').includes(${JSON.stringify(label)}))`;
    const tab=async label=>{
      for(let i=0;i<50;i++) {
        const matched=await evaluate(`(()=>{const el=Array.from(document.querySelectorAll('[role="tab"]')).find(el=>(el.getAttribute('aria-label')||'').startsWith(${JSON.stringify(label)}));if(!el)return false;el.click();return true;})()`);
        if(matched){await delay(400);return;}
        await delay(100);
      }
      throw Error('Navigation tab missing: '+label);
    };
    const fill=async(label,value)=>{
      const r=await locate(field(label));await click(r.x,r.y);
      await send('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
      await send('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
      await send('Input.insertText',{text:value});await delay(300);
    };
    const semantics=async()=>{
      for(let i=0;i<100;i++) {
        const ready=await evaluate("(()=>{const p=document.querySelector('flt-semantics-placeholder');if(p){p.click();return true;}return !!document.querySelector('flt-semantics');})()");
        if(ready) {await delay(800);return;}
        await delay(250);
      }
      throw Error('Flutter accessibility tree did not initialize');
    };
    const snapshot=async name=>{const shot=await send('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(artifacts,name+'.png'),Buffer.from(shot.data,'base64'));};
    await send('Runtime.enable');await send('Page.enable');await send('Network.enable');
    await send('Browser.setDownloadBehavior',{behavior:'allow',downloadPath:artifacts});
    return {send,evaluate,body,waitFor,click,wheel,control,fill,semantics,snapshot,locate,field,tab,errors,requests,close,delay};
  } catch(error) { await close(); throw error; }
}
module.exports={browserSession};
