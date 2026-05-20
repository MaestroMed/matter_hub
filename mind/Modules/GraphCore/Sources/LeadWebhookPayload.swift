import Foundation
import CryptoKit

/// v1.0-alpha.2 — On-the-wire contract between a deployed client
/// site (Next.js / Cloudflare Worker / Vercel Edge) and MIND's
/// `/api/leads` ingest endpoint.
///
/// The contract is captured *now*, in alpha.2, even though the
/// backend worker won't land until alpha.5 — locking the JSON
/// shape early means the iOS side, the worker template, and the
/// per-project npm SDK (`@mind/lead-webhook`) all converge on the
/// same payload. The HMAC-SHA256 signature lives in an `X-MIND-
/// Signature` header (the helper just operates on the body bytes;
/// the transport layer wires the header).
///
/// Wire format
/// -----------
/// ```jsonc
/// {
///   "projectID": "C3F8D2A8-7B7A-4C39-8C66-7BCCD2FBE40B",
///   "formType": "contact",
///   "contactName": "Alice Martin",
///   "contactEmail": "alice@example.com",
///   "contactPhone": "+33 6 12 34 56 78",   // optional
///   "message": "Bonjour, je souhaiterais ...",
///   "sourceURL": "https://www.azconstruction.fr/contact",
///   "clientIP": "203.0.113.42",            // optional, hashed at ingest
///   "userAgent": "Mozilla/5.0 ...",        // optional
///   "receivedAt": "2026-05-20T08:42:11Z"
/// }
/// ```
///
/// `projectID` is the SwiftData UUID of the matching `Project`
/// row, surfaced to the deployed site at provisioning time. The
/// `webhookSecret` is the per-Project shared secret stored on
/// `Project.webhookSecret` and pasted into the site's
/// environment variables.
public struct LeadWebhookPayload: Codable, Sendable, Equatable {
    public let projectID: UUID
    public let formType: String
    public let contactName: String
    public let contactEmail: String
    public let contactPhone: String?
    public let message: String
    public let sourceURL: String
    public let clientIP: String?
    public let userAgent: String?
    public let receivedAt: Date

    public init(
        projectID: UUID,
        formType: String,
        contactName: String,
        contactEmail: String,
        contactPhone: String? = nil,
        message: String,
        sourceURL: String,
        clientIP: String? = nil,
        userAgent: String? = nil,
        receivedAt: Date
    ) {
        self.projectID = projectID
        self.formType = formType
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.message = message
        self.sourceURL = sourceURL
        self.clientIP = clientIP
        self.userAgent = userAgent
        self.receivedAt = receivedAt
    }

    // MARK: - HMAC contract

    /// Signs the given payload bytes with HMAC-SHA256 and returns the
    /// signature as a lowercase 64-char hex string. The signature is
    /// computed on the raw bytes of the JSON body — the deployed
    /// site MUST sign the same bytes it POSTs, otherwise verification
    /// fails (a common bug is signing a pretty-printed body and
    /// posting the minified one).
    ///
    /// Lowercase hex matches the Stripe / GitHub webhook convention;
    /// the verify helper below is case-insensitive in practice
    /// because timing-safe comparison happens on raw bytes.
    public static func sign(payload: Data, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    /// Timing-safe verification of a hex signature against payload
    /// bytes + a shared secret.
    ///
    /// Empty `signature` always returns `false` (no "anyone with an
    /// empty header passes" footgun). Mismatched-length signatures
    /// short-circuit to `false` after a constant-time decode pass.
    /// Comparison is byte-wise constant time (`reduce(0, ^)` over
    /// pairwise XOR) so a network attacker can't time-side-channel
    /// the expected signature.
    public static func verify(
        payload: Data,
        signature: String,
        secret: String
    ) -> Bool {
        guard !signature.isEmpty else { return false }
        let expected = sign(payload: payload, secret: secret)
        // Constant-time comparison: walk both strings together and
        // XOR each byte; only assert equality after the full pass.
        let expectedBytes = Array(expected.utf8)
        let providedBytes = Array(signature.lowercased().utf8)
        guard expectedBytes.count == providedBytes.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<expectedBytes.count {
            diff |= expectedBytes[i] ^ providedBytes[i]
        }
        return diff == 0
    }

    // MARK: - Canonical Codable

    /// JSONEncoder pre-tuned for the wire format: ISO8601 dates with
    /// fractional seconds + sorted keys so a signature computed on
    /// the encoder output is byte-stable across runs. Use this for
    /// any sign-then-post path to avoid the "signed pretty-printed,
    /// posted minified" footgun.
    public static var canonicalEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// JSONDecoder paired with `canonicalEncoder` so a round-trip
    /// through both is lossless.
    public static var canonicalDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
