import XCTest
@testable import AuditKit

/// v0.24 — Covers the pure host → competitors table used by the
/// Audit Battle Mode form to auto-suggest 3 rivals.
final class CompetitorLookupTests: XCTestCase {

    /// Exact match against a known SaaS host returns its 3-entry
    /// competitor list. Locks the most-used path: Mehdi types
    /// "stripe.com" and gets Adyen / Mollie / Checkout as chips.
    func test_exactMatch_returnsCuratedCompetitors() {
        let result = CompetitorLookup.competitors(for: "stripe.com")
        XCTAssertEqual(result, ["adyen.com", "mollie.com", "checkout.com"])
    }

    /// `www.` prefix is stripped before lookup so "www.stripe.com"
    /// resolves the same way "stripe.com" does. Real-world copy-
    /// paste from a URL bar hits this branch every time.
    func test_wwwPrefix_isNormalised() {
        let result = CompetitorLookup.competitors(for: "www.stripe.com")
        XCTAssertEqual(result, ["adyen.com", "mollie.com", "checkout.com"])
    }

    /// Unknown hosts return an empty array — the UI then keeps the
    /// chips list empty and Mehdi types competitors manually. The
    /// table never crashes / never throws on a miss.
    func test_unknownHost_returnsEmpty() {
        let result = CompetitorLookup.competitors(for: "kairos.systems")
        XCTAssertTrue(result.isEmpty)
    }

    /// Lookup is case-insensitive: STRIPE.COM and "STRIPE.com"
    /// resolve to the same entry. Catches the case where a CSV
    /// import or a tap-on-link surfaces an uppercased host.
    func test_caseFolding_isLowercaseInsensitive() {
        XCTAssertEqual(
            CompetitorLookup.competitors(for: "STRIPE.COM"),
            CompetitorLookup.competitors(for: "stripe.com")
        )
    }

    /// Sanity: the curated table has no duplicate keys (Swift's
    /// dictionary literal would crash at runtime). And no entry
    /// lists the same competitor twice — the chips row dedupe
    /// upstream would silently swallow the second, but it's a
    /// signal of a paste-bug in the curation file.
    func test_table_hasNoDuplicateCompetitorsPerEntry() {
        for (host, competitors) in CompetitorLookup.table {
            let unique = Set(competitors)
            XCTAssertEqual(
                unique.count,
                competitors.count,
                "\(host) lists a competitor twice: \(competitors)"
            )
            // The host should never appear in its own competitor list.
            XCTAssertFalse(
                competitors.contains(host),
                "\(host) lists itself as a competitor"
            )
        }
    }
}
