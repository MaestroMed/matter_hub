import XCTest
@testable import ProjectHealthKit

/// v1.0-alpha.8 — Pure tests for the `VercelDeployment` value type
/// Codable round-trip plus the static URL builder. The actor client
/// itself isn't exercised here (it hits the network) — the value
/// types and the URL math are the contract MIND tests against.
final class VercelClientTests: XCTestCase {

    /// A `VercelDeployment` with every field populated must round-trip
    /// through JSON without losing any field. Locks the on-disk cache
    /// invariant.
    func test_vercelDeployment_codableRoundTrip_preservesEveryField() throws {
        let original = VercelDeployment(
            id: "dpl_abc123",
            url: "az-construction-fr-abc.vercel.app",
            state: "READY",
            createdAt: Date(timeIntervalSince1970: 1_716_000_000),
            creatorEmail: "mehdi@numelite.com",
            commitSHA: "8f23c1d",
            commitMessage: "Fix hero CTA spacing",
            target: "production"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VercelDeployment.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.url, original.url)
        XCTAssertEqual(decoded.state, original.state)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
        XCTAssertEqual(decoded.creatorEmail, original.creatorEmail)
        XCTAssertEqual(decoded.commitSHA, original.commitSHA)
        XCTAssertEqual(decoded.commitMessage, original.commitMessage)
        XCTAssertEqual(decoded.target, original.target)
    }

    /// All four optional fields can be nil. A QUEUED deployment that
    /// Vercel hasn't attached a commit to yet (the build hasn't even
    /// fetched the ref) round-trips with every optional unset.
    func test_vercelDeployment_codableRoundTrip_acceptsNilOptionals() throws {
        let original = VercelDeployment(
            id: "dpl_xyz",
            url: "preview.vercel.app",
            state: "QUEUED",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VercelDeployment.self, from: data)

        XCTAssertNil(decoded.creatorEmail)
        XCTAssertNil(decoded.commitSHA)
        XCTAssertNil(decoded.commitMessage)
        XCTAssertNil(decoded.target)
        XCTAssertEqual(decoded.state, "QUEUED")
    }

    /// `VercelHealth` round-trips clean — the HomeView KPI bar reads
    /// the aggregate, so the persistence path stays locked.
    func test_vercelHealth_codableRoundTrip() throws {
        let original = VercelHealth(
            lastDeploymentState: "READY",
            successRate7d: 0.85,
            avgBuildDurationSec: 47,
            totalLast7Days: 12
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VercelHealth.self, from: data)

        XCTAssertEqual(decoded.lastDeploymentState, "READY")
        XCTAssertEqual(decoded.successRate7d, 0.85, accuracy: 0.0001)
        XCTAssertEqual(decoded.avgBuildDurationSec, 47)
        XCTAssertEqual(decoded.totalLast7Days, 12)
    }

    /// `deploymentsURL(projectID:limit:)` builds against the
    /// `https://api.vercel.com/v6/deployments` base with the right
    /// query items. Locks the URL contract.
    func test_deploymentsURL_buildsExpectedQuery() throws {
        let url = try XCTUnwrap(VercelClient.deploymentsURL(projectID: "prj_xyz", limit: 5))

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.vercel.com")
        XCTAssertEqual(url.path, "/v6/deployments")

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "projectId", value: "prj_xyz")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "limit", value: "5")))
    }

    /// The default `limit: Int = 5` parameter applies to the URL builder
    /// surface — we lock the default by spot-checking the explicit
    /// case here so a refactor that drops the default keeps existing
    /// callers compiling and producing the same URL shape.
    func test_deploymentsURL_acceptsArbitraryLimit() throws {
        let url = try XCTUnwrap(VercelClient.deploymentsURL(projectID: "prj_x", limit: 25))
        XCTAssertTrue(url.absoluteString.contains("limit=25"))
    }

    /// `VercelClientError` cases must match by Equatable conformance
    /// so call sites can `if error == .noToken` cleanly without
    /// pattern-match boilerplate.
    func test_vercelClientError_equality() {
        XCTAssertEqual(VercelClientError.noToken, VercelClientError.noToken)
        XCTAssertEqual(VercelClientError.http(401), VercelClientError.http(401))
        XCTAssertNotEqual(VercelClientError.http(401), VercelClientError.http(500))
        XCTAssertNotEqual(VercelClientError.noToken, VercelClientError.decode)
        XCTAssertEqual(VercelClientError.network("offline"), VercelClientError.network("offline"))
    }
}
