// v1.0-alpha.5 — Public entry point for `@mind/lead-webhook`.
//
// One-liner usage from a Next.js / Astro / Remix API route:
//
//     import { sendLeadToMIND } from "@mind/lead-webhook";
//     await sendLeadToMIND(payload, {
//       webhookURL: process.env.MIND_WEBHOOK_URL!,
//       secret:     process.env.MIND_WEBHOOK_SECRET!,
//     });
//
// All errors are typed `MINDWebhookError` with a `code` field so the
// caller can branch on `signatureRejected` vs. `timeout` vs. `network`
// without parsing message strings.

import { sign } from "./sign.js";
import {
  LeadPayload,
  MINDWebhookError,
  SendLeadOptions,
  SendLeadResult,
} from "./types.js";

export * from "./types.js";
export { sign } from "./sign.js";

const REQUIRED_FIELDS: (keyof LeadPayload)[] = [
  "projectID",
  "formType",
  "contactName",
  "contactEmail",
  "message",
  "sourceURL",
];

/**
 * Sign-and-POST a lead to the MIND Cloudflare Worker.
 *
 * The payload is canonical-JSON encoded (sorted keys, no
 * pretty-printing) so the signed bytes match what gets posted —
 * sign-the-bytes-you-post is the only safe HMAC contract.
 *
 * Throws `MINDWebhookError` on validation, transport, or server error.
 * Best-effort by design — callers should `.catch(console.error)` and
 * never let a webhook failure block the end-user's form submission.
 */
export async function sendLeadToMIND(
  payload: LeadPayload,
  options: SendLeadOptions
): Promise<SendLeadResult> {
  validatePayload(payload);

  const enriched = { ...payload, receivedAt: new Date().toISOString() };
  const body = canonicalEncode(enriched);
  const signature = sign(body, options.secret);
  const timeout = options.timeout ?? 5000;

  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => controller.abort(), timeout);
  let response: Response;
  try {
    response = await fetch(options.webhookURL.replace(/\/+$/, "") + "/v1/leads", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-MIND-Signature": signature,
      },
      body,
      signal: controller.signal,
    });
  } catch (err) {
    if ((err as Error).name === "AbortError") {
      throw new MINDWebhookError("timeout", `POST to ${options.webhookURL} timed out after ${timeout}ms`);
    }
    throw new MINDWebhookError("network", (err as Error).message);
  } finally {
    clearTimeout(timeoutHandle);
  }

  if (response.status === 401) {
    throw new MINDWebhookError("signatureRejected", "Worker rejected the HMAC signature", 401);
  }
  if (response.status >= 400 && response.status < 500) {
    let detail = "";
    try { detail = JSON.stringify(await response.json()); } catch { /* ignore */ }
    throw new MINDWebhookError("badRequest", `Worker rejected payload: ${detail || response.statusText}`, response.status);
  }
  if (response.status >= 500) {
    throw new MINDWebhookError("serverError", `Worker errored: ${response.statusText}`, response.status);
  }

  let parsed: SendLeadResult;
  try {
    parsed = (await response.json()) as SendLeadResult;
  } catch {
    throw new MINDWebhookError("unknown", "Worker returned 2xx with unparseable body");
  }
  return parsed;
}

/**
 * Canonical JSON encoder — sorted top-level keys, no pretty-printing,
 * stable ordering so the signature computed locally matches the
 * signature the Worker recomputes on receipt. Mirrors the iOS
 * `LeadWebhookPayload.canonicalEncoder` settings (`sortedKeys`,
 * `withoutEscapingSlashes`).
 */
export function canonicalEncode(payload: Record<string, unknown>): string {
  const keys = Object.keys(payload).sort();
  const ordered: Record<string, unknown> = {};
  for (const k of keys) {
    if (payload[k] !== undefined) ordered[k] = payload[k];
  }
  // JSON.stringify already preserves insertion order for string keys
  // in V8 — the explicit sort above gives us byte-stable output.
  return JSON.stringify(ordered);
}

function validatePayload(payload: LeadPayload): void {
  for (const field of REQUIRED_FIELDS) {
    const value = payload[field];
    if (typeof value !== "string" || value.trim().length === 0) {
      throw new MINDWebhookError("validation", `Missing or empty required field: ${field}`);
    }
  }
  if (!payload.contactEmail.includes("@")) {
    throw new MINDWebhookError("validation", "contactEmail must contain '@'");
  }
}
