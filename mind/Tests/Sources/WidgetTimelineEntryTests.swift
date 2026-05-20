import XCTest
@testable import GraphCore

/// v1.0-alpha.16 — Locks the pure formatters the three iOS 26 Lock
/// Screen widgets render. Same pattern as the v0.27.1
/// `LockScreenWidgetFormatterTests` — the actual widget extension
/// can't be imported here (the appExtension target is sandboxed off
/// the host unit-test bundle), so the formatters live in GraphCore
/// and the tests pin every boundary.
final class WidgetTimelineEntryTests: XCTestCase {

    // MARK: - Lead inbox snapshot

    /// `SharedSnapshot.placeholder` carries Mehdi-shaped sample data
    /// (3 leads / Karim Benali / 830€). Locks the canonical preview
    /// the widget gallery shows.
    func test_placeholder_carriesMehdiPortfolioShape() {
        let placeholder = SharedSnapshot.placeholder
        XCTAssertEqual(placeholder.leadCount, 3)
        XCTAssertEqual(placeholder.leadLastContact, "Karim Benali")
        XCTAssertEqual(placeholder.totalMRR, 830)
        XCTAssertNil(placeholder.criticalProjectName)
    }

    // MARK: - MRR formatter

    /// Sub-thousand MRR renders as plain "<n>€" — the 0..999 path
    /// of the circular accessory glyph.
    func test_mrrFormatter_smallAmount_rendersPlainEuro() {
        XCTAssertEqual(WidgetMRRFormatter.compact(0), "0€")
        XCTAssertEqual(WidgetMRRFormatter.compact(830), "830€")
        XCTAssertEqual(WidgetMRRFormatter.compact(999), "999€")
    }

    /// 1000..9999 collapses to "X.Yk€" (one decimal). Drops the
    /// trailing ".0" for round numbers so "1k€" lands instead of
    /// "1.0k€".
    func test_mrrFormatter_mediumAmount_collapsesToKiloEuro() {
        XCTAssertEqual(WidgetMRRFormatter.compact(1_000), "1k€")
        XCTAssertEqual(WidgetMRRFormatter.compact(1_250), "1.3k€")
        XCTAssertEqual(WidgetMRRFormatter.compact(9_900), "9.9k€")
    }

    /// 10k..999k → integer k€, 1M+ → integer M€. Negative inputs
    /// collapse to 0€.
    func test_mrrFormatter_largeAmount_andNegativeInput() {
        XCTAssertEqual(WidgetMRRFormatter.compact(12_345), "12k€")
        XCTAssertEqual(WidgetMRRFormatter.compact(120_000), "120k€")
        XCTAssertEqual(WidgetMRRFormatter.compact(1_500_000), "1M€")
        XCTAssertEqual(WidgetMRRFormatter.compact(-50), "0€")
    }

    // MARK: - Deployment status formatter

    /// `criticalProjectName == nil` → "<default> ✓" inline branch.
    /// Confirms the all-green path renders the check glyph. We look
    /// at `unicodeScalars` because Swift's grapheme-aware
    /// `.contains(Character:)` collapses variation selectors.
    func test_deploymentFormatter_nilCritical_rendersAllGreenLine() {
        let line = WidgetDeploymentFormatter.inlineLine(
            criticalProjectName: nil,
            defaultProjectName: "AZ Construction"
        )
        XCTAssertTrue(line.contains("AZ Construction"))
        XCTAssertTrue(
            line.unicodeScalars.contains(where: { $0 == "\u{2713}" }),
            "All-green branch must include a check mark"
        )
    }

    /// `criticalProjectName != nil` → "<Name> ⚠️" inline branch.
    /// Confirms the failing-deployment path renders the warning
    /// glyph. Uses `unicodeScalars` to dodge the same grapheme
    /// collapse the all-green test does.
    func test_deploymentFormatter_withCritical_rendersWarningLine() {
        let line = WidgetDeploymentFormatter.inlineLine(
            criticalProjectName: "IEF&Co",
            defaultProjectName: "AZ Construction"
        )
        XCTAssertTrue(line.contains("IEF&Co"))
        XCTAssertTrue(
            line.unicodeScalars.contains(where: { $0 == "\u{26A0}" }),
            "Critical branch must include a warning sign"
        )
        XCTAssertFalse(line.contains("AZ Construction"),
                       "Critical branch must shadow the default name")
    }
}
