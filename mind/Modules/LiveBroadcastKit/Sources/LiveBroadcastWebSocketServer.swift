import Foundation
import Network
import GraphCore

/// v0.22.2 — Direct WebSocket broadcasting (Option B).
///
/// Replaces the polling JSON+static-HTML pipeline with an embedded
/// HTTP+WebSocket server inside the iOS app via `NWListener` (Network
/// framework). State updates push directly to every connected browser
/// instead of waiting for the next 800 ms poll tick.
///
/// **Topology**:
///
/// 1. The actor binds to `127.0.0.1:<port>` (or the caller's chosen
///    port — pass `0` for an OS-assigned ephemeral port).
/// 2. Browser connects via `http://<lan-ip>:<port>/`. The server
///    serves the WebSocket variant of the HTML template (renders
///    `new WebSocket(...)` instead of `fetch + setInterval`).
/// 3. Browser opens a second connection to `/ws` with an
///    `Upgrade: websocket` request. Network framework's
///    `NWProtocolWebSocket` handles the handshake + framing.
/// 4. Server tracks the connected `NWConnection` and pushes a JSON
///    text frame on every `broadcast(_:)` call.
///
/// **Acceptance**: zero-latency probe transitions on a browser
/// connected to the iPhone's local HTTP server.
///
/// **Lifecycle**: `start()` boots the listener, `stop()` cancels
/// every connection + the listener itself. The actor is single-shot —
/// `start` after `stop` is a no-op.
///
/// **Reach**: as documented in the ULTRAPLAN, this needs the viewer
/// to be on the same Wi-Fi as the iPhone (or to expose the iPhone
/// over tailscale / ngrok). The polling pipeline stays in place as
/// the fallback for clients on remote networks.
public actor LiveBroadcastWebSocketServer {

    /// Default port: 8787. Chosen above the ephemeral range (49152+)
    /// would conflict with macOS / iOS short-lived sockets, and below
    /// 1024 needs root. 8787 is memorable + unused by any common iOS
    /// service. Caller can override; passing `0` asks the OS for an
    /// ephemeral port (returned via `boundPort` after `start()`).
    public static let defaultPort: UInt16 = 8787

    /// Maximum number of simultaneously connected WebSocket clients.
    /// Above this, new upgrade requests are rejected with a 503 so a
    /// stuck or runaway client can't grow the connection set
    /// unboundedly. 16 is enough for a live demo with a few prospects
    /// + the consultant's screen sharing.
    public static let maxConcurrentClients: Int = 16

    // MARK: - State

    private var listener: NWListener?

    /// Active WebSocket connections — appended on upgrade, removed on
    /// connection failure / close. Held strongly so the connections
    /// stay alive past the upgrade callback.
    private var clients: [NWConnection] = []

    /// Last snapshot pushed. New clients receive it immediately on
    /// upgrade so their UI hydrates without waiting for the next
    /// `broadcast(_:)` call.
    private var lastSnapshot: LiveBroadcastState?

    /// Cached HTML body served on `GET /`. Computed lazily from
    /// `clientName` + `host` at `start()` time so the call site
    /// doesn't need to thread them through `broadcast(_:)`.
    private var cachedHTML: String?

    /// Port the OS actually bound to. Equal to the requested port
    /// when non-zero; otherwise filled in by the listener's state
    /// callback after the listener moves to `.ready`. `nil` before
    /// the listener is ready or after `stop()`.
    public private(set) var boundPort: UInt16?

    /// Tracks whether `start()` has been called. Idempotent guard.
    private var started: Bool = false

    /// One-shot continuation that the start() awaits until the
    /// listener fires `.ready` (and `boundPort` is filled in).
    private var readyContinuation: CheckedContinuation<UInt16, Error>?

    public init() {}

    // MARK: - Lifecycle

    /// Start the listener on `127.0.0.1:<port>`. Awaits until the
    /// listener moves to `.ready` and the OS reports the bound port,
    /// so the caller can immediately fold the port into a share URL.
    ///
    /// Throws if the listener fails to bind (port already in use,
    /// sandbox denial). A second call after a successful start is a
    /// no-op that returns the current `boundPort`.
    @discardableResult
    public func start(
        clientName: String,
        host: String,
        port requestedPort: UInt16 = LiveBroadcastWebSocketServer.defaultPort
    ) async throws -> UInt16 {
        if started, let bound = boundPort { return bound }
        cachedHTML = LiveBroadcastHTMLTemplate.renderWebSocket(
            clientName: clientName,
            host: host
        )

        let parameters = NWParameters.tcp
        // Loopback-only by default. The host App layer is the one
        // that decides whether to advertise the URL over Bonjour or
        // tailscale; the server itself just listens on loopback +
        // every interface (NWListener default).
        parameters.allowLocalEndpointReuse = true

        let port = NWEndpoint.Port(rawValue: requestedPort) ?? .any
        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters, on: port)
        } catch {
            await postTelemetry(name: "liveBroadcast.ws.startFailed", error: error)
            throw error
        }

        listener = newListener
        started = true

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleListenerState(state) }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.acceptIncoming(connection) }
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            self.readyContinuation = continuation
            newListener.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Tear the listener down + close every connected client. Safe to
    /// call before `start()` (no-op) and idempotent.
    public func stop() async {
        for connection in clients {
            connection.cancel()
        }
        clients.removeAll()
        listener?.cancel()
        listener = nil
        started = false
        boundPort = nil
        cachedHTML = nil
        lastSnapshot = nil
        await postTelemetry(name: "liveBroadcast.ws.stopped", error: nil)
    }

    // MARK: - Broadcasting

    /// Push the snapshot to every connected client as a single text
    /// frame. The JSON is the same `LiveBroadcastState.encoded()`
    /// payload the polling pipeline writes — the WebSocket template
    /// decodes it with the same `JSON.parse(...)` path as the polling
    /// template, so the renderer is identical end-to-end.
    public func broadcast(_ snapshot: LiveBroadcastState) async {
        lastSnapshot = snapshot
        let data: Data
        do {
            data = try snapshot.encoded()
        } catch {
            await postTelemetry(name: "liveBroadcast.ws.encodeFailed", error: error)
            return
        }
        for connection in clients {
            send(text: data, on: connection)
        }
    }

    /// Read-only client count for tests + telemetry.
    public var connectedClientCount: Int { clients.count }

    // MARK: - URL helpers

    /// Build the LAN URL the user can paste into a browser. Uses
    /// `host` if provided (typically the device's LAN IP or
    /// `.local` Bonjour name), or falls back to `127.0.0.1` for the
    /// simulator / on-device WKWebView preview.
    public nonisolated static func makeURL(
        scheme: String = "http",
        host: String = "127.0.0.1",
        port: UInt16
    ) -> URL {
        URL(string: "\(scheme)://\(host):\(port)/") ?? URL(fileURLWithPath: "/")
    }

    // MARK: - Listener callbacks

    private func handleListenerState(_ state: NWListener.State) async {
        switch state {
        case .ready:
            let port = listener?.port?.rawValue ?? 0
            boundPort = port
            if let continuation = readyContinuation {
                readyContinuation = nil
                continuation.resume(returning: port)
            }
            await postTelemetry(name: "liveBroadcast.ws.ready", error: nil)
        case .failed(let error):
            if let continuation = readyContinuation {
                readyContinuation = nil
                continuation.resume(throwing: error)
            }
            await postTelemetry(name: "liveBroadcast.ws.failed", error: error)
        case .cancelled:
            if let continuation = readyContinuation {
                readyContinuation = nil
                continuation.resume(throwing: LiveBroadcastWebSocketError.cancelledBeforeReady)
            }
        default:
            break
        }
    }

    /// Inspect the first bytes of a new connection to decide whether
    /// it's a plain HTTP GET (serve the HTML) or a WebSocket upgrade
    /// request (hand off to the WebSocket path).
    private func acceptIncoming(_ connection: NWConnection) async {
        connection.start(queue: .global(qos: .userInitiated))
        peekRequest(on: connection)
    }

    private func peekRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                Task { await self.handleConnectionError(error, on: connection) }
                return
            }
            guard let data, !data.isEmpty,
                  let head = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            Task { await self.route(head: head, data: data, on: connection) }
        }
    }

    private func route(head: String, data: Data, on connection: NWConnection) async {
        let request = HTTPRequestHead.parse(head)
        if request.isWebSocketUpgrade(forPath: "/ws") {
            await handleWebSocketUpgrade(request: request, on: connection)
        } else if request.method == "GET" {
            await serveHTML(on: connection)
        } else {
            await sendHTTP(status: 405, body: "Method Not Allowed", on: connection)
        }
    }

    private func serveHTML(on connection: NWConnection) async {
        let body = cachedHTML ?? "<!doctype html><title>MIND</title>"
        await sendHTTP(status: 200, body: body, contentType: "text/html; charset=utf-8", on: connection)
    }

    private func sendHTTP(
        status: Int,
        body: String,
        contentType: String = "text/plain; charset=utf-8",
        on connection: NWConnection
    ) async {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 405: reason = "Method Not Allowed"
        case 503: reason = "Service Unavailable"
        default: reason = "OK"
        }
        let bodyData = Data(body.utf8)
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        var payload = Data(header.utf8)
        payload.append(bodyData)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func handleWebSocketUpgrade(
        request: HTTPRequestHead,
        on connection: NWConnection
    ) async {
        guard clients.count < Self.maxConcurrentClients else {
            await sendHTTP(status: 503, body: "Too many clients", on: connection)
            return
        }
        guard let key = request.header("Sec-WebSocket-Key") else {
            await sendHTTP(status: 400, body: "Missing Sec-WebSocket-Key", on: connection)
            return
        }
        let accept = LiveBroadcastWebSocketServer.computeAcceptKey(forKey: key)
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r

        """
        let responseData = Data(response.utf8)
        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                Task { await self.handleConnectionError(error, on: connection) }
                return
            }
            Task { await self.registerClient(connection) }
        })
    }

    private func registerClient(_ connection: NWConnection) async {
        clients.append(connection)
        await postTelemetry(name: "liveBroadcast.ws.clientConnected", error: nil)
        // Hydrate the new client with the most recent snapshot so the
        // UI renders immediately.
        if let snapshot = lastSnapshot,
           let data = try? snapshot.encoded() {
            send(text: data, on: connection)
        }
        // Start reading incoming frames so we can spot close frames /
        // peer disconnects and prune the client list.
        startReadingFrames(on: connection)
    }

    private nonisolated func startReadingFrames(on connection: NWConnection) {
        // Use the connection's `stateUpdateHandler` for disconnect
        // detection rather than a recursive `receive` loop — the loop
        // was prone to scheduling a runaway chain of `Task` hops onto
        // the actor when the peer is chatty (browsers send periodic
        // pings). The state handler fires once on close and we prune
        // the connection then.
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                Task { await self.prune(connection) }
            default:
                break
            }
        }
    }

    private func handleConnectionError(_ error: Error, on connection: NWConnection) async {
        connection.cancel()
        await prune(connection)
        await postTelemetry(name: "liveBroadcast.ws.clientFailed", error: error)
    }

    private func prune(_ connection: NWConnection) async {
        clients.removeAll { $0 === connection }
    }

    // MARK: - Frame encoding

    /// Encode a single text frame per RFC 6455 §5.2. Server frames
    /// MUST NOT be masked (the masked bit stays 0). Payload length
    /// uses the appropriate width (7 bits / 16 bits / 64 bits) based
    /// on the payload size.
    public nonisolated static func encodeTextFrame(_ payload: Data) -> Data {
        var frame = Data()
        // FIN=1, RSV1-3=0, opcode=1 (text) → 0x81
        frame.append(0x81)
        let length = payload.count
        if length < 126 {
            frame.append(UInt8(length))
        } else if length <= UInt16.max {
            frame.append(126)
            frame.append(UInt8((length >> 8) & 0xff))
            frame.append(UInt8(length & 0xff))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((UInt64(length) >> shift) & 0xff))
            }
        }
        frame.append(payload)
        return frame
    }

    private func send(text payload: Data, on connection: NWConnection) {
        let frame = Self.encodeTextFrame(payload)
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            guard let self, let error else { return }
            Task { await self.handleConnectionError(error, on: connection) }
        })
    }

    // MARK: - Handshake helper

    /// RFC 6455 §4.2.2: `accept = base64(sha1(key + magic))` where
    /// `magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"`. Public so
    /// the unit test can lock the well-known sample value
    /// (`s3pPLMBiTxaQ9kYGzzhZRbK+xOo=` for `dGhlIHNhbXBsZSBub25jZQ==`).
    public nonisolated static func computeAcceptKey(forKey clientKey: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let concatenated = clientKey + magic
        let bytes = Array(concatenated.utf8)
        let digest = sha1(bytes)
        return Data(digest).base64EncodedString()
    }

    /// Pure-Swift SHA-1. Embedding it (vs `CryptoKit.Insecure.SHA1`)
    /// keeps the WebSocket layer free of an extra framework import +
    /// makes the function trivially testable in isolation.
    private nonisolated static func sha1(_ message: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        var bytes = message
        let originalLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0x00)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((originalLength >> shift) & 0xff))
        }

        for chunkStart in stride(from: 0, to: bytes.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let base = chunkStart + i * 4
                w[i] = (UInt32(bytes[base]) << 24)
                     | (UInt32(bytes[base + 1]) << 16)
                     | (UInt32(bytes[base + 2]) << 8)
                     | UInt32(bytes[base + 3])
            }
            for i in 16..<80 {
                let v = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
                w[i] = (v << 1) | (v >> 31)
            }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = (b << 30) | (b >> 2)
                b = a
                a = temp
            }
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }

        var result = [UInt8]()
        for value in [h0, h1, h2, h3, h4] {
            for shift in stride(from: 24, through: 0, by: -8) {
                result.append(UInt8((value >> shift) & 0xff))
            }
        }
        return result
    }

    // MARK: - Telemetry

    private nonisolated func postTelemetry(name: String, error: Error?) async {
        var data: [String: String] = [:]
        if let error { data["error"] = String(describing: error) }
        await MainActor.run {
            if error == nil {
                MINDTelemetry.info(name, data: data)
            } else {
                MINDTelemetry.warning(name, data: data)
            }
        }
    }
}

// MARK: - Errors

public enum LiveBroadcastWebSocketError: Error, Sendable, Equatable {
    /// Listener cancelled before it ever fired `.ready`. Happens when
    /// `stop()` is called between `start()` and the first state
    /// callback.
    case cancelledBeforeReady
}

// MARK: - HTTP request parsing

/// Minimal HTTP/1.1 request parser. Public so the WebSocket upgrade
/// path is unit-testable in isolation without spinning a server.
public struct HTTPRequestHead: Sendable, Equatable {
    public let method: String
    public let path: String
    public let headers: [(name: String, value: String)]

    public init(method: String, path: String, headers: [(name: String, value: String)]) {
        self.method = method
        self.path = path
        self.headers = headers
    }

    public static func == (lhs: HTTPRequestHead, rhs: HTTPRequestHead) -> Bool {
        guard lhs.method == rhs.method, lhs.path == rhs.path else { return false }
        guard lhs.headers.count == rhs.headers.count else { return false }
        for (a, b) in zip(lhs.headers, rhs.headers) {
            if a.name != b.name || a.value != b.value { return false }
        }
        return true
    }

    public func header(_ name: String) -> String? {
        let target = name.lowercased()
        for entry in headers where entry.name.lowercased() == target {
            return entry.value
        }
        return nil
    }

    /// True when the request is a well-formed RFC 6455 upgrade
    /// pointing at `forPath`. We accept any `Connection` header that
    /// contains `"upgrade"` (case-insensitive), matching what
    /// browsers actually send (`"keep-alive, Upgrade"` is common).
    public func isWebSocketUpgrade(forPath: String) -> Bool {
        guard method == "GET", path == forPath else { return false }
        guard let upgrade = header("Upgrade")?.lowercased(),
              upgrade.contains("websocket") else { return false }
        guard let connection = header("Connection")?.lowercased(),
              connection.contains("upgrade") else { return false }
        return header("Sec-WebSocket-Key") != nil
    }

    public static func parse(_ raw: String) -> HTTPRequestHead {
        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else {
            return HTTPRequestHead(method: "", path: "", headers: [])
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        let method = parts.count > 0 ? parts[0] : ""
        let path = parts.count > 1 ? parts[1] : ""
        var headers: [(name: String, value: String)] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon])
            let valueStart = line.index(after: colon)
            let value = String(line[valueStart...])
                .trimmingCharacters(in: .whitespaces)
            headers.append((name: name, value: value))
        }
        return HTTPRequestHead(method: method, path: path, headers: headers)
    }
}
