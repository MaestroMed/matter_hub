import XCTest
import Network
@testable import LiveBroadcastKit
@testable import AuditKit

/// v0.22.2 — Locks the embedded HTTP+WebSocket broadcaster.
///
/// Pure-unit tests cover frame encoding, the HTTP handshake key
/// derivation, request parsing, and the HTML template variant. A
/// dedicated end-to-end test spins the actor on `127.0.0.1` with an
/// ephemeral port and walks the full HTTP-GET → WebSocket-upgrade →
/// broadcast → receive loop against a raw TCP `NWConnection`.
final class LiveBroadcastWebSocketServerTests: XCTestCase {

    // MARK: - Frame encoding

    /// Tiny payloads (< 126 bytes) use the 7-bit length form. Per RFC
    /// 6455 §5.2, a server text frame is `0x81` then the length byte
    /// then the payload bytes (no mask). The test locks the byte
    /// sequence for a known input.
    func test_encodeTextFrame_usesShortLengthForm() {
        let payload = Data("hello".utf8)
        let frame = LiveBroadcastWebSocketServer.encodeTextFrame(payload)

        XCTAssertEqual(frame[0], 0x81, "First byte must be FIN=1 + opcode=1 (text)")
        XCTAssertEqual(frame[1], 5, "Length byte equals payload length for payloads < 126")
        XCTAssertEqual(frame.suffix(from: 2), payload,
                       "Payload must trail the 2-byte header verbatim, unmasked")
    }

    /// Payloads in the 126…65535 range use the 16-bit extended length
    /// form: length byte = 126, then two big-endian length bytes.
    func test_encodeTextFrame_usesExtended16BitLengthForm() {
        let payload = Data(repeating: 0x41, count: 200)
        let frame = LiveBroadcastWebSocketServer.encodeTextFrame(payload)

        XCTAssertEqual(frame[0], 0x81)
        XCTAssertEqual(frame[1], 126, "Length byte must signal 16-bit extended length")
        let advertisedLength = (UInt16(frame[2]) << 8) | UInt16(frame[3])
        XCTAssertEqual(advertisedLength, 200,
                       "Extended length must equal payload length in big-endian")
        XCTAssertEqual(frame.count, 4 + 200, "Header is 4 bytes, payload follows")
    }

    /// Server frames must never have the mask bit set. The polling-
    /// client → server direction does mask; server → client does not.
    func test_encodeTextFrame_neverMasksServerFrames() {
        let frame = LiveBroadcastWebSocketServer.encodeTextFrame(Data("x".utf8))
        let lengthByte = frame[1]
        XCTAssertEqual(lengthByte & 0x80, 0, "Mask bit must be 0 on server frames")
    }

    // MARK: - Handshake key derivation

    /// RFC 6455 §1.3 sample. With `Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==`,
    /// the server must reply `Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`.
    func test_computeAcceptKey_matchesRFC6455Sample() {
        let accept = LiveBroadcastWebSocketServer.computeAcceptKey(
            forKey: "dGhlIHNhbXBsZSBub25jZQ=="
        )
        XCTAssertEqual(accept, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
                       "Accept derivation must match the RFC sample")
    }

    /// A different key produces a different accept. Locks the
    /// derivation against a regression that always returned the
    /// same value.
    func test_computeAcceptKey_isInputDependent() {
        let a = LiveBroadcastWebSocketServer.computeAcceptKey(forKey: "AAAAAAAAAAAAAAAAAAAAAA==")
        let b = LiveBroadcastWebSocketServer.computeAcceptKey(forKey: "BBBBBBBBBBBBBBBBBBBBBB==")
        XCTAssertNotEqual(a, b, "Different keys must yield different accepts")
    }

    // MARK: - Request parsing

    /// Standard HTTP GET parse — method, path, header map.
    func test_httpRequestHead_parsesGETLineAndHeaders() {
        let raw = "GET /ws HTTP/1.1\r\nHost: 127.0.0.1:8787\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: abc123\r\n\r\n"
        let head = HTTPRequestHead.parse(raw)

        XCTAssertEqual(head.method, "GET")
        XCTAssertEqual(head.path, "/ws")
        XCTAssertEqual(head.header("Host"), "127.0.0.1:8787")
        XCTAssertEqual(head.header("Upgrade"), "websocket")
        XCTAssertEqual(head.header("sec-websocket-key"), "abc123",
                       "Header lookup must be case-insensitive")
    }

    /// `isWebSocketUpgrade(forPath:)` only fires when method + path +
    /// upgrade headers all align. The `Connection` header in real
    /// browser traffic is often `"keep-alive, Upgrade"` — the
    /// case-insensitive `contains("upgrade")` check must accept that.
    func test_httpRequestHead_detectsWebSocketUpgradeWithMixedConnectionHeader() {
        let raw = "GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Key: k\r\n\r\n"
        let head = HTTPRequestHead.parse(raw)
        XCTAssertTrue(head.isWebSocketUpgrade(forPath: "/ws"),
                      "Browsers send `Connection: keep-alive, Upgrade` — must still detect upgrade")
    }

    /// A plain `GET /` is not a WebSocket upgrade (no Upgrade header).
    func test_httpRequestHead_rejectsPlainGETAsUpgrade() {
        let raw = "GET / HTTP/1.1\r\nHost: x\r\n\r\n"
        let head = HTTPRequestHead.parse(raw)
        XCTAssertFalse(head.isWebSocketUpgrade(forPath: "/ws"))
        XCTAssertFalse(head.isWebSocketUpgrade(forPath: "/"))
    }

    // MARK: - URL helper

    /// `makeURL(host:port:)` builds an `http://host:port/` URL the
    /// share sheet can paste straight into the QR generator.
    func test_makeURL_buildsExpectedURL() {
        let url = LiveBroadcastWebSocketServer.makeURL(host: "192.168.1.42", port: 8787)
        XCTAssertEqual(url.absoluteString, "http://192.168.1.42:8787/")
    }

    // MARK: - HTML template variant

    /// The WebSocket template must NOT poll `state.json` — its
    /// renderer pulls state from a `new WebSocket(...)` connection
    /// instead. A regression that confused the two variants would
    /// quietly fall back to polling and the user would lose the
    /// "zero-latency" property.
    func test_htmlTemplateWebSocketVariant_dropsPollingDoesUpgrade() {
        let html = LiveBroadcastHTMLTemplate.renderWebSocket(
            clientName: "Acme",
            host: "acme.com"
        )

        XCTAssertFalse(html.contains("./state.json"),
                       "WebSocket variant must not poll a JSON snapshot")
        XCTAssertFalse(html.contains("setInterval(poll"),
                       "WebSocket variant must not schedule a polling loop")
        XCTAssertTrue(html.contains("new WebSocket("),
                      "WebSocket variant must open a WebSocket connection")
        XCTAssertTrue(html.contains("/ws"),
                      "WebSocket variant must target the /ws upgrade path")
    }

    /// The WebSocket template still falls under the 50 KB budget so
    /// the embedded server response stays snappy on poor radios.
    func test_htmlTemplateWebSocketVariant_staysUnderFileSizeBudget() {
        let html = LiveBroadcastHTMLTemplate.renderWebSocket(
            clientName: "Some Long Client Name LLC",
            host: "long.example.com"
        )
        let bytes = Data(html.utf8).count
        XCTAssertLessThanOrEqual(bytes, LiveBroadcastHTMLTemplate.maxBytes,
                                  "WebSocket variant must stay under 50 KB (got \(bytes))")
    }

    // MARK: - End-to-end loopback test

    /// Spin the server, perform a raw HTTP GET against `/`, assert
    /// the response is the HTML template. Validates the full
    /// `start()` → bind → accept → respond → cancel path.
    func test_server_serves_HTML_on_GET_root() async throws {
        let server = LiveBroadcastWebSocketServer()
        defer { Task { await server.stop() } }

        let port = try await server.start(
            clientName: "Acme",
            host: "acme.com",
            port: 0 // ephemeral
        )
        XCTAssertGreaterThan(port, 0, "OS must assign an ephemeral port")

        let response = try await rawGET(path: "/", port: port)
        XCTAssertTrue(response.contains("HTTP/1.1 200 OK"),
                      "GET / must return 200 OK")
        XCTAssertTrue(response.contains("Content-Type: text/html"),
                      "GET / must serve text/html")
        XCTAssertTrue(response.contains("<title>Audit live"),
                      "GET / must return the HTML template body")
        XCTAssertTrue(response.contains("new WebSocket("),
                      "GET / must return the WebSocket variant of the template")
    }

    /// Broadcasting before any client has connected must not crash
    /// the actor or leak state — the snapshot is cached as the
    /// `lastSnapshot` and replayed to whoever connects next. This is
    /// the boring-but-load-bearing guarantee: the controller starts
    /// the run + fires `auditCompleted` before the prospect even
    /// opens the share URL.
    func test_server_broadcastWithoutClients_isSafe() async throws {
        let server = LiveBroadcastWebSocketServer()
        defer { Task { await server.stop() } }

        _ = try await server.start(
            clientName: "Acme",
            host: "acme.com",
            port: 0
        )

        let snapshot = LiveBroadcastState(
            token: String(repeating: "f", count: 32),
            clientName: "Acme",
            host: "acme.com",
            startedAt: Date(timeIntervalSince1970: 1_747_699_200),
            updatedAt: Date(timeIntervalSince1970: 1_747_699_400),
            phase: "synthesizing"
        )
        await server.broadcast(snapshot)

        let count = await server.connectedClientCount
        XCTAssertEqual(count, 0, "No clients connected — broadcast must no-op safely")
    }

    // MARK: - Adapter integration

    /// The `LiveBroadcastWebSocketAdapter` must surface every
    /// controller transition into the cached state. Locks the wire
    /// shape after a representative sequence: run started → probe ok
    /// → audit completed.
    func test_webSocketAdapter_mirrorsControllerLifecycle() async {
        let server = LiveBroadcastWebSocketServer()
        defer { Task { await server.stop() } }

        let token = String(repeating: "b", count: 32)
        let adapter = LiveBroadcastWebSocketAdapter(
            server: server,
            token: token,
            clientName: "Acme",
            host: "acme.com"
        )

        // Initial state — every probe `pending`.
        let initial = adapter.currentState()
        XCTAssertEqual(initial.phase, "probing")
        XCTAssertEqual(initial.probes.count, AuditController.ProbeKind.allCases.count)
        XCTAssertTrue(initial.probes.allSatisfy { $0.state == "pending" })

        // probeStateChanged → the matching kind flips to ok.
        await adapter.probeStateChanged(
            kind: .pageSpeed,
            state: .ok,
            durationMs: 312
        )
        let afterProbe = adapter.currentState()
        let pageSpeedProbe = afterProbe.probes.first { $0.kind == "pageSpeed" }
        XCTAssertEqual(pageSpeedProbe?.state, "ok")
        XCTAssertEqual(pageSpeedProbe?.durationMs, 312)

        // auditCompleted → phase flips, scoring + synthesis populate.
        let report = AuditReport(
            client: AuditClient(url: URL(string: "https://acme.com")!, name: "Acme"),
            persona: .saasB2B,
            scoring: AuditReport.Scoring(
                overall: 87, performance: 80, seo: 90,
                security: 95, brand: 85, mobile: 88
            ),
            performance: nil,
            synthesis: "Identité tech-forward.",
            quickWins: [],
            strategicBets: [],
            hiddenRisks: [],
            pitch: "Hi team —"
        )
        await adapter.auditCompleted(report: report)
        let final = adapter.currentState()
        XCTAssertEqual(final.phase, "completed")
        XCTAssertEqual(final.scoring?.overall, 87)
        XCTAssertEqual(final.synthesis, "Identité tech-forward.")
        XCTAssertEqual(final.pitch, "Hi team —")
    }

    // MARK: - Raw TCP helpers

    /// Open a TCP socket to `127.0.0.1:port`, send a single HTTP
    /// request line + empty body, read until the connection closes,
    /// return the full response as a String. Use for one-shot GETs
    /// where the server closes after the response.
    private func rawGET(path: String, port: UInt16) async throws -> String {
        let connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let ready = expectation(description: "GET ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        connection.start(queue: .global())
        await fulfillment(of: [ready], timeout: 4)

        let request = "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        let sent = expectation(description: "GET sent")
        connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in
            sent.fulfill()
        })
        await fulfillment(of: [sent], timeout: 4)

        let response = try await receiveOnce(connection: connection, timeout: 4)
        connection.cancel()
        return String(data: response, encoding: .utf8) ?? ""
    }

    /// Read one chunk from the connection, bounded by a timeout via
    /// a `withThrowingTaskGroup` race so a stalled peer doesn't hang
    /// the test for the default 60s.
    private func receiveOnce(connection: NWConnection, timeout: TimeInterval) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        continuation.resume(returning: data ?? Data())
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw LiveBroadcastWebSocketServerTestsError.timeout
            }
            let first = try await group.next()
            group.cancelAll()
            return first ?? Data()
        }
    }
}

private enum LiveBroadcastWebSocketServerTestsError: Error {
    case timeout
}
