import { createHandler, runtimeDependencies } from "./handler.ts";

// Legacy service JWT is restricted to this server function. Never send it to
// Flutter. The existing development runtime provides this built-in secret.
Deno.serve(createHandler(runtimeDependencies(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
)));
