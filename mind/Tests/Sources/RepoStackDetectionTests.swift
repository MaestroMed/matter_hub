import XCTest
@testable import ProjectHealthKit

/// v1.0-alpha.11 — Locks the `RepoStackDetection` value type +
/// `GitHubClient.nextDependencyVersion(in:)` pure helper. Avoids
/// every network call by feeding `package.json` blobs through the
/// public static parser.
final class RepoStackDetectionTests: XCTestCase {

    func test_codable_roundTrips() throws {
        let original = RepoStackDetection(
            framework: "nextjs",
            version: "15.0.3",
            confidence: 0.95,
            signals: ["package.json: next@15.0.3", "vercel.json present"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RepoStackDetection.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_codable_nilVersion_roundTrips() throws {
        let original = RepoStackDetection(
            framework: "wordpress",
            version: nil,
            confidence: 0.7,
            signals: ["wp-content/ in tree"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RepoStackDetection.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.version)
    }

    /// `nextDependencyVersion` strips the leading `^` operator so a
    /// real `package.json` like `"next": "^15.0.3"` surfaces a
    /// clean `15.0.3`.
    func test_nextDependencyVersion_extractsAndCleansCaretPrefix() {
        let pkg = "{ \"dependencies\": { \"next\": \"^15.0.3\" } }"
        XCTAssertEqual(GitHubClient.nextDependencyVersion(in: pkg), "15.0.3")
    }

    /// A package.json without `next` returns nil — drives the planner
    /// past the Next.js branch.
    func test_nextDependencyVersion_missingNext_returnsNil() {
        let pkg = "{ \"dependencies\": { \"react\": \"18.0.0\" } }"
        XCTAssertNil(GitHubClient.nextDependencyVersion(in: pkg))
    }

    /// Equatable: identical detections compare equal.
    func test_equatable_identicalFields_compareEqual() {
        let lhs = RepoStackDetection(
            framework: "shopify",
            version: nil,
            confidence: 0.9,
            signals: ["theme.liquid in tree"]
        )
        let rhs = RepoStackDetection(
            framework: "shopify",
            version: nil,
            confidence: 0.9,
            signals: ["theme.liquid in tree"]
        )
        XCTAssertEqual(lhs, rhs)
    }
}
