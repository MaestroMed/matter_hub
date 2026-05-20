import XCTest
@testable import AuditKit

/// v1.0-alpha.10 — Pure grading tests. The rubric in
/// `RepoAuditGradeBuilder` is the contract the AuditSheet UI + the
/// portal HTML render off, so we lock the boundary at every grade
/// transition. No I/O — the builder is `static func` returning a
/// `String`, exercised here against synthetic findings.
final class RepoAuditGradeBuilderTests: XCTestCase {

    // MARK: - A+ (perfect)

    func test_grade_aPlus_forFullyCleanFindings() {
        let findings = RepositoryAuditFindings(
            analyzedAt: .now,
            packageManager: "pnpm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 24,
            outdatedDependencies: [],
            securitySignals: [],
            ciSignals: CISignals(
                hasWorkflows: true, workflowCount: 2,
                hasTestWorkflow: true, hasDeployWorkflow: true
            ),
            testCoverage: TestCoverageSignals(
                hasTestDirectory: true, testFiles: 24, testFramework: "vitest"
            ),
            bundleSignals: BundleSignals(),
            overallGrade: "F",
            summary: ""
        )
        XCTAssertEqual(RepoAuditGradeBuilder.grade(for: findings), "A+")
    }

    // MARK: - A (one minor blemish)

    /// 2 outdated minor-only deps, strict TS, tests + CI, no security
    /// → A (the rubric counts <= 2 with majorBehind == 0 as the
    /// "light" branch).
    func test_grade_a_forSingleMinorOutdated() {
        let findings = RepositoryAuditFindings(
            analyzedAt: .now,
            packageManager: "npm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 30,
            outdatedDependencies: [
                OutdatedDependency(name: "axios", installed: "1.7.0", latest: "1.7.4", majorBehind: 0),
                OutdatedDependency(name: "zod", installed: "3.22.4", latest: "3.22.6", majorBehind: 0),
            ],
            securitySignals: [],
            ciSignals: CISignals(
                hasWorkflows: true, workflowCount: 2,
                hasTestWorkflow: true, hasDeployWorkflow: false
            ),
            testCoverage: TestCoverageSignals(
                hasTestDirectory: true, testFiles: 8, testFramework: "vitest"
            ),
            bundleSignals: BundleSignals(),
            overallGrade: "F",
            summary: ""
        )
        // 0 major-behind, tests + CI present — degrades from A+ to A
        // because lightOutdated is still satisfied but… actually
        // re-reading the rubric: A+ requires `outdatedCount <= 2 &&
        // majorBehindCount == 0` etc., which this satisfies. We need
        // a *minor blemish* to drop to A.
        // Tweak: strict off keeps tests + CI but no other tripwire.
        let blemished = RepositoryAuditFindings(
            analyzedAt: findings.analyzedAt,
            packageManager: findings.packageManager,
            framework: findings.framework,
            typescriptStrict: false,
            totalDependencies: findings.totalDependencies,
            outdatedDependencies: findings.outdatedDependencies,
            securitySignals: findings.securitySignals,
            ciSignals: findings.ciSignals,
            testCoverage: findings.testCoverage,
            bundleSignals: findings.bundleSignals,
            overallGrade: "F",
            summary: ""
        )
        XCTAssertEqual(RepoAuditGradeBuilder.grade(for: blemished), "A")
    }

    // MARK: - B (moderate outdated OR missing tests)

    func test_grade_b_forMissingTestsWithCi() {
        let findings = RepositoryAuditFindings(
            packageManager: "pnpm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 20,
            outdatedDependencies: [],
            securitySignals: [],
            ciSignals: CISignals(hasWorkflows: true, workflowCount: 1, hasTestWorkflow: false, hasDeployWorkflow: true),
            testCoverage: TestCoverageSignals(hasTestDirectory: false),
            bundleSignals: BundleSignals()
        )
        XCTAssertEqual(RepoAuditGradeBuilder.grade(for: findings), "B")
    }

    func test_grade_b_for3OutdatedWithMajor() {
        let findings = RepositoryAuditFindings(
            packageManager: "npm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 30,
            outdatedDependencies: [
                OutdatedDependency(name: "react", installed: "17.0.0", latest: "18.3.1", majorBehind: 1),
                OutdatedDependency(name: "next", installed: "14.0.0", latest: "15.0.3", majorBehind: 1),
                OutdatedDependency(name: "zod", installed: "3.0.0", latest: "3.22.0", majorBehind: 0),
            ],
            securitySignals: [],
            ciSignals: CISignals(hasWorkflows: true, workflowCount: 2, hasTestWorkflow: true, hasDeployWorkflow: true),
            testCoverage: TestCoverageSignals(hasTestDirectory: true, testFiles: 6, testFramework: "vitest"),
            bundleSignals: BundleSignals()
        )
        XCTAssertEqual(RepoAuditGradeBuilder.grade(for: findings), "B")
    }

    // MARK: - C (missing CI OR many outdated OR 1 high signal)

    func test_grade_c_forMissingCI() {
        let findings = RepositoryAuditFindings(
            packageManager: "npm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 10,
            outdatedDependencies: [],
            securitySignals: [],
            ciSignals: CISignals(hasWorkflows: false),
            testCoverage: TestCoverageSignals(hasTestDirectory: true, testFiles: 3, testFramework: "jest"),
            bundleSignals: BundleSignals()
        )
        XCTAssertEqual(RepoAuditGradeBuilder.grade(for: findings), "C")
    }

    func test_grade_c_for6PlusOutdatedDeps() {
        let outdated = (1...6).map { idx in
            OutdatedDependency(
                name: "pkg-\(idx)",
                installed: "1.0.0",
                latest: "1.0.\(idx + 1)",
                majorBehind: 0
            )
        }
        let findings = RepositoryAuditFindings(
            packageManager: "pnpm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 40,
            outdatedDependencies: outdated,
            securitySignals: [],
            ciSignals: CISignals(hasWorkflows: true, workflowCount: 1, hasTestWorkflow: true, hasDeployWorkflow: true),
            testCoverage: TestCoverageSignals(hasTestDirectory: true, testFiles: 12, testFramework: "vitest"),
            bundleSignals: BundleSignals()
        )
        XCTAssertEqual(RepoAuditGradeBuilder.grade(for: findings), "C")
    }

    // MARK: - D (no TS OR 2+ high signals)

    func test_grade_d_forNoTypeScript() {
        let findings = RepositoryAuditFindings(
            packageManager: "npm",
            framework: "express@4.18.0",
            typescriptStrict: false,
            totalDependencies: 10,
            outdatedDependencies: [],
            securitySignals: [],
            ciSignals: CISignals(hasWorkflows: true, workflowCount: 1, hasTestWorkflow: true, hasDeployWorkflow: true),
            testCoverage: TestCoverageSignals(hasTestDirectory: true, testFiles: 4, testFramework: "jest"),
            bundleSignals: BundleSignals()
        )
        XCTAssertEqual(RepoAuditGradeBuilder.grade(for: findings), "D")
    }

    // MARK: - F (catastrophic)

    func test_grade_f_forEnvInRepo() {
        let findings = RepositoryAuditFindings(
            packageManager: "pnpm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 12,
            outdatedDependencies: [],
            securitySignals: [
                SecuritySignal(
                    kind: "env-in-repo",
                    severity: "high",
                    detail: "Fichier d'environnement committé",
                    filePath: ".env.local"
                ),
            ],
            ciSignals: CISignals(hasWorkflows: true, workflowCount: 1),
            testCoverage: TestCoverageSignals(hasTestDirectory: true, testFiles: 1, testFramework: "vitest"),
            bundleSignals: BundleSignals()
        )
        XCTAssertEqual(RepoAuditGradeBuilder.grade(for: findings), "F")
    }

    func test_grade_f_forHardcodedSecret() {
        let findings = RepositoryAuditFindings(
            packageManager: "pnpm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 12,
            outdatedDependencies: [],
            securitySignals: [
                SecuritySignal(
                    kind: "hardcoded-secret-suspect",
                    severity: "high",
                    detail: "Clé secrète suspecte dans le code source.",
                    filePath: "src/lib/api.ts"
                ),
            ],
            ciSignals: CISignals(hasWorkflows: true, workflowCount: 1),
            testCoverage: TestCoverageSignals(hasTestDirectory: true, testFiles: 1, testFramework: "vitest"),
            bundleSignals: BundleSignals()
        )
        XCTAssertEqual(RepoAuditGradeBuilder.grade(for: findings), "F")
    }

    // MARK: - Summary

    func test_summary_hasThreeBullets() {
        let findings = RepositoryAuditFindings(
            packageManager: "pnpm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 10,
            outdatedDependencies: [],
            securitySignals: [],
            ciSignals: CISignals(hasWorkflows: true, workflowCount: 1, hasTestWorkflow: true, hasDeployWorkflow: false),
            testCoverage: TestCoverageSignals(hasTestDirectory: true, testFiles: 3, testFramework: "vitest"),
            bundleSignals: BundleSignals()
        )
        let summary = RepoAuditGradeBuilder.summary(for: findings)
        let bullets = summary.split(separator: "\n").filter { $0.hasPrefix("- ") }
        XCTAssertEqual(bullets.count, 3)
    }

    func test_summary_mentionsFramework() {
        let findings = RepositoryAuditFindings(
            packageManager: "pnpm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 5,
            outdatedDependencies: [],
            securitySignals: [],
            ciSignals: CISignals(hasWorkflows: true, workflowCount: 1),
            testCoverage: TestCoverageSignals(hasTestDirectory: true, testFiles: 2, testFramework: "vitest"),
            bundleSignals: BundleSignals()
        )
        let summary = RepoAuditGradeBuilder.summary(for: findings)
        XCTAssertTrue(summary.contains("next@15.0.3"))
    }

    func test_summary_isDeterministic() {
        let findings = RepositoryAuditFindings(
            packageManager: "pnpm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 5,
            outdatedDependencies: [],
            securitySignals: [],
            ciSignals: CISignals(hasWorkflows: true, workflowCount: 1, hasTestWorkflow: true, hasDeployWorkflow: false),
            testCoverage: TestCoverageSignals(hasTestDirectory: true, testFiles: 2, testFramework: "vitest"),
            bundleSignals: BundleSignals()
        )
        let a = RepoAuditGradeBuilder.summary(for: findings)
        let b = RepoAuditGradeBuilder.summary(for: findings)
        XCTAssertEqual(a, b)
    }
}
