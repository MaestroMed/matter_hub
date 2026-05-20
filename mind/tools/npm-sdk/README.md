# @mind/lead-webhook

> Tiny, dependency-free SDK to forward signed lead webhooks from any
> deployed client site to the MIND iOS cockpit. Ship the same way
> Stripe ships their webhook signing helpers — paste it in, get a
> typed `sendLeadToMIND(payload, options)`, ship leads into Mehdi's
> pocket in < 200ms.

Shipped as part of MIND `v1.0-alpha.5`.

## Install

```bash
npm install @mind/lead-webhook
```

Requires Node 18+ (native `fetch`).

## Usage

Drop into a Next.js App Router API route:

```ts
// app/api/contact/route.ts
import { sendLeadToMIND } from "@mind/lead-webhook";

export async function POST(req: Request) {
  const body = await req.json();

  // your existing validation + DB save logic...

  // forward to MIND cockpit (best-effort — don't block UX)
  await sendLeadToMIND(
    {
      projectID:    process.env.MIND_PROJECT_ID!,
      formType:     "contact",
      contactName:  body.name,
      contactEmail: body.email,
      contactPhone: body.phone,
      message:      body.message,
      sourceURL:    req.headers.get("referer") ?? "",
    },
    {
      webhookURL: process.env.MIND_WEBHOOK_URL!,
      secret:     process.env.MIND_WEBHOOK_SECRET!,
    }
  ).catch(console.error);

  return Response.json({ ok: true });
}
```

## Environment

| Variable | Example | Description |
|----------|---------|-------------|
| `MIND_WEBHOOK_URL` | `https://mind-lead-webhook.mehdi.workers.dev` | The Cloudflare Worker URL. |
| `MIND_WEBHOOK_SECRET` | 64-char hex | HMAC-SHA256 secret. Same value lives in MIND iOS Settings → "Lead webhook". |
| `MIND_PROJECT_ID` | `C3F8D2A8-7B7A-4C39-8C66-7BCCD2FBE40B` | UUID of the matching MIND Project. Copy from Settings. |

## Error handling

All thrown errors are typed `MINDWebhookError` with a `code` field:

```ts
try {
  await sendLeadToMIND(payload, opts);
} catch (err) {
  if (err instanceof MINDWebhookError) {
    switch (err.code) {
      case "validation":         /* fix the payload */ break;
      case "signatureRejected":  /* rotate the secret */ break;
      case "timeout":            /* retry once */ break;
      case "network":            /* offline / DNS */ break;
      case "badRequest":         /* worker rejected payload */ break;
      case "serverError":        /* worker/KV down */ break;
    }
  }
}
```

## Contract

The signature is HMAC-SHA256 over the canonical-JSON-encoded body
(sorted keys, no pretty-printing), sent in the `X-MIND-Signature`
header as lowercase hex. The contract is byte-for-byte identical to:

- iOS `LeadWebhookPayload.sign(payload:secret:)` in
  `mind/Modules/GraphCore/Sources/LeadWebhookPayload.swift`
- Cloudflare Worker `signBody(...)` in
  `mind/tools/cloudflare-worker/src/index.ts`

The three sides MUST stay in lock-step.

## License

MIT
