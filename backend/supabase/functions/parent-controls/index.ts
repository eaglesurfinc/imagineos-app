import {createHandler, runtimeDependencies} from "./handler.ts";
Deno.serve(createHandler(runtimeDependencies(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "")));
