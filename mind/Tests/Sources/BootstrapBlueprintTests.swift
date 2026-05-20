import XCTest
@testable import BootstrapKit
@testable import GraphCore

/// v1.0-alpha.6 — Pure tests covering the wizard output value type.
/// Locks Codable round-trip, slug derivation, equality, defaults.
final class BootstrapBlueprintTests: XCTestCase {

    // MARK: - Defaults

    func test_init_defaults_areAllOff_andStackIsNextJS() {
        let bp = BootstrapBlueprint(
            projectName: "AZ Construction",
            slug: "az-construction",
            host: "www.azconstruction.fr"
        )
        XCTAssertEqual(bp.stack, .nextjs,
                       "Default stack should be Next.js — the only stack the scaffolder fully wires today")
        XCTAssertEqual(bp.githubOrg, "MaestroMed",
                       "Default GitHub org should be MaestroMed — Mehdi's org")
        XCTAssertEqual(bp.contractType, .oneshot)
        XCTAssertEqual(bp.monthlyRecurringRevenueEUR, 0)
        XCTAssertFalse(bp.includeAdminBackoffice)
        XCTAssertFalse(bp.includeBlogMDX)
        XCTAssertFalse(bp.includeI18nFREN)
        XCTAssertFalse(bp.includeStripe)
        XCTAssertEqual(bp.primaryColor, "#5E5BD8",
                       "Default primary color should be MIND iris (#5E5BD8)")
    }

    // MARK: - Derived

    func test_githubRepoPath_combinesOrgAndSlug() {
        let bp = BootstrapBlueprint(
            projectName: "AZ Construction",
            slug: "az-construction",
            host: "www.azconstruction.fr",
            githubOrg: "MaestroMed"
        )
        XCTAssertEqual(bp.githubRepoPath, "MaestroMed/az-construction")
    }

    func test_canonicalURL_alwaysPrependsHttps() {
        let bp = BootstrapBlueprint(
            projectName: "Acme",
            slug: "acme",
            host: "www.acme.fr"
        )
        XCTAssertEqual(bp.canonicalURL, "https://www.acme.fr",
                       "Canonical URL must always be https — never produce http scaffolds")
    }

    // MARK: - Codable

    func test_codable_roundTrip_preservesEveryField() throws {
        let fixed = Date(timeIntervalSince1970: 1_747_699_200)
        let original = BootstrapBlueprint(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            projectName: "IEF & Co",
            slug: "ief-and-co",
            host: "www.iefandco.com",
            githubOrg: "MaestroMed",
            stack: .nextjs,
            primaryColor: "#A371F7",
            contractType: .retainer,
            monthlyRecurringRevenueEUR: 350,
            includeAdminBackoffice: true,
            includeBlogMDX: true,
            includeI18nFREN: true,
            includeStripe: true,
            generatedAt: fixed
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BootstrapBlueprint.self, from: data)
        XCTAssertEqual(decoded, original,
                       "Codable round-trip must preserve every field byte-for-byte")
    }

    // MARK: - Equality

    func test_equality_isFieldByField_includingFlags() {
        let bp1 = BootstrapBlueprint(
            id: UUID(uuidString: "00000000-1111-2222-3333-444444444444")!,
            projectName: "Acme",
            slug: "acme",
            host: "acme.fr",
            includeAdminBackoffice: true
        )
        let bp2 = BootstrapBlueprint(
            id: UUID(uuidString: "00000000-1111-2222-3333-444444444444")!,
            projectName: "Acme",
            slug: "acme",
            host: "acme.fr",
            includeAdminBackoffice: false
        )
        XCTAssertNotEqual(bp1, bp2,
                          "Flipping a single optional-bundle flag must break equality")
    }

    // MARK: - Slug derivation

    func test_slugDerivation_viaProjectNormalizeSlug_isLowercaseAndDashed() {
        // The wizard calls Project.normalizeSlug(_:) to derive the
        // default slug. Lock that the GraphCore-side helper is stable
        // for typical Numelite client names.
        XCTAssertEqual(
            Project.normalizeSlug("AZ Construction"),
            "az-construction",
            "Slug must lowercase + dash-collapse for spaces"
        )
        XCTAssertEqual(
            Project.normalizeSlug("IEF & Co"),
            "ief-co",
            "Ampersand collapses to a single dash run"
        )
        XCTAssertEqual(
            Project.normalizeSlug("Épée Café"),
            "epee-cafe",
            "Diacritics must fold before slugging"
        )
    }
}
