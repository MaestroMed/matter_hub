import XCTest
@testable import ProjectHealthKit

/// v1.0-alpha.9 — Pure tests for the redeploy URL + body builder
/// added to `VercelClient`. The actor's actual `redeploy(...)` call
/// hits the network — we lock the pure inputs the call constructs so
/// a refactor that changes the Vercel API contract has to come
/// through these tests first.
final class VercelRedeployURLTests: XCTestCase {

    /// The POST body must carry the project name under `name`. Vercel
    /// uses this to look up the matching team's project.
    func test_redeployBody_carriesProjectName() {
        let body = VercelClient.redeployBody(
            projectName: "az-construction",
            githubRepo: "MaestroMed/AZConstruction_v0"
        )
        XCTAssertEqual(body["name"] as? String, "az-construction")
    }

    /// `gitSource.type` must be `"github"` — Vercel rejects the POST
    /// with a 400 if this is missing or set to something else.
    func test_redeployBody_gitSourceTypeIsGithub() throws {
        let body = VercelClient.redeployBody(
            projectName: "any",
            githubRepo: "MaestroMed/any_v0"
        )
        let gitSource = try XCTUnwrap(body["gitSource"] as? [String: Any])
        XCTAssertEqual(gitSource["type"] as? String, "github")
    }

    /// `gitSource.repo` must be the `<owner>/<repo>` string we pass
    /// in. The redeploy fans out from the project's `githubRepo`
    /// field — the API expects it back verbatim.
    func test_redeployBody_repoMatchesInput() throws {
        let body = VercelClient.redeployBody(
            projectName: "any",
            githubRepo: "MaestroMed/AZConstruction_v0"
        )
        let gitSource = try XCTUnwrap(body["gitSource"] as? [String: Any])
        XCTAssertEqual(gitSource["repo"] as? String, "MaestroMed/AZConstruction_v0")
    }

    /// `target` must be `"production"` — otherwise Vercel produces a
    /// preview deployment instead, which isn't what the Redeploy CTA
    /// promises.
    func test_redeployBody_targetIsProduction() {
        let body = VercelClient.redeployBody(
            projectName: "any",
            githubRepo: "any/any"
        )
        XCTAssertEqual(body["target"] as? String, "production")
    }

    /// `ref` defaults to `"main"` when the caller doesn't pass a
    /// branch. Locks the production-on-main convention that all of
    /// the Numelite client repos follow.
    func test_redeployBody_defaultBranchIsMain() throws {
        let body = VercelClient.redeployBody(
            projectName: "any",
            githubRepo: "any/any"
        )
        let gitSource = try XCTUnwrap(body["gitSource"] as? [String: Any])
        XCTAssertEqual(gitSource["ref"] as? String, "main")
    }

    /// Caller-supplied branch overrides the default. Locks the
    /// override path for the future "redeploy from staging" UI.
    func test_redeployBody_explicitBranchOverridesDefault() throws {
        let body = VercelClient.redeployBody(
            projectName: "any",
            githubRepo: "any/any",
            branch: "staging"
        )
        let gitSource = try XCTUnwrap(body["gitSource"] as? [String: Any])
        XCTAssertEqual(gitSource["ref"] as? String, "staging")
    }
}
