import XCTest
@testable import ProjectHealthKit

/// v1.0-alpha.11 — Locks the slim `GitHubRepoSummary` value type
/// projected from `GET /user/repos`. Pure Codable / Equatable
/// round-trips; no network, no fixtures on disk.
final class GitHubRepoSummaryTests: XCTestCase {

    private func sample(
        fullName: String = "MaestroMed/AZConstruction_v0",
        homepage: String? = "https://www.azconstruction.fr",
        stars: Int = 12,
        topics: [String] = ["nextjs", "real-estate"]
    ) -> GitHubRepoSummary {
        GitHubRepoSummary(
            fullName: fullName,
            name: "AZConstruction_v0",
            description: "Premium Next.js landing for AZ Construction.",
            isPrivate: false,
            defaultBranch: "main",
            pushedAt: Date(timeIntervalSince1970: 1_715_000_000),
            homepageURL: homepage,
            stars: stars,
            topics: topics
        )
    }

    /// Round-trips a fully-populated summary through JSON. Locks the
    /// shape so any future Codable drift breaks loudly.
    func test_codable_fullyPopulated_roundTrips() throws {
        let original = sample()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubRepoSummary.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// `description` / `homepageURL` / `topics` all permit absence —
    /// the wire payload can omit them on slim org repos.
    func test_codable_nilDescriptionAndHomepage_roundTrips() throws {
        let original = GitHubRepoSummary(
            fullName: "MaestroMed/Empty",
            name: "Empty",
            description: nil,
            isPrivate: true,
            defaultBranch: "main",
            pushedAt: Date(timeIntervalSince1970: 0),
            homepageURL: nil,
            stars: 0,
            topics: []
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubRepoSummary.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.description)
        XCTAssertNil(decoded.homepageURL)
        XCTAssertTrue(decoded.topics.isEmpty)
    }

    /// Two summaries with identical columns compare equal — Equatable
    /// is field-by-field, not identity.
    func test_equatable_identicalFields_compareEqual() {
        let a = sample(stars: 5)
        let b = sample(stars: 5)
        XCTAssertEqual(a, b)
    }

    /// A differing `stars` count is enough to break equality. Stops a
    /// future drift where stars is excluded from Equatable accidentally.
    func test_equatable_differentStars_compareUnequal() {
        let a = sample(stars: 5)
        let b = sample(stars: 6)
        XCTAssertNotEqual(a, b)
    }

    /// `isPrivate == false` is the default for a public Numelite
    /// portfolio repo; the column round-trips both ways without
    /// silently flipping.
    func test_codable_preservesPrivateFlag() throws {
        let publicRepo = sample()
        let privateRepo = GitHubRepoSummary(
            fullName: publicRepo.fullName,
            name: publicRepo.name,
            description: publicRepo.description,
            isPrivate: true,
            defaultBranch: publicRepo.defaultBranch,
            pushedAt: publicRepo.pushedAt,
            homepageURL: publicRepo.homepageURL,
            stars: publicRepo.stars,
            topics: publicRepo.topics
        )
        let publicData = try JSONEncoder().encode(publicRepo)
        let privateData = try JSONEncoder().encode(privateRepo)
        let publicDecoded = try JSONDecoder().decode(GitHubRepoSummary.self, from: publicData)
        let privateDecoded = try JSONDecoder().decode(GitHubRepoSummary.self, from: privateData)
        XCTAssertFalse(publicDecoded.isPrivate)
        XCTAssertTrue(privateDecoded.isPrivate)
    }

    /// `topics` round-trips intact — order matters because the wizard
    /// surfaces them as comma-joined chips downstream.
    func test_codable_topicsOrderPreserved() throws {
        let original = sample(topics: ["nextjs", "real-estate", "landing"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubRepoSummary.self, from: data)
        XCTAssertEqual(decoded.topics, ["nextjs", "real-estate", "landing"])
    }
}
