import XCTest
@testable import AuditKit

/// v1.0-alpha.10 — Codable round-trip + defaults for the new
/// `RepositoryAuditFindings` value type and its nested signal shapes.
/// Pure tests — no I/O — pulled into a dedicated file so the schema
/// stays locked against accidental drift between the AuditSheet UI,
/// the portal HTML, and any future Notion / Linear sync writer that
/// consumes these signals.
final class RepositoryAuditFindingsTests: XCTestCase {

    /// Defaults: every field is optional or zero except `analyzedAt`
    /// (which the initializer fills with `.now`) so a probe that
    /// soft-failed every signal still produces a valid Codable
    /// payload.
    func test_defaults_areAllNilOrZero() {
        let findings = RepositoryAuditFindings()
        XCTAssertNil(findings.packageManager)
        XCTAssertNil(findings.framework)
        XCTAssertFalse(findings.typescriptStrict)
        XCTAssertEqual(findings.totalDependencies, 0)
        XCTAssertEqual(findings.outdatedDependencies, [])
        XCTAssertEqual(findings.securitySignals, [])
        XCTAssertEqual(findings.ciSignals, CISignals())
        XCTAssertEqual(findings.testCoverage, TestCoverageSignals())
        XCTAssertEqual(findings.bundleSignals, BundleSignals())
        XCTAssertEqual(findings.overallGrade, "F")
        XCTAssertEqual(findings.summary, "")
    }

    /// Codable round-trip with every optional field nil. Locks the
    /// shape so a payload archived before the next field gets added
    /// keeps decoding cleanly.
    func test_codableRoundTrip_allOptionalsNil() throws {
        let original = RepositoryAuditFindings(
            analyzedAt: Date(timeIntervalSince1970: 1_716_500_000),
            packageManager: nil,
            framework: nil,
            typescriptStrict: false,
            totalDependencies: 0,
            outdatedDependencies: [],
            securitySignals: [],
            ciSignals: CISignals(),
            testCoverage: TestCoverageSignals(),
            bundleSignals: BundleSignals(),
            overallGrade: "F",
            summary: ""
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RepositoryAuditFindings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// Codable round-trip with every field populated. Catches an
    /// accidental key rename / lost field on the decode path.
    func test_codableRoundTrip_allFieldsPopulated() throws {
        let original = RepositoryAuditFindings(
            analyzedAt: Date(timeIntervalSince1970: 1_716_600_000),
            packageManager: "pnpm",
            framework: "next@15.0.3",
            typescriptStrict: true,
            totalDependencies: 42,
            outdatedDependencies: [
                OutdatedDependency(
                    name: "react",
                    installed: "^17.0.2",
                    latest: "18.3.1",
                    majorBehind: 1
                ),
            ],
            securitySignals: [
                SecuritySignal(
                    kind: "env-in-repo",
                    severity: "high",
                    detail: "Fichier d'environnement committé",
                    filePath: ".env.local"
                ),
            ],
            ciSignals: CISignals(
                hasWorkflows: true,
                workflowCount: 3,
                hasTestWorkflow: true,
                hasDeployWorkflow: true
            ),
            testCoverage: TestCoverageSignals(
                hasTestDirectory: true,
                testFiles: 17,
                testFramework: "vitest"
            ),
            bundleSignals: BundleSignals(
                heavyDependencies: ["moment", "lodash"],
                estimatedKB: 612
            ),
            overallGrade: "B",
            summary: "- next@15.0.3 · pnpm · TypeScript strict\n- 42 dépendances, 1 en retard dont 1 majeur(s)\n- tests présents (vitest) · CI active (3 workflows) · aucun signal de sécurité haut"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RepositoryAuditFindings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// `OutdatedDependency` Equatable + Codable lock.
    func test_outdatedDependency_codable() throws {
        let dep = OutdatedDependency(
            name: "@stripe/stripe-js",
            installed: "1.54.0",
            latest: "3.6.0",
            majorBehind: 2
        )
        let data = try JSONEncoder().encode(dep)
        let decoded = try JSONDecoder().decode(OutdatedDependency.self, from: data)
        XCTAssertEqual(decoded, dep)
        XCTAssertEqual(decoded.majorBehind, 2)
    }

    /// `SecuritySignal` filePath is optional and round-trips.
    func test_securitySignal_filePathOptional() throws {
        let signal = SecuritySignal(
            kind: "missing-package-lock",
            severity: "low",
            detail: "Aucun fichier de verrouillage détecté.",
            filePath: nil
        )
        let data = try JSONEncoder().encode(signal)
        let decoded = try JSONDecoder().decode(SecuritySignal.self, from: data)
        XCTAssertEqual(decoded, signal)
        XCTAssertNil(decoded.filePath)
    }

    /// `AuditReport` should backwards-compatibly decode a payload
    /// without the new `repoFindings` key (legacy audits).
    func test_auditReport_decodesWithoutRepoFindings() throws {
        let client = AuditClient(
            url: URL(string: "https://example.com")!,
            name: "Example"
        )
        let legacyJSON = """
        {
            "client": \(String(data: try JSONEncoder().encode(client), encoding: .utf8) ?? "{}"),
            "generatedAt": \(Date(timeIntervalSince1970: 1_716_700_000).timeIntervalSinceReferenceDate),
            "persona": "saasB2B",
            "scoring": {"overall": 80, "performance": 80, "seo": 80, "security": 80, "brand": 80, "mobile": 80},
            "synthesis": "x",
            "quickWins": [],
            "strategicBets": [],
            "pitch": "p"
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let report = try JSONDecoder().decode(AuditReport.self, from: data)
        XCTAssertNil(report.repoFindings)
        XCTAssertEqual(report.mockups, [])
        XCTAssertEqual(report.hiddenRisks, [])
    }
}
