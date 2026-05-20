import Foundation
import GraphCore  // MINDTelemetry

/// v0.32 — On-disk archive of every completed `AuditReport`.
///
/// The archive is the substrate for the new "Audit comparisons (multi-
/// target)" surface: the user picks 2–4 previously-audited clients and
/// the ComparisonSheet derives a side-by-side scoreboard + quick-wins
/// overlap + hidden-risks delta from the persisted reports.
///
/// Persistence shape mirrors `InvoiceStore` and `FollowUpStore`: one
/// JSON file per record under `Documents/audits/<uuid>.json`, in-memory
/// `cache` for hot reads, lock-free at the OS layer because the actor
/// serialises concurrent writes. A corrupt write of one report can
/// never sink the whole archive — the next hydration just logs the
/// decode failure and skips the file.
///
/// AuditController calls `AuditReportArchive.shared.save(_:)` from a
/// detached Task right after the audit completes, so the archive
/// hydrates organically as Mehdi runs audits.
public actor AuditReportArchive {

    /// Shared singleton — the AuditController save path and the
    /// ComparisonSheet picker both reach this instance. Tests inject
    /// their own with a hermetic temp directory.
    public static let shared = AuditReportArchive()

    /// Root directory holding every report JSON. Lazily created on
    /// the first write. `Documents/audits/`.
    private let rootURL: URL

    /// In-memory mirror of every report read so far. Populated on
    /// first access via `hydrateIfNeeded()`; mutations write through
    /// to disk via `writeToDisk(_:)`.
    private var cache: [UUID: AuditReport] = [:]

    /// Tracks whether we've hydrated `cache` from disk yet.
    private var hydrated: Bool = false

    public init(
        rootURL: URL = AuditReportArchive.defaultRootURL()
    ) {
        self.rootURL = rootURL
    }

    /// Default `Documents/audits/` directory under the app sandbox.
    public nonisolated static func defaultRootURL() -> URL {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return documents.appendingPathComponent("audits", isDirectory: true)
    }

    // MARK: - CRUD

    /// Save (insert or replace) a report. Idempotent — the file is
    /// fully rewritten so a partial earlier write never sticks
    /// around. Keyed by the `AuditClient.id` so re-auditing the same
    /// client replaces the previous report rather than accumulating
    /// duplicates (the ComparisonSheet picker would otherwise show
    /// the same name twice and the most recent state would win
    /// ambiguously).
    public func save(_ report: AuditReport) async {
        await hydrateIfNeeded()
        cache[report.client.id] = report
        writeToDisk(report)
        await telemetryInfo(
            "audit.archive.saved",
            data: [
                "clientID": report.client.id.uuidString,
                "host": report.client.url.host(percentEncoded: false)
                    ?? report.client.url.absoluteString,
                "overall": String(report.scoring.overall),
            ]
        )
    }

    /// Returns every archived report, most-recent first. Used by the
    /// ComparisonSheet picker to populate the multi-select list.
    public func allReports() async -> [AuditReport] {
        await hydrateIfNeeded()
        return cache.values.sorted { $0.generatedAt > $1.generatedAt }
    }

    /// Returns a specific report by client id, or nil when no audit
    /// has ever been archived for that client. Useful when the
    /// AuditController wants to short-circuit a fresh run with the
    /// cached version (future use — not required by v0.32).
    public func report(forClientID id: UUID) async -> AuditReport? {
        await hydrateIfNeeded()
        return cache[id]
    }

    /// Deletes the report file + cache entry. Soft-fail.
    public func delete(clientID: UUID) async {
        cache.removeValue(forKey: clientID)
        let url = fileURL(for: clientID)
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes every archived report. Used by tests + a future
    /// Settings "Clear audit archive" path.
    public func clearAll() async {
        cache.removeAll()
        try? FileManager.default.removeItem(at: rootURL)
        hydrated = true  // empty cache is a valid hydrated state
    }

    // MARK: - Disk I/O

    private func hydrateIfNeeded() async {
        guard !hydrated else { return }
        hydrated = true
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootURL.path) else { return }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            await telemetryWarning(
                "audit.archive.hydrate.failed",
                data: ["error": String(describing: error)]
            )
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let report = try decoder.decode(AuditReport.self, from: data)
                cache[report.client.id] = report
            } catch {
                await telemetryWarning(
                    "audit.archive.decode.failed",
                    data: [
                        "file": url.lastPathComponent,
                        "error": String(describing: error),
                    ]
                )
            }
        }
    }

    private func writeToDisk(_ report: AuditReport) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            Task { await telemetryWarning(
                "audit.archive.mkdir.failed",
                data: ["error": String(describing: error)]
            ) }
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(report)
            try data.write(to: fileURL(for: report.client.id), options: [.atomic])
        } catch {
            Task { await telemetryWarning(
                "audit.archive.write.failed",
                data: [
                    "clientID": report.client.id.uuidString,
                    "error": String(describing: error),
                ]
            ) }
        }
    }

    private func fileURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    // MARK: - Telemetry MainActor bridges

    private func telemetryInfo(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.info(name, data: data) }
    }

    private func telemetryWarning(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.warning(name, data: data) }
    }
}
