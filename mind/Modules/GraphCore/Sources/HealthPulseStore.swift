import Foundation

/// v1.0-alpha.8 — On-disk store for the most recent `HealthPulse`
/// per Project.
///
/// Why "most recent only"
/// ----------------------
/// The Cockpit only ever surfaces "is this site up right now?" — a
/// full time-series of every historical probe is overkill for the
/// status-dot use case. Keeping one record per `projectID` caps disk
/// usage at ~N projects × ~200 bytes = trivial, and the read path
/// stays an O(1) cache lookup. A future "uptime chart" feature can
/// graduate to per-day rollups under a sibling store without touching
/// this one.
///
/// File layout: `Documents/health-pulses/<projectID>.json`. Per-file
/// granularity means a partial write of one project's pulse never
/// corrupts the rest of the cache. Same shape contract as
/// `SEOSwarmStore` (v1.0-alpha.7) and `FollowUpStore` (v0.29) so the
/// soft-fail/telemetry pattern stays single-sourced.
public actor HealthPulseStore {

    public static let shared = HealthPulseStore()

    /// Root directory holding every pulse JSON file. Lazily created
    /// on the first write. Defaults to `Documents/health-pulses/`.
    private let rootURL: URL

    /// In-memory mirror of every pulse read so far. Populated on first
    /// access via `hydrateIfNeeded()`; mutations write through to disk
    /// via `writeToDisk(_:)`.
    private var cache: [UUID: HealthPulse] = [:]
    private var hydrated: Bool = false

    public init(rootURL: URL = HealthPulseStore.defaultRootURL()) {
        self.rootURL = rootURL
    }

    /// Default `Documents/health-pulses/` directory under the app
    /// sandbox. Static + nonisolated so the singleton + injected
    /// test instances share the convention without duplicating the
    /// lookup.
    public nonisolated static func defaultRootURL() -> URL {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return documents.appendingPathComponent("health-pulses", isDirectory: true)
    }

    // MARK: - Public API

    /// Save (insert or replace) the most recent pulse for a project.
    /// Idempotent — the file is fully rewritten so a partial earlier
    /// write never sticks around. On disk failure, the mutation stays
    /// in-memory and a warning breadcrumb is emitted.
    public func save(_ pulse: HealthPulse) async {
        await hydrateIfNeeded()
        cache[pulse.projectID] = pulse
        writeToDisk(pulse)
    }

    /// Load the most recent pulse for a project. Returns nil when no
    /// pulse has ever been saved for that project, or when the on-disk
    /// file exists but is corrupt.
    public func load(projectID: UUID) async -> HealthPulse? {
        await hydrateIfNeeded()
        return cache[projectID]
    }

    /// Every pulse currently in the cache, regardless of status. Used
    /// by the Cockpit "what's on fire" surfaces + tests.
    public func allPulses() async -> [HealthPulse] {
        await hydrateIfNeeded()
        return Array(cache.values)
    }

    /// Delete a project's pulse file + cache entry. Soft-fail.
    public func delete(projectID: UUID) async {
        cache.removeValue(forKey: projectID)
        let url = fileURL(for: projectID)
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
                "health.store.hydrate.failed",
                data: ["error": String(describing: error)]
            )
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let pulse = try decoder.decode(HealthPulse.self, from: data)
                cache[pulse.projectID] = pulse
            } catch {
                await telemetryWarning(
                    "health.store.decode.failed",
                    data: [
                        "file": url.lastPathComponent,
                        "error": String(describing: error),
                    ]
                )
            }
        }
    }

    private func writeToDisk(_ pulse: HealthPulse) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            Task { await telemetryWarning(
                "health.store.mkdir.failed",
                data: ["error": String(describing: error)]
            ) }
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(pulse)
            try data.write(to: fileURL(for: pulse.projectID), options: [.atomic])
        } catch {
            Task { await telemetryWarning(
                "health.store.write.failed",
                data: [
                    "projectID": pulse.projectID.uuidString,
                    "error": String(describing: error),
                ]
            ) }
        }
    }

    private func fileURL(for projectID: UUID) -> URL {
        rootURL.appendingPathComponent("\(projectID.uuidString).json", isDirectory: false)
    }

    // MARK: - Telemetry MainActor bridges

    private func telemetryWarning(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.warning(name, data: data) }
    }
}
