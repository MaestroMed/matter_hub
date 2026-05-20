import XCTest
@testable import GraphCore

/// v1.0-alpha.13 — Locks the dormant-project heuristic. The
/// HomeView card rendering itself is verified by the vision-verify
/// screenshot; the math + branch picks are covered here.
final class ProjectLifecycleHeuristicTests: XCTestCase {

    // MARK: - Fixtures

    @MainActor
    private func makeProject(
        name: String = "Acme",
        host: String = "acme.com",
        lifecycle: ProjectLifecycleStage = .active,
        lastActivityDaysAgo: Int,
        githubRepo: String? = nil
    ) -> Project {
        let calendar = Calendar(identifier: .gregorian)
        let lastActivityAt = calendar.date(
            byAdding: .day,
            value: -lastActivityDaysAgo,
            to: .now
        ) ?? .now
        let project = Project(
            name: name,
            host: host,
            githubRepo: githubRepo,
            lifecycleStage: lifecycle,
            startedAt: lastActivityAt
        )
        project.lastActivityAt = lastActivityAt
        return project
    }

    // MARK: - Dormant detection

    @MainActor
    func test_dormantProjects_emptyInput_returnsEmpty() {
        let dormant = ProjectLifecycleHeuristic.dormantProjects([])
        XCTAssertEqual(dormant, [])
    }

    @MainActor
    func test_dormantProjects_freshProject_isNotDormant() {
        let project = makeProject(lastActivityDaysAgo: 10)
        let dormant = ProjectLifecycleHeuristic.dormantProjects([project])
        XCTAssertTrue(dormant.isEmpty,
                      "A project active in the last 90 days must NOT be dormant")
    }

    @MainActor
    func test_dormantProjects_oldProjectWithNoGithub_isDormant() {
        let project = makeProject(lastActivityDaysAgo: 120)
        let dormant = ProjectLifecycleHeuristic.dormantProjects([project])
        XCTAssertEqual(dormant.count, 1)
        XCTAssertEqual(dormant.first?.id, project.id)
    }

    @MainActor
    func test_dormantProjects_recentGitHubPushKeepsItActive() {
        let project = makeProject(
            lastActivityDaysAgo: 200,
            githubRepo: "MaestroMed/Acme_v0"
        )
        let recentPush = Date.now.addingTimeInterval(-86_400 * 5) // 5 days ago
        let dormant = ProjectLifecycleHeuristic.dormantProjects(
            [project],
            lastPushByRepo: ["MaestroMed/Acme_v0": recentPush]
        )
        XCTAssertTrue(dormant.isEmpty,
                      "A recent GitHub push must keep the project active even when lastActivityAt is stale")
    }

    @MainActor
    func test_dormantProjects_archivedExcluded() {
        let project = makeProject(
            lifecycle: .archived,
            lastActivityDaysAgo: 999
        )
        let dormant = ProjectLifecycleHeuristic.dormantProjects([project])
        XCTAssertTrue(dormant.isEmpty,
                      "Archived projects must never appear in the dormant list")
    }

    @MainActor
    func test_dormantProjects_orderedLongestDormantFirst() {
        let staler  = makeProject(name: "Older",  lastActivityDaysAgo: 300)
        let stale   = makeProject(name: "Old",    lastActivityDaysAgo: 200)
        let stalest = makeProject(name: "Oldest", lastActivityDaysAgo: 500)
        let dormant = ProjectLifecycleHeuristic.dormantProjects([staler, stale, stalest])
        XCTAssertEqual(dormant.map(\.name), ["Oldest", "Older", "Old"],
                       "Dormant list must be ordered longest-dormant-first")
    }

    @MainActor
    func test_reason_picksGitHubPushBranchWhenFreshest() {
        let project = makeProject(lastActivityDaysAgo: 300)
        let lastPush = Date.now.addingTimeInterval(-86_400 * 30) // 30 days ago
        let reason = ProjectLifecycleHeuristic.reason(
            for: project,
            lastPush: lastPush
        )
        // The reason picks the YOUNGEST signal — push is younger
        // than activity, so the localized FR/EN string must mention
        // the day count for push.
        XCTAssertTrue(
            reason.contains("30"),
            "Reason must reflect 30-day count: \(reason)"
        )
    }

    @MainActor
    func test_dormantProjects_tighterThresholdSelectsMore() {
        let project = makeProject(lastActivityDaysAgo: 45)
        // With default 90-day threshold, NOT dormant.
        let defaultDormant = ProjectLifecycleHeuristic.dormantProjects([project])
        XCTAssertTrue(defaultDormant.isEmpty)
        // With tighter 30-day threshold, IS dormant.
        let tightDormant = ProjectLifecycleHeuristic.dormantProjects(
            [project],
            thresholdDays: 30
        )
        XCTAssertEqual(tightDormant.count, 1)
    }
}
