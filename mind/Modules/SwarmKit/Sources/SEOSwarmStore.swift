import Foundation
import GraphCore  // MINDTelemetry

/// v1.0-alpha.7 — On-disk store for `SEOSwarmJob` values.
///
/// Each job is persisted as `Documents/seo-swarm-jobs/<uuid>.json`.
/// Same shape contract as the v0.29 `FollowUpStore` — per-file
/// granularity means a partial write of one job never corrupts the
/// whole queue, and an in-memory mirror (`cache`) backs every read so
/// the UI never round-trips through the filesystem on render.
///
/// Soft-fail strategy: every disk write that throws is downgraded to
/// a MINDTelemetry warning + an in-memory-only mutation. The next
/// successful write upgrades the in-memory state back to disk.
public actor SEOSwarmStore {

    public static let shared = SEOSwarmStore()

    /// Root directory holding every job JSON file. Lazily created on
    /// the first write. Defaults to `Documents/seo-swarm-jobs/`.
    private let rootURL: URL

    /// In-memory mirror of every job read so far. Populated on first
    /// access via `hydrateIfNeeded()`; mutations write through to
    /// disk via `writeToDisk(_:)`.
    private var cache: [UUID: SEOSwarmJob] = [:]
    private var hydrated: Bool = false

    public init(rootURL: URL = SEOSwarmStore.defaultRootURL()) {
        self.rootURL = rootURL
    }

    /// Default `Documents/seo-swarm-jobs/` directory under the app
    /// sandbox. Static so the singleton + injected instances can
    /// share the convention without duplicating the lookup.
    public nonisolated static func defaultRootURL() -> URL {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return documents.appendingPathComponent("seo-swarm-jobs", isDirectory: true)
    }

    // MARK: - Public API

    /// Save (insert or replace) a job. Idempotent — the file is fully
    /// rewritten so a partial earlier write never sticks around. On
    /// disk failure, the mutation stays in-memory and a warning
    /// breadcrumb is emitted.
    public func save(_ job: SEOSwarmJob) async {
        await hydrateIfNeeded()
        cache[job.id] = job
        writeToDisk(job)
    }

    /// Load a single job by id. Returns nil when the job has never
    /// been saved (or has been deleted) or when the on-disk file
    /// exists but is corrupt.
    public func load(_ id: UUID) async -> SEOSwarmJob? {
        await hydrateIfNeeded()
        return cache[id]
    }

    /// Every job currently in the cache, regardless of status. Used
    /// by the Cockpit history view + tests.
    public func allJobs() async -> [SEOSwarmJob] {
        await hydrateIfNeeded()
        return Array(cache.values)
    }

    /// Delete a job's file + cache entry. Soft-fail.
    public func delete(_ id: UUID) async {
        cache.removeValue(forKey: id)
        let url = fileURL(for: id)
        try? FileManager.default.removeItem(at: url)
    }

    /// Wipe the entire store. Used by Settings → Danger zone + tests.
    public func clearAll() async {
        cache.removeAll()
        try? FileManager.default.removeItem(at: rootURL)
        hydrated = true
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
                "swarm.store.hydrate.failed",
                data: ["error": String(describing: error)]
            )
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let job = try decoder.decode(SEOSwarmJob.self, from: data)
                cache[job.id] = job
            } catch {
                await telemetryWarning(
                    "swarm.store.decode.failed",
                    data: [
                        "file": url.lastPathComponent,
                        "error": String(describing: error),
                    ]
                )
            }
        }
    }

    private func writeToDisk(_ job: SEOSwarmJob) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            Task { await telemetryWarning(
                "swarm.store.mkdir.failed",
                data: ["error": String(describing: error)]
            ) }
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(job)
            try data.write(to: fileURL(for: job.id), options: [.atomic])
        } catch {
            Task { await telemetryWarning(
                "swarm.store.write.failed",
                data: [
                    "jobID": job.id.uuidString,
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
