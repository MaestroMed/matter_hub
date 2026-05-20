import XCTest
@testable import ProjectHealthKit

/// v1.0-alpha.8 — Pure tests for `LighthouseScore` Codable + the
/// static endpoint builder. The actor's network call is not
/// exercised — the contract is the value type and the URL math.
final class LighthouseProbeTests: XCTestCase {

    func test_lighthouseScore_codableRoundTrip() throws {
        let original = LighthouseScore(
            performance: 92,
            accessibility: 88,
            bestPractices: 95,
            seo: 91,
            lcpSeconds: 2.1,
            inpMs: 180,
            cls: 0.05,
            fetchedAt: Date(timeIntervalSince1970: 1_716_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LighthouseScore.self, from: data)

        XCTAssertEqual(decoded.performance, 92)
        XCTAssertEqual(decoded.accessibility, 88)
        XCTAssertEqual(decoded.bestPractices, 95)
        XCTAssertEqual(decoded.seo, 91)
        XCTAssertEqual(decoded.lcpSeconds, 2.1, accuracy: 0.0001)
        XCTAssertEqual(decoded.inpMs, 180)
        XCTAssertEqual(decoded.cls, 0.05, accuracy: 0.0001)
        XCTAssertEqual(decoded.fetchedAt, original.fetchedAt)
    }

    /// `overall` is the unweighted average of the four category
    /// scores, integer-truncated. Locks the formula the UI pill
    /// reads.
    func test_lighthouseScore_overallIsAverageOfFourCategories() {
        let score = LighthouseScore(
            performance: 90,
            accessibility: 80,
            bestPractices: 70,
            seo: 100,
            lcpSeconds: 0,
            inpMs: 0,
            cls: 0
        )
        // (90 + 80 + 70 + 100) / 4 = 85
        XCTAssertEqual(score.overall, 85)
    }

    /// `endpoint(forHost:)` prepends https:// when the host lacks
    /// a scheme. Locks the contract that ProjectCard passes a bare
    /// `project.host` without scheme.
    func test_endpoint_prependsHttpsWhenSchemeMissing() throws {
        let url = try XCTUnwrap(LighthouseProbe.endpoint(forHost: "www.az-construction.fr"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let urlItem = items.first { $0.name == "url" }?.value
        XCTAssertEqual(urlItem, "https://www.az-construction.fr")

        // mobile is the default
        XCTAssertTrue(items.contains(URLQueryItem(name: "strategy", value: "mobile")))
    }

    /// `endpoint(forHost:)` rejects an empty host outright — caller
    /// stops early instead of hitting Google with a URL that returns
    /// 400.
    func test_endpoint_rejectsEmptyHost() {
        XCTAssertNil(LighthouseProbe.endpoint(forHost: ""))
        XCTAssertNil(LighthouseProbe.endpoint(forHost: "   "))
    }
}
