import XCTest
@testable import SwarmKit

/// v1.0-alpha.7 — Locks the static `SwarmZoneCatalog` reference data.
/// The wizard autocomplete is the user's primary path into the
/// catalog so the data contract is load-bearing.
final class SwarmZoneCatalogTests: XCTestCase {

    /// >=200 zones — the wizard advertises "100 communes courantes"
    /// for IDF + a regional cohort, and the test sets a 200 floor
    /// because a regression that drops to a few dozen would still
    /// pass any naive smoke test.
    func test_catalog_hasAtLeast200Zones() {
        XCTAssertGreaterThanOrEqual(SwarmZoneCatalog.zones.count, 200)
    }

    /// Every zone must have a non-empty slug + non-empty display
    /// name. Empty slugs would route to `/service/` and 404; empty
    /// names would render blank chips.
    func test_catalog_allZonesHaveSlugAndDisplayName() {
        for zone in SwarmZoneCatalog.zones {
            XCTAssertFalse(zone.slug.isEmpty, "Empty slug in zone \(zone)")
            XCTAssertFalse(zone.displayName.isEmpty, "Empty displayName in zone \(zone)")
            XCTAssertFalse(zone.departmentCode.isEmpty, "Empty departmentCode in zone \(zone)")
        }
    }

    /// No duplicate slugs — the swarm orchestrator uses the slug as
    /// the per-page identifier, and duplicates would silently
    /// overwrite each other in the exporter's `[path: Data]` map.
    func test_catalog_hasNoDuplicateSlugs() {
        let slugs = SwarmZoneCatalog.zones.map(\.slug)
        let unique = Set(slugs)
        XCTAssertEqual(slugs.count, unique.count, "Duplicate slugs detected")
    }

    /// All slugs must be URL-safe: lowercased ASCII letters, digits,
    /// and hyphens. Any special character would break the Next.js
    /// route + the per-page filesystem path.
    func test_catalog_allSlugsAreURLSafe() {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for zone in SwarmZoneCatalog.zones {
            let cs = CharacterSet(charactersIn: zone.slug)
            XCTAssertTrue(
                allowed.isSuperset(of: cs),
                "Slug \(zone.slug) contains non-URL-safe characters"
            )
            XCTAssertFalse(zone.slug.hasPrefix("-"), "Slug \(zone.slug) starts with -")
            XCTAssertFalse(zone.slug.hasSuffix("-"), "Slug \(zone.slug) ends with -")
        }
    }

    /// The exposed `zones` array must be sorted alphabetically by
    /// `displayName` (case-insensitive) so the wizard's autocomplete
    /// renders in a predictable order.
    func test_catalog_sortedAlphabetically() {
        let names = SwarmZoneCatalog.zones.map(\.displayName)
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        XCTAssertEqual(names, sorted)
    }
}
