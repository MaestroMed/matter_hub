// v1.0-alpha.5 — `sendLeadToMIND` integration tests with mocked
// fetch + AbortController. Locks the public contract: success path,
// every typed error code, and the validation short-circuit.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { sendLeadToMIND, canonicalEncode, MINDWebhookError } from "../src/index";
import { LeadPayload } from "../src/types";

const ORIGINAL_FETCH = globalThis.fetch;

function validPayload(): LeadPayload {
  return {
    projectID: "C3F8D2A8-7B7A-4C39-8C66-7BCCD2FBE40B",
    formType: "contact",
    contactName: "Alice Martin",
    contactEmail: "alice@example.com",
    message: "Hello",
    sourceURL: "https://www.azconstruction.fr/contact",
  };
}

function mockFetch(handler: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>) {
  globalThis.fetch = vi.fn(handler) as unknown as typeof fetch;
}

describe("sendLeadToMIND", () => {
  beforeEach(() => {
    globalThis.fetch = ORIGINAL_FETCH;
  });
  afterEach(() => {
    globalThis.fetch = ORIGINAL_FETCH;
  });

  it("posts a signed body and returns the worker's leadID", async () => {
    const captured: { url: string; init?: RequestInit } = { url: "" };
    mockFetch(async (input, init) => {
      captured.url = String(input);
      captured.init = init;
      return new Response(JSON.stringify({ status: "queued", leadID: "abc-123" }), { status: 200 });
    });

    const result = await sendLeadToMIND(validPayload(), {
      webhookURL: "https://w.example.com",
      secret: "s",
    });
    expect(result).toEqual({ status: "queued", leadID: "abc-123" });
    expect(captured.url).toBe("https://w.example.com/v1/leads");

    const headers = new Headers(captured.init?.headers as HeadersInit);
    expect(headers.get("X-MIND-Signature")).toMatch(/^[0-9a-f]{64}$/);
    expect(headers.get("content-type")).toBe("application/json");
  });

  it("throws `signatureRejected` on a 401", async () => {
    mockFetch(async () =>
      new Response(JSON.stringify({ error: "invalid_signature" }), { status: 401 })
    );
    await expect(
      sendLeadToMIND(validPayload(), { webhookURL: "https://w", secret: "s" })
    ).rejects.toMatchObject({ code: "signatureRejected", status: 401 });
  });

  it("throws `badRequest` on a 400", async () => {
    mockFetch(async () =>
      new Response(JSON.stringify({ error: "invalid_payload", field: "message" }), { status: 400 })
    );
    await expect(
      sendLeadToMIND(validPayload(), { webhookURL: "https://w", secret: "s" })
    ).rejects.toMatchObject({ code: "badRequest", status: 400 });
  });

  it("throws `serverError` on a 503", async () => {
    mockFetch(async () => new Response("kv down", { status: 503 }));
    await expect(
      sendLeadToMIND(validPayload(), { webhookURL: "https://w", secret: "s" })
    ).rejects.toMatchObject({ code: "serverError", status: 503 });
  });

  it("throws `timeout` when fetch is aborted", async () => {
    mockFetch(async (_input, init) => {
      return new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          const err = new Error("aborted");
          err.name = "AbortError";
          reject(err);
        });
      });
    });
    await expect(
      sendLeadToMIND(validPayload(), { webhookURL: "https://w", secret: "s", timeout: 10 })
    ).rejects.toMatchObject({ code: "timeout" });
  });

  it("throws `network` when fetch rejects without an abort", async () => {
    mockFetch(async () => {
      throw new TypeError("fetch failed");
    });
    await expect(
      sendLeadToMIND(validPayload(), { webhookURL: "https://w", secret: "s" })
    ).rejects.toMatchObject({ code: "network" });
  });

  it("throws `validation` synchronously when projectID is empty", async () => {
    const broken: LeadPayload = { ...validPayload(), projectID: "" };
    await expect(
      sendLeadToMIND(broken, { webhookURL: "https://w", secret: "s" })
    ).rejects.toBeInstanceOf(MINDWebhookError);
  });

  it("throws `validation` when contactEmail has no @", async () => {
    const broken: LeadPayload = { ...validPayload(), contactEmail: "not-an-email" };
    await expect(
      sendLeadToMIND(broken, { webhookURL: "https://w", secret: "s" })
    ).rejects.toMatchObject({ code: "validation" });
  });

  it("normalises trailing slashes in the webhookURL", async () => {
    const seen: string[] = [];
    mockFetch(async (input) => {
      seen.push(String(input));
      return new Response(JSON.stringify({ status: "queued", leadID: "x" }), { status: 200 });
    });
    await sendLeadToMIND(validPayload(), { webhookURL: "https://w///", secret: "s" });
    expect(seen[0]).toBe("https://w/v1/leads");
  });

  it("injects `receivedAt` as an ISO timestamp", async () => {
    let body: string | null = null;
    mockFetch(async (_input, init) => {
      body = init?.body as string;
      return new Response(JSON.stringify({ status: "queued", leadID: "x" }), { status: 200 });
    });
    await sendLeadToMIND(validPayload(), { webhookURL: "https://w", secret: "s" });
    expect(body).toMatch(/"receivedAt":"\d{4}-\d{2}-\d{2}T/);
  });
});

describe("canonicalEncode", () => {
  it("sorts top-level keys alphabetically", () => {
    const encoded = canonicalEncode({ b: 1, a: 2, c: 3 });
    expect(encoded).toBe('{"a":2,"b":1,"c":3}');
  });

  it("strips undefined values (preserves explicit nulls)", () => {
    const encoded = canonicalEncode({ a: null, b: undefined, c: 1 });
    expect(encoded).toBe('{"a":null,"c":1}');
  });

  it("is deterministic for the same input", () => {
    const a = canonicalEncode({ x: "y", a: 1 });
    const b = canonicalEncode({ a: 1, x: "y" });
    expect(a).toBe(b);
  });
});
