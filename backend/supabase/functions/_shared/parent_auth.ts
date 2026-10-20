export type Parent = {id: string; email: string; sessionId: string};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/// Auth verifies the signature before we use the session claim. Every sensitive
/// database operation must additionally check that session still exists.
export function parentAuth(url: string, publicKey: string, fetcher: typeof fetch = fetch) {
  const call = (path: string, init: RequestInit) => fetcher(`${url}${path}`,
    {...init, redirect:"error", signal:AbortSignal.timeout(8000)});
  return {
    async authenticate(authorization: string): Promise<Parent | null> {
      const result = await call("/auth/v1/user", {headers:{apikey:publicKey, authorization}});
      if ([401,403,404].includes(result.status)) return null;
      if (!result.ok) throw Error();
      const user = await result.json();
      const payload = JSON.parse(atob(authorization.split(".")[1].replace(/-/g,"+").replace(/_/g,"/")));
      if (!uuid.test(user.id) || !uuid.test(payload.session_id) || user.is_anonymous || !user.email) return null;
      return {id:user.id,email:user.email,sessionId:payload.session_id};
    },
    async confirmPassword(parent: Parent, password: string): Promise<boolean> {
      const result = await call("/auth/v1/token?grant_type=password", {
        method:"POST", headers:{apikey:publicKey,"content-type":"application/json"},
        body:JSON.stringify({email:parent.email,password})});
      if ([400,401].includes(result.status)) return false;
      if (!result.ok) throw Error();
      const session = await result.json();
      // Revoke the temporary session even if its identity unexpectedly differs.
      const signedOut = await call("/auth/v1/logout?scope=local", {
        method:"POST",headers:{apikey:publicKey,authorization:`Bearer ${session.access_token}`}});
      if (!signedOut.ok) throw Error();
      return session.user?.id === parent.id;
    },
  };
}
