import XCTest
@testable import ProjectHealthKit

/// v1.0-alpha.8 — Pure tests for the `GitHubCommit` / `GitHubRepoStats`
/// value types Codable round-trip plus the static URL builders. Same
/// strategy as `VercelClientTests` — actor network calls are not
/// exercised here, the contract is the value types + URLs.
final class GitHubClientTests: XCTestCase {

    func test_gitHubCommit_codableRoundTrip_preservesEveryField() throws {
        let original = GitHubCommit(
            sha: "8f23c1d2e9b04a3c91e0f4a8b9d2e1f7c3b6a4e5",
            message: "Fix hero CTA spacing",
            authorName: "Mehdi Nafaa",
            authorEmail: "mehdi@numelite.com",
            committedAt: Date(timeIntervalSince1970: 1_716_000_000),
            url: "https://github.com/MaestroMed/AZConstruction_v0/commit/8f23c1d"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubCommit.self, from: data)

        XCTAssertEqual(decoded.sha, original.sha)
        XCTAssertEqual(decoded.message, original.message)
        XCTAssertEqual(decoded.authorName, original.authorName)
        XCTAssertEqual(decoded.authorEmail, original.authorEmail)
        XCTAssertEqual(decoded.committedAt, original.committedAt)
        XCTAssertEqual(decoded.url, original.url)
    }

    /// `GitHubCommit.id` aliases `sha` — locks the Identifiable
    /// contract used by SwiftUI `ForEach`.
    func test_gitHubCommit_idMatchesSha() {
        let commit = GitHubCommit(
            sha: "abc",
            message: "m",
            authorName: "n",
            authorEmail: "e",
            committedAt: Date(timeIntervalSince1970: 0),
            url: "u"
        )
        XCTAssertEqual(commit.id, "abc")
    }

    func test_gitHubRepoStats_codableRoundTrip() throws {
        let original = GitHubRepoStats(
            stars: 42,
            openIssues: 3,
            defaultBranch: "main",
            lastPushedAt: Date(timeIntervalSince1970: 1_716_100_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubRepoStats.self, from: data)

        XCTAssertEqual(decoded.stars, 42)
        XCTAssertEqual(decoded.openIssues, 3)
        XCTAssertEqual(decoded.defaultBranch, "main")
        XCTAssertEqual(decoded.lastPushedAt, original.lastPushedAt)
    }

    /// `commitsURL(repo:limit:)` builds against the `api.github.com`
    /// base with the right query items. Locks the URL contract.
    func test_commitsURL_buildsExpectedQuery() throws {
        let url = try XCTUnwrap(GitHubClient.commitsURL(repo: "MaestroMed/AZConstruction_v0", limit: 5))

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.github.com")
        XCTAssertEqual(url.path, "/repos/MaestroMed/AZConstruction_v0/commits")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "per_page", value: "5")))
    }

    func test_repoURL_isSimpleAppend() throws {
        let url = try XCTUnwrap(GitHubClient.repoURL(repo: "MaestroMed/IEFCo_v0"))
        XCTAssertEqual(url.absoluteString, "https://api.github.com/repos/MaestroMed/IEFCo_v0")
    }

    /// `commitsURL(repo:)` returns nil for an empty repo string —
    /// callers that hand back nil-token / nil-repo states early
    /// stop a request from being built against a bogus path.
    func test_commitsURL_rejectsEmptyRepo() {
        XCTAssertNil(GitHubClient.commitsURL(repo: "", limit: 5))
        XCTAssertNil(GitHubClient.repoURL(repo: ""))
        XCTAssertNil(GitHubClient.issuesURL(repo: "", limit: 5))
    }

    /// `issuesURL(repo:limit:)` carries the `state=open` filter so the
    /// cockpit only ever reads open issues.
    func test_issuesURL_filtersByOpenState() throws {
        let url = try XCTUnwrap(GitHubClient.issuesURL(repo: "MaestroMed/AZConstruction_v0", limit: 10))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "state", value: "open")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "per_page", value: "10")))
    }

    func test_gitHubClientError_equality() {
        XCTAssertEqual(GitHubClientError.noToken, GitHubClientError.noToken)
        XCTAssertEqual(GitHubClientError.http(404), GitHubClientError.http(404))
        XCTAssertNotEqual(GitHubClientError.http(404), GitHubClientError.http(500))
        XCTAssertEqual(GitHubClientError.network("dns"), GitHubClientError.network("dns"))
    }
}
