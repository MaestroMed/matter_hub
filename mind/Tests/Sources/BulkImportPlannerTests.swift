import XCTest
@testable import BootstrapKit
@testable import ProjectHealthKit

/// v1.0-alpha.11 — Locks the bucketing logic in `BulkImportPlanner`.
/// Pure inputs in, pure plan out — no GitHubClient, no SwiftData, no
/// clock. Every test pins one branch of the framework / confidence /
/// dedup decision tree.
final class BulkImportPlannerTests: XCTestCase {

    private func summary(
        fullName: String,
        stars: Int = 0,
        homepage: String? = nil
    ) -> GitHubRepoSummary {
        let name = String(fullName.split(separator: "/").last ?? "")
        return GitHubRepoSummary(
            fullName: fullName,
            name: name,
            description: nil,
            isPrivate: false,
            defaultBranch: "main",
            pushedAt: Date(timeIntervalSince1970: 0),
            homepageURL: homepage,
            stars: stars,
            topics: []
        )
    }

    private func detection(
        framework: String,
        confidence: Double
    ) -> RepoStackDetection {
        RepoStackDetection(
            framework: framework,
            version: nil,
            confidence: confidence,
            signals: []
        )
    }

    // MARK: - Empty / boundary

    func test_plan_emptyInput_returnsEmptyPlan() {
        let plan = BulkImportPlanner.plan(repos: [], detections: [:])
        XCTAssertTrue(plan.recommendedImports.isEmpty)
        XCTAssertTrue(plan.skippedRepos.isEmpty)
        XCTAssertEqual(plan.acceptedCount, 0)
    }

    /// Boundary at 0.5: inclusive in the recommended bucket.
    func test_plan_confidence0_5_isRecommended() {
        let repo = summary(fullName: "MaestroMed/Edge")
        let det = detection(framework: "nextjs", confidence: 0.5)
        let plan = BulkImportPlanner.plan(repos: [repo], detections: [repo.fullName: det])
        XCTAssertEqual(plan.recommendedImports.count, 1)
        XCTAssertTrue(plan.skippedRepos.isEmpty)
    }

    /// Just below the boundary: skipped.
    func test_plan_confidenceBelow0_5_isSkipped() {
        let repo = summary(fullName: "MaestroMed/Edge")
        let det = detection(framework: "nextjs", confidence: 0.49)
        let plan = BulkImportPlanner.plan(repos: [repo], detections: [repo.fullName: det])
        XCTAssertTrue(plan.recommendedImports.isEmpty)
        XCTAssertEqual(plan.skippedRepos.count, 1)
    }

    // MARK: - Recommended bucket

    func test_plan_allNextjsHighConfidence_allRecommended() {
        let repos = [
            summary(fullName: "MaestroMed/A"),
            summary(fullName: "MaestroMed/B"),
            summary(fullName: "MaestroMed/C"),
        ]
        let det = detection(framework: "nextjs", confidence: 0.9)
        let detections = Dictionary(uniqueKeysWithValues: repos.map { ($0.fullName, det) })
        let plan = BulkImportPlanner.plan(repos: repos, detections: detections)
        XCTAssertEqual(plan.recommendedImports.count, 3)
        XCTAssertTrue(plan.skippedRepos.isEmpty)
        XCTAssertTrue(plan.recommendedImports.allSatisfy(\.accepted),
                      "Default-accepted should be true for every recommended row.")
    }

    func test_plan_wordpressAndStatic_areRecommended() {
        let wp = summary(fullName: "MaestroMed/WP")
        let st = summary(fullName: "MaestroMed/Docs")
        let detections = [
            wp.fullName: detection(framework: "wordpress", confidence: 0.9),
            st.fullName: detection(framework: "static", confidence: 0.8),
        ]
        let plan = BulkImportPlanner.plan(repos: [wp, st], detections: detections)
        XCTAssertEqual(plan.recommendedImports.count, 2)
        XCTAssertTrue(plan.skippedRepos.isEmpty)
    }

    // MARK: - Skipped bucket

    func test_plan_otherFramework_isSkipped() {
        let repo = summary(fullName: "MaestroMed/Mystery")
        let det = detection(framework: "other", confidence: 0.3)
        let plan = BulkImportPlanner.plan(repos: [repo], detections: [repo.fullName: det])
        XCTAssertTrue(plan.recommendedImports.isEmpty)
        XCTAssertEqual(plan.skippedRepos.count, 1)
    }

    /// Skip reason includes the framework name + confidence number.
    func test_plan_skippedRepo_reasonIncludesFrameworkAndConfidence() {
        let repo = summary(fullName: "MaestroMed/Mystery")
        let det = detection(framework: "other", confidence: 0.32)
        let plan = BulkImportPlanner.plan(repos: [repo], detections: [repo.fullName: det])
        let reason = plan.skippedRepos.first?.reason ?? ""
        XCTAssertTrue(reason.contains("other"),
                      "Reason '\(reason)' should mention the framework name.")
        XCTAssertTrue(reason.contains("0.32"),
                      "Reason '\(reason)' should mention the confidence value.")
    }

    // MARK: - Ordering / determinism / dedup

    /// Recommended rows order by stars descending — most-popular repos
    /// float to the top of the wizard's review step.
    func test_plan_recommendedOrderedByStarsDesc() {
        let low = summary(fullName: "MaestroMed/Low", stars: 1)
        let high = summary(fullName: "MaestroMed/High", stars: 10)
        let med = summary(fullName: "MaestroMed/Med", stars: 5)
        let det = detection(framework: "nextjs", confidence: 0.9)
        let detections = [low.fullName: det, high.fullName: det, med.fullName: det]
        let plan = BulkImportPlanner.plan(repos: [low, high, med], detections: detections)
        XCTAssertEqual(plan.recommendedImports.map(\.metadata.summary.fullName), [
            "MaestroMed/High",
            "MaestroMed/Med",
            "MaestroMed/Low",
        ])
    }

    /// Same input → same plan. Drives idempotent UI refresh + lets the
    /// review step compare-and-reapply state safely.
    func test_plan_isDeterministic() {
        let repos = [
            summary(fullName: "MaestroMed/A", stars: 3),
            summary(fullName: "MaestroMed/B", stars: 7),
        ]
        let det = detection(framework: "nextjs", confidence: 0.9)
        let detections = [repos[0].fullName: det, repos[1].fullName: det]
        let first = BulkImportPlanner.plan(repos: repos, detections: detections)
        let second = BulkImportPlanner.plan(repos: repos, detections: detections)
        XCTAssertEqual(
            first.recommendedImports.map(\.metadata.summary.fullName),
            second.recommendedImports.map(\.metadata.summary.fullName)
        )
    }

    /// Mix of frameworks: each row lands in its bucket.
    func test_plan_mixedFrameworks_correctlyBucketed() {
        let next = summary(fullName: "MaestroMed/Next")
        let wp = summary(fullName: "MaestroMed/WP")
        let mystery = summary(fullName: "MaestroMed/Mystery")
        let detections = [
            next.fullName: detection(framework: "nextjs", confidence: 0.9),
            wp.fullName: detection(framework: "wordpress", confidence: 0.9),
            mystery.fullName: detection(framework: "other", confidence: 0.3),
        ]
        let plan = BulkImportPlanner.plan(repos: [next, wp, mystery], detections: detections)
        XCTAssertEqual(plan.recommendedImports.count, 2)
        XCTAssertEqual(plan.skippedRepos.count, 1)
    }

    /// Duplicate input fullNames collapse to one row (first wins).
    func test_plan_duplicateFullName_collapsesToFirst() {
        let dup = summary(fullName: "MaestroMed/Dup")
        let det = detection(framework: "nextjs", confidence: 0.9)
        let plan = BulkImportPlanner.plan(
            repos: [dup, dup, dup],
            detections: [dup.fullName: det]
        )
        XCTAssertEqual(plan.recommendedImports.count, 1)
        XCTAssertTrue(plan.skippedRepos.isEmpty)
    }
}
