// Node 24+, isolated Edge/Chromium, configured release at localhost:8766.
// Requires prepared fictional accounts (prepare_auth_fixtures.py + create SQL).
const {spawn}=require('node:child_process');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const assert=require('node:assert/strict');
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));


function photoFixture() {
  const {deflateSync}=require('node:zlib');
  const crc=buffer=>{let v=0xffffffff;for(const b of buffer){v^=b;for(let i=0;i<8;i++)v=(v>>>1)^((v&1)?0xedb88320:0);}return(v^0xffffffff)>>>0;};
  const chunk=(name,data)=>{const type=Buffer.from(name),size=Buffer.alloc(4),check=Buffer.alloc(4);size.writeUInt32BE(data.length);check.writeUInt32BE(crc(Buffer.concat([type,data])));return Buffer.concat([size,type,data,check]);};
  const width=512,height=512,pixels=Buffer.alloc((width*3+1)*height);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    let rgb=((x>>5)+(y>>5))%2?[95,120,145]:[142,98,66];
    if(x>70&&x<442&&y>55&&y<455)rgb=[248,247,245];
    const distance=((x-256)/105)**2+((y-262)/125)**2;
    if(distance<1)rgb=distance>.92?[22,22,30]:[225,35,75];
    if(((x-222)**2+(y-235)**2<11**2)||((x-290)**2+(y-235)**2<11**2))rgb=[22,22,30];
    if(y>288&&y<295&&x>220&&x<292)rgb=[22,22,30];
    const i=y*(width*3+1)+1+x*3;for(let c=0;c<3;c++)pixels[i+c]=rgb[c];
  }
  const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(width);ihdr.writeUInt32BE(height,4);ihdr[8]=8;ihdr[9]=2;
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),chunk('IDAT',deflateSync(pixels)),chunk('IEND',Buffer.alloc(0))]);
}

(async()=>{
  const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json','utf8'));
  assert(accounts.length===2&&accounts.every(a=>a.email.endsWith('@example.invalid')));
  const config=JSON.parse(fs.readFileSync('config/supabase.local.json','utf8'));
  assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');
  const login=async account=>{const response=await fetch(config.SUPABASE_URL+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'},body:JSON.stringify(account)});assert.equal(response.status,200);return response.json();};
  const session=await login(accounts[0]),other=await login(accounts[1]);
  const headers={apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${session.access_token}`};
  const otherHeaders={apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${other.access_token}`};
  let response=await fetch(config.SUPABASE_URL+'/rest/v1/families?select=id',{headers});
  const family=(await response.json())[0];
  response=await fetch(config.SUPABASE_URL+'/rest/v1/child_profiles',{method:'POST',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify({family_id:family.id,nickname:'Fictional artist'})});assert.equal(response.status,201);
  const profile=fs.mkdtempSync(path.join(os.tmpdir(),'imagineos-drawing-browser-'));
  const characterName='Drawn friend '+Date.now().toString(36),photoName='Photo friend '+Date.now().toString(36);
  const originalPath=path.join(profile,'fictional-photo.png');
  const photo=photoFixture();fs.writeFileSync(originalPath,photo);
  const browser=spawn(process.env.IMAGINEOS_BROWSER_PATH || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    ['--headless=new','--remote-debugging-port=9333',`--user-data-dir=${profile}`,'--no-first-run','about:blank'],
    {windowsHide:true,stdio:'ignore'});
  let ws;
  try {
    let pages;
    for(let i=0;i<60;i++){try {pages=await(await fetch('http://127.0.0.1:9333/json')).json();break;}catch {await delay(250);}}
    assert(pages,'Browser did not start');
    ws=new WebSocket(pages.find(page=>page.type==='page').webSocketDebuggerUrl);
    await new Promise(resolve=>ws.addEventListener('open',resolve,{once:true}));
    let sequence=0,chooser=null;
    const pending=new Map(),errors=[];
    ws.addEventListener('message',event=>{
      const message=JSON.parse(event.data);
      if(message.id){const request=pending.get(message.id);pending.delete(message.id);message.error?request.reject(message.error):request.resolve(message.result);}
      else if(message.method==='Runtime.exceptionThrown')errors.push(message.params);
      else if(message.method==='Page.fileChooserOpened')chooser=message.params;
    });
    const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
    const evaluate=async expression=>(await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true})).result.value;
    const body=()=>evaluate('document.body.innerText');
    const waitFor=async text=>{for(let i=0;i<80;i++){if((await body()).includes(text))return;await delay(250);}throw Error('Missing UI state: '+text+'\n'+await body());};
    const click=async(x,y)=>{await send('Input.dispatchMouseEvent',{type:'mousePressed',x,y,button:'left',clickCount:1});await send('Input.dispatchMouseEvent',{type:'mouseReleased',x,y,button:'left',clickCount:1});await delay(300);};
    const wheel=async deltaY=>{await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:190,y:500,deltaX:0,deltaY});await delay(250);};
    const locate=async expression=>{
      await wheel(-10000);
      for(let i=0;i<24;i++){
        const rect=await evaluate(`(()=>{const el=${expression};if(!el)return null;const r=el.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()`);
        const limit=await evaluate(`innerHeight-(document.body.innerText.includes('For parents')?108:12)`);
        if(rect && rect.y>8 && rect.y<limit)return rect;
        await wheel(250);
      }
      throw Error('Control not visible: '+expression+'\n'+await body());
    };
    const button=async label=>{
      const rect=await locate(`Array.from(document.querySelectorAll('[role="button"],[role="radio"],[role="checkbox"],button')).find(el=>(el.innerText || el.getAttribute('aria-label') || '').startsWith(${JSON.stringify(label)}))`);
      await click(rect.x,rect.y);
    };
    const fill=async(label,value)=>{
      const rect=await locate(`document.querySelector('input[aria-label=${JSON.stringify(label)}]')`);
      await click(rect.x,rect.y);
      await send('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
      await send('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
      await send('Input.insertText',{text:value});await delay(200);
    };
    const snapshot=async name=>{const result=await send('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(os.tmpdir(),`imagineos-${name}.png`),Buffer.from(result.data,'base64'));};
    const waitImage=async name=>{
      for(let i=0;i<80;i++){
        if(await evaluate(`Array.from(document.querySelectorAll('[aria-label]')).some(el=>(el.getAttribute('aria-label') || '').startsWith(${JSON.stringify('Original drawing for '+name+', version ')}))`))return;
        await delay(250);
      }
      throw Error('Original image not rendered: '+await body());
    };
    const choose=async file=>{
      chooser=null;await button('Choose drawing');
      for(let i=0;i<30 && !chooser;i++)await delay(100);
      assert(chooser?.backendNodeId,'No intercepted file input');
      await send('DOM.setFileInputFiles',{files:[file],backendNodeId:chooser.backendNodeId});
      for(let i=0;i<40;i++){if((await body()).includes('Image selection ready.'))return;await wheel(1500);}
      throw Error('Image selection did not complete: '+await body());
    };
    const activateSemantics=async()=>{await delay(5000);await evaluate("document.querySelector('flt-semantics-placeholder')?.click()");await delay(800);};

    const canvasRect=async()=>{
      await wheel(-10000);
      for(let i=0;i<80;i++){
        const rect=await evaluate(`(()=>{const el=Array.from(document.querySelectorAll('flt-semantics')).find(el=>el.firstElementChild?.tagName==='SPAN'&&el.textContent.startsWith('Drawing canvas.'));if(!el)return null;const r=el.getBoundingClientRect();const size=Math.min(r.width-24,r.height-24);return {x:r.x+(r.width-size)/2,y:r.y+(r.height-size)/2,width:size,height:size};})()`);
        if(rect&&rect.width>0&&rect.height>0)return rect;
        await delay(200);
      }
      await snapshot('drawing-canvas-locator');
      throw Error('Drawing canvas not available: '+await body()+'\n'+await evaluate(`Array.from(document.querySelectorAll('*')).filter(el=>el.textContent?.startsWith('Drawing canvas.')||el.getAttribute('aria-label')?.startsWith('Drawing canvas.')).slice(-8).map(el=>el.outerHTML.slice(0,2200)).join('\\n')`));
    };
    const stroke=async points=>{
      const rect=await canvasRect();
      const at=p=>({x:rect.x+p[0]*rect.width,y:rect.y+p[1]*rect.height});
      const first=at(points[0]);
      await send('Input.dispatchMouseEvent',{type:'mousePressed',...first,button:'left',buttons:1,clickCount:1});
      for(const point of points.slice(1)){await send('Input.dispatchMouseEvent',{type:'mouseMoved',...at(point),button:'left',buttons:1});await delay(35);}
      await send('Input.dispatchMouseEvent',{type:'mouseReleased',...at(points.at(-1)),button:'left',buttons:0,clickCount:1});
      await delay(800);
    };
    const reload=async()=>{await send('Page.reload',{ignoreCache:true});await activateSemantics();await waitFor('Save an original');};
    const saved=async()=>{for(let i=0;i<60;i++){if((await body()).includes('Original saved. You can reopen it below.'))return;await wheel(1500);}throw Error('Save did not finish: '+await body());};
    const rows=async name=>{const r=await fetch(config.SUPABASE_URL+'/rest/v1/original_uploads?state=eq.ready&select=*',{headers});assert.equal(r.status,200);return(await r.json()).filter(row=>row.name===name);};
    const download=async row=>{const r=await fetch(config.SUPABASE_URL+'/storage/v1/object/character-originals/'+row.object_path+'?cacheBust='+Date.now(),{headers});assert.equal(r.status,200);return Buffer.from(await r.arrayBuffer());};
    const inspect=async bytes=>evaluate(`(async()=>{const raw=atob(${JSON.stringify(bytes.toString('base64'))});const data=Uint8Array.from(raw,c=>c.charCodeAt(0));const bitmap=await createImageBitmap(new Blob([data],{type:'image/png'}));const canvas=document.createElement('canvas');canvas.width=bitmap.width;canvas.height=bitmap.height;const ctx=canvas.getContext('2d');ctx.drawImage(bitmap,0,0);const p=ctx.getImageData(0,0,canvas.width,canvas.height).data;let painted=0;for(let i=3;i<p.length;i+=4)if(p[i])painted++;const center=(Math.floor(canvas.height/2)*canvas.width+Math.floor(canvas.width/2))*4;return{width:canvas.width,height:canvas.height,corner:p[3],painted,center:Array.from(p.slice(center,center+4))};})()`);
    await send('Runtime.enable');await send('Page.enable');
    await send('Page.setInterceptFileChooserDialog',{enabled:true});
    await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
    await send('Page.navigate',{url:'http://127.0.0.1:8766'});await activateSemantics();
    await click(292,800);await waitFor('Create a parent account');
    await fill('Parent email',accounts[0].email);await fill('Password',accounts[0].password);
    await button('Sign in');await waitFor('Unlock parent settings');
    await click(98,800);await waitFor('Save an original');
    await button('Draw a character');await waitFor('Drawing studio');
    console.log('Checking phone drawing and editable reload recovery.');
    await stroke([[.3,.4],[.35,.32],[.42,.3],[.5,.35],[.58,.3],[.65,.32],[.7,.4],[.65,.65],[.5,.7],[.35,.65],[.3,.4]]);
    await waitFor('Draft kept on this device.');await snapshot('drawing-studio-phone');
    await reload();await button('Draw a character');await waitFor('Device draft restored.');
    await button('Use drawing');await waitFor('Drawing ready.');
    await fill('Character name',characterName);await delay(600);
    await reload();await waitFor('Drawing selection restored.');
    await button('Save character');await saved();
    await wheel(-10000);await snapshot('library-new-theme-phone');
    console.log('Checking cloud drawing bytes and original-photo extraction.');
    const drawn=(await rows(characterName))[0];assert(drawn,'Drawn character missing');
    const painted=await inspect(await download(drawn));assert.equal(painted.width,1024);assert.equal(painted.corner,0);assert(painted.painted>100);
    await button(characterName);await waitImage(characterName);await button('Back');
    await fill('Character name',photoName);await choose(originalPath);
    await button('Save original and open studio');await waitFor('Drawing studio');
    await send('Emulation.setDeviceMetricsOverride',{width:1024,height:768,deviceScaleFactor:1,mobile:false});await delay(500);
    await button('Remove paper background');await waitFor('Review extracted drawing');await snapshot('paper-extraction-review');
    await button('Use extraction');await waitFor('Draft kept on this device.');
    await button('Outline cutout');
    await stroke([[.27,.25],[.73,.25],[.77,.5],[.73,.79],[.27,.79],[.23,.5],[.27,.25]]);
    await waitFor('Review extracted drawing');await snapshot('busy-photo-outline-review');await button('Use extraction');
    await waitFor('Draft kept on this device.');
    await button('Pan');await button('Zoom in');await snapshot('drawing-studio-tablet-zoom');await button('Fit canvas');
    await button('Use drawing');await waitFor('Add a new version');await button('Save new version');await saved();
    console.log('Checking preserved photo, extracted version, and account cleanup.');
    await reload();await button(photoName);await waitImage(photoName);
    const versions=(await rows(photoName)).sort((a,b)=>a.version_number-b.version_number);
    assert.equal(versions.length,2);assert.equal(versions[0].character_id,versions[1].character_id);
    assert.deepEqual(await download(versions[0]),photo,'Uploaded photo changed');
    const extracted=await inspect(await download(versions[1]));assert.equal(extracted.corner,0);assert(extracted.painted>1000);assert.equal(extracted.center[0],225);
    const foreign=await fetch(config.SUPABASE_URL+'/storage/v1/object/character-originals/'+versions[1].object_path+'?cacheBust='+Date.now(),{headers:otherHeaders});assert(foreign.status>=400);
    await button('Back');
    await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});await delay(300);
    await button('Draw a character');await waitFor('Drawing studio');await stroke([[.3,.3],[.6,.6]]);await waitFor('Draft kept on this device.');
    await button('Keep draft and return');await waitFor('Save an original');
    assert(await evaluate(`Object.keys(localStorage).some(k=>k.includes('imagineos.draft.v1.'))`));
    await click(292,800);await button('Sign out');await waitFor('Create a parent account');
    for(let i=0;i<40;i++){if(!await evaluate(`Object.keys(localStorage).some(k=>k.includes('imagineos.draft.v1.'))`))break;await delay(100);}
    assert.equal(await evaluate(`Object.keys(localStorage).some(k=>k.includes('imagineos.draft.v1.'))`),false,'Sign-out retained a drawing draft');
    assert.equal(errors.length,0,JSON.stringify(errors));
    console.log('PASS: blank drawing, local reload recovery, restored PNG selection, cloud save/reopen, original photo preservation, paper extraction, busy-background outline, transparent derivative version, family isolation, canvas zoom, and sign-out draft cleanup.');
  } finally {if(ws)ws.close();browser.kill();}
})().catch(error=>{console.error(error);process.exitCode=1;});
