import { verifyAppleJws } from "./apple-jws";

interface Env { DB: D1Database; PHOTOS: R2Bucket; JWT_SECRET: string; APPLE_IOS_CLIENT_ID: string; APPLE_WEB_CLIENT_ID: string; WEB_ORIGIN: string }
type Payload = Record<string, unknown>;
type SyncRecordRow = { entity: string; record_id: string; payload: string | null; deleted: number; version: number; updated_at: string };

const encoder = new TextEncoder();
const b64 = (data: Uint8Array) => btoa(String.fromCharCode(...data)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const ub64 = (value: string) => Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
const now = () => new Date().toISOString();
const corsHeaders = { "Access-Control-Allow-Origin": "https://3dprintkit.app", "Access-Control-Allow-Credentials": "true", "Access-Control-Allow-Headers": "Authorization, Content-Type", "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS", Vary: "Origin" };
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
    // A few early tag payloads used `color` for a hex value. Treat it as a
    // swatch only when it is actually a CSS hex colour; names stay names.
    color_hex: stringValue("color_hex", stringValue("colorHex"))
      || (/^#[0-9a-f]{6}$/i.test(stringValue("color")) ? stringValue("color") : null),
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

const PRO_CAPABILITIES = [
  "canUseCloudSync", "canAccessWeb", "canWriteNFC", "canAddUnlimitedSpools",
  "canAddUnlimitedPrinters", "canAddUnlimitedProjects", "canUseAdvancedAnalytics",
  "canUsePrintReadiness", "canUsePersonalKnowledge", "canUseAdvancedExport",
  "canUseAdvancedMaterialTools", "canUsePhotos", "canUseMaintenanceAndDrying",
  "canUseHardwareInventory", "canUseRecords",
];
const PRO_STATUSES = new Set(["trial", "active", "grace", "billing_retry"]);
const PRODUCT_IDS = new Set([
  "com.3dprintkit.pro.monthly",
  "com.3dprintkit.pro.annual",
  "com.3dprintkit.pro.lifetime",
]);
type EntitlementRow = {
  plan: string; entitlement_status: string; entitlement_source: string | null;
  subscription_expires_at: string | null; lifetime_access: number; last_verified_at: string | null;
};
type AppleTransaction = {
  transactionId: string; originalTransactionId: string; bundleId: string; productId: string;
  type: string; purchaseDate: number; expiresDate?: number; environment: string;
  appAccountToken?: string; revocationDate?: number; offerType?: number; signedDate?: number;
};

function entitlementState(row: EntitlementRow | null) {
  const lifetime = Boolean(row?.lifetime_access);
  const status = row?.entitlement_status ?? "none";
  const expiresAt = row?.subscription_expires_at ?? null;
  const stillValid = expiresAt === null || new Date(expiresAt).getTime() > Date.now();
  const pro = lifetime || (PRO_STATUSES.has(status) && stillValid);
  const effectiveStatus = !lifetime && PRO_STATUSES.has(status) && !stillValid ? "expired" : status;
  return {
    plan: pro ? "pro" : "free", status: effectiveStatus, source: row?.entitlement_source ?? null,
    expires_at: lifetime ? null : expiresAt, lifetime,
    capabilities: pro ? PRO_CAPABILITIES : [],
    quotas: pro ? { spools: null, printers: null, projects: null } : { spools: 10, printers: 1, projects: 0 },
    last_verified_at: row?.last_verified_at ?? null,
  };
}

async function loadEntitlement(env: Env, userID: string) {
  const row = await env.DB.prepare(
    "SELECT plan, entitlement_status, entitlement_source, subscription_expires_at, lifetime_access, last_verified_at FROM users WHERE id = ?",
  ).bind(userID).first<EntitlementRow>();
  return entitlementState(row);
}

async function entitlementApi(request: Request, env: Env, userID: string): Promise<Response> {
  if (request.method === "GET") return json(await loadEntitlement(env, userID));
  const body = await request.json() as { signed_transaction?: unknown };
  if (typeof body.signed_transaction !== "string" || body.signed_transaction.length < 32) {
    return error("A signed transaction is required.", 400, "invalid_transaction");
  }
  let transaction: AppleTransaction;
  try { transaction = await verifyAppleJws<AppleTransaction>(body.signed_transaction); }
  catch (cause) { return error(cause instanceof Error ? cause.message : "The transaction could not be verified.", 400, "invalid_transaction"); }
  if (transaction.bundleId !== "com.3dprintkit.app" || !PRODUCT_IDS.has(transaction.productId) || !transaction.originalTransactionId) {
    return error("Transaction does not belong to 3dPrintKit.", 400, "invalid_transaction");
  }
  if (transaction.appAccountToken && transaction.appAccountToken.toLowerCase() !== userID.toLowerCase()) {
    return error("Transaction belongs to a different account.", 403, "transaction_account_mismatch");
  }
  const existing = await env.DB.prepare("SELECT user_id, latest_signed_date FROM app_store_transactions WHERE original_transaction_id = ?")
    .bind(transaction.originalTransactionId).first<{ user_id: string; latest_signed_date: string }>();
  if (existing && existing.user_id !== userID) return error("Transaction belongs to a different account.", 403, "transaction_account_mismatch");
  const signedAt = new Date(transaction.signedDate ?? transaction.purchaseDate).toISOString();
  if (existing && new Date(existing.latest_signed_date).getTime() > new Date(signedAt).getTime()) return json(await loadEntitlement(env, userID));
  const lifetime = transaction.productId === "com.3dprintkit.pro.lifetime" || transaction.type === "Non-Consumable";
  const expiresAt = lifetime || transaction.expiresDate === undefined ? null : new Date(transaction.expiresDate).toISOString();
  const status = transaction.revocationDate !== undefined ? "refunded" : lifetime ? "active" : transaction.expiresDate !== undefined && transaction.expiresDate <= Date.now() ? "expired" : transaction.offerType === 1 ? "trial" : "active";
  const next = entitlementState({ plan: lifetime || PRO_STATUSES.has(status) ? "pro" : "free", entitlement_status: status, entitlement_source: lifetime ? "app_store_lifetime" : "app_store_subscription", subscription_expires_at: expiresAt, lifetime_access: lifetime ? 1 : 0, last_verified_at: now() });
  await env.DB.batch([
    env.DB.prepare("INSERT INTO app_store_transactions (original_transaction_id, user_id, product_id, kind, status, expires_at, environment, latest_signed_date, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(original_transaction_id) DO UPDATE SET user_id=excluded.user_id, product_id=excluded.product_id, kind=excluded.kind, status=excluded.status, expires_at=excluded.expires_at, environment=excluded.environment, latest_signed_date=excluded.latest_signed_date, updated_at=excluded.updated_at")
      .bind(transaction.originalTransactionId, userID, transaction.productId, lifetime ? "lifetime" : transaction.productId.endsWith(".annual") ? "annual" : "monthly", status, expiresAt, transaction.environment, signedAt, now()),
    env.DB.prepare("UPDATE users SET plan = ?, entitlement_status = ?, entitlement_source = ?, subscription_expires_at = ?, lifetime_access = ?, last_verified_at = ?, app_account_token = COALESCE(?, app_account_token) WHERE id = ?")
      .bind(next.plan, status, next.source, expiresAt, lifetime ? 1 : 0, now(), transaction.appAccountToken?.toLowerCase() ?? null, userID),
  ]);
  return json(await loadEntitlement(env, userID));
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

const ENTITY_NAMES = new Set(["spools", "printers", "profiles", "prints", "projects", "transfers", "maintenance"]);

function decodeRecord(row: SyncRecordRow): Payload {
  try {
    const payload = JSON.parse(row.payload ?? "{}") as Payload;
    // The first Cloud Sync release stored spools in the compact NFC/tag shape
    // (`color`, `product`, `material`, ...). Keep those records readable by
    // the full web editor while newer clients gradually republish the richer
    // canonical payload, including the selected colour hex value.
    const normalized = row.entity === "spools"
      ? {
        ...payload,
        manufacturer: typeof payload.manufacturer === "string" ? payload.manufacturer : "",
        product_line: typeof payload.product_line === "string" ? payload.product_line : typeof payload.product === "string" ? payload.product : "",
        material_id: typeof payload.material_id === "string" ? payload.material_id : typeof payload.material === "string" ? payload.material : "pla",
        color_name: typeof payload.color_name === "string" ? payload.color_name : typeof payload.colorName === "string" ? payload.colorName : typeof payload.color === "string" ? payload.color : "",
        color_hex: typeof payload.color_hex === "string" ? payload.color_hex : typeof payload.colorHex === "string" ? payload.colorHex : "",
      }
      : payload;
    return { ...normalized, id: row.record_id, updated_at: row.updated_at, deleted_at: row.deleted ? row.updated_at : null };
  } catch {
    return { id: row.record_id, updated_at: row.updated_at, deleted_at: row.deleted ? row.updated_at : null };
  }
}

async function nextVersion(env: Env): Promise<number> {
  const row = await env.DB.prepare("INSERT INTO sync_versions DEFAULT VALUES RETURNING version").first<{ version: number }>();
  return row?.version ?? 0;
}

async function readRecord(env: Env, userID: string, entity: string, recordID: string) {
  return env.DB.prepare(
    "SELECT entity, record_id, payload, deleted, version, updated_at FROM sync_records WHERE user_id = ? AND entity = ? AND record_id = ?",
  ).bind(userID, entity, recordID).first<SyncRecordRow>();
}

async function writeRecord(env: Env, userID: string, entity: string, recordID: string, payload: Payload | null, deleted = false): Promise<void> {
  const version = await nextVersion(env);
  const updatedAt = now();
  await env.DB.prepare(
    "INSERT INTO sync_records (user_id, entity, record_id, payload, deleted, version, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, entity, record_id) DO UPDATE SET payload = excluded.payload, deleted = excluded.deleted, version = excluded.version, updated_at = excluded.updated_at",
  ).bind(userID, entity, recordID, payload ? JSON.stringify({ ...payload, id: recordID }) : null, deleted ? 1 : 0, version, updatedAt).run();
}

async function entityApi(request: Request, env: Env, userID: string, entity: string, recordID?: string): Promise<Response> {
  if (!ENTITY_NAMES.has(entity)) return error("Route not found.", 404, "not_found");
  if (request.method === "GET" && !recordID) {
    const rows = await env.DB.prepare(
      "SELECT entity, record_id, payload, deleted, version, updated_at FROM sync_records WHERE user_id = ? AND entity = ? AND deleted = 0 ORDER BY updated_at DESC",
    ).bind(userID, entity).all<SyncRecordRow>();
    return json(rows.results.map(decodeRecord));
  }
  if (request.method === "POST" && !recordID) {
    const body = await request.json() as Payload;
    const id = typeof body.id === "string" && body.id ? body.id : crypto.randomUUID();
    await writeRecord(env, userID, entity, id, body);
    return json({ id }, 201);
  }
  if (request.method === "PATCH" && recordID) {
    const current = await readRecord(env, userID, entity, recordID);
    if (!current || current.deleted) return error("Record not found.", 404, "not_found");
    const patch = await request.json() as Payload;
    await writeRecord(env, userID, entity, recordID, { ...decodeRecord(current), ...patch, id: recordID });
    return json({ id: recordID });
  }
  if (request.method === "DELETE" && recordID) {
    const current = await readRecord(env, userID, entity, recordID);
    if (!current || current.deleted) return error("Record not found.", 404, "not_found");
    await writeRecord(env, userID, entity, recordID, null, true);
    return json({ deleted: recordID });
  }
  return error("Route not found.", 404, "not_found");
}

async function completePrintApi(request: Request, env: Env, userID: string): Promise<Response> {
  const body = await request.json() as Payload;
  const printID = typeof body.print_id === "string" ? body.print_id : "";
  const spoolID = typeof body.spool_id === "string" ? body.spool_id : "";
  const grams = typeof body.grams_used === "number" && Number.isFinite(body.grams_used) ? body.grams_used : NaN;
  if (!printID || !spoolID || !Number.isFinite(grams) || grams <= 0) return error("A print, spool, and positive filament amount are required.");
  const spoolRow = await readRecord(env, userID, "spools", spoolID);
  if (!spoolRow || spoolRow.deleted) return error("Spool not found.", 404, "not_found");
  const spool = decodeRecord(spoolRow);
  const currentWeight = numberValue(spool.current_weight_g, numberValue(spool.remainingWeight, 0));
  const timestamp = now();
  await writeRecord(env, userID, "prints", printID, {
    id: printID, name: typeof body.name === "string" ? body.name : "", spool_id: spoolID,
    printer_id: typeof body.printer_id === "string" ? body.printer_id : null,
    profile_id: typeof body.profile_id === "string" ? body.profile_id : null,
    project_id: typeof body.project_id === "string" ? body.project_id : null,
    material_id: typeof spool.material_id === "string" ? spool.material_id : "",
    date: timestamp, duration_minutes: numberValue(body.duration_minutes, 0), grams_used: grams,
    success: body.success !== false, category: typeof body.category === "string" ? body.category : "Final Part",
    cost: numberValue(body.cost, 0), notes: typeof body.notes === "string" ? body.notes : "",
  });
  await writeRecord(env, userID, "spools", spoolID, { ...spool, current_weight_g: Math.max(0, currentWeight - grams), last_used_date: timestamp });
  if (typeof body.printer_id === "string" && body.printer_id) {
    const printerRow = await readRecord(env, userID, "printers", body.printer_id);
    if (printerRow && !printerRow.deleted) {
      const printer = decodeRecord(printerRow);
      await writeRecord(env, userID, "printers", body.printer_id, { ...printer, total_print_hours: numberValue(printer.total_print_hours, 0) + numberValue(body.duration_minutes, 0) / 60 });
    }
  }
  return json({ print_id: printID }, 201);
}

async function transferApi(request: Request, env: Env, userID: string): Promise<Response> {
  const body = await request.json() as Payload;
  const transferID = typeof body.transfer_id === "string" ? body.transfer_id : "";
  const spoolID = typeof body.spool_id === "string" ? body.spool_id : "";
  const spoolRow = spoolID ? await readRecord(env, userID, "spools", spoolID) : null;
  if (!transferID || !spoolRow || spoolRow.deleted) return error("A valid transfer and spool are required.", 404, "not_found");
  const spool = decodeRecord(spoolRow);
  const toLocation = typeof body.to_location_id === "string" ? body.to_location_id : null;
  const slot = typeof body.ams_slot_label === "string" ? body.ams_slot_label : undefined;
  await writeRecord(env, userID, "spools", spoolID, { ...spool, storage_location_id: toLocation, ...(slot === undefined ? {} : { ams_slot_label: slot }) });
  await writeRecord(env, userID, "transfers", transferID, {
    id: transferID, spool_id: spoolID,
    from_location_id: typeof body.from_location_id === "string" ? body.from_location_id : null,
    to_location_id: toLocation, date: now(), notes: typeof body.notes === "string" ? body.notes : "",
  });
  return json({ transfer_id: transferID }, 201);
}

async function amsReassignApi(request: Request, env: Env, userID: string): Promise<Response> {
  const body = await request.json() as { printer_id?: string; assignments?: Array<{ slot_label?: string; spool_id?: string | null }> };
  if (!body.printer_id || !Array.isArray(body.assignments)) return error("A printer and assignments are required.");
  const printer = await readRecord(env, userID, "printers", body.printer_id);
  if (!printer || printer.deleted) return error("Printer not found.", 404, "not_found");
  const assignments = body.assignments.filter((item) => typeof item.slot_label === "string" && item.slot_label.length > 0);
  const labels = new Set(assignments.map((item) => item.slot_label as string));
  const requested = new Map(assignments.filter((item) => item.spool_id).map((item) => [item.spool_id as string, item.slot_label as string]));
  const rows = await env.DB.prepare(
    "SELECT entity, record_id, payload, deleted, version, updated_at FROM sync_records WHERE user_id = ? AND entity = 'spools' AND deleted = 0",
  ).bind(userID).all<SyncRecordRow>();
  const known = new Set(rows.results.map((row) => row.record_id));
  if ([...requested.keys()].some((id) => !known.has(id))) return error("One or more assigned spools were not found.", 404, "not_found");
  for (const row of rows.results) {
    const spool = decodeRecord(row);
    const current = typeof spool.ams_slot_label === "string" ? spool.ams_slot_label : "";
    const next = requested.get(row.record_id) ?? (labels.has(current) ? "" : current);
    if (next !== current) await writeRecord(env, userID, "spools", row.record_id, { ...spool, ams_slot_label: next });
  }
  return json({ printer_id: body.printer_id });
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
  if (path === "/api/v1/auth/logout-all" && request.method === "POST") {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM refresh_sessions WHERE user_id = ?").bind(userID),
      env.DB.prepare("DELETE FROM web_sessions WHERE user_id = ?").bind(userID),
    ]);
    const response = json({}); response.headers.append("Set-Cookie", "pk_session=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0"); return response;
  }
  if (path === "/api/v1/account" && request.method === "DELETE") {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM sync_records WHERE user_id = ?").bind(userID),
      env.DB.prepare("DELETE FROM sync_operations WHERE user_id = ?").bind(userID),
      env.DB.prepare("DELETE FROM refresh_sessions WHERE user_id = ?").bind(userID),
      env.DB.prepare("DELETE FROM web_sessions WHERE user_id = ?").bind(userID),
      env.DB.prepare("DELETE FROM users WHERE id = ?").bind(userID),
    ]);
    const response = json({}); response.headers.append("Set-Cookie", "pk_session=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0"); return response;
  }
  if (path === "/api/v1/entitlement" && (request.method === "GET" || request.method === "POST")) return entitlementApi(request, env, userID);
  if (path === "/api/v1/entitlement/verify" && request.method === "POST") return entitlementApi(request, env, userID);
  if (path === "/api/v1/sync" && (request.method === "GET" || request.method === "POST")) return sync(request, env, userID);
  if (path === "/api/v1/ops/complete-print" && request.method === "POST") return completePrintApi(request, env, userID);
  if (path === "/api/v1/ops/transfer" && request.method === "POST") return transferApi(request, env, userID);
  if (path === "/api/v1/ops/ams-reassign" && request.method === "POST") return amsReassignApi(request, env, userID);
  const entityMatch = path.match(/^\/api\/v1\/(spools|printers|profiles|prints|projects|transfers|maintenance)(?:\/([^/]+))?$/);
  if (entityMatch) return entityApi(request, env, userID, entityMatch[1] as string, entityMatch[2]);
  return error("Route not found.", 404, "not_found");
} } satisfies ExportedHandler<Env>;
