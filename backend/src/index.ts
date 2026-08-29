interface Env { DB: D1Database; PHOTOS: R2Bucket; JWT_SECRET: string; APPLE_IOS_CLIENT_ID: string }
type Payload = Record<string, unknown>;

const encoder = new TextEncoder();
const b64 = (data: Uint8Array) => btoa(String.fromCharCode(...data)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const ub64 = (value: string) => Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
const now = () => new Date().toISOString();
const json = (data: unknown, status = 200) => Response.json({ success: status < 400, data: status < 400 ? data : null, error: status < 400 ? null : data, request_id: crypto.randomUUID(), server_time: now() }, { status, headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "Authorization, Content-Type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" } });
const error = (message: string, status = 400, code = "bad_request") => json({ code, message }, status);
async function digest(value: string) { return b64(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)))); }
async function jwt(payload: Payload, secret: string) {
  const head = b64(encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = b64(encoder.encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return `${head}.${body}.${b64(new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(`${head}.${body}`))))}`;
}
async function userFrom(request: Request, env: Env): Promise<string | null> {
  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const parts = token.split("."); if (parts.length !== 3) return null;
  const key = await crypto.subtle.importKey("raw", encoder.encode(env.JWT_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  if (!await crypto.subtle.verify("HMAC", key, ub64(parts[2]), encoder.encode(`${parts[0]}.${parts[1]}`))) return null;
  const claims = JSON.parse(new TextDecoder().decode(ub64(parts[1]))) as { sub?: string; exp?: number };
  return claims.sub && (claims.exp ?? 0) > Date.now() / 1000 ? claims.sub : null;
}
async function appleClaims(identityToken: string, audience: string) {
  const [head, body, signature] = identityToken.split("."); if (!head || !body || !signature) throw new Error("Invalid Apple identity token.");
  const header = JSON.parse(new TextDecoder().decode(ub64(head))) as { kid: string };
  const claims = JSON.parse(new TextDecoder().decode(ub64(body))) as { iss: string; aud: string | string[]; sub: string; exp: number };
  if (claims.iss !== "https://appleid.apple.com" || !(Array.isArray(claims.aud) ? claims.aud : [claims.aud]).includes(audience) || claims.exp < Date.now() / 1000) throw new Error("Apple identity token is not valid for this app.");
  const jwks = await fetch("https://appleid.apple.com/auth/keys").then(r => r.json()) as { keys: JsonWebKey[] };
  const jwk = jwks.keys.find(key => key.kid === header.kid); if (!jwk) throw new Error("Apple signing key was not found.");
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  if (!await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, ub64(signature), encoder.encode(`${head}.${body}`))) throw new Error("Apple identity token signature is invalid.");
  return claims;
}
async function authApple(request: Request, env: Env) {
  const input = await request.json() as { identity_token?: string; display_name?: string; email?: string };
  if (!input.identity_token) return error("Missing Apple identity token.");
  try {
    const claims = await appleClaims(input.identity_token, env.APPLE_IOS_CLIENT_ID);
    const existing = await env.DB.prepare("SELECT id, display_name FROM users WHERE apple_sub = ?").bind(claims.sub).first<{ id: string; display_name: string }>();
    const id = existing?.id ?? crypto.randomUUID(); const name = input.display_name?.trim() || existing?.display_name || "3DPrintKit User";
    if (existing) await env.DB.prepare("UPDATE users SET display_name = COALESCE(NULLIF(?, ''), display_name), email = COALESCE(?, email) WHERE id = ?").bind(input.display_name ?? "", input.email ?? null, id).run();
    else await env.DB.prepare("INSERT INTO users (id, apple_sub, display_name, email) VALUES (?, ?, ?, ?)").bind(id, claims.sub, name, input.email ?? null).run();
    const refresh = crypto.randomUUID() + crypto.randomUUID();
    await env.DB.prepare("INSERT INTO refresh_sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)").bind(await digest(refresh), id, Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 90).run();
    return json({ access_token: await jwt({ sub: id, exp: Math.floor(Date.now() / 1000) + 900 }, env.JWT_SECRET), refresh_token: refresh, account_id: id, display_name: name });
  } catch (cause) { return error(cause instanceof Error ? cause.message : "Apple sign in failed.", 401, "invalid_apple_token"); }
}
async function sync(request: Request, env: Env, userID: string) {
  if (request.method === "GET") {
    const since = Number(new URL(request.url).searchParams.get("since") ?? 0);
    const rows = await env.DB.prepare("SELECT entity, record_id, payload, deleted, version FROM sync_records WHERE user_id = ? AND version > ? ORDER BY version ASC").bind(userID, since).all<{ entity: string; record_id: string; payload: string | null; deleted: number; version: number }>();
    const max = rows.results.reduce((value, row) => Math.max(value, row.version), since);
    return json({ cursor: String(max), server_time: now(), spools: rows.results.filter(row => row.entity === "spools" && !row.deleted).map(row => JSON.parse(row.payload ?? "{}")), deleted: rows.results.filter(row => row.deleted).map(row => ({ entity: row.entity, record_id: row.record_id })) });
  }
  const input = await request.json() as { operations?: Array<{ id: string; kind: string; entity: string; record_id: string; payload?: string | null }> };
  const accepted: string[] = [], rejected: { id: string; reason: string }[] = [];
  for (const op of input.operations ?? []) {
    if (!op.id || !op.entity || !op.record_id || (op.kind !== "delete" && !op.payload)) { rejected.push({ id: op.id, reason: "Invalid sync operation." }); continue; }
    const prior = await env.DB.prepare("SELECT operation_id FROM sync_operations WHERE operation_id = ?").bind(op.id).first(); if (prior) { accepted.push(op.id); continue; }
    const versionRow = await env.DB.prepare("INSERT INTO sync_versions DEFAULT VALUES RETURNING version").first<{ version: number }>();
    await env.DB.batch([
      env.DB.prepare("INSERT INTO sync_operations (operation_id, user_id, entity, record_id) VALUES (?, ?, ?, ?)").bind(op.id, userID, op.entity, op.record_id),
      env.DB.prepare("INSERT INTO sync_records (user_id, entity, record_id, payload, deleted, version, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, entity, record_id) DO UPDATE SET payload=excluded.payload, deleted=excluded.deleted, version=excluded.version, updated_at=excluded.updated_at").bind(userID, op.entity, op.record_id, op.kind === "delete" ? null : op.payload ?? null, op.kind === "delete" ? 1 : 0, versionRow?.version ?? 0, now())
    ]); accepted.push(op.id);
  }
  return json({ accepted, rejected });
}
export default { async fetch(request: Request, env: Env): Promise<Response> {
  if (request.method === "OPTIONS") return new Response(null, { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "Authorization, Content-Type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" } });
  const path = new URL(request.url).pathname;
  if (path === "/" || path === "/health") {
    try {
      const check = await env.DB.prepare("SELECT 1 AS ok").first<{ ok: number }>();
      if (check?.ok !== 1) throw new Error("Unexpected D1 health-check result.");
      return json({ service: "3DPrintKit API", status: "ok", database: "ok" });
    } catch {
      return error("Database is unavailable.", 503, "database_unavailable");
    }
  }
  if (path === "/api/v1/auth/apple" && request.method === "POST") return authApple(request, env);
  const userID = await userFrom(request, env); if (!userID) return error("Authentication required.", 401, "unauthorized");
  if (path === "/api/v1/sync" && (request.method === "GET" || request.method === "POST")) return sync(request, env, userID);
  return error("Route not found.", 404, "not_found");
} } satisfies ExportedHandler<Env>;
