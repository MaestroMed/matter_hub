// v1.0-alpha.5 — Public type contract for `@mind/lead-webhook`.
//
// Mirrors the iOS LeadWebhookPayload Codable shape in
// mind/Modules/GraphCore/Sources/LeadWebhookPayload.swift and the
// Worker validator in mind/tools/cloudflare-worker/src/index.ts.
// The three sides MUST stay in lock-step — a field rename here is a
// breaking change for every deployed client site.

export type LeadFormType = "contact" | "devis" | "newsletter" | "other";

export interface LeadPayload {
  /** UUID of the MIND Project — see Settings → "Copier mon Project ID". */
  projectID: string;
  formType: LeadFormType;
  contactName: string;
  contactEmail: string;
  contactPhone?: string;
  message: string;
  /** Page URL where the form lives. Usually `request.headers.referer`. */
  sourceURL: string;
  /** Best-effort client IP. The Worker hashes it before storing. */
  clientIP?: string;
  /** Browser user-agent string, surfaces in the iOS lead detail row. */
  userAgent?: string;
}

export interface SendLeadOptions {
  /** Worker URL, e.g. `https://mind-lead-webhook.mehdi.workers.dev` */
  webhookURL: string;
  /** Shared HMAC secret. The same value lives in MIND iOS Settings. */
  secret: string;
  /** Request timeout in milliseconds. Defaults to 5_000. */
  timeout?: number;
}

export interface SendLeadResult {
  status: "queued";
  leadID: string;
}

/**
 * Error codes thrown by `sendLeadToMIND`. Callers branch on
 * `err.code` to decide whether to retry, log, or surface to the
 * end-user (typically: don't surface — leads should never block UX).
 */
export type MINDWebhookErrorCode =
  | "validation"
  | "signatureRejected"
  | "badRequest"
  | "serverError"
  | "timeout"
  | "network"
  | "unknown";

export class MINDWebhookError extends Error {
  public readonly code: MINDWebhookErrorCode;
  public readonly status?: number;
  constructor(code: MINDWebhookErrorCode, message: string, status?: number) {
    super(message);
    this.name = "MINDWebhookError";
    this.code = code;
    this.status = status;
  }
}
