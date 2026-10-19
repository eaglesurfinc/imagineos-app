// Node 24+, isolated Edge/Chromium, configured release at localhost:8766.
// Requires prepared fictional accounts and character_storage_smoke.mjs fixtures.
const {spawn}=require('node:child_process');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const assert=require('node:assert/strict');
const {createHash}=require('node:crypto');
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));

(async()=>{
  const accounts=JSON.parse(fs.readFileSync('config/auth-test.local.json','utf8'));
  assert(accounts[0].email.endsWith('@example.invalid'));
  const fixture=JSON.parse(fs.readFileSync('config/stage3-fixture.local.json','utf8'));
  const config=JSON.parse(fs.readFileSync('config/supabase.local.json','utf8'));
  assert.equal(config.SUPABASE_URL,'https://hgsivbqmbcliqbstrkdz.supabase.co');
  const profile=fs.mkdtempSync(path.join(os.tmpdir(),'imagineos-character-browser-'));
  const characterName='Browser friend '+Date.now().toString(36), updatedName=characterName+' updated';
  const originalPath=path.join(profile,'original.png'),revisedPath=path.join(profile,'revised.png');
  fs.writeFileSync(originalPath,Buffer.from(fixture.original,'base64'));
  fs.writeFileSync(revisedPath,Buffer.from(fixture.revised,'base64'));
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
        const detail=await evaluate(`Array.from(document.querySelectorAll('[role="button"]')).some(el=>el.innerText==='Back')`);
        if(rect && rect.y>65 && rect.y<(detail?830:735))return rect;
        await wheel(250);
      }
      throw Error('Control not visible: '+expression+'\n'+await body());
    };
    const button=async label=>{
      const rect=await locate(`Array.from(document.querySelectorAll('[role="button"],button')).find(el=>(el.innerText || el.getAttribute('aria-label') || '').startsWith(${JSON.stringify(label)}))`);
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
    await send('Runtime.enable');await send('Page.enable');
    await send('Page.setInterceptFileChooserDialog',{enabled:true});
    await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
    await send('Page.navigate',{url:'http://127.0.0.1:8766'});await activateSemantics();
    await click(292,800);await waitFor('Create a parent account');
    await fill('Parent email',accounts[0].email);await fill('Password',accounts[0].password);
    await button('Sign in');await waitFor('Your family is ready.');
    await click(98,800);await waitFor('Save an original');
    await fill('Character name',characterName);await choose(originalPath);await button('Save character');
    for(let i=0;i<40;i++){if((await body()).includes('Original saved. You can reopen it below.'))break;await wheel(1500);}
    await waitFor('Original saved. You can reopen it below.');
    await button(characterName);await waitFor('This saved original stays unchanged.');
    await waitImage(characterName);await snapshot('character-original-phone');
    await button('Add new version');await waitFor('Add a new version');
    await fill('Character name',updatedName);await choose(revisedPath);await button('Save new version');
    for(let i=0;i<40;i++){if((await body()).includes('Original saved. You can reopen it below.'))break;await wheel(1500);}
    await waitFor('Original saved. You can reopen it below.');
    await send('Page.reload',{ignoreCache:true});await activateSemantics();await waitFor('Save an original');
    await button(updatedName);await waitFor('Version 2: '+updatedName);
    await waitImage(updatedName);await snapshot('character-reopened-phone');
    await send('Emulation.setDeviceMetricsOverride',{width:1024,height:768,deviceScaleFactor:1,mobile:false});await delay(500);await snapshot('character-reopened-tablet');
    // Verify exactly what the browser saved through an independent REST read.
    const login=await fetch(config.SUPABASE_URL+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'},body:JSON.stringify(accounts[0])});
    assert.equal(login.status,200);const session=await login.json();
    const headers={apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${session.access_token}`};
    try {
      const response=await fetch(config.SUPABASE_URL+'/rest/v1/original_uploads?state=eq.ready&select=*',{headers});assert.equal(response.status,200);
      const rows=(await response.json()).filter(row=>[characterName,updatedName].includes(row.name));
      assert.equal(rows.length,2);assert.equal(rows[0].character_id,rows[1].character_id);
      for(const row of rows){
        const image=await fetch(config.SUPABASE_URL+'/storage/v1/object/character-originals/'+row.object_path,{headers});assert.equal(image.status,200);
        const actual=Buffer.from(await image.arrayBuffer());
        assert.deepEqual(actual,Buffer.from(row.version_number===1?fixture.original:fixture.revised,'base64'));
        assert.equal(createHash('sha256').update(actual).digest('hex'),row.sha256);
      }
      if (process.argv.includes('--delete')) {
        await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
        await button('Delete selected version');await waitFor('Delete version 2?');
        await snapshot('character-delete-version-confirm');
        await button('Cancel');
        let check=await fetch(config.SUPABASE_URL+'/rest/v1/original_uploads?character_id=eq.'+rows[0].character_id,{headers});
        assert.equal((await check.json()).length,2,'Cancel deleted artwork');
        await button('Delete selected version');await button('Delete permanently');
        for(let i=0;i<40;i++){if((await body()).includes('Deletion complete.'))break;await wheel(1500);}
        await waitFor('Deletion complete.');
        await send('Page.reload',{ignoreCache:true});await activateSemantics();
        await button(characterName);await waitImage(characterName);
        check=await fetch(config.SUPABASE_URL+'/rest/v1/original_uploads?character_id=eq.'+rows[0].character_id,{headers});
        const remaining=await check.json();assert.equal(remaining.length,1);assert.equal(remaining[0].version_number,1);
        const deleted=rows.find(row=>row.version_number===2);
        let image=await fetch(config.SUPABASE_URL+'/storage/v1/object/character-originals/'+deleted.object_path+'?cacheBust='+Date.now(),{headers});
        assert(image.status>=400,'Deleted version file remains accessible');
        await button('Delete character');await waitFor('Delete character?');
        await snapshot('character-delete-whole-confirm');await button('Delete permanently');
        for(let i=0;i<40;i++){if((await body()).includes('Deletion complete.'))break;await wheel(1500);}
        await waitFor('Deletion complete.');
        await send('Page.reload',{ignoreCache:true});await activateSemantics();
        check=await fetch(config.SUPABASE_URL+'/rest/v1/original_uploads?character_id=eq.'+rows[0].character_id,{headers});
        assert.deepEqual(await check.json(),[],'Deleted character reappeared');
        image=await fetch(config.SUPABASE_URL+'/storage/v1/object/character-originals/'+remaining[0].object_path+'?cacheBust='+Date.now(),{headers});
        assert(image.status>=400,'Deleted character file remains accessible');
        console.log('PASS: browser cancellation, selected-version removal, reopening older version after reload, whole-character removal, and independent REST/Storage cleanup checks.');
      }
    } finally {await fetch(config.SUPABASE_URL+'/auth/v1/logout?scope=local',{method:'POST',headers});}
    assert.equal(errors.length,0,'Browser runtime exceptions occurred');
    console.log('PASS: real file picker → upload/save → reopen → intentional new version → reload; both original byte streams preserved. Phone/tablet screenshots captured; no runtime exceptions.');
  } finally {if(ws)ws.close();browser.kill();}
})().catch(error=>{console.error(error);process.exitCode=1;});
