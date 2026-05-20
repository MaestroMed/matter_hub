import Foundation
import GraphCore

/// v1.0-alpha.9 — Lightweight, Sendable mirror of a `Project` row that
/// the aggregator can carry across the actor boundary without dragging
/// the SwiftData `@Model` itself across isolation domains. Built on
/// the MainActor from the `[Project]` query result and passed into the
/// aggregator's snapshot fan-out.
public struct ProjectIdentity: Sendable, Equatable, Hashable {
    public let id: UUID
    public let vercelProjectID: String?
    public let githubRepo: String?
    public let host: String

    public init(
        id: UUID,
        vercelProjectID: String?,
        githubRepo: String?,
        host: String
    ) {
        self.id = id
        self.vercelProjectID = vercelProjectID
        self.githubRepo = githubRepo
        self.host = host
    }
}

/// v1.0-alpha.9 — Aggregate portfolio-level health rollup surfaced in
/// the HomeView KPI bar + the PortfolioHealthSheet. Every field is
/// derived from the per-project `ProjectHealthBundle` cache so the
/// snapshot is pure once the per-project data lands.
///
/// `lastRefreshAt` carries the moment the snapshot was assembled so
/// the UI can render "actualisé il y a X" without re-fanning.
public struct PortfolioHealth: Sendable, Equatable {
    public let totalActiveProjects: Int
    public let buildsInProgress: Int
    public let buildErrors24h: Int
    public let avgLighthousePerf: Int?
    public let lastRefreshAt: Date

    public init(
        totalActiveProjects: Int,
        buildsInProgress: Int,
        buildErrors24h: Int,
        avgLighthousePerf: Int?,
        lastRefreshAt: Date
    ) {
        self.totalActiveProjects = totalActiveProjects
        self.buildsInProgress = buildsInProgress
        self.buildErrors24h = buildErrors24h
        self.avgLighthousePerf = avgLighthousePerf
        self.lastRefreshAt = lastRefreshAt
    }
}

/// v1.0-alpha.9 — Actor that rolls up the per-project
/// `ProjectHealthBundle` cache into a `PortfolioHealth` snapshot.
///
/// Two paths:
///
///  - `snapshot(for:)` is the production call site — fans out cache
///    reads + (optionally) live Vercel fetches via a TaskGroup with a
///    5-parallel ceiling, so one slow project doesn't block the
///    others. Soft-fail per project — a network or decode error on
///    one Vercel call collapses to "unknown" for that row instead of
///    sinking the whole snapshot.
///
///  - `reduce(bundles:now:)` is the pure reducer that turns a sequence
///    of `ProjectHealthBundle` slots into the aggregate fields. Tested
///    in isolation to lock the counting logic without touching the
///    network.
public actor PortfolioHealthAggregator {
    public static let shared = PortfolioHealthAggregator()

    /// Maximum number of in-flight project fetches. Keeps us under the
    /// Vercel free-tier rate ceiling for the typical 5-10 project
    /// portfolio Mehdi runs.
    public static let parallelism = 5

    /// 24 hours, the threshold used to count `ERROR` deployments as
    /// "recent" for the KPI bar.
    public static let errorWindow: TimeInterval = 24 * 60 * 60

    public init() {}

    // MARK: - Public API

    /// Build a portfolio snapshot from the cached bundles. Doesn't
    /// hit the network — the caller is expected to refresh the cache
    /// separately if it wants fresh data (HomeView's pull-to-refresh
    /// + ProjectDetailSheet's `.task` both do this).
    public func snapshot(for projects: [ProjectIdentity]) async -> PortfolioHealth {
        let cache = ProjectHealthCache.shared
        var bundles: [ProjectHealthBundle?] = []
        bundles.reserveCapacity(projects.count)
        for project in projects {
            let bundle = await cache.bundle(for: project.id)
            bundles.append(bundle)
        }
        return Self.reduce(
            bundles: bundles,
            totalActiveProjects: projects.count,
            now: .now
        )
    }

    /// Pure reducer that turns the per-project bundle slots into the
    /// aggregate. Exposed for tests so the counting logic stays locked
    /// without going through `ProjectHealthCache`.
    public static func reduce(
        bundles: [ProjectHealthBundle?],
        totalActiveProjects: Int,
        now: Date = .now
    ) -> PortfolioHealth {
        var buildsInProgress = 0
        var buildErrors24h = 0
        var lighthouseSum = 0
        var lighthouseCount = 0

        for bundle in bundles {
            guard let bundle else { continue }
            if let deployment = bundle.latestDeployment {
                let state = deployment.state.uppercased()
                if state == "BUILDING" || state == "QUEUED" || state == "INITIALIZING" {
                    buildsInProgress += 1
                }
                if state == "ERROR" {
                    let age = now.timeIntervalSince(deployment.createdAt)
                    if age >= 0, age <= errorWindow {
                        buildErrors24h += 1
                    }
                }
            }
            if let lighthouse = bundle.lighthouse {
                lighthouseSum += lighthouse.performance
                lighthouseCount += 1
            }
        }

        let avg: Int? = lighthouseCount > 0
            ? Int((Double(lighthouseSum) / Double(lighthouseCount)).rounded())
            : nil

        return PortfolioHealth(
            totalActiveProjects: totalActiveProjects,
            buildsInProgress: buildsInProgress,
            buildErrors24h: buildErrors24h,
            avgLighthousePerf: avg,
            lastRefreshAt: now
        )
    }

    /// Fan-out fresh fetch — re-pulls the latest deployment for every
    /// project with a `vercelProjectID` + token, then rolls up. Used
    /// by HomeView's pull-to-refresh. Soft-fails per project; a
    /// failing project keeps its prior cached value.
    public func refreshAndSnapshot(for projects: [ProjectIdentity]) async -> PortfolioHealth {
        let cache = ProjectHealthCache.shared
        let hasToken = VercelTokenStore.read() != nil

        if hasToken {
            await withTaskGroup(of: Void.self) { group in
                let semaphore = ParallelGate(limit: Self.parallelism)
                for project in projects {
                    guard
                        let projectID = project.vercelProjectID,
                        !projectID.isEmpty
                    else { continue }
                    group.addTask {
                        await semaphore.acquire()
                        defer { Task { await semaphore.release() } }
                        do {
                            if let latest = try await VercelClient.shared.latest(projectID: projectID) {
                                await cache.update(project.id, keyPath: \.latestDeployment, value: latest)
                            }
                        } catch {
                            // Soft-fail per project — keep the cache slot.
                        }
                    }
                }
            }
        }

        return await snapshot(for: projects)
    }
}

/// Tiny semaphore-style gate to cap TaskGroup parallelism. We don't
/// pull in `AsyncSemaphore` from a third-party package — five-line
/// actor does the job.
actor ParallelGate {
    private let limit: Int
    private var inFlight: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if inFlight < limit {
            inFlight += 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
        inFlight += 1
    }

    func release() {
        inFlight -= 1
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
        }
    }
}
