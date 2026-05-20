import XCTest
@testable import ProjectHealthKit

/// v1.0-alpha.8 — Locks the on-disk + in-memory contract of
/// `ProjectHealthCache`. Same shape as `HealthPulseStoreTests` —
/// each test instantiates a fresh cache rooted at a temp directory
/// so the singleton never gets polluted by the test runner.
final class ProjectHealthCacheTests: XCTestCase {

    private func makeCache() -> (ProjectHealthCache, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-health-test-\(UUID().uuidString)", isDirectory: true)
        return (ProjectHealthCache(rootURL: root), root)
    }

    /// A bundle that was just saved must round-trip on the next read.
    func test_save_thenBundle_roundTripsValues() async {
        let (cache, _) = makeCache()
        let projectID = UUID()
        let bundle = ProjectHealthBundle(
            latestDeployment: VercelDeployment(
                id: "dpl_1",
                url: "demo.vercel.app",
                state: "READY",
                createdAt: Date(timeIntervalSince1970: 1_716_000_000)
            ),
            recentCommits: [
                GitHubCommit(
                    sha: "abc", message: "init", authorName: "n",
                    authorEmail: "e", committedAt: Date(timeIntervalSince1970: 1_716_000_000),
                    url: "u"
                )
            ]
        )
        await cache.save(bundle, for: projectID)

        let loaded = await cache.bundle(for: projectID)
        XCTAssertEqual(loaded?.latestDeployment?.id, "dpl_1")
        XCTAssertEqual(loaded?.recentCommits.count, 1)
        XCTAssertEqual(loaded?.recentCommits.first?.sha, "abc")
    }

    /// `isFresh` reads true inside the TTL window, false past it.
    /// Locks the 5-minute TTL contract.
    func test_isFresh_inWindowReadsTrue_pastWindowReadsFalse() async {
        let (cache, _) = makeCache()
        let projectID = UUID()
        let bundle = ProjectHealthBundle()
        await cache.save(bundle, for: projectID)

        let nowFresh = await cache.isFresh(projectID, now: .now)
        XCTAssertTrue(nowFresh, "Just-saved bundle must be fresh.")

        // 6 minutes from now is past the 5-minute TTL.
        let later = Date(timeIntervalSinceNow: 6 * 60)
        let stale = await cache.isFresh(projectID, now: later)
        XCTAssertFalse(stale, "Bundle 6 min old must read stale.")
    }

    /// An empty bundle for an unknown project reads as nil.
    func test_bundleForUnknownProject_isNil() async {
        let (cache, _) = makeCache()
        let loaded: ProjectHealthBundle? = await cache.bundle(for: UUID())
        XCTAssertNil(loaded)
    }

    /// `update(_:keyPath:value:)` mutates one slot without dropping
    /// the others — the fan-out fetcher in ProjectDetailSheet relies
    /// on this invariant when Vercel + GitHub land at different times.
    func test_update_mutatesOneSlot_preservesOthers() async {
        let (cache, _) = makeCache()
        let projectID = UUID()
        let initial = ProjectHealthBundle(
            recentCommits: [
                GitHubCommit(
                    sha: "abc", message: "m", authorName: "n",
                    authorEmail: "e", committedAt: Date(timeIntervalSince1970: 1_716_000_000),
                    url: "u"
                )
            ]
        )
        await cache.save(initial, for: projectID)

        let deployment = VercelDeployment(
            id: "dpl_new",
            url: "u",
            state: "BUILDING",
            createdAt: Date(timeIntervalSince1970: 1_716_100_000)
        )
        await cache.update(projectID, keyPath: \.latestDeployment, value: deployment)

        let loaded = await cache.bundle(for: projectID)
        XCTAssertEqual(loaded?.latestDeployment?.id, "dpl_new")
        XCTAssertEqual(loaded?.recentCommits.count, 1,
                       "Existing slots must survive a partial update.")
    }

    /// `clearAll()` wipes memory + disk. Re-instantiating a fresh
    /// cache over the same root yields nothing.
    func test_clearAll_wipesEverything() async {
        let (cache, root) = makeCache()
        let id = UUID()
        await cache.save(ProjectHealthBundle(), for: id)
        await cache.clearAll()

        let postClear = await cache.bundle(for: id)
        XCTAssertNil(postClear)

        // Fresh instance over the same root → still empty.
        let fresh = ProjectHealthCache(rootURL: root)
        let freshLoad = await fresh.bundle(for: id)
        XCTAssertNil(freshLoad)
    }
}
