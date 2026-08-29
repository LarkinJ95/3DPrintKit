interface Env { DB: D1Database; PHOTOS: R2Bucket; JWT_SECRET: string; APPLE_IOS_CLIENT_ID: string; APPLE_WEB_CLIENT_ID: string }
type Payload = Record<string, unknown>;
type SyncRecordRow = { entity: string; record_id: string; payload: string | null; deleted: number; version: number; updated_at: string };

const encoder = new TextEncoder();
const b64 = (data: Uint8Array) => btoa(String.fromCharCode(...data)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const ub64 = (value: string) => Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
const now = () => new Date().toISOString();
const corsHeaders = { "Access-Control-Allow-Origin": "https://printkit-web.jlarkin-e6e.workers.dev", "Access-Control-Allow-Credentials": "true", "Access-Control-Allow-Headers": "Authorization, Content-Type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS, DELETE" };
const json = (data: unknown, status = 200) => Response.json({ success: status < 400, data: status < 400 ? data : null, error: status < 400 ? null : data, request_id: crypto.randomUUID(), server_time: now() }, { status, headers: corsHeaders });
const error = (message: string, status = 400, code = "bad_request") => json({ code, message }, status);
const cookie = (request: Request, name: string) => request.headers.get("Cookie")?.split(";").map(item => item.trim()).find(item => item.startsWith(`${name}=`))?.slice(name.length + 1) ?? null;
async function digest(value: string) { return b64(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)))); }
const numberValue = (value: unknown, fallback: number) => typeof value === "number" && Number.isFinite(value) ? value : fallback;
function spoolSyncDTO(row: SyncRecordRow) {
  let value: Record<string, unknown> = {};
  try { value = JSON.parse(row.payload ?? "{}") as Record<string, unknown>; } catch { /* malformed legacy records become safe defaults */ }
  const stringValue = (key: string, fallback = "") => typeof value[key] === "string" ? value[key] as string : fallback;
  return {
    id: stringValue("id", stringValue("spoolID", row.record_id)),
    manufacturer: stringValue("manufacturer"),
    product_line: stringValue("product_line", stringValue("productLine")),
    material_id: stringValue("material_id", stringValue("materialID", stringValue("material", "pla"))),
    color_name: stringValue("color_name", stringValue("colorName", stringValue("color"))),
    color_hex: stringValue("color_hex", stringValue("colorHex")) || null,
    diameter: numberValue(value.diameter, 1.75),
    original_weight_g: numberValue(value.original_weight_g, numberValue(value.originalNetWeightG, numberValue(value.originalWeight, 1000))),
    current_weight_g: numberValue(value.current_weight_g, numberValue(value.currentWeightG, numberValue(value.remainingWeight, 1000))),
    empty_spool_weight_g: numberValue(value.empty_spool_weight_g, numberValue(value.emptySpoolWeightG, 140)),
    notes: stringValue("notes"),
    archived: value.archived === true || value.isArchived === true,
    updated_at: stringValue("updated_at", row.updated_at)
  };
}
async function jwt(payload: Payload, secret: string) {
  const head = b64(encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = b64(encoder.encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return `${head}.${body}.${b64(new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(`${head}.${body}`))))}`;
}
async function userFrom(request: Request, env: Env): Promise<string | null> {
  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) {
    const session = cookie(request, "pk_session");
    if (!session) return null;
    const row = await env.DB.prepare("SELECT user_id FROM web_sessions WHERE session_hash = ? AND expires_at > ?").bind(await digest(session), Math.floor(Date.now() / 1000)).first<{ user_id: string }>();
    return row?.user_id ?? null;
  }
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
  const input = await request.json() as { identity_token?: string; display_name?: string; email?: string; web?: boolean };
  if (!input.identity_token) return error("Missing Apple identity token.");
  try {
    const audience = input.web ? env.APPLE_WEB_CLIENT_ID : env.APPLE_IOS_CLIENT_ID;
    if (!audience) return error("Web Sign in with Apple is not configured.", 503, "apple_not_configured");
    const claims = await appleClaims(input.identity_token, audience);
    const existing = await env.DB.prepare("SELECT id, display_name FROM users WHERE apple_sub = ?").bind(claims.sub).first<{ id: string; display_name: string }>();
    const id = existing?.id ?? crypto.randomUUID(); const name = input.display_name?.trim() || existing?.display_name || "3DPrintKit User";
    if (existing) await env.DB.prepare("UPDATE users SET display_name = COALESCE(NULLIF(?, ''), display_name), email = COALESCE(?, email) WHERE id = ?").bind(input.display_name ?? "", input.email ?? null, id).run();
    else await env.DB.prepare("INSERT INTO users (id, apple_sub, display_name, email) VALUES (?, ?, ?, ?)").bind(id, claims.sub, name, input.email ?? null).run();
    const refresh = crypto.randomUUID() + crypto.randomUUID();
    await env.DB.prepare("INSERT INTO refresh_sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)").bind(await digest(refresh), id, Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 90).run();
    const response = json({ access_token: await jwt({ sub: id, exp: Math.floor(Date.now() / 1000) + 900 }, env.JWT_SECRET), refresh_token: refresh, account_id: id, display_name: name });
    if (input.web) {
      const session = crypto.randomUUID() + crypto.randomUUID();
      const expiresAt = Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 30;
      await env.DB.prepare("INSERT INTO web_sessions (session_hash, user_id, expires_at) VALUES (?, ?, ?)").bind(await digest(session), id, expiresAt).run();
      response.headers.append("Set-Cookie", `pk_session=${session}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${60 * 60 * 24 * 30}`);
    }
    return response;
  } catch (cause) { return error(cause instanceof Error ? cause.message : "Apple sign in failed.", 401, "invalid_apple_token"); }
}
async function refreshAuth(request: Request, env: Env) {
  const input = await request.json() as { refresh_token?: string };
  if (!input.refresh_token) return error("Missing refresh token.", 401, "invalid_refresh_token");
  const tokenHash = await digest(input.refresh_token);
  const session = await env.DB.prepare("SELECT user_id FROM refresh_sessions WHERE token_hash = ? AND expires_at > ?").bind(tokenHash, Math.floor(Date.now() / 1000)).first<{ user_id: string }>();
  if (!session) return error("Refresh session expired. Please sign in again.", 401, "invalid_refresh_token");
  // Rotate refresh tokens so a leaked older token cannot be replayed.
  const refresh = crypto.randomUUID() + crypto.randomUUID();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM refresh_sessions WHERE token_hash = ?").bind(tokenHash),
    env.DB.prepare("INSERT INTO refresh_sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)").bind(await digest(refresh), session.user_id, Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 90)
  ]);
  return json({ access_token: await jwt({ sub: session.user_id, exp: Math.floor(Date.now() / 1000) + 900 }, env.JWT_SECRET), refresh_token: refresh });
}
async function sync(request: Request, env: Env, userID: string) {
  if (request.method === "GET") {
    const since = Number(new URL(request.url).searchParams.get("since") ?? 0);
    const rows = await env.DB.prepare("SELECT entity, record_id, payload, deleted, version, updated_at FROM sync_records WHERE user_id = ? AND version > ? ORDER BY version ASC").bind(userID, since).all<SyncRecordRow>();
    const max = rows.results.reduce((value, row) => Math.max(value, row.version), since);
    return json({ cursor: String(max), server_time: now(), spools: rows.results.filter(row => row.entity === "spools" && !row.deleted).map(spoolSyncDTO), deleted: rows.results.filter(row => row.deleted).map(row => ({ entity: row.entity, record_id: row.record_id })) });
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
  if (request.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
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
  if (path === "/api/v1/auth/refresh" && request.method === "POST") return refreshAuth(request, env);
  const userID = await userFrom(request, env); if (!userID) return error("Authentication required.", 401, "unauthorized");
  if (path === "/api/v1/account" && request.method === "GET") {
    const account = await env.DB.prepare("SELECT id, display_name, created_at FROM users WHERE id = ?").bind(userID).first<{ id: string; display_name: string; created_at: string }>();
    return account ? json({ account_id: account.id, display_name: account.display_name, created_at: account.created_at }) : error("Account not found.", 404, "not_found");
  }
  if (path === "/api/v1/auth/logout" && request.method === "POST") {
    const session = cookie(request, "pk_session");
    if (session) await env.DB.prepare("DELETE FROM web_sessions WHERE session_hash = ?").bind(await digest(session)).run();
    const response = json({}); response.headers.append("Set-Cookie", "pk_session=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0"); return response;
  }
  if (path === "/api/v1/sync" && (request.method === "GET" || request.method === "POST")) return sync(request, env, userID);
  return error("Route not found.", 404, "not_found");
} } satisfies ExportedHandler<Env>;
