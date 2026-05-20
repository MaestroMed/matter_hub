// v1.0-alpha.5 — MIND lead-webhook Worker tests.
//
// Locks the routing contract and the HMAC verification path so a
// careless edit can't ship a Worker that accepts every POST or
// rejects every legitimate POST. Uses an in-memory KV stub +
// stubbed APNs env so the tests stay hermetic — no network, no
// real Cloudflare account.

import { describe, expect, it, beforeEach } from "vitest";
import worker, {
  signBody,
  signBodySHA1,
  timingSafeEqual,
  vercelStatusLabel,
  Env,
} from "../src/index";

class FakeKV {
  store = new Map<string, { value: string; ttl: number }>();
  async put(key: string, value: string, opts?: { expirationTtl?: number }) {
    this.store.set(key, { value, ttl: opts?.expirationTtl ?? 0 });
  }
  async get(key: string) {
    return this.store.get(key)?.value ?? null;
  }
  async list({ prefix, limit }: { prefix?: string; limit?: number }) {
    const matches = [...this.store.keys()]
      .filter((k) => (prefix ? k.startsWith(prefix) : true))
      .slice(0, limit ?? 100)
      .map((name) => ({ name }));
    return { keys: matches, list_complete: true, cursor: "" };
  }
}

function makeEnv(overrides: Partial<Env> = {}): Env {
  return {
    WEBHOOK_SECRET: "test-secret",
    VERCEL_WEBHOOK_SECRET: "test-vercel-secret",
    APNS_KEY_P8: "",
    APNS_KEY_ID: "",
    APNS_TEAM_ID: "",
    APNS_DEVICE_TOKEN: "",
    APNS_BUNDLE_ID: "app.mind.ios",
    APNS_HOST: "api.push.apple.com",
    LEAD_TTL_SECONDS: "2592000",
    LEADS: new FakeKV() as unknown as KVNamespace,
    ...overrides,
  };
}

function makeCtx(): ExecutionContext {
  return {
    waitUntil: () => {},
    passThroughOnException: () => {},
    props: {} as never,
  } as unknown as ExecutionContext;
}

function validPayload() {
  return {
    projectID: "C3F8D2A8-7B7A-4C39-8C66-7BCCD2FBE40B",
    formType: "contact",
    contactName: "Alice Martin",
    contactEmail: "alice@example.com",
    contactPhone: "+33 6 12 34 56 78",
    message: "Hello, je voudrais un devis",
    sourceURL: "https://www.azconstruction.fr/contact",
  };
}

async function signedPostRequest(body: object, secret: string): Promise<Request> {
  const bodyText = JSON.stringify(body);
  const signature = await signBody(new TextEncoder().encode(bodyText).buffer, secret);
  return new Request("https://w.example.com/v1/leads", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-MIND-Signature": signature,
    },
    body: bodyText,
  });
}

describe("timingSafeEqual", () => {
  it("returns true for identical strings", () => {
    expect(timingSafeEqual("abc", "abc")).toBe(true);
  });
  it("returns false for different lengths", () => {
    expect(timingSafeEqual("a", "ab")).toBe(false);
  });
  it("returns false for one-bit difference", () => {
    expect(timingSafeEqual("abc", "abd")).toBe(false);
  });
});

describe("POST /v1/leads", () => {
  let env: Env;
  beforeEach(() => {
    env = makeEnv();
  });

  it("accepts a correctly signed payload and stores it in KV", async () => {
    const req = await signedPostRequest(validPayload(), "test-secret");
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(200);
    const body = (await res.json()) as { status: string; leadID: string };
    expect(body.status).toBe("queued");
    expect(body.leadID).toMatch(/^[0-9a-f-]{36}$/);

    const fake = env.LEADS as unknown as FakeKV;
    expect(fake.store.size).toBe(1);
    const stored = JSON.parse([...fake.store.values()][0].value);
    expect(stored.contactName).toBe("Alice Martin");
    expect(stored.receivedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it("rejects a payload signed with the wrong secret", async () => {
    const req = await signedPostRequest(validPayload(), "wrong-secret");
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(401);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe("invalid_signature");
  });

  it("rejects a payload missing the signature header", async () => {
    const bodyText = JSON.stringify(validPayload());
    const req = new Request("https://w.example.com/v1/leads", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: bodyText,
    });
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(401);
  });

  it("rejects an empty body", async () => {
    const sig = await signBody(new TextEncoder().encode("").buffer, "test-secret");
    const req = new Request("https://w.example.com/v1/leads", {
      method: "POST",
      headers: { "X-MIND-Signature": sig },
      body: "",
    });
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe("empty_body");
  });

  it("rejects a payload missing a required field", async () => {
    const broken = { ...validPayload(), contactEmail: "" };
    const req = await signedPostRequest(broken, "test-secret");
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string; field: string };
    expect(body.error).toBe("invalid_payload");
    expect(body.field).toBe("contactEmail");
  });

  it("rejects a payload with an unknown formType", async () => {
    const broken = { ...validPayload(), formType: "spam" };
    const req = await signedPostRequest(broken, "test-secret");
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(400);
    const body = (await res.json()) as { field: string };
    expect(body.field).toBe("formType");
  });

  it("rejects a payload with a malformed email", async () => {
    const broken = { ...validPayload(), contactEmail: "not-an-email" };
    const req = await signedPostRequest(broken, "test-secret");
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(400);
    const body = (await res.json()) as { field: string };
    expect(body.field).toBe("contactEmail");
  });

  it("rejects non-JSON bodies even when signed", async () => {
    const text = "<html>not json</html>";
    const sig = await signBody(new TextEncoder().encode(text).buffer, "test-secret");
    const req = new Request("https://w.example.com/v1/leads", {
      method: "POST",
      headers: { "X-MIND-Signature": sig },
      body: text,
    });
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe("invalid_json");
  });

  it("stores the lead with the configured TTL", async () => {
    env = makeEnv({ LEAD_TTL_SECONDS: "1234" });
    const req = await signedPostRequest(validPayload(), "test-secret");
    await worker.fetch(req, env, makeCtx());
    const fake = env.LEADS as unknown as FakeKV;
    const stored = [...fake.store.values()][0];
    expect(stored.ttl).toBe(1234);
  });
});

describe("GET /v1/leads", () => {
  let env: Env;
  beforeEach(() => {
    env = makeEnv();
  });

  it("returns an empty list when KV is empty", async () => {
    const req = new Request("https://w.example.com/v1/leads", { method: "GET" });
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(200);
    const body = (await res.json()) as { leads: unknown[]; count: number };
    expect(body.leads).toEqual([]);
    expect(body.count).toBe(0);
  });

  it("returns stored leads, capped at 100", async () => {
    const fake = env.LEADS as unknown as FakeKV;
    const sample = { ...validPayload(), id: "x", receivedAt: new Date().toISOString() };
    await fake.put(`lead:${sample.projectID}:${Date.now()}:abc`, JSON.stringify(sample));
    const req = new Request("https://w.example.com/v1/leads", { method: "GET" });
    const res = await worker.fetch(req, env, makeCtx());
    const body = (await res.json()) as { leads: unknown[]; count: number };
    expect(body.count).toBe(1);
  });

  it("filters by `since` query parameter using the key timestamp", async () => {
    const fake = env.LEADS as unknown as FakeKV;
    const oldTs = Date.now() - 1_000_000;
    const newTs = Date.now();
    const old = { ...validPayload(), id: "old", receivedAt: new Date(oldTs).toISOString() };
    const fresh = { ...validPayload(), id: "new", receivedAt: new Date(newTs).toISOString() };
    await fake.put(`lead:${old.projectID}:${oldTs}:o1`, JSON.stringify(old));
    await fake.put(`lead:${fresh.projectID}:${newTs}:n1`, JSON.stringify(fresh));

    const sinceISO = new Date(newTs - 1).toISOString();
    const req = new Request(`https://w.example.com/v1/leads?since=${encodeURIComponent(sinceISO)}`, {
      method: "GET",
    });
    const res = await worker.fetch(req, env, makeCtx());
    const body = (await res.json()) as { leads: { id: string }[] };
    expect(body.leads.length).toBe(1);
    expect(body.leads[0].id).toBe("new");
  });

  it("400s when `since` is unparseable", async () => {
    const req = new Request("https://w.example.com/v1/leads?since=not-a-date", { method: "GET" });
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(400);
  });
});

describe("OPTIONS /v1/leads", () => {
  it("returns 204 with CORS headers", async () => {
    const req = new Request("https://w.example.com/v1/leads", { method: "OPTIONS" });
    const res = await worker.fetch(req, makeEnv(), makeCtx());
    expect(res.status).toBe(204);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(res.headers.get("Access-Control-Allow-Methods")).toContain("POST");
    expect(res.headers.get("Access-Control-Allow-Headers")).toContain("X-MIND-Signature");
  });
});

describe("misc routing", () => {
  it("returns 404 for unknown paths", async () => {
    const req = new Request("https://w.example.com/v1/unknown", { method: "GET" });
    const res = await worker.fetch(req, makeEnv(), makeCtx());
    expect(res.status).toBe(404);
  });

  it("returns 405 for unsupported methods on /v1/leads", async () => {
    const req = new Request("https://w.example.com/v1/leads", { method: "PUT" });
    const res = await worker.fetch(req, makeEnv(), makeCtx());
    expect(res.status).toBe(405);
  });
});

// MARK: - Vercel webhook (v1.1.0)

function vercelEvent(overrides: Partial<{
  type: string;
  createdAt: number;
  payload: object;
}> = {}) {
  return {
    type: "deployment.succeeded",
    createdAt: 1_716_000_000_000,
    payload: {
      deploymentId: "dpl_abc123",
      projectId: "prj_xyz789",
      name: "az-construction",
      url: "az-construction-abc123.vercel.app",
      team: { name: "Numelite", id: "team_1" },
      meta: {
        githubCommitSha: "f1e2d3c4b5a6978899aabbccddeeff0011223344",
        githubCommitMessage: "feat: refresh hero section",
        githubCommitAuthorName: "Mehdi Nafaa",
      },
    },
    ...overrides,
  };
}

async function signedVercelRequest(body: object, secret: string): Promise<Request> {
  const bodyText = JSON.stringify(body);
  const sig = await signBodySHA1(bodyText, secret);
  return new Request("https://w.example.com/v1/vercel-webhook", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-vercel-signature": sig,
    },
    body: bodyText,
  });
}

describe("POST /v1/vercel-webhook (v1.1.0)", () => {
  let env: Env;
  beforeEach(() => {
    env = makeEnv();
  });

  it("accepts a SHA-1 HMAC-signed event and stores the vercel row in KV", async () => {
    const req = await signedVercelRequest(vercelEvent(), "test-vercel-secret");
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(200);
    const body = (await res.json()) as { status: string };
    expect(body.status).toBe("queued");

    const fake = env.LEADS as unknown as FakeKV;
    expect(fake.store.size).toBe(1);
    const [key] = [...fake.store.keys()];
    expect(key).toMatch(/^vercel:prj_xyz789:\d+:dpl_abc123$/);
    const stored = JSON.parse([...fake.store.values()][0].value);
    expect(stored.type).toBe("deployment.succeeded");
    expect(stored.projectId).toBe("prj_xyz789");
    expect(stored.deploymentId).toBe("dpl_abc123");
    expect(stored.commitSHA).toBe("f1e2d3c4b5a6978899aabbccddeeff0011223344");
    expect(stored.commitMessage).toBe("feat: refresh hero section");
    expect(stored.occurredAt).toBe(new Date(1_716_000_000_000).toISOString());
  });

  it("rejects an event signed with the wrong secret", async () => {
    const req = await signedVercelRequest(vercelEvent(), "wrong-secret");
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(401);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe("unauthorized");

    const fake = env.LEADS as unknown as FakeKV;
    expect(fake.store.size).toBe(0);
  });

  it("rejects an event whose payload lacks a projectId", async () => {
    const broken = vercelEvent({ payload: { deploymentId: "dpl_no_proj" } as object });
    const req = await signedVercelRequest(broken, "test-vercel-secret");
    const res = await worker.fetch(req, env, makeCtx());
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe("invalid_payload");

    const fake = env.LEADS as unknown as FakeKV;
    expect(fake.store.size).toBe(0);
  });

  it("uses the right FR label per Vercel event type", () => {
    expect(vercelStatusLabel("deployment.created")).toBe("Déploiement démarré");
    expect(vercelStatusLabel("deployment.succeeded")).toBe("✓ Déploiement réussi");
    expect(vercelStatusLabel("deployment.error")).toBe("❌ Build échoué");
    expect(vercelStatusLabel("deployment.canceled")).toBe("Annulé");
    expect(vercelStatusLabel("deployment-ready")).toBe("✓ Déploiement réussi");
    expect(vercelStatusLabel("unknown.future.event")).toBe("Évènement Vercel");
  });
});
