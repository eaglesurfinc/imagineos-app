export const allowedOrigins = new Set(["https://imagineos-app.vercel.app", "http://localhost:8766", "http://127.0.0.1:8766"]);
export async function digest(value: string | Uint8Array): Promise<string> {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value);
  const result = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(result), b=>b.toString(16).padStart(2,"0")).join("");
}
export async function readJson(request: Request, limit=8192) {
  if (request.headers.get("content-type")?.split(";")[0].trim() !== "application/json" || !request.body) throw Error();
  const reader=request.body.getReader(), decoder=new TextDecoder("utf-8",{fatal:true});
  let result="",size=0;
  try {
    while(true) {
      const {done,value}=await reader.read();
      if(done) break;
      size+=value.length;
      if(size>limit){await reader.cancel();throw Error();}
      result+=decoder.decode(value,{stream:true});
    }
    return JSON.parse(result+decoder.decode());
  } finally {reader.releaseLock();}
}
export const exactKeys=(value:unknown,keys:string[]):value is Record<string,unknown>=>
  !!value && typeof value==="object" && !Array.isArray(value) &&
  Object.keys(value).length===keys.length && keys.every(k=>Object.hasOwn(value,k));
export const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
