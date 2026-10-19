import { createHandler, runtimeDependencies } from "./handler.ts";

// Both keys are public API identifiers. Ownership always uses the caller JWT.
let publishable = "";
try { publishable = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}").default ?? ""; } catch { /* fail closed below */ }
const publicKey = publishable || Deno.env.get("SUPABASE_ANON_KEY") || "";
Deno.serve(createHandler(runtimeDependencies(Deno.env.get("SUPABASE_URL") ?? "", publicKey)));
