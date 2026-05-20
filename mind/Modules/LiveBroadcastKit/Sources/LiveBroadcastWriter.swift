import Foundation
import AuditKit
import GraphCore

/// Owns the on-disk lifecycle of a live audit broadcast:
///
/// - `create(for:)` mints a fresh 16-byte hex token, lays the static
///   `index.html` template and an initial `state.json` snapshot under
///   `<rootURL>/<token>/`, and returns a `LiveBroadcastSession` the
///   call site uses to attach the writer to `AuditController`.
/// - `update(_:mutating:)` is the per-probe / per-state hot path:
///   reads the current snapshot from disk, hands the caller a mutable
///   copy, then writes the result back **atomically** so polling
///   browsers never `fetch` a half-written JSON.
/// - `close(_:)` flips `phase` to `"completed"` (or `"failed"`) and
///   writes the final snapshot. The folder stays on disk; cleanup is
///   the user's job (or the next `create(…)`-triggered GC pass).
/// - `cleanupExpiredBroadcasts(under:olderThan:)` walks `<rootURL>`
///   and deletes any session folder older than 7 days by default, so
///   the Documents dir doesn't bloat over a year of consulting.
///
/// Concurrency model: `actor` isolation guarantees a single in-flight
/// `update` per writer. The AuditController fires updates from its
/// MainActor, awaiting each — the actor serialises them.
public actor LiveBroadcastWriter {

    /// Default cleanup window. Subsequent `create(for:)` calls scan
    /// the destination root and delete sessions older than this. Pinned
    /// at 7 days per ULTRAPLAN spec.
    public static let defaultRetention: TimeInterval = 7 * 24 * 3_600

    /// File name for the JSON snapshot. Locked here — the HTML
    /// template hard-codes the same path (`fetch('./state.json')`).
    public static let stateFileName = "state.json"

    /// File name for the HTML viewer.
    public static let indexFileName = "index.html"

    /// Canonical broadcast root inside the iOS app sandbox:
    /// `Documents/live-broadcasts/`. Created lazily on first write so a
    /// fresh install doesn't carry an empty folder around.
    public static func defaultRoot() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("live-broadcasts", isDirectory: true)
    }

    /// Inject a clock for deterministic tests. The shared singleton
    /// uses `Date.init`; tests pass a fixed-time provider so JSON
    /// snapshots are byte-stable.
    private let now: @Sendable () -> Date

    /// Random-bytes provider for token generation. Tests inject a
    /// fixed sequence; production uses `SystemRandomNumberGenerator`.
    private let randomBytes: @Sendable (Int) -> [UInt8]

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        randomBytes: @escaping @Sendable (Int) -> [UInt8] = { count in
            var bytes = [UInt8](repeating: 0, count: count)
            var rng = SystemRandomNumberGenerator()
            for i in 0..<count {
                bytes[i] = UInt8.random(in: 0...255, using: &rng)
            }
            return bytes
        }
    ) {
        self.now = now
        self.randomBytes = randomBytes
    }

    // MARK: - Lifecycle

    /// Mint a session, lay down the static folder, return the handle.
    /// Throws if the destination folder can't be created or the
    /// initial snapshot can't be written — both indicate a sandboxed
    /// IO failure and propagate up to AuditSheet's error banner.
    ///
    /// As a side effect this runs a best-effort garbage pass over the
    /// `rootURL` and removes session folders older than
    /// `Self.defaultRetention`. Failures during the GC pass are
    /// silently absorbed (the broadcast itself is still good).
    @discardableResult
    public func create(
        for client: AuditClient,
        under rootURL: URL = LiveBroadcastWriter.defaultRoot()
    ) async throws -> LiveBroadcastSession {
        let token = mintToken()
        let folder = rootURL.appendingPathComponent(token, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let host = client.url.host(percentEncoded: false)
            ?? client.url.absoluteString
        let html = LiveBroadcastHTMLTemplate.render(
            clientName: client.displayName,
            host: host
        )
        let indexURL = folder.appendingPathComponent(Self.indexFileName)
        try Data(html.utf8).write(to: indexURL, options: .atomic)

        let stamp = now()
        let initial = LiveBroadcastState(
            token: token,
            clientName: client.displayName,
            host: host,
            startedAt: stamp,
            updatedAt: stamp,
            phase: LiveBroadcastState.Phase.probing.rawValue,
            probes: Self.initialProbes()
        )
        try writeState(initial, to: folder)

        // Best-effort GC.
        cleanupExpiredBroadcasts(under: rootURL, olderThan: Self.defaultRetention)

        let session = LiveBroadcastSession(
            token: token,
            folderURL: folder,
            suggestedURL: indexURL
        )
        await postTelemetry(name: "liveBroadcast.created", token: token, host: host)
        return session
    }

    /// Read-modify-write the snapshot atomically. The closure runs
    /// inside the actor's isolated context, so it can mutate the
    /// inout state freely without a separate lock. Any throw inside
    /// the IO path bubbles up — the caller decides whether to surface
    /// the error or swallow it (AuditController logs + drops).
    public func update(
        token: String,
        under rootURL: URL = LiveBroadcastWriter.defaultRoot(),
        mutating mutation: @Sendable (inout LiveBroadcastState) -> Void
    ) async throws {
        let folder = rootURL.appendingPathComponent(token, isDirectory: true)
        guard var current = try readState(from: folder) else {
            throw LiveBroadcastWriterError.broadcastNotFound(token: token)
        }
        mutation(&current)
        // Always re-stamp updatedAt so the polling client can render a
        // "Mis à jour il y a Xs" footer that drifts forward on every
        // write, regardless of whether the mutation touched it.
        let stamped = LiveBroadcastState(
            token: current.token,
            clientName: current.clientName,
            host: current.host,
            startedAt: current.startedAt,
            updatedAt: now(),
            phase: current.phase,
            probes: current.probes,
            scoring: current.scoring,
            synthesis: current.synthesis,
            pitch: current.pitch
        )
        try writeState(stamped, to: folder)
        await postTelemetry(name: "liveBroadcast.updated", token: token, host: stamped.host)
    }

    /// Flip the broadcast to its terminal phase. `success == true`
    /// writes `"completed"`, otherwise `"failed"`. The folder is not
    /// deleted — the broadcast URL keeps working as a static snapshot
    /// for as long as the destination root holds the file.
    public func close(
        token: String,
        success: Bool,
        under rootURL: URL = LiveBroadcastWriter.defaultRoot()
    ) async throws {
        try await update(token: token, under: rootURL) { state in
            state = LiveBroadcastState(
                token: state.token,
                clientName: state.clientName,
                host: state.host,
                startedAt: state.startedAt,
                updatedAt: state.updatedAt,
                phase: success
                    ? LiveBroadcastState.Phase.completed.rawValue
                    : LiveBroadcastState.Phase.failed.rawValue,
                probes: state.probes,
                scoring: state.scoring,
                synthesis: state.synthesis,
                pitch: state.pitch
            )
        }
        await postTelemetry(name: "liveBroadcast.closed", token: token, host: nil)
    }

    /// Walk every immediate child folder of `rootURL` and remove any
    /// whose `state.json` is older than `maxAge`. Non-throwing: a
    /// stat or delete failure on one entry is swallowed so we never
    /// blow a live broadcast over a cleanup hiccup.
    public nonisolated func cleanupExpiredBroadcasts(
        under rootURL: URL,
        olderThan maxAge: TimeInterval
    ) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for entry in entries {
            let stateFile = entry.appendingPathComponent(Self.stateFileName)
            let attrs = try? fm.attributesOfItem(atPath: stateFile.path)
            let mtime = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
            if mtime < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }

    // MARK: - Tokens

    /// 16 random bytes → 32 lowercase hex chars. Cryptographically
    /// strong in production (uses `SystemRandomNumberGenerator`),
    /// deterministic in tests (the injected `randomBytes` returns a
    /// fixed sequence).
    public static let tokenByteLength: Int = 16

    /// Internal helper exposed for tests. Validates that a candidate
    /// string is a 32-char lowercase hex token.
    public nonisolated static func isValidToken(_ candidate: String) -> Bool {
        guard candidate.count == tokenByteLength * 2 else { return false }
        for ch in candidate.unicodeScalars {
            switch ch.value {
            case 0x30...0x39, 0x61...0x66: continue   // 0-9, a-f
            default: return false
            }
        }
        return true
    }

    /// Default seed for the initial snapshot — every probe shown as
    /// `pending` so the grid renders even before the first transition.
    public nonisolated static func initialProbes() -> [LiveBroadcastState.ProbeStatus] {
        AuditController.ProbeKind.allCases.map { kind in
            LiveBroadcastState.ProbeStatus(
                kind: kind.rawValue,
                state: LiveBroadcastState.ProbeLifecycle.pending.rawValue
            )
        }
    }

    private func mintToken() -> String {
        let bytes = randomBytes(Self.tokenByteLength)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - IO primitives

    /// Read + decode the snapshot, returning nil when the folder
    /// exists but `state.json` doesn't (legal mid-creation race).
    private func readState(from folder: URL) throws -> LiveBroadcastState? {
        let url = folder.appendingPathComponent(Self.stateFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try LiveBroadcastState.canonicalDecoder.decode(LiveBroadcastState.self, from: data)
    }

    /// Encode + write the snapshot atomically. `.atomic` writes via a
    /// temp sibling + rename so the polling client never sees a
    /// half-flushed JSON.
    private func writeState(_ state: LiveBroadcastState, to folder: URL) throws {
        let url = folder.appendingPathComponent(Self.stateFileName)
        let data = try state.encoded()
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Telemetry hop

    /// Telemetry is `@MainActor`-isolated; hop off the writer's actor
    /// to post the breadcrumb. Failures here are silent — telemetry
    /// must never interfere with broadcast correctness.
    private nonisolated func postTelemetry(
        name: String,
        token: String,
        host: String?
    ) async {
        var data: [String: String] = ["token_prefix": String(token.prefix(8))]
        if let host { data["host"] = host }
        await MainActor.run {
            MINDTelemetry.info(name, data: data)
        }
    }
}

/// Hard failure modes. Soft failures (IO transient errors) propagate
/// as raw `NSError` from the underlying `Data.write` / `FileManager`
/// calls — those messages are already informative.
public enum LiveBroadcastWriterError: Error, Equatable, Sendable {
    case broadcastNotFound(token: String)
}
