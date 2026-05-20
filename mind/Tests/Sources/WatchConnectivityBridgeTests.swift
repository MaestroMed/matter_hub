import XCTest
@testable import GraphCore

/// v1.0-alpha.17 — Locks the message-envelope contract both the
/// iPhone host and the Apple Watch side of `WatchConnectivityBridge`
/// follow. The two sides ship duplicated bridge files (the Watch
/// target can't link GraphCore); these tests live in the iPhone-side
/// suite because that's where the canonical envelope shape is
/// authored.
final class WatchConnectivityBridgeTests: XCTestCase {

    // MARK: - Envelope build

    /// Building an envelope from a typed payload produces a
    /// dictionary with the canonical `mind.envelope.kind` /
    /// `mind.envelope.payload` keys and the kind raw value matches
    /// the case rawValue.
    func test_envelope_carriesKindAndPayloadKeys() throws {
        let payload = WatchConnectivityBridge.WatchPortfolioKPI(
            leadsToday: 4,
            mrrEUR: 830,
            buildErrors: 0
        )

        let envelope = try XCTUnwrap(
            WatchConnectivityBridge.envelope(
                kind: .portfolioSnapshot,
                payload: payload
            )
        )

        XCTAssertEqual(
            envelope[WatchConnectivityBridge.envelopeKindKey] as? String,
            "portfolio.snapshot"
        )
        XCTAssertNotNil(envelope[WatchConnectivityBridge.envelopePayloadKey])
    }

    /// The unpack helper round-trips the kind back into the typed
    /// enum and exposes the raw payload as `Any` so the receiver can
    /// re-decode it into the typed shape.
    func test_unpack_roundTripsKind_andPayload() throws {
        let original = WatchConnectivityBridge.FocusStartPayload(
            intention: "Pomodoro",
            durationSeconds: 1_500
        )
        let envelope = try XCTUnwrap(
            WatchConnectivityBridge.envelope(
                kind: .focusStart,
                payload: original
            )
        )

        let unpacked = try XCTUnwrap(
            WatchConnectivityBridge.unpack(envelope)
        )

        XCTAssertEqual(unpacked.kind, .focusStart)
        let dict = try XCTUnwrap(unpacked.payload as? [String: Any])
        XCTAssertEqual(dict["intention"] as? String, "Pomodoro")
        XCTAssertEqual(dict["durationSeconds"] as? Int, 1_500)
    }

    /// A malformed envelope (no kind key) collapses to nil. The
    /// receiver treats nil as "drop the message" — never throws.
    func test_unpack_missingKindKey_returnsNil() {
        let envelope: [String: Any] = [
            "mind.envelope.payload": ["foo": "bar"],
        ]
        XCTAssertNil(WatchConnectivityBridge.unpack(envelope))
    }

    /// A malformed envelope (unknown kind raw value) collapses to nil.
    func test_unpack_unknownKind_returnsNil() {
        let envelope: [String: Any] = [
            WatchConnectivityBridge.envelopeKindKey: "garbage.kind",
            WatchConnectivityBridge.envelopePayloadKey: [String: Any](),
        ]
        XCTAssertNil(WatchConnectivityBridge.unpack(envelope))
    }

    /// A malformed envelope (no payload key) collapses to nil.
    func test_unpack_missingPayloadKey_returnsNil() {
        let envelope: [String: Any] = [
            WatchConnectivityBridge.envelopeKindKey: "focus.start",
        ]
        XCTAssertNil(WatchConnectivityBridge.unpack(envelope))
    }

    // MARK: - Value-type Codable round-trips

    /// `WatchLeadDigest` round-trips through JSON without losing any
    /// field. Critical because every Watch payload travels as JSON.
    func test_leadDigest_codableRoundTrip_preservesEveryField() throws {
        let id = UUID()
        let original = WatchConnectivityBridge.WatchLeadDigest(
            id: id,
            contactName: "Karim Benali",
            messagePreview: "Bonjour, j'aimerais discuter d'un projet.",
            receivedAtMillis: 1_716_000_000_000
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            WatchConnectivityBridge.WatchLeadDigest.self,
            from: data
        )

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.contactName, "Karim Benali")
        XCTAssertEqual(decoded.messagePreview, "Bonjour, j'aimerais discuter d'un projet.")
        XCTAssertEqual(decoded.receivedAtMillis, 1_716_000_000_000)
    }

    /// `WatchPortfolioKPI` round-trips through JSON without drift and
    /// the `.empty` literal preserves the zero-state contract.
    func test_portfolioKPI_codableRoundTrip_andEmpty() throws {
        let original = WatchConnectivityBridge.WatchPortfolioKPI(
            leadsToday: 12,
            mrrEUR: 4_200,
            buildErrors: 2
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            WatchConnectivityBridge.WatchPortfolioKPI.self,
            from: data
        )
        XCTAssertEqual(decoded, original)

        let empty = WatchConnectivityBridge.WatchPortfolioKPI.empty
        XCTAssertEqual(empty.leadsToday, 0)
        XCTAssertEqual(empty.mrrEUR, 0)
        XCTAssertEqual(empty.buildErrors, 0)
    }

    /// `FocusStartPayload` round-trips through JSON and the default
    /// pomodoro literal carries the 25-min duration the Watch UI
    /// shows by default.
    func test_focusStartPayload_codableRoundTrip_andDefault() throws {
        let original = WatchConnectivityBridge.FocusStartPayload(
            intention: "Audit prep",
            durationSeconds: 600
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            WatchConnectivityBridge.FocusStartPayload.self,
            from: data
        )
        XCTAssertEqual(decoded, original)

        let pomodoro = WatchConnectivityBridge.FocusStartPayload.pomodoroDefault
        XCTAssertEqual(pomodoro.durationSeconds, 1_500)
        XCTAssertEqual(pomodoro.intention, "Pomodoro")
    }

    // MARK: - SnapshotKey constants

    /// The App Group key namespace stays stable — the Watch-side
    /// reader depends on the exact strings to find the cached
    /// snapshot. Any rename here MUST be mirrored in the Watch
    /// target's bridge clone.
    func test_snapshotKeys_areStable() {
        XCTAssertEqual(WatchConnectivityBridge.SnapshotKey.leads, "mind.watch.leads")
        XCTAssertEqual(WatchConnectivityBridge.SnapshotKey.portfolio, "mind.watch.portfolio")
        XCTAssertEqual(WatchConnectivityBridge.SnapshotKey.focusRunning, "mind.watch.focus.running")
        XCTAssertEqual(WatchConnectivityBridge.appGroupSuiteName, "group.app.mind.ios")
    }

    /// The MessageKind enum has the four cases the Watch + iPhone
    /// rely on, with the canonical raw values. The Watch target's
    /// clone of the bridge mirrors this contract.
    func test_messageKind_rawValues_areStable() {
        XCTAssertEqual(WatchConnectivityBridge.MessageKind.leadsSnapshot.rawValue, "leads.snapshot")
        XCTAssertEqual(WatchConnectivityBridge.MessageKind.portfolioSnapshot.rawValue, "portfolio.snapshot")
        XCTAssertEqual(WatchConnectivityBridge.MessageKind.focusStart.rawValue, "focus.start")
        XCTAssertEqual(WatchConnectivityBridge.MessageKind.focusEnd.rawValue, "focus.end")
    }
}
