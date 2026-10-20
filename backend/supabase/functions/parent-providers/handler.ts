import {parentAuth, type Parent} from "../_shared/parent_auth.ts";
import {requestLog, type LogSink} from "../_shared/observability.ts";
// Connection management only. This module cannot generate images or spend AI
// credits. Never log incoming bodies, credentials, passwords or upstream errors.
export const providers = [
  { id: "openai", name: "OpenAI", image_generation: true,
    subscription: "ChatGPT plan sharing does not currently include image generation.",
    connection: "api_key", login_available: false,
    billing: "Uses the parent's OpenAI API account and eligible API credits." },
  { id: "claude", name: "Claude", image_generation: false,
    subscription: "Subscription access requires an eligible official integration; it is not enabled here.",
    connection: "api_key", login_available: false,
    billing: "Uses the parent's Anthropic API account. Image analysis only; Claude cannot render illustrations." },
  { id: "gemini", name: "Gemini", image_generation: true,
    subscription: "Google sign-in alone does not grant Gemini subscription image credits.",
    connection: "api_key", login_available: false,
    billing: "Uses the parent's Gemini API project and its eligible quota or credits." },
] as const;

type Connection = { provider: string; connected_at: string };
export type Dependencies = {
  log?: LogSink;
  authenticate(authorization: string): Promise<Parent | null>;
  manage(parent: Parent, action: string, provider?: string, secret?: string): Promise<unknown>;
  confirmPassword(parent: Parent, password: string): Promise<boolean>;
  verifyKey(provider: string, secret: string): Promise<boolean>;
};
const origins = new Set(["https://imagineos-app.vercel.app", "http://localhost:8766", "http://127.0.0.1:8766"]);
const ids = new Set<string>(providers.map((p) => p.id));
function validSecret(provider: string, value: unknown): value is string {
  return typeof value === "string" && value.length >= 16 && value.length <= 2048 &&
    /^[\x21-\x7e]+$/.test(value) &&
    (provider === "openai" ? value.startsWith("sk-") :
      provider === "claude" ? value.startsWith("sk-ant-") : value.startsWith("AIza"));
}
async function body(request: Request) {
  if (request.headers.get("content-type")?.split(";")[0].trim() !== "application/json" || !request.body) throw Error();
  const reader = request.body.getReader();
  let text = "", size = 0;
  const decoder = new TextDecoder("utf-8", { fatal: true });
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 8192) { await reader.cancel(); throw Error(); }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
    return JSON.parse(text);
  } finally { reader.releaseLock(); }
}
export function createHandler(deps: Dependencies) {
  return async (request: Request): Promise<Response> => {
    const log = requestLog("parent-providers", request.method, {sink: deps.log});
    const headers = new Headers({ "content-type": "application/json", "cache-control": "no-store", "vary": "Origin" });
    const origin = request.headers.get("origin");
    const trace = crypto.randomUUID();
    headers.set("x-trace-id", trace);
    if (origin && origins.has(origin)) {
      headers.set("access-control-allow-origin", origin);
      headers.set("access-control-allow-headers", "authorization, apikey, content-type, x-client-info");
      headers.set("access-control-allow-methods", "POST, OPTIONS");
    }
    const respond = (status: number, code: string, data: unknown = null) => {
      log(status, code, trace);
      return new Response(JSON.stringify({ contract_version: 1, code, data, trace_id: trace }), { status, headers });
    };
    if (origin && !origins.has(origin)) return respond(403, "ORIGIN_DENIED");
    if (request.method === "OPTIONS") {log(204, "PREFLIGHT", trace); return new Response(null, { status: 204, headers });}
    if (request.method !== "POST") return respond(405, "METHOD_NOT_ALLOWED");
    const authorization = request.headers.get("authorization") ?? "";
    if (!/^Bearer [^\s]+$/.test(authorization)) return respond(401, "AUTH_REQUIRED");
    let value;
    try {
      value = await body(request);
      if (!value || Array.isArray(value) || typeof value !== "object") throw Error();
      const allowed = value.action === "list" ? ["action"] :
        value.action === "connect" ? ["action", "provider", "api_key", "password"] :
        value.action === "disconnect" ? ["action", "provider", "password"] : [];
      if (!allowed.length || Object.keys(value).length !== allowed.length ||
          !allowed.every((key) => Object.hasOwn(value, key))) throw Error();
      if (value.action !== "list" && (!ids.has(value.provider) ||
          typeof value.password !== "string" || value.password.length < 1 || value.password.length > 1024)) throw Error();
      if (value.action === "connect" && !validSecret(value.provider, value.api_key)) throw Error();
    } catch { return respond(422, "INVALID_REQUEST"); }
    try {
      const parent = await deps.authenticate(authorization);
      if (!parent) return respond(401, "AUTH_REQUIRED");
      if (value.action === "list") {
        const connections = await deps.manage(parent, "list") as Connection[];
        // Whitelist safe metadata even if a dependency changes its response.
        return respond(200, "OK", { providers, generation_enabled: false,
          connections: connections.filter((c) => ids.has(c.provider)).map((c) =>
            ({ provider: c.provider, connected_at: c.connected_at })) });
      }
      if (await deps.manage(parent, "attempt") !== true) return respond(429, "TOO_MANY_ATTEMPTS");
      if (!await deps.confirmPassword(parent, value.password)) return respond(403, "PARENT_CONFIRMATION_REQUIRED");
      if (value.action === "connect" && !await deps.verifyKey(value.provider, value.api_key))
        return respond(422, "PROVIDER_CREDENTIAL_REJECTED");
      await deps.manage(parent, value.action === "connect" ? "save" : "disconnect", value.provider, value.api_key);
      return respond(200, "OK");
    } catch { return respond(503, "CONNECTION_UNAVAILABLE"); }
  };
}

export function runtimeDependencies(url: string, publicKey: string, serverKey: string,
    fetcher: typeof fetch = fetch): Dependencies {
  const call = (target: string, init: RequestInit) => fetcher(target,
    { ...init, redirect: "error", signal: AbortSignal.timeout(8000) });
  return {
    ...parentAuth(url, publicKey, fetcher),
    async manage(parent, action, provider, secret) {
      if (!serverKey) throw Error();
      const result = await call(`${url}/rest/v1/rpc/manage_parent_provider`, {
        method: "POST", headers: { apikey: serverKey, authorization: `Bearer ${serverKey}`, "content-type": "application/json" },
        body: JSON.stringify({ p_parent_id: parent.id, p_session_id: parent.sessionId,
          p_action: action, p_provider: provider ?? null, p_secret: secret ?? null }),
      });
      if (!result.ok) throw Error();
      return result.json();
    },
    async verifyKey(provider, secret) {
      // Read-only model discovery. No prompt, drawing, image or generation call.
      const target = provider === "openai" ? "https://api.openai.com/v1/models" :
        provider === "claude" ? "https://api.anthropic.com/v1/models?limit=1" :
        "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1";
      const headers: Record<string, string> = provider === "claude"
        ? { "x-api-key": secret, "anthropic-version": "2023-06-01" }
        : provider === "gemini" ? { "x-goog-api-key": secret } : { authorization: `Bearer ${secret}` };
      const result = await call(target, { headers });
      // Do not read or return the provider response body. Key validity does not
      // prove a credit balance, image-model permission or sufficient quota.
      await result.body?.cancel();
      if ([401, 403, 400].includes(result.status)) return false;
      if (!result.ok) throw Error();
      return true;
    },
  };
}
