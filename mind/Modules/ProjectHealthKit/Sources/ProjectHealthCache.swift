import Foundation
import GraphCore

/// v1.0-alpha.8 — Cached snapshot of every live integration we surface
/// in ProjectDetailSheet. Codable so we can mirror to Documents and
/// rehydrate across launches without re-hitting the APIs.
///
/// A nil field reads as "never fetched yet" — the UI surfaces an
/// empty state with a "Token Vercel manquant" CTA when the matching
/// integration's token isn't configured. A non-nil field that's older
/// than `ProjectHealthCache.ttl` reads as stale; the surface fetches
/// in the background and updates the slot as soon as the answer
/// lands.
public struct ProjectHealthBundle: Sendable, Codable, Hashable {
    public var latestDeployment: VercelDeployment?
    public var vercelHealth: VercelHealth?
    public var recentCommits: [GitHubCommit]
    public var repoStats: GitHubRepoStats?
    public var lighthouse: LighthouseScore?
    public var refreshedAt: Date

    public init(
        latestDeployment: VercelDeployment? = nil,
        vercelHealth: VercelHealth? = nil,
        recentCommits: [GitHubCommit] = [],
        repoStats: GitHubRepoStats? = nil,
        lighthouse: LighthouseScore? = nil,
        refreshedAt: Date = .now
    ) {
        self.latestDeployment = latestDeployment
        self.vercelHealth = vercelHealth
        self.recentCommits = recentCommits
        self.repoStats = repoStats
        self.lighthouse = lighthouse
        self.refreshedAt = refreshedAt
    }
}

/// v1.0-alpha.8 — In-memory + on-disk cache for `ProjectHealthBundle`,
/// keyed by `Project.id`. Mirrors `HealthPulseStore` shape so the
/// telemetry conventions stay consistent.
///
/// TTL: 5 minutes. Inside the TTL window, every `load(...)` call hits
/// the cache. Past the TTL, the cache is still served (so the UI
/// renders something immediately) but the caller is expected to kick
/// a background refresh — there is no internal scheduling here.
public actor ProjectHealthCache {
    public static let shared = ProjectHealthCache(rootURL: defaultRootURL())

    /// 5-minute TTL — short enough that Mehdi watching a deploy in
    /// real time sees fresh data within a sheet re-open, long enough
    /// that idle browsing of the cockpit doesn't burn the Vercel /
    /// GitHub free-tier quotas.
    public static let ttl: TimeInterval = 5 * 60

    private let rootURL: URL
    private var cache: [UUID: ProjectHealthBundle] = [:]
    private var didHydrate: Bool = false

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    // MARK: - Public API

    /// Returns the cached bundle if any (fresh or stale).
    public func bundle(for projectID: UUID) async -> ProjectHealthBundle? {
        await hydrateIfNeeded()
        return cache[projectID]
    }

    /// True iff the bundle for the given project exists AND is inside
    /// the TTL window. The UI uses this to gate "show spinner" vs
    /// "render cached data".
    public func isFresh(_ projectID: UUID, now: Date = .now) async -> Bool {
        guard let bundle = await self.bundle(for: projectID) else { return false }
        return now.timeIntervalSince(bundle.refreshedAt) < Self.ttl
    }

    /// Replaces the entire bundle for a project. Bumps the
    /// `refreshedAt` field automatically — callers don't need to
    /// stamp it themselves.
    public func save(_ bundle: ProjectHealthBundle, for projectID: UUID) async {
        await hydrateIfNeeded()
        var stamped = bundle
        stamped.refreshedAt = .now
        cache[projectID] = stamped
        await writeToDisk(stamped, for: projectID)
        await telemetry("projectHealth.cache.write", level: .info)
    }

    /// Mutates one slot of the bundle in place. Used by the fan-out
    /// fetcher in ProjectDetailSheet — Vercel / GitHub / Lighthouse
    /// each land on their own clock and update only their slot.
    public func update<T>(
        _ projectID: UUID,
        keyPath: WritableKeyPath<ProjectHealthBundle, T>,
        value: T
    ) async {
        await hydrateIfNeeded()
        var bundle = cache[projectID] ?? ProjectHealthBundle()
        bundle[keyPath: keyPath] = value
        bundle.refreshedAt = .now
        cache[projectID] = bundle
        await writeToDisk(bundle, for: projectID)
    }

    /// Drops every cached bundle (memory + disk). Used by Settings →
    /// Danger zone → "Wipe all data".
    public func clearAll() async {
        cache.removeAll()
        let fm = FileManager.default
        if let entries = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) {
            for entry in entries where entry.pathExtension == "json" {
                try? fm.removeItem(at: entry)
            }
        }
    }

    // MARK: - Internals

    private func hydrateIfNeeded() async {
        guard !didHydrate else { return }
        didHydrate = true
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.pathExtension == "json" {
            let stem = entry.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: stem) else { continue }
            guard let data = try? Data(contentsOf: entry) else { continue }
            do {
                let bundle = try JSONDecoder().decode(ProjectHealthBundle.self, from: data)
                cache[id] = bundle
            } catch {
                // Soft-skip corrupt entries — a future probe will rewrite the slot.
                await telemetry("projectHealth.cache.decode.failed", level: .warning, data: ["entry": stem])
            }
        }
    }

    private func writeToDisk(_ bundle: ProjectHealthBundle, for projectID: UUID) async {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            await telemetry("projectHealth.cache.mkdir.failed",
                            level: .warning,
                            data: ["error": error.localizedDescription])
            return
        }
        let target = rootURL.appendingPathComponent("\(projectID.uuidString).json")
        do {
            let data = try JSONEncoder().encode(bundle)
            try data.write(to: target, options: .atomic)
        } catch {
            await telemetry("projectHealth.cache.write.failed",
                            level: .warning,
                            data: ["error": error.localizedDescription])
        }
    }

    /// MainActor bridge for `MINDTelemetry` since the facade is
    /// MainActor-isolated and the cache is a non-MainActor actor.
    /// Same shape as `HealthPulseStore.telemetryWarning` /
    /// `FollowUpStore.telemetry*` so the call-site vocabulary stays
    /// consistent across modules.
    private func telemetry(_ name: String, level: MINDTelemetry.Level, data: [String: String] = [:]) async {
        await MainActor.run {
            MINDTelemetry.breadcrumb(name, level: level, data: data)
        }
    }

    private static func defaultRootURL() -> URL {
        let fm = FileManager.default
        let documents = (try? fm.url(for: .documentDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true))
            ?? fm.temporaryDirectory
        return documents.appendingPathComponent("project-health", isDirectory: true)
    }
}
