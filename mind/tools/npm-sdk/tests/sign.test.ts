// v1.0-alpha.5 — Pure HMAC unit tests for `@mind/lead-webhook`.
// Locks the byte-for-byte parity contract with the iOS
// `LeadWebhookPayload.sign(...)` helper. If any of these break the
// Worker will reject every legitimate POST.

import { describe, expect, it } from "vitest";
import { sign } from "../src/sign";

describe("sign()", () => {
  it("returns a 64-char lowercase hex string", () => {
    const out = sign("hello", "topsecret");
    expect(out.length).toBe(64);
    expect(out).toBe(out.toLowerCase());
    expect(/^[0-9a-f]+$/.test(out)).toBe(true);
  });

  it("is deterministic for the same input and secret", () => {
    const a = sign("{\"a\":1}", "s");
    const b = sign("{\"a\":1}", "s");
    expect(a).toBe(b);
  });

  it("changes when the secret changes", () => {
    const a = sign("hello", "az");
    const b = sign("hello", "ief");
    expect(a).not.toBe(b);
  });

  it("changes when the body changes", () => {
    const a = sign("hello", "s");
    const b = sign("hello!", "s");
    expect(a).not.toBe(b);
  });

  it("matches the documented Stripe/GitHub HMAC-SHA256 reference vector", () => {
    // RFC 4231 test case 2: key "Jefe", data "what do ya want for nothing?"
    // expected = 5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
    const out = sign("what do ya want for nothing?", "Jefe");
    expect(out).toBe("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
  });
});
