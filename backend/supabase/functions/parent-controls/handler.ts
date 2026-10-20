import { parentAuth, type Parent } from "../_shared/parent_auth.ts";
import {digest as hash,readJson as readBody,uuid} from "../_shared/http.ts";

type Dependencies = {
  authenticate(authorization: string): Promise<Parent | null>;
  confirmPassword(parent: Parent, password: string): Promise<boolean>;
  manage(parent: Parent, action: string, hash?: string): Promise<unknown>;
  manageChildren?(parent:Parent,action:string,hash:string,data:Record<string,unknown>):Promise<unknown>;
  privacy?(parent:Parent,action:string,hash:string,paused?:boolean):Promise<unknown>;
  removeFiles(paths: string[]): Promise<void>;
  removeAccount(parent: Parent): Promise<void>;
};
const origins = new Set(["https://imagineos-app.vercel.app", "http://localhost:8766", "http://127.0.0.1:8766"]);
const counts = ["child_profiles", "characters", "versions", "original_files", "page_drafts", "stories", "provider_connections"];
const childActions:Record<string,string[]>={child_list:[],child_add:["nickname"],
  child_approve:["child_id","minutes"],child_settings:["child_id","minutes","allow_export","blocked"],child_end:["session_id"]};
export function createHandler(deps: Dependencies) {
  return async (request: Request): Promise<Response> => {
    const headers = new Headers({"content-type":"application/json", "cache-control":"no-store", "vary":"Origin"});
    const trace = crypto.randomUUID(), origin = request.headers.get("origin");
    headers.set("x-trace-id", trace);
    if (origin && origins.has(origin)) {
      headers.set("access-control-allow-origin", origin);
      headers.set("access-control-allow-headers", "authorization, apikey, content-type, x-client-info, x-imagineos-parent-grant");
      headers.set("access-control-allow-methods", "POST, OPTIONS");
    }
    const respond = (status: number, code: string, data: unknown = null) =>
      new Response(JSON.stringify({contract_version:1, code, data, trace_id:trace}), {status, headers});
    if (origin && !origins.has(origin)) return respond(403, "ORIGIN_DENIED");
    if (request.method === "OPTIONS") return new Response(null, {status:204, headers});
    if (request.method !== "POST") return respond(405, "METHOD_NOT_ALLOWED");
    const authorization = request.headers.get("authorization") ?? "";
    if (!/^Bearer [^\s]+$/.test(authorization)) return respond(401, "AUTH_REQUIRED");
    let value;
    try {
      value = await readBody(request);
      if (!value || typeof value !== "object" || Array.isArray(value)) throw Error();
      const allowed = childActions[value.action] ? ["action",...childActions[value.action]] : value.action === "unlock" ? ["action", "password"] :
        value.action === "start_delete" ? ["action", "password", "confirmation"] :
        value.action === "privacy_pause" ? ["action","paused"] :
        ["overview", "lock", "continue_delete","privacy_status","recovery_snapshot"].includes(value.action) ? ["action"] : [];
      if (!allowed.length || Object.keys(value).length !== allowed.length || !allowed.every(k=>Object.hasOwn(value,k))) throw Error();
      if (["unlock", "start_delete"].includes(value.action) &&
        (typeof value.password !== "string" || !value.password.length || value.password.length>1024)) throw Error();
      if (value.action === "start_delete" && value.confirmation !== "DELETE MY FAMILY") throw Error();
      if (value.action === "privacy_pause" && typeof value.paused !== "boolean") throw Error();
      if (childActions[value.action]) {
        if ("child_id" in value && (typeof value.child_id!=="string" || !uuid.test(value.child_id))) throw Error();
        if ("session_id" in value && (typeof value.session_id!=="string" || !uuid.test(value.session_id))) throw Error();
        if ("minutes" in value && (!Number.isInteger(value.minutes)||value.minutes<1||value.minutes>480)) throw Error();
        if (value.action==="child_add" && (typeof value.nickname!=="string"||!value.nickname.trim()||value.nickname.length>40)) throw Error();
        if (value.action==="child_settings" && (typeof value.blocked!=="boolean"||typeof value.allow_export!=="boolean")) throw Error();
      }
    } catch { return respond(422, "INVALID_REQUEST"); }
    try {
      const parent = await deps.authenticate(authorization);
      if (!parent) return respond(401, "AUTH_REQUIRED");
      if (value.action === "unlock") {
        if (await deps.manage(parent,"attempt") !== true) return respond(429,"TOO_MANY_ATTEMPTS");
        if (!await deps.confirmPassword(parent,value.password)) return respond(403,"PARENT_CONFIRMATION_REQUIRED");
        const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), b=>b.toString(16).padStart(2,"0")).join("");
        const result = await deps.manage(parent,"unlock",await hash(token)) as {expires_at:string};
        return respond(200,"OK",{grant:token,expires_at:result.expires_at});
      }
      const token = request.headers.get("x-imagineos-parent-grant") ?? "";
      if (!/^[0-9a-f]{64}$/.test(token)) return respond(403,"PARENT_LOCKED");
      const digest = await hash(token);
      if (["privacy_status","privacy_pause","recovery_snapshot"].includes(value.action)) {
        if (!deps.privacy) throw Error();
        return respond(200,"OK",await deps.privacy(parent,value.action,digest,value.paused));
      }
      if (childActions[value.action]) {
        if (!deps.manageChildren) throw Error();
        const {action,...payload}=value;
        let code:string|undefined;
        if (action==="child_approve") {
          code=Array.from(crypto.getRandomValues(new Uint8Array(16)),b=>b.toString(16).padStart(2,"0")).join("");
          payload.code_hash=await hash(code);
        }
        const data=await deps.manageChildren(parent,action,digest,payload);
        if(data===null)return respond(429,"TOO_MANY_ATTEMPTS");
        return respond(200,"OK",code?{...(data as Record<string,unknown>),code}:data);
      }
      if (value.action === "lock") {
        await deps.manage(parent,"lock",digest);
        return respond(200,"OK");
      }
      const overview = await deps.manage(parent,"overview",digest) as Record<string,unknown> | null;
      if (!overview) return respond(403,"PARENT_LOCKED");
      if (value.action === "overview") {
        const data: Record<string,unknown> = {deletion_pending:overview.deletion_pending === true,generation_enabled:false};
        for (const key of counts) {
          if (!Number.isSafeInteger(overview[key]) || (overview[key] as number)<0) throw Error();
          data[key] = overview[key];
        }
        return respond(200,"OK",data);
      }
      if (value.action === "start_delete") {
        if (await deps.manage(parent,"attempt") !== true) return respond(429,"TOO_MANY_ATTEMPTS");
        if (!await deps.confirmPassword(parent,value.password)) return respond(403,"PARENT_CONFIRMATION_REQUIRED");
        if (await deps.manage(parent,"delete_begin",digest) !== true) return respond(403,"PARENT_LOCKED");
      } else if (overview.deletion_pending !== true) return respond(409,"DELETION_NOT_STARTED");
      const paths = await deps.manage(parent,"delete_batch",digest);
      if (!Array.isArray(paths) || paths.length>100 || paths.some(p=>typeof p!=="string" || !/^[0-9a-f-]{36}\/[0-9a-f-]{36}$/.test(p))) throw Error();
      if (paths.length) await deps.removeFiles(paths);
      const ready = await deps.manage(parent,"delete_ready",digest);
      if (ready === null) return respond(403,"PARENT_LOCKED");
      if (ready !== true) return respond(200,"OK",{deleted:false, pending:true});
      // Auth is removed last. Its FK cascades erase family records, Vault keys,
      // retry records and ALL sessions. File cleanup failure cannot reach here.
      await deps.removeAccount(parent);
      return respond(200,"OK",{deleted:true,pending:false});
    } catch(error) {
      if(error instanceof PrivacyError)return respond(error.status,error.code);
      return respond(503,"PARENT_CONTROLS_UNAVAILABLE");
    }
  };
}

export class PrivacyError extends Error {
  status:number;
  code:string;
  constructor(status:number,code:string){super(code);this.status=status;this.code=code;}
}

export function runtimeDependencies(url: string, publicKey: string, serverKey: string,
  fetcher: typeof fetch = fetch): Dependencies {
  const auth = parentAuth(url,publicKey,fetcher);
  const call = async (path: string, body: unknown, method="POST") => {
    if (!serverKey) throw Error();
    const result = await fetcher(`${url}${path}`, {method,redirect:"error",signal:AbortSignal.timeout(15000),
      headers:{apikey:serverKey,authorization:`Bearer ${serverKey}`,"content-type":"application/json"},
      body:JSON.stringify(body)});
    if (!result.ok) { await result.body?.cancel(); throw Error(); }
    return result;
  };
  return {
    authenticate:auth.authenticate, confirmPassword:auth.confirmPassword,
    async manage(parent,action,digest) {
      const result = await call("/rest/v1/rpc/parent_controls",{p_parent_id:parent.id,
        p_session_id:parent.sessionId,p_action:action,p_token_hash:digest??null});
      return result.json();
    },
    async manageChildren(parent,action,digest,data) {
      const result=await fetcher(`${url}/rest/v1/rpc/manage_child_access`,{method:"POST",redirect:"error",signal:AbortSignal.timeout(15000),
        headers:{apikey:serverKey,authorization:`Bearer ${serverKey}`,"content-type":"application/json"},
        body:JSON.stringify({p_parent:parent.id,p_session:parent.sessionId,p_grant_hash:digest,p_action:action,p_data:data})});
      if(!result.ok){const e=await result.json().catch(()=>null);
        if(e?.code==="42501" && e?.message==="CHILD_ACCESS_PAUSED")throw new PrivacyError(409,"CHILD_ACCESS_PAUSED");
        throw Error();}
      return result.json();
    },
    async privacy(parent,action,digest,paused) {
      const response=await fetcher(`${url}/rest/v1/rpc/parent_privacy`,{method:"POST",redirect:"error",signal:AbortSignal.timeout(15000),
        headers:{apikey:serverKey,authorization:`Bearer ${serverKey}`,"content-type":"application/json"},
        body:JSON.stringify({p_parent:parent.id,p_session:parent.sessionId,p_grant_hash:digest,p_action:action,p_paused:paused??null})});
      if(!response.ok){const e=await response.json().catch(()=>null);
        if(e?.code==="42501")throw new PrivacyError(403,"PARENT_LOCKED");
        if(e?.code==="54000")throw new PrivacyError(413,"BACKUP_TOO_LARGE");
        throw Error();}
      return response.json();
    },
    async removeFiles(paths) {
      const result = await call("/storage/v1/object/character-originals",{prefixes:paths},"DELETE");
      await result.body?.cancel();
    },
    async removeAccount(parent) {
      const result = await call(`/auth/v1/admin/users/${parent.id}`,{should_soft_delete:false},"DELETE");
      await result.body?.cancel();
    },
  };
}
