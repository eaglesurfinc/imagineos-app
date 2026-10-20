import {requestLog, type LogSink} from "../_shared/observability.ts";
// No provider SDK, generation flag, privileged key or billable operation exists
// in this Stage 5 handler. Enabling generation requires a reviewed replacement.
export type IllustrationRequest = {
  contract_version: 1;
  request_id: string;
  trace_id: string;
  page_id: string;
  character: { character_id: string; version_id: string; asset_id: string; sha256: string };
  scene_direction: string;
  layout: "portrait";
};

export type Dependencies = {
  log?: LogSink;
  authenticate: (authorization: string) => Promise<boolean>;
  ownsReadyReference: (authorization: string, request: IllustrationRequest) => Promise<boolean>;
};

const origins = new Set([
  "https://imagineos-app.vercel.app",
  "http://localhost:8766",
  "http://127.0.0.1:8766",
]);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const digest = /^[0-9a-f]{64}$/;
const exactKeys = (value: unknown, keys: string[]): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value) &&
  Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));

export function validRequest(value: unknown): value is IllustrationRequest {
  if (!exactKeys(value, ["contract_version", "request_id", "trace_id", "page_id", "character", "scene_direction", "layout"])) return false;
  const character = value.character;
  return value.contract_version === 1 && value.layout === "portrait" &&
    [value.request_id, value.trace_id, value.page_id].every((id) => typeof id === "string" && uuid.test(id)) &&
    typeof value.scene_direction === "string" && value.scene_direction.trim().length > 0 && value.scene_direction.length <= 2000 &&
    exactKeys(character, ["character_id", "version_id", "asset_id", "sha256"]) &&
    [character.character_id, character.version_id, character.asset_id].every((id) => typeof id === "string" && uuid.test(id)) &&
    typeof character.sha256 === "string" && digest.test(character.sha256);
}

export async function fingerprint(request: IllustrationRequest): Promise<string> {
  const c = request.character;
  const canonical = JSON.stringify([1, request.page_id, c.character_id, c.version_id, c.asset_id, c.sha256, request.scene_direction, request.layout]);
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  return Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function boundedJson(request: Request): Promise<unknown> {
  if (request.headers.get("content-type")?.split(";")[0].trim() !== "application/json" || !request.body) throw Error("invalid");
  const reader = request.body.getReader();
  let bytes = 0;
  const chunks: Uint8Array[] = [];
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.length;
      if (bytes > 16384) {
        await reader.cancel();
        throw Error("too large");
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const buffer = new Uint8Array(bytes);
  let offset = 0;
  for (const chunk of chunks) { buffer.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(buffer));
}

export function createHandler(deps: Dependencies) {
  return async (request: Request): Promise<Response> => {
    const log = requestLog("illustration-gateway", request.method, {sink: deps.log});
    const origin = request.headers.get("origin");
    const headers = new Headers({ "content-type": "application/json", "cache-control": "no-store", "vary": "Origin" });
    if (origin && origins.has(origin)) {
      headers.set("access-control-allow-origin", origin);
      headers.set("access-control-allow-headers", "authorization, apikey, content-type, x-client-info");
      headers.set("access-control-allow-methods", "POST, OPTIONS");
      headers.set("access-control-expose-headers", "x-trace-id");
    }
    let parsed: IllustrationRequest | undefined;
    let hash: string | null = null;
    const respond = (http: number, status: string, code: string, retryable = false) => {
      const trace = parsed?.trace_id ?? crypto.randomUUID();
      log(http, code, trace);
      headers.set("x-trace-id", trace);
      return new Response(JSON.stringify({
        contract_version: 1, request_id: parsed?.request_id ?? null,
        trace_id: trace, fingerprint: hash, status, code, retryable,
        output: null, cost_micros: 0, provider_attempts: 0,
      }), { status: http, headers });
    };
    if (origin && !origins.has(origin)) return respond(403, "rejected", "ORIGIN_DENIED");
    if (request.method === "OPTIONS") {
      log(204, "PREFLIGHT", crypto.randomUUID());
      return new Response(null, { status: 204, headers });
    }
    if (request.method !== "POST") return respond(405, "rejected", "METHOD_NOT_ALLOWED");
    const authorization = request.headers.get("authorization") ?? "";
    if (!/^Bearer [^\s]+$/.test(authorization)) return respond(401, "rejected", "AUTH_REQUIRED");
    // Parse first so authenticated failures can still carry client correlation.
    try {
      const value = await boundedJson(request);
      if (!validRequest(value)) return respond(422, "rejected", "INVALID_REQUEST");
      parsed = value;
      hash = await fingerprint(parsed);
    } catch { return respond(422, "rejected", "INVALID_REQUEST"); }
    try {
      if (!await deps.authenticate(authorization)) return respond(401, "rejected", "AUTH_REQUIRED");
      if (!await deps.ownsReadyReference(authorization, parsed)) return respond(404, "rejected", "REFERENCE_UNAVAILABLE");
      return respond(200, "disabled", "GENERATION_DISABLED");
    } catch {
      // Never expose tokens, scene text, user data or upstream error details.
      return respond(503, "failed", "BACKEND_UNAVAILABLE", true);
    }
  };
}

/** Read-only, user-scoped Auth/Data API dependencies. No administrative key. */
export function runtimeDependencies(url: string, publicKey: string, fetcher: typeof fetch = fetch): Dependencies {
  async function read(path: string, authorization: string) {
    if (!url || !publicKey) throw Error("configuration unavailable");
    return fetcher(`${url}${path}`, {
      headers: { apikey: publicKey, Authorization: authorization },
      signal: AbortSignal.timeout(5000),
    });
  }
  return {
    async authenticate(authorization) {
      const result = await read("/auth/v1/user", authorization);
      if (result.status === 401 || result.status === 403) return false;
      if (!result.ok) throw Error("auth unavailable");
      const user = await result.json();
      return typeof user.id === "string" && user.is_anonymous !== true;
    },
    async ownsReadyReference(authorization, request) {
      const c = request.character;
      const query = new URLSearchParams({
        select: "request_id,character_id,version_id,sha256,state,deleting_character",
        request_id: `eq.${c.asset_id}`, character_id: `eq.${c.character_id}`,
        version_id: `eq.${c.version_id}`, limit: "1",
      });
      const result = await read(`/rest/v1/original_uploads?${query}`, authorization);
      if (!result.ok) throw Error("reference lookup unavailable");
      const rows = await result.json();
      return Array.isArray(rows) && rows.length === 1 && rows[0].sha256 === c.sha256 &&
        rows[0].state === "ready" && rows[0].deleting_character === false;
    },
  };
}
