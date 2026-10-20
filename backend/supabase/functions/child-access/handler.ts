import {allowedOrigins,digest,exactKeys,readJson,uuid} from "../_shared/http.ts";
import {requestLog,type LogSink} from "../_shared/observability.ts";
type Asset={path:string;mime_type:string;sha256:string;byte_size:number;state:string};
type Dependencies={
  log?:LogSink;
  rpc(action:string,hash:string,data:Record<string,unknown>):Promise<unknown>;
  download(asset:Asset):Promise<Uint8Array>;
  upload(asset:Asset,bytes:Uint8Array):Promise<void>;
};
export class ChildDenied extends Error {}
const actions:Record<string,string[]>={login:["code","request_id","secret"],status:[],logout:[],library:[],
  stories:["offset"],save_story:["id","child_id","revision","title","format","panels"],
  reserve:["request_id","child_id","character_id","name","mime_type","byte_size","sha256"],
  download:["asset_id"],upload:["asset_id","bytes"],finish:["asset_id"],pages:["asset_id"],
  save_page:["page_id","asset_id","revision","scene","dialogue","narration"],authorize_export:[]};
const secret=/^[a-f0-9]{64}$/;
function validAsset(value:unknown):value is Asset {
  if(!value||typeof value!=="object")return false;
  const a=value as Asset;
  return typeof a.path==="string"&&/^[a-f0-9-]{36}\/[a-f0-9-]{36}$/.test(a.path)&&
    ["image/png","image/jpeg","image/webp"].includes(a.mime_type)&&secret.test(a.sha256)&&
    Number.isInteger(a.byte_size)&&a.byte_size>0&&a.byte_size<=5242880&&["pending","ready"].includes(a.state);
}
function signature(bytes:Uint8Array,mime:string) {
  return mime==="image/png" ? bytes.slice(0,8).join(",")==="137,80,78,71,13,10,26,10" :
    mime==="image/jpeg" ? bytes[0]===255&&bytes[1]===216&&bytes[2]===255 :
    new TextDecoder().decode(bytes.slice(0,4))==="RIFF"&&new TextDecoder().decode(bytes.slice(8,12))==="WEBP";
}
export function createHandler(deps:Dependencies) {
  return async(request:Request):Promise<Response>=>{
    const log=requestLog("child-access",request.method,{sink:deps.log});
    const headers=new Headers({"content-type":"application/json","cache-control":"no-store","vary":"Origin"});
    const trace=crypto.randomUUID(),origin=request.headers.get("origin");headers.set("x-trace-id",trace);
    if(origin&&allowedOrigins.has(origin)){
      headers.set("access-control-allow-origin",origin);
      headers.set("access-control-allow-headers","authorization, apikey, content-type, x-client-info, x-imagineos-child-session");
      headers.set("access-control-allow-methods","POST, OPTIONS");
    }
    const reply=(status:number,code:string,data:unknown=null)=>{
      log(status,code,trace);
      return new Response(JSON.stringify({contract_version:1,code,data,trace_id:trace}),{status,headers});
    };
    if(origin&&!allowedOrigins.has(origin))return reply(403,"ORIGIN_DENIED");
    if(request.method==="OPTIONS"){log(204,"PREFLIGHT",trace);return new Response(null,{status:204,headers});}
    if(request.method!=="POST")return reply(405,"METHOD_NOT_ALLOWED");
    let value:Record<string,unknown>,token:string;
    try {
      const body=await readJson(request,8*1024*1024);
      if(!body||typeof body.action!=="string"||!Object.hasOwn(actions,body.action)||!exactKeys(body,["action",...actions[body.action]]))throw Error();
      value=body;
      token=value.action==="login" ? value.secret as string : request.headers.get("x-imagineos-child-session")??"";
      if(!secret.test(token))return reply(401,"CHILD_APPROVAL_REQUIRED");
      if(value.action==="login"&&(typeof value.code!=="string"||!/^[a-f0-9]{32}$/.test(value.code)||
        typeof value.request_id!=="string"||!uuid.test(value.request_id)))throw Error();
      for(const key of ["asset_id","child_id","request_id","page_id","id"])
        if(key in value&&(typeof value[key]!=="string"||!uuid.test(value[key] as string)))throw Error();
      if(value.action==="upload"&&(typeof value.bytes!=="string"||value.bytes.length>6990508||
        !/^[A-Za-z0-9+/]*={0,2}$/.test(value.bytes)))throw Error();
    } catch{return reply(422,"INVALID_REQUEST");}
    try {
      const hash=await digest(token),{action,secret:_,code,...data}=value;
      if(action==="login")data.code_hash=await digest(code as string);
      if(action==="upload"||action==="download"){
        const asset=await deps.rpc("asset",hash,{asset_id:data.asset_id});
        if(!validAsset(asset))throw Error();
        if(action==="upload"){
          const raw=atob(data.bytes as string),bytes=Uint8Array.from(raw,c=>c.charCodeAt(0));
          if(bytes.length!==asset.byte_size||!signature(bytes,asset.mime_type)||await digest(bytes)!==asset.sha256)return reply(422,"INVALID_IMAGE");
          if(asset.state!=="pending")throw new ChildDenied();
          await deps.upload(asset,bytes);
          await deps.rpc("status",hash,{});
          return reply(200,"OK",true);
        }
        const bytes=await deps.download(asset);
        if(bytes.length!==asset.byte_size||await digest(bytes)!==asset.sha256)throw Error();
        await deps.rpc("status",hash,{});
        headers.set("content-type","application/octet-stream");
        log(200,"OK",trace);
        return new Response(bytes,{status:200,headers});
      }
      return reply(200,"OK",await deps.rpc(action as string,hash,data));
    } catch(error){return error instanceof ChildDenied?reply(401,"CHILD_APPROVAL_REQUIRED"):reply(503,"CHILD_ACCESS_UNAVAILABLE");}
  };
}
export function runtimeDependencies(url:string,serverKey:string,fetcher:typeof fetch=fetch):Dependencies {
  const call=(path:string,init:RequestInit)=>fetcher(`${url}${path}`,{...init,redirect:"error",signal:AbortSignal.timeout(20000),
    headers:{apikey:serverKey,authorization:`Bearer ${serverKey}`,...init.headers}});
  const download=async(asset:Asset)=>{
    const result=await call(`/storage/v1/object/character-originals/${asset.path}`,{});
    if(!result.ok)throw Error();
    if(Number(result.headers.get("content-length")??0)>5242880){await result.body?.cancel();throw Error();}
    const reader=result.body!.getReader(),chunks:Uint8Array[]=[];let size=0;
    try{while(true){const{done,value}=await reader.read();if(done)break;size+=value.length;
      if(size>5242880){await reader.cancel();throw Error();}chunks.push(value);}}finally{reader.releaseLock();}
    const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}return bytes;
  };
  return {
    async rpc(action,hash,data){
      const result=await call("/rest/v1/rpc/child_access",{method:"POST",headers:{"content-type":"application/json"},
        body:JSON.stringify({p_action:action,p_token_hash:hash,p_data:data})});
      if(!result.ok){const error=await result.json().catch(()=>null);if(error?.code==="42501")throw new ChildDenied();throw Error();}
      return result.json();
    },download,
    async upload(asset,bytes){
      const result=await call(`/storage/v1/object/character-originals/${asset.path}`,{method:"POST",
        headers:{"content-type":asset.mime_type,"x-upsert":"false"},body:bytes});
      if(result.ok){await result.body?.cancel();return;}
      // Lost/duplicate upload responses may replay only the identical original.
      await result.body?.cancel();
      const existing=await download(asset);
      if(await digest(existing)!==asset.sha256)throw Error();
    },
  };
}
