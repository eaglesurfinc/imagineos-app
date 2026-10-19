// Node 24+, isolated Edge/Chromium, OFFLINE release at localhost:8766.
// No backend accounts or real artwork. PNG artifacts go to ignored build/.
const {spawn}=require('node:child_process');
const {createHash}=require('node:crypto');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const assert=require('node:assert/strict');
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));

function photoFixture(noisy=false) {
  const {deflateSync}=require('node:zlib');
  const crc=buffer=>{let v=0xffffffff;for(const b of buffer){v^=b;for(let i=0;i<8;i++)v=(v>>>1)^((v&1)?0xedb88320:0);}return(v^0xffffffff)>>>0;};
  const chunk=(name,data)=>{const type=Buffer.from(name),size=Buffer.alloc(4),check=Buffer.alloc(4);size.writeUInt32BE(data.length);check.writeUInt32BE(crc(Buffer.concat([type,data])));return Buffer.concat([size,type,data,check]);};
  const width=512,height=512,pixels=Buffer.alloc((width*3+1)*height);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    let rgb=[248,247,245];
    if(noisy){const shade=Math.round(20*x/511+12*y/511),noise=((x*17+y*31)%13)-6;rgb=[235-shade+noise,225-shade+noise,203-shade+noise];}
    if(y===100 && x>40 && x<470)rgb=[235,234,232];
    if(noisy&&y===100&&x>40&&x<470){const shade=Math.round(20*x/511+12*y/511);rgb=[205-shade,195-shade,173-shade];}
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
  const profile=fs.mkdtempSync(path.join(os.tmpdir(),'imagineos-precision-browser-'));
  const downloads=path.resolve('build/drawing-browser-downloads',Date.now().toString(36));
  fs.mkdirSync(downloads,{recursive:true});
  const browser=spawn(process.env.IMAGINEOS_BROWSER_PATH || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
      ['--headless=new','--remote-debugging-port=9334',`--user-data-dir=${profile}`,'--no-first-run','about:blank'],
      {windowsHide:true,stdio:'ignore'});
  let ws;
  try {
    let pages;
    for(let i=0;i<60;i++){try {pages=await(await fetch('http://127.0.0.1:9334/json')).json();break;}catch{await delay(250);}}
    assert(pages,'Browser did not start');
    ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);
    await new Promise(resolve=>ws.addEventListener('open',resolve,{once:true}));
    let sequence=0;const pending=new Map(),errors=[];
    ws.addEventListener('message',event=>{
      const message=JSON.parse(event.data);
      if(message.id){const request=pending.get(message.id);pending.delete(message.id);message.error?request.reject(message.error):request.resolve(message.result);}
      else if(message.method==='Runtime.exceptionThrown')errors.push(message.params);
    });
    const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
    const evaluate=async expression=>{const result=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));return result.result.value;};
    const body=()=>evaluate("document.body.innerText+'\\n'+Array.from(document.querySelectorAll('[aria-label]')).map(el=>el.getAttribute('aria-label')).join('\\n')");
    const waitFor=async text=>{for(let i=0;i<100;i++){if((await body()).includes(text))return;await delay(200);}throw Error('Missing UI state: '+text+'\n'+await body());};
    const click=async(x,y)=>{await send('Input.dispatchMouseEvent',{type:'mousePressed',x,y,button:'left',clickCount:1});await send('Input.dispatchMouseEvent',{type:'mouseReleased',x,y,button:'left',clickCount:1});await delay(250);};
    const wheel=async deltaY=>{
      const dialog=(await body()).includes('Review extracted drawing')||(await body()).includes('Connect your drawing pen')||(await body()).includes('Canvas text');
      const x=dialog?await evaluate('innerWidth/2'):140;
      await send('Input.dispatchMouseEvent',{type:'mouseWheel',x,y:500,deltaX:0,deltaY});await delay(180);
    };
    const button=async label=>{
      await wheel(-10000);
      for(let i=0;i<28;i++){
        const rect=await evaluate(`(()=>{const el=Array.from(document.querySelectorAll('[role="button"],[role="checkbox"],[role="switch"],button')).find(el=>(el.innerText || el.getAttribute('aria-label') || '').startsWith(${JSON.stringify(label)}));if(!el)return null;const r=el.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};})()`);
        if(rect&&rect.y>8&&rect.y<730){await click(rect.x,rect.y);return;}
        await wheel(240);
      }
      throw Error('Control not visible: '+label+'\n'+await body());
    };
    const snapshot=async label=>{const r=await send('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(downloads,label+'.png'),Buffer.from(r.data,'base64'));};
    const canvas=async()=>{
      await wheel(-10000);
      const rect=await evaluate(`(()=>{const el=Array.from(document.querySelectorAll('flt-semantics')).find(el=>el.firstElementChild?.tagName==='SPAN'&&el.textContent.startsWith('Drawing canvas.'));if(!el)return null;const r=el.getBoundingClientRect();const size=Math.min(r.width-24,r.height-24);return{x:r.x+(r.width-size)/2,y:r.y+(r.height-size)/2,width:size,height:size};})()`);
      assert(rect&&rect.width>0,'Missing canvas: '+await body());return rect;
    };
    const stroke=async(points,pen=false)=>{
      const r=await canvas(),at=p=>({x:r.x+p[0]*r.width,y:r.y+p[1]*r.height});
      const kind=pen?{pointerType:'pen'}:{};
      await send('Input.dispatchMouseEvent',{type:'mousePressed',...at(points[0]),...kind,force:.25,button:'left',buttons:1,clickCount:1});
      for(const p of points.slice(1)){await send('Input.dispatchMouseEvent',{type:'mouseMoved',...at(p),...kind,force:.75,button:'left',buttons:1});await delay(30);}
      await send('Input.dispatchMouseEvent',{type:'mouseReleased',...at(points.at(-1)),...kind,button:'left',buttons:0,clickCount:1});await delay(900);
    };
    const key='imagineos.draft.v1.'+createHash('sha256').update('offline').digest('hex')+'.new';
    const draft=()=>evaluate(`JSON.parse(JSON.parse(localStorage.getItem(${JSON.stringify(key)})))`);
    const open=async document=>{
      if(document)await evaluate(`localStorage.setItem(${JSON.stringify(key)},JSON.stringify(JSON.stringify(${JSON.stringify(document)})))`);
      await send('Page.navigate',{url:'http://127.0.0.1:8766'});await delay(4500);
      for(let i=0;i<50;i++){
        await evaluate("document.querySelector('flt-semantics-placeholder')?.click()");
        if((await body()).includes('Try drawing studio'))break;
        await delay(200);
      }
      await button('Try drawing studio');await waitFor('Drawing studio');await delay(600);
    };
    const inspect=async(base,points)=>evaluate(`(async()=>{const raw=atob(${JSON.stringify(base)});const bitmap=await createImageBitmap(new Blob([Uint8Array.from(raw,c=>c.charCodeAt(0))],{type:'image/png'}));const c=document.createElement('canvas');c.width=bitmap.width;c.height=bitmap.height;const ctx=c.getContext('2d');ctx.drawImage(bitmap,0,0);return ${JSON.stringify(points)}.map(([x,y])=>Array.from(ctx.getImageData(x,y,1,1).data));})()`);
    const checkCanvasText=async()=>{
    console.log('Checking editable exact canvas text and colors.');
    await button('Text');await stroke([[.15,.15]]);await waitFor('Canvas text');
    const textRect=await evaluate("(()=>{const el=document.querySelector('textarea')||Array.from(document.querySelectorAll('input')).find(el=>(el.getAttribute('aria-label')||'').startsWith('Your exact text'));const r=el.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};})()");
    await click(textRect.x,textRect.y);await send('Input.insertText',{text:'  Hello Moon!\nKeep my words.  '});
    await button('Text color E4475D');await snapshot('canvas-text-fonts');await button('Place text');await delay(1200);
    let item=(await draft()).frame.strokes.at(-1);
    assert.equal(item.tool,'text');assert.equal(item.text,'  Hello Moon!\nKeep my words.  ');assert.equal(item.color,0xffe4475d);assert.equal(item.font_family,'Nunito');
    await stroke([[.15,.15]]);await waitFor('Canvas text');
    await wheel(-10000);
    const fontRect=await evaluate("(()=>{const el=Array.from(document.querySelectorAll('[role=button]')).find(el=>(el.innerText||el.getAttribute('aria-label')||'').includes('Nunito - Rounded'));if(!el)return null;const r=el.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};})()");
    assert(fontRect,'Font picker not exposed');await click(fontRect.x,fontRect.y);await snapshot('canvas-font-menu');await waitFor('Caveat - Cursive');
    const choice=await evaluate("(()=>{const el=Array.from(document.querySelectorAll('flt-semantics')).find(el=>(el.innerText||el.getAttribute('aria-label')||'').trim()==='Caveat - Cursive');if(!el)return null;const r=el.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};})()");
    assert(choice,'Caveat choice missing');await click(choice.x,choice.y);
    await button('Text color 3E80D6');await button('Place text');await delay(1200);
    item=(await draft()).frame.strokes.at(-1);assert.equal(item.text,'  Hello Moon!\nKeep my words.  ');assert.equal(item.color,0xff3e80d6);assert.equal(item.font_family,'Caveat');
    await snapshot('canvas-text-color');
    };
    const photo=photoFixture().toString('base64');
    const document={schema:1,width:512,height:512,frame:{base:photo,strokes:[],background:0}};
    await send('Runtime.enable');await send('Page.enable');
    await send('Browser.setDownloadBehavior',{behavior:'allow',downloadPath:downloads});
    await send('Emulation.setDeviceMetricsOverride',{width:1024,height:768,deviceScaleFactor:1,mobile:false});
    await send('Page.navigate',{url:'http://127.0.0.1:8766'});await delay(1500);
    if(process.argv.includes('--text-only')){await open({schema:1,width:1024,height:1024,frame:{base:null,strokes:[],background:0}});await checkCanvasText();assert.equal(errors.length,0,JSON.stringify(errors));console.log('PASS: exact canvas text, palette colors, font selection and editable updates. Artifacts: '+downloads);return;}
    await open(document);
    console.log('Checking adaptive extraction and original comparison.');
    await button('Remove paper background');await waitFor('Review extracted drawing');
    await button('Compare original');await button('Compare original');
    await snapshot('paper-line-review');await button('Use extraction');await delay(1400);
    let pixels=await inspect((await draft()).frame.base,[[2,2],[100,100],[256,262]]);
    assert.equal(pixels[0][3],0);assert.equal(pixels[1][0],235);assert.equal(pixels[1][3],255);assert.equal(pixels[2][0],225);
    console.log('Checking selection boundaries, shape clipping and undo.');
    await button('Select area');await stroke([[.05,.05],[.45,.95]]);
    await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Delete',code:'Delete',windowsVirtualKeyCode:46});
    await send('Input.dispatchKeyEvent',{type:'keyUp',key:'Delete',code:'Delete',windowsVirtualKeyCode:46});await delay(1400);
    pixels=await inspect((await draft()).frame.base,[[100,100],[256,262]]);assert.equal(pixels[0][3],0);assert.equal(pixels[1][0],225);
    await button('Undo');await delay(1100);
    pixels=await inspect((await draft()).frame.base,[[100,100]]);assert.equal(pixels[0][3],255);
    await button('Star');await stroke([[.05,.4],[.4,.8]]);
    assert.equal((await draft()).frame.strokes.at(-1).tool,'star');assert.equal((await draft()).frame.strokes.at(-1).selection.length,4);
    await button('Deselect');await button('Lasso select');await stroke([[.25,.22],[.8,.22],[.8,.84],[.25,.84],[.25,.22]]);
    await button('Keep only selection');await waitFor('Review extracted drawing');await button('Use extraction');await delay(1400);
    pixels=await inspect((await draft()).frame.base,[[10,10],[256,262]]);assert.equal(pixels[0][3],0);assert.equal(pixels[1][0],225);
    console.log('Checking connected removal review.');
    await open(document);await button('Remove area');await stroke([[.07,.07]]);await waitFor('Review extracted drawing');
    // Flutter exposes switch titles through aria-label rather than innerText.
    await button('Protect drawing edges');await delay(800);
    await button('Protect drawing edges');await delay(800);
    await snapshot('remove-area-edge-review');
    await button('Use extraction');await delay(1200);
    pixels=await inspect((await draft()).frame.base,[[10,10],[256,262]]);assert.equal(pixels[0][3],0);assert.equal(pixels[1][3],255);
    console.log('Checking warm noisy photo extraction.');
    await open({schema:1,width:512,height:512,frame:{base:photoFixture(true).toString('base64'),strokes:[],background:0}});
    await button('Remove paper background');await waitFor('Review extracted drawing');
    await snapshot('noisy-warm-paper-review');await button('Use extraction');await delay(1400);
    pixels=await inspect((await draft()).frame.base,[[20,20],[475,475],[100,100]]);
    assert.equal(pixels[0][3],0);assert.equal(pixels[1][3],0);assert.equal(pixels[2][3],255);
    const warmResult=(await draft()).frame.base;
    const missingArt=await evaluate(`(async()=>{
      async function pixels(base){const bytes=Uint8Array.from(atob(base),c=>c.charCodeAt(0));const bitmap=await createImageBitmap(new Blob([bytes],{type:'image/png'}));const c=document.createElement('canvas');c.width=bitmap.width;c.height=bitmap.height;const ctx=c.getContext('2d');ctx.drawImage(bitmap,0,0);return ctx.getImageData(0,0,c.width,c.height).data;}
      const source=await pixels(${JSON.stringify(photoFixture(true).toString('base64'))}),result=await pixels(${JSON.stringify(warmResult)});let bad=0;
      for(let i=0;i<source.length;i+=4)if(source[i]===225&&source[i+1]===35&&source[i+2]===75&&(result[i]!==225||result[i+1]!==35||result[i+2]!==75||result[i+3]!==255))bad++;
      return bad;
    })()`);
    assert.equal(missingArt,0,'cleanup damaged pixels in the colored drawing');
    console.log('Checking pen input, touch navigation, PNG device download and phone controls.');
    await open({schema:1,width:1024,height:1024,frame:{base:null,strokes:[],background:0}});
    await stroke([[.2,.3],[.4,.45],[.6,.35]],true);
    let current=await draft();assert.equal(current.frame.strokes.length,1);
    assert(current.frame.strokes[0].points.some(p=>p[2]<.9),'Pen pressure was not received');
    await button('Connect a pen');await waitFor('Connect your drawing pen');await button('Return and test pen');
    await button('Pen only');
    const r=await canvas();
    const a={x:r.x+r.width*.35,y:r.y+r.height*.5,id:1},b={x:r.x+r.width*.65,y:r.y+r.height*.5,id:2};
    await send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[a]});
    await send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[a,b]});
    await send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{...a,x:a.x-40},{...b,x:b.x+40}]});
    await send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await delay(700);
    assert.equal((await draft()).frame.strokes.length,1,'Pinch painted a stray stroke');
    await snapshot('tablet-pen-touch');await button('Fit canvas');
    await button('Save to device');
    let saved;
    for(let i=0;i<100;i++){saved=fs.readdirSync(downloads).find(name=>name.startsWith('imagineos-drawing-')&&name.endsWith('.png'));if(saved)break;await delay(100);}
    assert(saved,'PNG download did not complete');const bytes=fs.readFileSync(path.join(downloads,saved));
    assert.equal(bytes.readUInt32BE(16),1024);assert.equal(bytes.readUInt32BE(20),1024);
    pixels=await inspect(bytes.toString('base64'),[[0,0]]);assert.equal(pixels[0][3],0);
    assert.equal((await draft()).frame.strokes.length,1,'Device save changed the editable drawing');
    await checkCanvasText();
    await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});await delay(700);
    await snapshot('phone-device-save');assert((await body()).includes('Save to device'));
    assert.equal(errors.length,0,JSON.stringify(errors));
    console.log('PASS: clean and noisy warm paper removal, comparison, keyboard selection delete/undo, shapes and lasso, edge-aware removal, browser pen pressure, touch pinch, real PNG download, and editable exact colored text.');
    console.log('Fictional screenshots and downloaded PNG: '+downloads);
  } finally {if(ws)ws.close();browser.kill();}
})().catch(error=>{console.error(error);process.exitCode=1;});
