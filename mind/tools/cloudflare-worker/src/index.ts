// v1.0-alpha.5 — MIND lead-webhook Cloudflare Worker.
//
// Receives signed POSTs from any deployed client site (Next.js,
// Astro, plain HTML) and pushes the lead into MIND's iOS cockpit
// via APNs. The same lead is stashed in Cloudflare KV for 30 days
// so the iOS app can pull-fallback in case a push was lost
// (push delivery is best-effort by design).
//
// v1.1.0 — Adds a second ingest route for Vercel deployment
// webhooks. Same APNs + KV shape, distinct payload + signature
// scheme (Vercel signs with SHA-1 HMAC under x-vercel-signature).
//
// Routes:
//   POST  /v1/leads             — ingest a signed lead
//   GET   /v1/leads?since=ISO   — list KV-stored leads (capped 100)
//   OPTIONS /v1/leads           — CORS preflight (204)
//   POST  /v1/vercel-webhook    — ingest a Vercel deployment event
//
// Required Worker secrets / vars:
//   WEBHOOK_SECRET, VERCEL_WEBHOOK_SECRET, APNS_KEY_P8, APNS_KEY_ID,
//   APNS_TEAM_ID, APNS_DEVICE_TOKEN, APNS_BUNDLE_ID, APNS_HOST,
//   LEAD_TTL_SECONDS
//
// KV bindings:
//   LEADS — keyed by `lead:<projectID>:<timestamp>:<uuid>` and
//           `vercel:<projectID>:<timestamp>:<deploymentID>`.

export interface Env {
  WEBHOOK_SECRET: string;
  VERCEL_WEBHOOK_SECRET: string;
  APNS_KEY_P8: string;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_DEVICE_TOKEN: string;
  APNS_BUNDLE_ID: string;
  APNS_HOST: string;
  LEAD_TTL_SECONDS: string;
  LEADS: KVNamespace;
}

export interface LeadPayload {
  projectID: string;
  formType: string;
  contactName: string;
  contactEmail: string;
  contactPhone?: string | null;
  message: string;
  sourceURL: string;
  clientIP?: string | null;
  userAgent?: string | null;
  receivedAt?: string;
}

export interface StoredLead extends LeadPayload {
  id: string;
  receivedAt: string;
}

// Allowed formType values. Keep in lockstep with the iOS Codable
// contract in mind/Modules/GraphCore/Sources/LeadWebhookPayload.swift
// and with the npm SDK in mind/tools/npm-sdk/src/types.ts.
const ALLOWED_FORM_TYPES = new Set(["contact", "devis", "newsletter", "other"]);

const REQUIRED_FIELDS: (keyof LeadPayload)[] = [
  "projectID",
  "formType",
  "contactName",
  "contactEmail",
  "message",
  "sourceURL",
];

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-MIND-Signature",
  "Access-Control-Max-Age": "86400",
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (url.pathname === "/v1/leads") {
      if (request.method === "POST") {
        return handleIngest(request, env, ctx);
      }
      if (request.method === "GET") {
        return handleList(url, env);
      }
      return json({ error: "method_not_allowed" }, 405);
    }

    // v1.1.0 — Vercel deployment webhook ingest. Same APNs + KV
    // pattern as /v1/leads but verifies a SHA-1 HMAC signature
    // (Vercel's legacy signing scheme) under the x-vercel-signature
    // header.
    if (url.pathname === "/v1/vercel-webhook") {
      if (request.method === "POST") {
        return handleVercelWebhook(request, env, ctx);
      }
      return json({ error: "method_not_allowed" }, 405);
    }

    return json({ error: "not_found" }, 404);
  },
};

// MARK: - POST /v1/leads

async function handleIngest(
  request: Request,
  env: Env,
  ctx: ExecutionContext
): Promise<Response> {
  let bodyBytes: ArrayBuffer;
  try {
    bodyBytes = await request.arrayBuffer();
  } catch {
    return json({ error: "body_unreadable" }, 400);
  }
  if (bodyBytes.byteLength === 0) {
    return json({ error: "empty_body" }, 400);
  }

  const signature = request.headers.get("X-MIND-Signature") ?? "";
  const valid = await verifySignature(bodyBytes, signature, env.WEBHOOK_SECRET);
  if (!valid) {
    return json({ error: "invalid_signature" }, 401);
  }

  let payload: LeadPayload;
  try {
    const text = new TextDecoder().decode(bodyBytes);
    payload = JSON.parse(text) as LeadPayload;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const validationError = validatePayload(payload);
  if (validationError) {
    return json({ error: "invalid_payload", field: validationError }, 400);
  }

  const leadID = crypto.randomUUID();
  const receivedAt = payload.receivedAt ?? new Date().toISOString();
  const stored: StoredLead = { ...payload, id: leadID, receivedAt };
  const key = `lead:${payload.projectID}:${Date.now()}:${leadID}`;

  try {
    const ttl = Math.max(60, parseInt(env.LEAD_TTL_SECONDS ?? "2592000", 10));
    await env.LEADS.put(key, JSON.stringify(stored), { expirationTtl: ttl });
  } catch {
    return json({ error: "kv_unavailable" }, 503);
  }

  // Push notification is best-effort — never fail the ingest just
  // because APNs is having a bad day. The KV write above is the
  // source of truth; the iOS app will pull-fallback within minutes.
  ctx.waitUntil(sendPushNotification(env, stored).catch(() => undefined));

  return json({ status: "queued", leadID }, 200);
}

function validatePayload(payload: LeadPayload): string | null {
  for (const field of REQUIRED_FIELDS) {
    const value = payload[field];
    if (typeof value !== "string" || value.trim().length === 0) {
      return field;
    }
  }
  if (!ALLOWED_FORM_TYPES.has(payload.formType)) {
    return "formType";
  }
  // Smoke-test the email — full RFC 5322 isn't worth shipping, but a
  // missing @ is a copy-paste mistake we can catch cheaply.
  if (!payload.contactEmail.includes("@")) {
    return "contactEmail";
  }
  return null;
}

// MARK: - GET /v1/leads

async function handleList(url: URL, env: Env): Promise<Response> {
  const since = url.searchParams.get("since");
  let sinceMs = 0;
  if (since) {
    const parsed = Date.parse(since);
    if (Number.isNaN(parsed)) {
      return json({ error: "invalid_since" }, 400);
    }
    sinceMs = parsed;
  }

  try {
    const listing = await env.LEADS.list({ prefix: "lead:", limit: 100 });
    const leads: StoredLead[] = [];
    for (const key of listing.keys) {
      // Key shape: lead:<projectID>:<ts>:<uuid> — parse the ts
      // segment so we can skip a KV.get for stale rows.
      const parts = key.name.split(":");
      const ts = parts.length >= 4 ? parseInt(parts[2], 10) : 0;
      if (sinceMs > 0 && Number.isFinite(ts) && ts < sinceMs) {
        continue;
      }
      const value = await env.LEADS.get(key.name);
      if (!value) continue;
      try {
        leads.push(JSON.parse(value) as StoredLead);
      } catch {
        // Skip any value that fails to parse — operator can clean it
        // up via wrangler. Don't 500 the whole listing for one bad row.
      }
    }
    return json({ leads, count: leads.length }, 200);
  } catch {
    return json({ error: "kv_unavailable" }, 503);
  }
}

// MARK: - HMAC verification

async function verifySignature(
  body: ArrayBuffer,
  signature: string,
  secret: string
): Promise<boolean> {
  if (!signature) return false;
  if (!secret) return false;
  const expected = await signBody(body, secret);
  return timingSafeEqual(expected, signature.toLowerCase());
}

export async function signBody(body: ArrayBuffer, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const macBuffer = await crypto.subtle.sign("HMAC", key, body);
  return toHex(new Uint8Array(macBuffer));
}

function toHex(bytes: Uint8Array): string {
  let out = "";
  for (let i = 0; i < bytes.length; i++) {
    out += bytes[i].toString(16).padStart(2, "0");
  }
  return out;
}

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

// MARK: - APNs push

async function sendPushNotification(env: Env, lead: StoredLead): Promise<void> {
  if (!env.APNS_KEY_P8 || !env.APNS_KEY_ID || !env.APNS_TEAM_ID || !env.APNS_DEVICE_TOKEN) {
    return; // No APNs configured — skip silently.
  }
  const jwt = await mintAPNsJWT(env);
  const url = `https://${env.APNS_HOST || "api.push.apple.com"}/3/device/${env.APNS_DEVICE_TOKEN}`;
  const body = buildPushPayload(lead);

  await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": env.APNS_BUNDLE_ID || "app.mind.ios",
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body,
  });
}

function buildPushPayload(lead: StoredLead): string {
  return JSON.stringify({
    aps: {
      alert: {
        title: "Nouveau lead",
        body: `${lead.contactName} via ${lead.formType}`,
      },
      sound: "default",
      badge: 1,
    },
    lead: {
      id: lead.id,
      projectID: lead.projectID,
      formType: lead.formType,
      contactName: lead.contactName,
      contactEmail: lead.contactEmail,
      sourceURL: lead.sourceURL,
      receivedAt: lead.receivedAt,
    },
  });
}

async function mintAPNsJWT(env: Env): Promise<string> {
  const header = { alg: "ES256", kid: env.APNS_KEY_ID };
  const claims = {
    iss: env.APNS_TEAM_ID,
    iat: Math.floor(Date.now() / 1000),
  };
  const encoder = new TextEncoder();
  const headerSeg = base64url(encoder.encode(JSON.stringify(header)));
  const claimsSeg = base64url(encoder.encode(JSON.stringify(claims)));
  const signingInput = `${headerSeg}.${claimsSeg}`;

  const pkcs8 = parsePKCS8(env.APNS_KEY_P8);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput)
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

function parsePKCS8(pem: string): ArrayBuffer {
  const stripped = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(stripped);
  const buffer = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    buffer[i] = binary.charCodeAt(i);
  }
  return buffer.buffer;
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// MARK: - Vercel webhook (v1.1.0)

/// Wire-format slice we read from a Vercel webhook event. Vercel
/// ships a flat envelope with `type`, `createdAt`, and a `payload`
/// dict carrying the deployment + project + commit metadata. We
/// don't decode the entire envelope — only the fields the iOS
/// notification + KV row needs.
export interface VercelWebhookEvent {
  type: string;
  createdAt: number;
  payload: {
    deploymentId?: string;
    projectId: string;
    name?: string;
    url?: string;
    team?: { name?: string; id?: string };
    meta?: {
      githubCommitSha?: string;
      githubCommitMessage?: string;
      githubCommitAuthorName?: string;
    };
  };
}

/// Projection shipped to the iOS device under `userInfo["vercel"]`.
/// Mirrors the Swift `PushPayloadParser.VercelPayload` value type
/// so a careless rename surfaces as a divergent test failure on
/// both sides.
export interface VercelPushPayload {
  type: string;
  projectId: string;
  deploymentId?: string;
  url?: string;
  commitSHA?: string;
  commitMessage?: string;
  authorEmail?: string;
  occurredAt: string;
}

async function handleVercelWebhook(
  request: Request,
  env: Env,
  ctx: ExecutionContext
): Promise<Response> {
  const rawBody = await request.text();
  if (rawBody.length === 0) {
    return json({ error: "empty_body" }, 400);
  }

  const sig = request.headers.get("x-vercel-signature") ?? "";
  if (!env.VERCEL_WEBHOOK_SECRET) {
    return json({ error: "secret_unset" }, 401);
  }
  const expected = await signBodySHA1(rawBody, env.VERCEL_WEBHOOK_SECRET);
  if (!sig || !timingSafeEqual(sig.toLowerCase(), expected)) {
    return json({ error: "unauthorized" }, 401);
  }

  let event: VercelWebhookEvent;
  try {
    event = JSON.parse(rawBody) as VercelWebhookEvent;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (!event.payload || typeof event.payload.projectId !== "string" || event.payload.projectId.length === 0) {
    return json({ error: "invalid_payload" }, 400);
  }

  const occurredAt = new Date(typeof event.createdAt === "number" ? event.createdAt : Date.now()).toISOString();
  const vercelPayload: VercelPushPayload = {
    type: event.type,
    projectId: event.payload.projectId,
    deploymentId: event.payload.deploymentId,
    url: event.payload.url,
    commitSHA: event.payload.meta?.githubCommitSha,
    commitMessage: event.payload.meta?.githubCommitMessage,
    authorEmail: event.payload.meta?.githubCommitAuthorName,
    occurredAt,
  };

  const teamLabel = event.payload.team?.name?.trim();
  const projectLabel = event.payload.name?.trim() || event.payload.projectId;
  const titlePrefix = teamLabel && teamLabel.length > 0 ? teamLabel : "Vercel";
  const statusLabel = vercelStatusLabel(event.type);
  const commitMessage = (event.payload.meta?.githubCommitMessage ?? "").trim().slice(0, 80);
  const bodyText = commitMessage.length > 0 ? `${statusLabel} · ${commitMessage}` : statusLabel;

  const pushBody = JSON.stringify({
    aps: {
      alert: {
        title: `${titlePrefix} — ${projectLabel}`,
        body: bodyText,
      },
      sound: "default",
      "thread-id": `vercel.${event.payload.projectId}`,
    },
    vercel: vercelPayload,
  });

  // KV write is the source of truth: even if APNs is down the iOS
  // app's pull-fallback (future iteration) catches the event up.
  const deploymentKeySegment = event.payload.deploymentId ?? "unknown";
  try {
    await env.LEADS.put(
      `vercel:${event.payload.projectId}:${Date.now()}:${deploymentKeySegment}`,
      JSON.stringify(vercelPayload),
      { expirationTtl: 60 * 60 * 24 * 7 } // 7 days
    );
  } catch {
    return json({ error: "kv_unavailable" }, 503);
  }

  // APNs is best-effort, same posture as the lead path.
  ctx.waitUntil(sendVercelAPNs(env, pushBody).catch(() => undefined));

  return json({ status: "queued" }, 200);
}

/// FR labels surfaced in the APNs body for every Vercel event type.
/// Mirrored by the iOS-side strings catalog so a manual decode in
/// the Lock Screen widget reads the same vocabulary.
export function vercelStatusLabel(type: string): string {
  switch (type) {
    case "deployment.created":
    case "deployment-created":
    case "deployment":
      return "Déploiement démarré";
    case "deployment.succeeded":
    case "deployment-succeeded":
    case "deployment-ready":
    case "deployment.ready":
      return "✓ Déploiement réussi";
    case "deployment.error":
    case "deployment-error":
      return "❌ Build échoué";
    case "deployment.canceled":
    case "deployment-canceled":
      return "Annulé";
    default:
      return "Évènement Vercel";
  }
}

/// Signs a UTF-8 body string with HMAC-SHA1 and returns the
/// signature as a lowercase 64-char hex string. Vercel historically
/// signs with SHA-1 (not SHA-256) — keeping a separate helper from
/// `signBody` (which uses SHA-256 for the MIND lead path) means
/// the two contracts never get accidentally mixed.
export async function signBodySHA1(body: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"]
  );
  const macBuffer = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(body)
  );
  const bytes = new Uint8Array(macBuffer);
  let out = "";
  for (let i = 0; i < bytes.length; i++) {
    out += bytes[i].toString(16).padStart(2, "0");
  }
  return out;
}

/// Pushes a pre-built APNs payload string to the configured device.
/// Same APNs auth path as `sendPushNotification` for leads; the
/// distinction is the JSON body (the alert wording + the `vercel`
/// userInfo dict the NSE decorates).
async function sendVercelAPNs(env: Env, body: string): Promise<void> {
  if (!env.APNS_KEY_P8 || !env.APNS_KEY_ID || !env.APNS_TEAM_ID || !env.APNS_DEVICE_TOKEN) {
    return;
  }
  const jwt = await mintAPNsJWT(env);
  const url = `https://${env.APNS_HOST || "api.push.apple.com"}/3/device/${env.APNS_DEVICE_TOKEN}`;
  await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": env.APNS_BUNDLE_ID || "app.mind.ios",
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body,
  });
}

// MARK: - Helpers

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...CORS_HEADERS,
    },
  });
}
