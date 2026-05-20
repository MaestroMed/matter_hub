import XCTest
@testable import GraphCore

/// v1.0-alpha.2 — Locks the on-the-wire contract between a
/// deployed client site and MIND's `/api/leads` ingest endpoint:
/// JSON round-trip with optional fields, HMAC-SHA256 signature
/// format + length, verify accepts a matching signature, verify
/// rejects every documented failure mode (mismatched secret,
/// mismatched payload, empty signature, malformed length).
final class LeadWebhookPayloadTests: XCTestCase {

    // MARK: - Codable round-trip

    /// A full payload with every field populated round-trips
    /// through the canonical encoder + decoder pair lossless.
    /// Locks the "iOS-decoded payload matches what the worker
    /// posted" contract.
    func test_codable_fullPayload_roundTripsLossless() throws {
        let payload = LeadWebhookPayload(
            projectID: UUID(uuidString: "C3F8D2A8-7B7A-4C39-8C66-7BCCD2FBE40B")!,
            formType: "contact",
            contactName: "Alice Martin",
            contactEmail: "alice@example.com",
            contactPhone: "+33 6 12 34 56 78",
            message: "Bonjour, je souhaiterais un devis pour …",
            sourceURL: "https://www.azconstruction.fr/contact",
            clientIP: "203.0.113.42",
            userAgent: "Mozilla/5.0",
            receivedAt: Date(timeIntervalSince1970: 1_716_192_131)
        )
        let data = try LeadWebhookPayload.canonicalEncoder.encode(payload)
        let decoded = try LeadWebhookPayload.canonicalDecoder.decode(LeadWebhookPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
    }

    /// A minimal payload with every optional field set to nil
    /// round-trips identically — `contactPhone`, `clientIP`,
    /// `userAgent` all preserve their nil-ness.
    func test_codable_nilOptionals_roundTripLossless() throws {
        let payload = LeadWebhookPayload(
            projectID: UUID(),
            formType: "devis",
            contactName: "Bob",
            contactEmail: "bob@example.com",
            contactPhone: nil,
            message: "Hello",
            sourceURL: "https://example.com/devis",
            clientIP: nil,
            userAgent: nil,
            receivedAt: Date(timeIntervalSince1970: 1_716_192_131)
        )
        let data = try LeadWebhookPayload.canonicalEncoder.encode(payload)
        let decoded = try LeadWebhookPayload.canonicalDecoder.decode(LeadWebhookPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
        XCTAssertNil(decoded.contactPhone)
        XCTAssertNil(decoded.clientIP)
        XCTAssertNil(decoded.userAgent)
    }

    // MARK: - HMAC sign

    /// `sign` always returns a 64-char lowercase hex string
    /// (SHA-256 produces 32 bytes → 64 hex chars). Locks the
    /// "Stripe-shaped" wire-format convention.
    func test_sign_returnsLowercase64CharHex() {
        let payload = Data("hello".utf8)
        let signature = LeadWebhookPayload.sign(payload: payload, secret: "topsecret")
        XCTAssertEqual(signature.count, 64,
                       "HMAC-SHA256 hex output must be exactly 64 chars.")
        XCTAssertEqual(signature, signature.lowercased(),
                       "Hex output must be lowercase to match Stripe / GitHub convention.")
        // Every char must be a valid hex digit.
        let hexAlphabet = Set("0123456789abcdef")
        XCTAssertTrue(signature.allSatisfy { hexAlphabet.contains($0) },
                      "Every char must be a valid lowercase hex digit.")
    }

    /// Same input → same output. Deterministic.
    func test_sign_isDeterministic() {
        let payload = Data(#"{"projectID":"abc"}"#.utf8)
        let a = LeadWebhookPayload.sign(payload: payload, secret: "secret")
        let b = LeadWebhookPayload.sign(payload: payload, secret: "secret")
        XCTAssertEqual(a, b)
    }

    // MARK: - HMAC verify

    /// `verify` accepts a signature produced by `sign` with the
    /// same payload + secret. The happy-path round-trip.
    func test_verify_matchingSignature_isAccepted() {
        let payload = Data(#"{"foo":"bar"}"#.utf8)
        let signature = LeadWebhookPayload.sign(payload: payload, secret: "shhh")
        XCTAssertTrue(LeadWebhookPayload.verify(
            payload: payload,
            signature: signature,
            secret: "shhh"
        ))
    }

    /// Verify rejects a signature computed with a different secret.
    /// Locks the per-Project secret-isolation contract — leaking
    /// AZ's secret must not let an attacker forge an IEF lead.
    func test_verify_wrongSecret_isRejected() {
        let payload = Data(#"{"foo":"bar"}"#.utf8)
        let signature = LeadWebhookPayload.sign(payload: payload, secret: "az-secret")
        XCTAssertFalse(LeadWebhookPayload.verify(
            payload: payload,
            signature: signature,
            secret: "ief-secret"
        ))
    }

    /// Verify rejects a signature when the payload bytes have been
    /// tampered with after signing.
    func test_verify_tamperedPayload_isRejected() {
        let original = Data(#"{"amount":100}"#.utf8)
        let tampered = Data(#"{"amount":999}"#.utf8)
        let signature = LeadWebhookPayload.sign(payload: original, secret: "secret")
        XCTAssertFalse(LeadWebhookPayload.verify(
            payload: tampered,
            signature: signature,
            secret: "secret"
        ))
    }

    /// Verify rejects an empty signature — no "anyone with an empty
    /// X-MIND-Signature header passes" footgun.
    func test_verify_emptySignature_isRejected() {
        let payload = Data("hello".utf8)
        XCTAssertFalse(LeadWebhookPayload.verify(
            payload: payload,
            signature: "",
            secret: "secret"
        ))
    }

    /// Verify rejects a signature of wrong length — short-circuits
    /// to false rather than running a partial timing-side-channel.
    func test_verify_wrongLengthSignature_isRejected() {
        let payload = Data("hello".utf8)
        XCTAssertFalse(LeadWebhookPayload.verify(
            payload: payload,
            signature: "deadbeef", // 8 chars, not 64
            secret: "secret"
        ))
    }

    /// Verify accepts the same signature in any case — hex chars
    /// are case-insensitive on the wire.
    func test_verify_uppercaseSignature_isAccepted() {
        let payload = Data("hello".utf8)
        let lowercase = LeadWebhookPayload.sign(payload: payload, secret: "secret")
        let uppercase = lowercase.uppercased()
        XCTAssertTrue(LeadWebhookPayload.verify(
            payload: payload,
            signature: uppercase,
            secret: "secret"
        ))
    }
}
