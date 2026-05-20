import XCTest
@testable import ProjectHealthKit

/// v1.0-alpha.11 — Locks the pure derivation pipeline that turns a
/// `GitHubRepoSummary` (+ `RepoStackDetection`) into a `RepoMetadata`.
/// Slug normalisation, name humanisation, host selection, primary
/// color extraction.
final class RepoMetadataDerivationTests: XCTestCase {

    private func summary(
        fullName: String,
        homepage: String? = nil,
        description: String? = nil,
        topics: [String] = []
    ) -> GitHubRepoSummary {
        let name = String(fullName.split(separator: "/").last ?? "")
        return GitHubRepoSummary(
            fullName: fullName,
            name: name,
            description: description,
            isPrivate: false,
            defaultBranch: "main",
            pushedAt: Date(timeIntervalSince1970: 0),
            homepageURL: homepage,
            stars: 0,
            topics: topics
        )
    }

    private let nextjsDetection = RepoStackDetection(
        framework: "nextjs",
        version: "15.0.3",
        confidence: 0.95,
        signals: ["package.json: next@15.0.3"]
    )

    // MARK: - Slug

    /// `AZConstruction_v0` → `az-construction` — version suffix
    /// stripped, CamelCase split, lowercased.
    func test_deriveSlug_azConstruction_dropsVersionSuffix() {
        XCTAssertEqual(RepoMetadata.deriveSlug(from: "AZConstruction_v0"), "az-construction")
    }

    /// Underscore separator collapses to a dash regardless of version
    /// suffix presence.
    func test_deriveSlug_underscoreCollapsesToDash() {
        XCTAssertEqual(RepoMetadata.deriveSlug(from: "iefco_v1"), "iefco")
        XCTAssertEqual(RepoMetadata.deriveSlug(from: "ief_and_co"), "ief-and-co")
    }

    /// Trailing dashes don't survive. `acme!` → `acme`.
    func test_deriveSlug_trimsTrailingNonAlnum() {
        XCTAssertEqual(RepoMetadata.deriveSlug(from: "acme!"), "acme")
        XCTAssertEqual(RepoMetadata.deriveSlug(from: "acme--"), "acme")
    }

    /// `IEFandCo_v0` → `ie-fand-co` — CamelCase boundary detection
    /// keeps the `IEF` cluster together until the next case shift.
    func test_deriveSlug_camelCaseRunBoundary() {
        XCTAssertEqual(RepoMetadata.deriveSlug(from: "IEFandCo_v0"), "ie-fand-co")
    }

    // MARK: - Name

    /// CamelCase repo → spaced human name.
    func test_deriveName_azConstruction_spacesCamelCase() {
        XCTAssertEqual(RepoMetadata.deriveName(from: "AZConstruction_v0"), "AZ Construction")
    }

    /// `IEFandCo_v0` → `IE Fand Co` matches the documented spec.
    func test_deriveName_iefAndCoSplitsCamelCaseRun() {
        XCTAssertEqual(RepoMetadata.deriveName(from: "IEFandCo_v0"), "IE Fand Co")
    }

    /// A name already containing spaces is preserved (only the
    /// version suffix is removed).
    func test_deriveName_alreadySpaced_returnsAsIs() {
        XCTAssertEqual(RepoMetadata.deriveName(from: "AZ Construction_v0"), "AZ Construction")
    }

    // MARK: - Host

    /// A repo with a `homepage` field surfaces that as the host
    /// (scheme + trailing slash stripped).
    func test_deriveHost_withHomepage_returnsCleanedHost() {
        let s = summary(fullName: "MaestroMed/AZConstruction_v0", homepage: "https://www.azconstruction.fr/")
        XCTAssertEqual(RepoMetadata.deriveHost(from: s, slug: "az-construction"), "www.azconstruction.fr")
    }

    /// Without a homepage MIND defaults to `<slug>.vercel.app` so the
    /// cockpit card has a plausible hostname to render.
    func test_deriveHost_withoutHomepage_fallsBackToVercelApp() {
        let s = summary(fullName: "MaestroMed/AZConstruction_v0", homepage: nil)
        XCTAssertEqual(RepoMetadata.deriveHost(from: s, slug: "az-construction"), "az-construction.vercel.app")
    }

    // MARK: - Primary color

    /// A repo whose description carries a hex code surfaces that exact
    /// color (uppercased) so the seeded `AZ Concept` palette
    /// (#3FB950) survives a re-import.
    func test_derivePrimaryColor_hexInDescription_returnsHex() {
        let s = summary(
            fullName: "MaestroMed/AZConcept_v0",
            description: "Brand color: #3FB950 — concrete polishing services"
        )
        XCTAssertEqual(RepoMetadata.derivePrimaryColor(from: s), "#3FB950")
    }

    /// No color anywhere → fallback to MIND iris (`#5E5BD8`).
    func test_derivePrimaryColor_noHex_returnsDefault() {
        let s = summary(
            fullName: "MaestroMed/Empty_v0",
            description: "No color here"
        )
        XCTAssertEqual(RepoMetadata.derivePrimaryColor(from: s), RepoMetadata.defaultPrimaryColor)
    }
}
