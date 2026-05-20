import XCTest
@testable import AuditKit

final class AuditFindingsTests: XCTestCase {

    func test_hasAnyData_isFalseForEmptyFindings() {
        let empty = AuditFindings()
        XCTAssertFalse(empty.hasAnyData)
    }

    func test_hasAnyData_isTrueWhenAtLeastOneSectionPresent() {
        var f = AuditFindings()
        f.cdn = CDNFindings(provider: "Cloudflare", serverHeader: "cloudflare")
        XCTAssertTrue(f.hasAnyData)
    }

    func test_openGraphFindings_completenessScoreReflectsFlags() {
        let allOff = OpenGraphFindings(
            hasTitle: false, hasDescription: false, hasImage: false,
            hasType: false, hasTwitterCard: false, completenessScore: 0
        )
        XCTAssertEqual(allOff.completenessScore, 0)

        let allOn = OpenGraphFindings(
            hasTitle: true, hasDescription: true, hasImage: true,
            hasType: true, hasTwitterCard: true, completenessScore: 100
        )
        XCTAssertEqual(allOn.completenessScore, 100)
    }

    func test_mobileFindings_noAppByDefault() {
        let none = MobileFindings(hasIOSApp: false)
        XCTAssertFalse(none.hasIOSApp)
        XCTAssertNil(none.appName)
        XCTAssertNil(none.averageRating)
    }

    func test_analyticsFindings_hasAnyAnalyticsMirrorsArray() {
        let none = AnalyticsFindings(providers: [], hasErrorTracking: false)
        XCTAssertFalse(none.hasAnyAnalytics)

        let some = AnalyticsFindings(providers: ["Plausible"], hasErrorTracking: true)
        XCTAssertTrue(some.hasAnyAnalytics)
    }

    func test_paymentFindings_hasMonetizationMirrorsProcessorsOrPayWall() {
        let nothing = PaymentFindings(processors: [], hasPayWall: false)
        XCTAssertFalse(nothing.hasMonetization)

        let processors = PaymentFindings(processors: ["Stripe"], hasPayWall: false)
        XCTAssertTrue(processors.hasMonetization)

        let paywall = PaymentFindings(processors: [], hasPayWall: true)
        XCTAssertTrue(paywall.hasMonetization)
    }
}
