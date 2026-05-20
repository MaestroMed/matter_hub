import XCTest
@testable import AuditKit
@testable import ProjectHealthKit

/// v1.0-alpha.10 — Pure parser tests for the
/// `RepositoryAuditProbe`. The actor's full network round-trip is
/// exercised live; here we lock the static helpers so a malformed
/// `package.json` / `tsconfig.json` / tree listing degrades
/// gracefully rather than crashing the audit run.
final class RepositoryAuditProbeTests: XCTestCase {

    /// Extracts framework + package manager + deps from a realistic
    /// Next.js / pnpm payload.
    func test_parsePackageJSON_inferredFrameworkAndPackageManager() {
        let json = """
        {
            "name": "az-construction-v0",
            "packageManager": "pnpm@9.10.0",
            "engines": { "node": ">=20.0.0" },
            "dependencies": {
                "next": "^15.0.3",
                "react": "^18.3.1",
                "react-dom": "^18.3.1",
                "tailwindcss": "^3.4.0"
            },
            "devDependencies": {
                "vitest": "^1.6.0",
                "typescript": "^5.5.0"
            }
        }
        """
        let info = RepositoryAuditProbe.parsePackageJSON(json)
        XCTAssertEqual(info.framework, "next@15.0.3")
        XCTAssertEqual(info.packageManager, "pnpm")
        XCTAssertEqual(info.nodeEngine, ">=20.0.0")
        XCTAssertEqual(info.totalDependencyCount, 6)
        XCTAssertTrue(info.dependencies.contains(where: { $0.name == "next" }))
        XCTAssertTrue(info.devDependencies.contains(where: { $0.name == "vitest" }))
    }

    /// Empty / malformed input returns the default `PackageInfo` so
    /// the rest of the probe pipeline can continue without throwing.
    func test_parsePackageJSON_handlesMalformedInput() {
        XCTAssertEqual(RepositoryAuditProbe.parsePackageJSON(nil), RepositoryAuditProbe.PackageInfo())
        XCTAssertEqual(RepositoryAuditProbe.parsePackageJSON(""), RepositoryAuditProbe.PackageInfo())
        XCTAssertEqual(RepositoryAuditProbe.parsePackageJSON("{not json"), RepositoryAuditProbe.PackageInfo())
    }

    /// `tsconfig.json` with JSONC comments + `strict: true` is
    /// detected as strict.
    func test_detectTypescriptStrict_handlesJsonc() {
        let tsconfig = """
        {
            // The project uses TypeScript strict mode.
            "compilerOptions": {
                /* strict block on */
                "strict": true,
                "target": "ES2022"
            }
        }
        """
        XCTAssertTrue(RepositoryAuditProbe.detectTypescriptStrict(tsconfig))
    }

    /// Strict explicitly false returns false. Missing key returns
    /// false. Nil input returns false (the rubric reads this as
    /// "no TS strict" without throwing).
    func test_detectTypescriptStrict_falseAndMissingPaths() {
        let off = """
        { "compilerOptions": { "strict": false } }
        """
        let missing = """
        { "compilerOptions": { "target": "ES2022" } }
        """
        XCTAssertFalse(RepositoryAuditProbe.detectTypescriptStrict(off))
        XCTAssertFalse(RepositoryAuditProbe.detectTypescriptStrict(missing))
        XCTAssertFalse(RepositoryAuditProbe.detectTypescriptStrict(nil))
        XCTAssertFalse(RepositoryAuditProbe.detectTypescriptStrict("not json"))
    }

    /// Detects a workflow that ships both a test step and a deploy
    /// step in distinct files.
    func test_classifyWorkflows_detectsTestAndDeploy() {
        let entries: [GitHubContentEntry] = [
            GitHubContentEntry(name: "test.yml", path: ".github/workflows/test.yml", type: "file"),
            GitHubContentEntry(name: "deploy.yml", path: ".github/workflows/deploy.yml", type: "file"),
            GitHubContentEntry(name: "README", path: ".github/workflows/README", type: "file"),
        ]
        let signals = RepositoryAuditProbe.classifyWorkflows(entries)
        XCTAssertTrue(signals.hasWorkflows)
        XCTAssertEqual(signals.workflowCount, 2)
        XCTAssertTrue(signals.hasTestWorkflow)
        XCTAssertTrue(signals.hasDeployWorkflow)
    }

    /// `.env*` files trip a high-severity signal; the canonical
    /// `.env.example` does not.
    func test_detectSecuritySignals_envInRepoTripsHighSeverity() {
        let tree: [GitHubTreeEntry] = [
            GitHubTreeEntry(path: ".env", type: "blob", size: 120),
            GitHubTreeEntry(path: ".env.example", type: "blob", size: 60),
        ]
        let info = RepositoryAuditProbe.PackageInfo()
        let signals = RepositoryAuditProbe.detectSecuritySignals(tree: tree, packageInfo: info)
        XCTAssertTrue(signals.contains(where: { $0.kind == "env-in-repo" && $0.severity == "high" }))
        XCTAssertFalse(signals.contains(where: { $0.detail.contains(".env.example") }))
    }

    /// Node 16 → stale (less than current LTS minus one). Node 20 →
    /// fresh. Empty / non-numeric → not stale (silent pass).
    func test_isNodeEngineStale_boundary() {
        XCTAssertTrue(RepositoryAuditProbe.isNodeEngineStale("16.0.0"))
        XCTAssertTrue(RepositoryAuditProbe.isNodeEngineStale(">=14"))
        XCTAssertFalse(RepositoryAuditProbe.isNodeEngineStale("20.0.0"))
        XCTAssertFalse(RepositoryAuditProbe.isNodeEngineStale(""))
        XCTAssertFalse(RepositoryAuditProbe.isNodeEngineStale("not-a-version"))
    }

    /// `majorVersion(of:)` strips operators + the trailing tail.
    func test_majorVersion_stripsOperators() {
        XCTAssertEqual(RepositoryAuditProbe.majorVersion(of: "^15.0.3"), 15)
        XCTAssertEqual(RepositoryAuditProbe.majorVersion(of: "~3.22.0"), 3)
        XCTAssertEqual(RepositoryAuditProbe.majorVersion(of: ">=18.0.0"), 18)
        XCTAssertEqual(RepositoryAuditProbe.majorVersion(of: "1.0.0"), 1)
        XCTAssertNil(RepositoryAuditProbe.majorVersion(of: "garbage"))
    }
}
