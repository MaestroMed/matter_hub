import XCTest
@testable import ProjectHealthKit

/// v1.0-alpha.9 — Pure tests for `PortfolioHealthAggregator.reduce`.
/// The reducer is the load-bearing logic the HomeView KPI bar reads;
/// we lock its counting rules here without going through the actor +
/// the on-disk cache so the suite stays fast and deterministic.
final class PortfolioHealthAggregatorTests: XCTestCase {

    /// Empty input → every count is zero, `avgLighthousePerf` is nil
    /// because there's nothing to average.
    func test_reduce_emptyInput_yieldsZeroCounts() {
        let snapshot = PortfolioHealthAggregator.reduce(
            bundles: [],
            totalActiveProjects: 0,
            now: .now
        )
        XCTAssertEqual(snapshot.totalActiveProjects, 0)
        XCTAssertEqual(snapshot.buildsInProgress, 0)
        XCTAssertEqual(snapshot.buildErrors24h, 0)
        XCTAssertNil(snapshot.avgLighthousePerf)
    }

    /// Three projects all in READY state → no builds in progress, no
    /// errors. The total still reflects the count we passed in.
    func test_reduce_threeReadyProjects_zeroBuilds_zeroErrors() {
        let bundles: [ProjectHealthBundle?] = (0..<3).map { _ in
            ProjectHealthBundle(
                latestDeployment: VercelDeployment(
                    id: "dpl_ready",
                    url: "demo.vercel.app",
                    state: "READY",
                    createdAt: .now
                )
            )
        }
        let snapshot = PortfolioHealthAggregator.reduce(
            bundles: bundles,
            totalActiveProjects: 3,
            now: .now
        )
        XCTAssertEqual(snapshot.totalActiveProjects, 3)
        XCTAssertEqual(snapshot.buildsInProgress, 0)
        XCTAssertEqual(snapshot.buildErrors24h, 0)
    }

    /// 2 READY + 1 BUILDING → buildsInProgress reads 1.
    func test_reduce_twoReadyOneBuilding_oneBuildInProgress() {
        let bundles: [ProjectHealthBundle?] = [
            ProjectHealthBundle(latestDeployment: VercelDeployment(
                id: "dpl_a", url: "u", state: "READY", createdAt: .now)),
            ProjectHealthBundle(latestDeployment: VercelDeployment(
                id: "dpl_b", url: "u", state: "READY", createdAt: .now)),
            ProjectHealthBundle(latestDeployment: VercelDeployment(
                id: "dpl_c", url: "u", state: "BUILDING", createdAt: .now)),
        ]
        let snapshot = PortfolioHealthAggregator.reduce(
            bundles: bundles,
            totalActiveProjects: 3,
            now: .now
        )
        XCTAssertEqual(snapshot.buildsInProgress, 1)
        XCTAssertEqual(snapshot.buildErrors24h, 0)
    }

    /// 1 ERROR that landed inside the 24h window → buildErrors24h
    /// reads 1.
    func test_reduce_errorWithin24h_countsAsRecent() {
        let now = Date(timeIntervalSince1970: 1_716_000_000)
        let bundles: [ProjectHealthBundle?] = [
            ProjectHealthBundle(latestDeployment: VercelDeployment(
                id: "dpl_err",
                url: "u",
                state: "ERROR",
                // 6 hours ago.
                createdAt: now.addingTimeInterval(-6 * 60 * 60)
            )),
        ]
        let snapshot = PortfolioHealthAggregator.reduce(
            bundles: bundles,
            totalActiveProjects: 1,
            now: now
        )
        XCTAssertEqual(snapshot.buildErrors24h, 1)
    }

    /// 1 ERROR that landed > 24h ago → buildErrors24h reads 0. The
    /// boundary check uses the 24h `errorWindow` constant; locking
    /// the behaviour ensures a refactor that drops the window check
    /// won't silently inflate the "errors today" KPI.
    func test_reduce_errorOlderThan24h_doesNotCount() {
        let now = Date(timeIntervalSince1970: 1_716_000_000)
        let bundles: [ProjectHealthBundle?] = [
            ProjectHealthBundle(latestDeployment: VercelDeployment(
                id: "dpl_old",
                url: "u",
                state: "ERROR",
                // 48 hours ago — well outside the 24h window.
                createdAt: now.addingTimeInterval(-48 * 60 * 60)
            )),
        ]
        let snapshot = PortfolioHealthAggregator.reduce(
            bundles: bundles,
            totalActiveProjects: 1,
            now: now
        )
        XCTAssertEqual(snapshot.buildErrors24h, 0)
    }

    /// `avgLighthousePerf` is the integer-rounded mean of the
    /// performance scores across projects that have a cached
    /// `LighthouseScore`. Projects without one are skipped — the
    /// average isn't dragged down by a nil slot.
    func test_reduce_avgLighthousePerf_isMeanAcrossCachedProjects() {
        let bundles: [ProjectHealthBundle?] = [
            ProjectHealthBundle(lighthouse: LighthouseScore(
                performance: 90, accessibility: 100, bestPractices: 100, seo: 100,
                lcpSeconds: 0, inpMs: 0, cls: 0,
                fetchedAt: .now
            )),
            ProjectHealthBundle(lighthouse: LighthouseScore(
                performance: 70, accessibility: 100, bestPractices: 100, seo: 100,
                lcpSeconds: 0, inpMs: 0, cls: 0,
                fetchedAt: .now
            )),
            // This bundle has no lighthouse — must be excluded.
            ProjectHealthBundle(),
        ]
        let snapshot = PortfolioHealthAggregator.reduce(
            bundles: bundles,
            totalActiveProjects: 3,
            now: .now
        )
        // (90 + 70) / 2 = 80.
        XCTAssertEqual(snapshot.avgLighthousePerf, 80)
    }
}
