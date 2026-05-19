import Foundation
import AuditKit

/// On-disk wire format for a live audit broadcast.
///
/// One JSON document per session. The browser-side `index.html`
/// template polls `./state.json` every 800 ms (a `fetch` from inline
/// `<script>` JS) and re-renders the whole UI from the result, so this
/// type must:
///
/// 1. Be **stable on the wire** — JSON keys never rename without a
///    matching template patch. Field order is alphabetical for
///    deterministic snapshots in tests.
/// 2. **Codable + Sendable** so the `LiveBroadcastWriter` actor can
///    hand it across isolation hops without contortion.
/// 3. **Self-describing** — the template never queries any other
///    endpoint, so every datum it needs to render (hero, probe grid,
///    scoring gauges, synthesis, pitch, CTAs) must live here.
public struct LiveBroadcastState: Codable, Sendable, Hashable {

    /// 16-byte hex string (32 ASCII chars, `[0-9a-f]`). Mints the URL
    /// path slug — `https://broadcast.mehdi.app/<token>/` —
    /// and is unguessable in practice so the client can hand the link
    /// to a prospect without enumerating every other Mehdi audit.
    public let token: String

    /// Human-friendly client name as it should display in the hero.
    public let clientName: String

    /// Audited host (`"stripe.com"`). Renders under the client name
    /// as a monospaced subtitle so the prospect immediately recognises
    /// the target.
    public let host: String

    /// When this broadcast was minted. The browser-side `<time>` tag
    /// can format it however it likes — we ship ISO 8601 UTC.
    public let startedAt: Date

    /// Last write timestamp. Drives the "Live" badge pulse and the
    /// "Mis à jour il y a Xs" footer in the template.
    public let updatedAt: Date

    /// Coarse-grained pipeline phase. Mirrors `AuditController.Phase`'s
    /// raw values (`"probing"`, `"synthesizing"`, `"completed"`,
    /// `"failed"`) so the template can branch off a single string
    /// switch without re-deriving from the probe list.
    public let phase: String

    /// One entry per probe — exactly `ProbeKind.allCases.count` rows,
    /// in declaration order, so the template renders a stable grid.
    /// Empty array is legal (initial snapshot before the first
    /// transition lands).
    public let probes: [ProbeStatus]

    /// Five-axis scoring + overall, populated when synthesis lands.
    /// `nil` before — the template keeps the gauges grey while
    /// the audit is still probing.
    public let scoring: Scoring?

    /// Long-form markdown synthesis. Grows monotonically — the
    /// template re-runs its tiny "typewriter" reveal each time the
    /// length changes. `nil` until synthesis starts.
    public let synthesis: String?

    /// Ready-to-paste cold-email pitch. Surfaced inside the
    /// "Discuter avec Mehdi" CTA after the audit completes.
    /// `nil` until completion.
    public let pitch: String?

    public init(
        token: String,
        clientName: String,
        host: String,
        startedAt: Date,
        updatedAt: Date,
        phase: String,
        probes: [ProbeStatus] = [],
        scoring: Scoring? = nil,
        synthesis: String? = nil,
        pitch: String? = nil
    ) {
        self.token = token
        self.clientName = clientName
        self.host = host
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.phase = phase
        self.probes = probes
        self.scoring = scoring
        self.synthesis = synthesis
        self.pitch = pitch
    }

    // MARK: - Nested types

    /// Per-probe lifecycle entry. The template renders one card per
    /// probe; the card colour and icon swap based on `state`.
    public struct ProbeStatus: Codable, Sendable, Hashable, Identifiable {
        /// Stable identifier matching `AuditController.ProbeKind.rawValue`
        /// — `"pageSpeed"`, `"security"`, `"email"`, etc. Used as the
        /// React-style key in the template's grid render.
        public let kind: String

        /// Coarse lifecycle. Allowed values:
        /// `"pending"` (not yet started), `"running"` (in-flight),
        /// `"ok"` (completed successfully), `"failed"` (soft-failed
        /// with a reason in `error`). Template renders a coloured dot
        /// + label keyed off this value.
        public let state: String

        /// Wall-clock duration in milliseconds, populated when the
        /// probe lands a terminal state. `nil` while running.
        public let durationMs: Int?

        /// Localised failure reason, populated only when `state ==
        /// "failed"`. Surfaces as a red sub-label under the probe card.
        public let error: String?

        public var id: String { kind }

        public init(
            kind: String,
            state: String,
            durationMs: Int? = nil,
            error: String? = nil
        ) {
            self.kind = kind
            self.state = state
            self.durationMs = durationMs
            self.error = error
        }
    }

    /// Mirrors `AuditReport.Scoring`. Re-declared (not aliased) so the
    /// JSON keys stay stable even if AuditKit's `Scoring` ever changes
    /// internal field naming.
    public struct Scoring: Codable, Sendable, Hashable {
        public let overall: Int
        public let performance: Int
        public let seo: Int
        public let security: Int
        public let brand: Int
        public let mobile: Int

        public init(
            overall: Int,
            performance: Int,
            seo: Int,
            security: Int,
            brand: Int,
            mobile: Int
        ) {
            self.overall = overall
            self.performance = performance
            self.seo = seo
            self.security = security
            self.brand = brand
            self.mobile = mobile
        }

        /// Lift from the canonical `AuditReport.Scoring` value so the
        /// AuditController integration doesn't have to spell every
        /// field by hand on every write.
        public init(_ source: AuditReport.Scoring) {
            self.overall = source.overall
            self.performance = source.performance
            self.seo = source.seo
            self.security = source.security
            self.brand = source.brand
            self.mobile = source.mobile
        }
    }

    // MARK: - Allowed string values

    /// Allowed values for `phase`. Pinned as enum cases so the
    /// AuditController call sites can't typo a new phase into the
    /// wire format without first touching this file.
    public enum Phase: String, Sendable {
        case probing
        case synthesizing
        case completed
        case failed
    }

    /// Allowed values for `ProbeStatus.state`.
    public enum ProbeLifecycle: String, Sendable {
        case pending
        case running
        case ok
        case failed
    }
}

// MARK: - Canonical encode / decode

public extension LiveBroadcastState {

    /// JSON encoder with the wire contract baked in:
    /// - **Sorted keys** so the same input produces the same bytes
    ///   (the "determinism" test asserts this).
    /// - **ISO 8601** dates with fractional seconds for cross-platform
    ///   parsing in the browser-side `<script>`.
    /// - **Pretty-print** disabled — the file is machine-only, the
    ///   smaller the better for the polling client.
    static var canonicalEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.isoString(from: date))
        }
        return encoder
    }

    /// Inverse of `canonicalEncoder`. Public so the
    /// `LiveBroadcastWriterTests` can round-trip a freshly-written
    /// snapshot back into a value and compare structurally.
    static var canonicalDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = Self.date(fromISO: str) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO 8601 date string with fractional seconds, got '\(str)'"
            )
        }
        return decoder
    }

    /// Sendable-safe ISO 8601 helpers. `ISO8601DateFormatter` is not
    /// `Sendable` so we cannot capture it inside a `.custom` strategy
    /// closure under Swift 6 strict concurrency. Building one per
    /// call keeps the closure pure; the throughput cost is negligible
    /// next to the JSON encode itself.
    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func date(fromISO str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str)
    }

    /// Encode to UTF-8 bytes. Throws on encoder failure; callers
    /// should not silence the error — a write that drops state mid-
    /// audit is a visible bug in the broadcast viewer.
    func encoded() throws -> Data {
        try LiveBroadcastState.canonicalEncoder.encode(self)
    }
}
