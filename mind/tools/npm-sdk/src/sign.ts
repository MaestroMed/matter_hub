// v1.0-alpha.5 — Pure HMAC helper for `@mind/lead-webhook`.
//
// Byte-for-byte equivalent to the iOS
// `LeadWebhookPayload.sign(payload:secret:)` helper and the Worker's
// `signBody(...)` — same SHA-256, same lowercase hex, same secret-as-
// UTF-8-bytes key shape. Cross-platform parity is the whole point of
// pulling this out as its own module: tests assert the exact same
// signature regardless of which side computed it.

import { createHmac } from "node:crypto";

/**
 * Computes the HMAC-SHA256 of `payloadJSON` using `secret`, returns a
 * 64-character lowercase hex string.
 *
 * The caller is responsible for canonical JSON encoding (sorted keys,
 * no pretty-printing) — sign-the-bytes-you-post is the only safe
 * contract. See `canonicalEncode(...)` in `./index.ts`.
 */
export function sign(payloadJSON: string, secret: string): string {
  const mac = createHmac("sha256", secret);
  mac.update(payloadJSON, "utf8");
  return mac.digest("hex").toLowerCase();
}
