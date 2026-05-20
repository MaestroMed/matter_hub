# MIND lead-webhook Worker

> Cloudflare Worker that receives signed lead POSTs from any deployed client
> site and pushes them into the MIND iOS cockpit. Shipped as part of
> MIND `v1.0-alpha.5`.

## Quick deploy

```bash
cd mind/tools/cloudflare-worker
npm install
npm test                 # 16 Vitest cases on routing + HMAC
npm run dev              # local dev at http://127.0.0.1:8787
npm run deploy           # publish to Cloudflare
```

After the first deploy, set the four runtime secrets:

```bash
npx wrangler secret put WEBHOOK_SECRET   # openssl rand -hex 32
npx wrangler secret put APNS_KEY_P8       # paste the .p8 file contents
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_TEAM_ID
npx wrangler secret put APNS_DEVICE_TOKEN
```

Then create the KV namespace and copy the id/preview_id into
`wrangler.toml`:

```bash
npx wrangler kv:namespace create LEADS
npx wrangler kv:namespace create LEADS --preview
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/leads` | Ingest a signed lead. Body verified against `X-MIND-Signature` header. |
| `GET`  | `/v1/leads?since=ISO8601` | List stored leads (capped at 100). |
| `OPTIONS` | `/v1/leads` | CORS preflight (204). |

### Signing

HMAC-SHA256 over the raw request body bytes, lowercase hex (Stripe
convention). Same canonical encoding as the iOS
`LeadWebhookPayload.sign(payload:secret:)` helper in
`mind/Modules/GraphCore/Sources/LeadWebhookPayload.swift` and the npm
SDK in `mind/tools/npm-sdk` — the three sides MUST stay in lock-step.

### Required payload fields

```json
{
  "projectID": "C3F8D2A8-7B7A-4C39-8C66-7BCCD2FBE40B",
  "formType":  "contact",
  "contactName":  "Alice Martin",
  "contactEmail": "alice@example.com",
  "message":      "Bonjour, je souhaiterais ...",
  "sourceURL":    "https://www.azconstruction.fr/contact"
}
```

Optional fields: `contactPhone`, `clientIP`, `userAgent`, `receivedAt`.

`formType` MUST be one of `contact`, `devis`, `newsletter`, `other`.

## Architecture

```
Client browser
   POST /api/contact (your Next.js / Astro / static form)
       calls @mind/lead-webhook → signAndPost(payload, secret)
             POST /v1/leads (Cloudflare Worker)
                  HMAC verify → KV put → APNs push
                                            ↓
                                       MIND iOS cockpit
                                       (or pull fallback)
```

## Notes

- KV stores each lead for 30 days (`LEAD_TTL_SECONDS`). The iOS app
  pull-falls back via `GET /v1/leads?since=<lastSeen>` if push was
  missed (airplane mode, app uninstalled, APNs hiccup).
- APNs sending is best-effort. Push failures never fail the ingest —
  the KV write is the source of truth.
- The bundle id is hard-pinned to `app.mind.ios`. Any iOS rebrand
  must bump this here and in the iOS target's `CFBundleIdentifier`
  in lock-step.
- CORS is permissive on `Access-Control-Allow-Origin: *` because
  client sites POST cross-origin from arbitrary domains. Auth is
  enforced by the HMAC signature, not the origin header.
