import XCTest
@testable import LiveBroadcastKit
@testable import AuditKit

/// v0.22 — Locks the on-disk lifecycle of a live audit broadcast.
///
/// Every assertion walks freshly-created temp folders under
/// `NSTemporaryDirectory()` so the tests stay hermetic. The writer's
/// clock and random-bytes provider are both injectable, which means
/// the JSON snapshots are byte-stable and the determinism test below
/// is meaningful.
final class LiveBroadcastWriterTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LiveBroadcastWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let root = tempRoot, FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.removeItem(at: root)
        }
        try await super.tearDown()
    }

    // MARK: - Codable round trip

    /// `LiveBroadcastState` is the wire contract every browser-side
    /// `fetch('./state.json')` decodes. A silent rename of a key here
    /// breaks the template's render path. This test catches that
    /// regression by round-tripping a fully-populated sample.
    func test_liveBroadcastState_roundTripsAcrossCanonicalCoders() throws {
        let original = LiveBroadcastState(
            token: String(repeating: "a", count: 32),
            clientName: "Stripe",
            host: "stripe.com",
            startedAt: Date(timeIntervalSince1970: 1_747_699_200),
            updatedAt: Date(timeIntervalSince1970: 1_747_699_400),
            phase: LiveBroadcastState.Phase.synthesizing.rawValue,
            probes: [
                LiveBroadcastState.ProbeStatus(kind: "pageSpeed", state: "ok", durationMs: 312),
                LiveBroadcastState.ProbeStatus(kind: "security", state: "failed",
                                               durationMs: 144, error: "TLS handshake timeout"),
            ],
            scoring: LiveBroadcastState.Scoring(
                overall: 87, performance: 80, seo: 90, security: 95, brand: 85, mobile: 88
            ),
            synthesis: "## Identité\nStripe is the world's leading payments infra.",
            pitch: "Hi team — following my audit…"
        )

        let data = try original.encoded()
        let decoded = try LiveBroadcastState.canonicalDecoder
            .decode(LiveBroadcastState.self, from: data)

        XCTAssertEqual(decoded, original,
                       "Canonical encoder + decoder must round-trip a fully-populated snapshot byte-for-byte")
    }

    // MARK: - Token format

    /// Token must be exactly 32 lowercase hex chars (16 random bytes).
    /// The browser-side URL is `https://.../<token>/index.html`, so a
    /// slug with `'/'` or capital letters would break path routing on
    /// most hosting providers.
    func test_create_producesValidHexToken() async throws {
        let writer = LiveBroadcastWriter()
        let client = AuditClient(url: URL(string: "https://stripe.com")!, name: "Stripe")
        let session = try await writer.create(for: client, under: tempRoot)

        XCTAssertEqual(session.token.count, 32, "Token must be 32 hex chars")
        XCTAssertTrue(LiveBroadcastWriter.isValidToken(session.token),
                      "Token must match [0-9a-f]{32}, got '\(session.token)'")
    }

    // MARK: - Folder + initial files

    /// `create(for:)` must lay down both the static `index.html`
    /// template AND the initial `state.json` snapshot before
    /// returning. The browser-side first paint depends on both.
    func test_create_writesIndexHTMLAndInitialStateJSON() async throws {
        let writer = LiveBroadcastWriter()
        let client = AuditClient(url: URL(string: "https://stripe.com")!, name: "Stripe")
        let session = try await writer.create(for: client, under: tempRoot)

        let indexURL = session.folderURL.appendingPathComponent(LiveBroadcastWriter.indexFileName)
        let stateURL = session.folderURL.appendingPathComponent(LiveBroadcastWriter.stateFileName)

        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path),
                      "index.html must be on disk after create()")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path),
                      "state.json must be on disk after create()")

        // Sanity check on the state JSON: phase is "probing", probes
        // list seeded with `pending` entries.
        let stateData = try Data(contentsOf: stateURL)
        let state = try LiveBroadcastState.canonicalDecoder
            .decode(LiveBroadcastState.self, from: stateData)
        XCTAssertEqual(state.phase, "probing")
        XCTAssertEqual(state.probes.count, AuditController.ProbeKind.allCases.count)
        XCTAssertTrue(state.probes.allSatisfy { $0.state == "pending" })
        XCTAssertEqual(state.clientName, "Stripe")
        XCTAssertEqual(state.host, "stripe.com")
    }

    // MARK: - HTML template content

    /// The HTML template must contain the polling JS snippet that
    /// hits `./state.json`. Without that snippet the page is a
    /// static husk.
    func test_htmlTemplate_containsPollingScript() {
        let html = LiveBroadcastHTMLTemplate.render(clientName: "Acme", host: "acme.com")

        XCTAssertTrue(html.contains("./state.json"),
                      "Template must fetch from './state.json' so it works under any hosting")
        XCTAssertTrue(html.contains("setInterval"),
                      "Template must schedule a recurring poll")
        XCTAssertTrue(html.contains("fetch("),
                      "Template must use fetch() to read state")
    }

    /// `./state.json` must be the relative path — a hard-coded
    /// `http://localhost:…` or absolute path would break the moment
    /// Mehdi pushes the folder to Vercel / Cloudflare Pages.
    func test_htmlTemplate_referencesStateJSONByRelativePath() {
        let html = LiveBroadcastHTMLTemplate.render(clientName: "Acme", host: "acme.com")

        XCTAssertFalse(html.contains("http://localhost"),
                       "Template must not hard-code localhost")
        XCTAssertFalse(html.contains("https://broadcast.mind.app"),
                       "Template must not hard-code any host")
    }

    // MARK: - File size budget

    /// Hard 50 KB budget on the HTML template. Adding a heavy CSS
    /// section or pulling in a JS framework would push us over —
    /// breaking this test instead of silently bloating every
    /// broadcast.
    func test_htmlTemplate_staysUnderFileSizeBudget() {
        let html = LiveBroadcastHTMLTemplate.render(
            clientName: "Some Long Client Name LLC",
            host: "long.example.com"
        )
        let bytes = Data(html.utf8).count
        XCTAssertLessThan(bytes, LiveBroadcastHTMLTemplate.maxBytes,
                          "HTML template must stay under \(LiveBroadcastHTMLTemplate.maxBytes) bytes, got \(bytes)")
    }

    // MARK: - Update / atomicity

    /// `update(_:mutating:)` reads, mutates, writes — atomically. We
    /// can't easily prove "no half-written JSON visible mid-write"
    /// without spinning up a concurrent reader, but we CAN assert
    /// that successive updates land cleanly without corrupting the
    /// JSON between rounds.
    func test_update_mutatesAndPersists() async throws {
        let writer = LiveBroadcastWriter()
        let client = AuditClient(url: URL(string: "https://stripe.com")!, name: "Stripe")
        let session = try await writer.create(for: client, under: tempRoot)

        try await writer.update(token: session.token, under: tempRoot) { state in
            var probes = state.probes
            probes[0] = LiveBroadcastState.ProbeStatus(
                kind: probes[0].kind, state: "ok", durationMs: 444
            )
            state = LiveBroadcastState(
                token: state.token,
                clientName: state.clientName,
                host: state.host,
                startedAt: state.startedAt,
                updatedAt: state.updatedAt,
                phase: state.phase,
                probes: probes,
                scoring: state.scoring,
                synthesis: state.synthesis,
                pitch: state.pitch
            )
        }

        let stateURL = session.folderURL.appendingPathComponent(LiveBroadcastWriter.stateFileName)
        let data = try Data(contentsOf: stateURL)
        let snapshot = try LiveBroadcastState.canonicalDecoder
            .decode(LiveBroadcastState.self, from: data)

        XCTAssertEqual(snapshot.probes.first?.state, "ok",
                       "update() must persist the mutation to disk")
        XCTAssertEqual(snapshot.probes.first?.durationMs, 444)
    }

    /// Calling `update` against an unknown token must throw
    /// `broadcastNotFound` rather than silently writing a stray file.
    func test_update_throwsBroadcastNotFoundForUnknownToken() async throws {
        let writer = LiveBroadcastWriter()
        let missingToken = String(repeating: "0", count: 32)
        do {
            try await writer.update(token: missingToken, under: tempRoot) { _ in }
            XCTFail("Expected broadcastNotFound for missing token")
        } catch LiveBroadcastWriterError.broadcastNotFound(let token) {
            XCTAssertEqual(token, missingToken)
        }
    }

    // MARK: - Close

    /// `close(_:success:)` flips the JSON `phase` field to `"completed"`
    /// (on `true`) or `"failed"` (on `false`). The browser-side
    /// renderer uses that field to swap the status pill colour and
    /// surface the final CTA.
    func test_close_setsPhaseToCompletedOrFailed() async throws {
        let writer = LiveBroadcastWriter()
        let client = AuditClient(url: URL(string: "https://stripe.com")!, name: "Stripe")
        let session = try await writer.create(for: client, under: tempRoot)

        try await writer.close(token: session.token, success: true, under: tempRoot)

        let stateURL = session.folderURL.appendingPathComponent(LiveBroadcastWriter.stateFileName)
        let data = try Data(contentsOf: stateURL)
        let snapshot = try LiveBroadcastState.canonicalDecoder
            .decode(LiveBroadcastState.self, from: data)
        XCTAssertEqual(snapshot.phase, "completed")
    }

    // MARK: - JSON escaping safety

    /// A synthesis or pitch that includes `"`, `\`, newlines or HTML
    /// fragments must round-trip through the encoder without breaking
    /// the JSON file. This catches the regression where a careless
    /// switch to a non-escaping encoder ships a parse error to every
    /// polling browser.
    func test_jsonEncoding_escapesQuotesAndControlCharacters() throws {
        let nasty = LiveBroadcastState(
            token: String(repeating: "f", count: 32),
            clientName: #"He said "hello"\nworld"#,
            host: "stripe.com",
            startedAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000),
            phase: "probing",
            probes: [],
            synthesis: "<script>alert('xss')</script>\nNewline here\tand a tab"
        )

        let data = try nasty.encoded()
        let decoded = try LiveBroadcastState.canonicalDecoder
            .decode(LiveBroadcastState.self, from: data)
        XCTAssertEqual(decoded.clientName, nasty.clientName)
        XCTAssertEqual(decoded.synthesis, nasty.synthesis)

        // Sanity-check the bytes are valid UTF-8 and look JSON-y.
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.hasPrefix("{"))
        XCTAssertTrue(text.hasSuffix("}"))
    }

    // MARK: - Determinism

    /// Same logical input → same encoded bytes. The
    /// `LiveBroadcastWriter` injects a clock + random-bytes provider
    /// for this exact reason: tests can pin both and assert that the
    /// JSON snapshot is byte-stable across runs.
    func test_canonicalEncoder_isDeterministicForIdenticalInput() throws {
        let state = LiveBroadcastState(
            token: String(repeating: "9", count: 32),
            clientName: "Stripe",
            host: "stripe.com",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_010),
            phase: "probing",
            probes: [
                LiveBroadcastState.ProbeStatus(kind: "pageSpeed", state: "running"),
            ]
        )

        let bytes1 = try state.encoded()
        let bytes2 = try state.encoded()
        XCTAssertEqual(bytes1, bytes2,
                       "Canonical encoder must produce byte-stable output (sorted keys, fixed date strategy)")
    }

    // MARK: - Mapping

    /// `LiveBroadcastState.probes(from:)` must preserve
    /// `ProbeKind.allCases` order so the browser-side grid stays
    /// visually stable. A `Dictionary` walk would reorder them
    /// unpredictably.
    func test_probesMapping_preservesProbeKindOrder() {
        let states: [AuditController.ProbeKind: AuditController.ProbeState] = [
            .pageSpeed: .ok,
            .security:  .failed(reason: "Boom"),
            .email:     .running,
        ]
        let probes = LiveBroadcastState.probes(from: states)
        XCTAssertEqual(probes.count, AuditController.ProbeKind.allCases.count)
        XCTAssertEqual(probes.map(\.kind),
                       AuditController.ProbeKind.allCases.map(\.rawValue))
        XCTAssertEqual(probes[0].state, "ok")
        XCTAssertEqual(probes[1].state, "failed")
        XCTAssertEqual(probes[1].error, "Boom")
        XCTAssertEqual(probes[2].state, "running")
    }

    // MARK: - Cleanup of expired broadcasts

    /// `cleanupExpiredBroadcasts(under:olderThan:)` must remove
    /// session folders whose `state.json` is older than the
    /// retention window. We don't actually wait 7 days — instead we
    /// stamp the file's modification date back in time.
    func test_cleanup_removesExpiredSessionFolders() async throws {
        let writer = LiveBroadcastWriter()
        let client = AuditClient(url: URL(string: "https://stripe.com")!, name: "Stripe")
        let session = try await writer.create(for: client, under: tempRoot)

        // Back-date the state.json to 30 days ago.
        let stateURL = session.folderURL.appendingPathComponent(LiveBroadcastWriter.stateFileName)
        let past = Date().addingTimeInterval(-30 * 24 * 3_600)
        try FileManager.default.setAttributes([.modificationDate: past],
                                              ofItemAtPath: stateURL.path)

        writer.cleanupExpiredBroadcasts(under: tempRoot, olderThan: 7 * 24 * 3_600)

        XCTAssertFalse(FileManager.default.fileExists(atPath: session.folderURL.path),
                       "Cleanup must remove session folders older than the retention window")
    }
}
