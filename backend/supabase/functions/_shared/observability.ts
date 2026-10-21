// Explicit metadata only. This module never receives a Request, body, headers,
// identity, URL, secret, upstream exception or application data.
export const functionNames = ["illustration-gateway", "parent-providers", "parent-controls", "child-access"] as const;
export type FunctionName = typeof functionNames[number];
export type LogSink = (line: string) => void;
const methods = new Set(["GET", "POST", "OPTIONS", "PUT", "PATCH", "DELETE", "HEAD"]);
export const resultCodes = new Set([
  "OK", "PREFLIGHT", "ORIGIN_DENIED", "METHOD_NOT_ALLOWED", "AUTH_REQUIRED", "INVALID_REQUEST",
  "REFERENCE_UNAVAILABLE", "GENERATION_DISABLED", "BACKEND_UNAVAILABLE", "TOO_MANY_ATTEMPTS",
  "PARENT_CONFIRMATION_REQUIRED", "PROVIDER_CREDENTIAL_REJECTED", "CONNECTION_UNAVAILABLE",
  "PARENT_LOCKED", "DELETION_NOT_STARTED", "PARENT_CONTROLS_UNAVAILABLE", "BACKUP_TOO_LARGE",
  "CHILD_APPROVAL_REQUIRED", "CHILD_ACCESS_PAUSED", "INVALID_IMAGE", "CHILD_ACCESS_UNAVAILABLE", "RECOVERY_CONFLICT", "UNKNOWN",
]);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function requestLog(name: FunctionName, method: string,
    { sink = (line: string) => console.log(line), clock = () => performance.now() }:
    { sink?: LogSink; clock?: () => number } = {}) {
  const started = clock(), fallbackTrace = crypto.randomUUID();
  let finished = false;
  return (status: number, code: string, trace: string) => {
    if (finished) return;
    finished = true;
    try {
      const elapsed = clock() - started;
      sink(JSON.stringify({
        event: "imagineos.request", schema: 1,
        function: functionNames.includes(name) ? name : "unknown",
        method: methods.has(method) ? method : "UNKNOWN",
        status: Number.isInteger(status) && status >= 100 && status <= 599 ? status : 500,
        code: resultCodes.has(code) ? code : "UNKNOWN",
        trace_id: uuid.test(trace) ? trace : fallbackTrace,
        duration_ms: Number.isFinite(elapsed) ? Math.round(Math.max(0, Math.min(600000, elapsed))) : 0,
      }));
    } catch { /* Telemetry failure must never fail or repeat a user operation. */ }
  };
}
