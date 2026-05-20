import XCTest
@testable import AuditKit

/// v0.32 — Locks the pure derivation contract of
/// `AuditComparisonBuilder.build(from:)`. The builder is the single
/// surface the ComparisonSheet reads — every regression in this file
/// reflects a regression a user would see on screen (wrong leader,
/// missing overlap, ghost unique risk).
final class AuditComparisonTests: XCTestCase {

    // MARK: - Bounds + truncation

    /// One report is below the minimum — the comparison is empty so
    /// the UI renders the "select at least 2" hint instead of an
    /// awkward single-column scoreboard.
    func test_build_withOneReport_returnsEmptyComparison() {
        let report = makeReport(name: "Stripe", overall: 80)
        let comparison = AuditComparisonBuilder.build(from: [report])
        XCTAssertTrue(comparison.isEmpty)
        XCTAssertEqual(comparison.reports.count, 1)
        XCTAssertTrue(comparison.metricMatrix.isEmpty)
        XCTAssertTrue(comparison.leaders.isEmpty)
        XCTAssertTrue(comparison.quickWinOverlap.isEmpty)
        XCTAssertTrue(comparison.uniqueHiddenRisks.isEmpty)
    }

    /// Zero reports — same empty-comparison contract. The sheet
    /// surfaces the "no audits archived" card instead.
    func test_build_withEmpty_returnsEmptyComparison() {
        let comparison = AuditComparisonBuilder.build(from: [])
        XCTAssertTrue(comparison.isEmpty)
        XCTAssertEqual(comparison.reports.count, 0)
    }

    /// Five reports — silently truncated to the first 4 so the table
    /// stays readable on an iPhone screen and the leader index never
    /// overflows the column count.
    func test_build_truncatesAboveFour() {
        let reports = (0..<5).map { idx in
            makeReport(name: "Client \(idx)", overall: 50 + idx)
        }
        let comparison = AuditComparisonBuilder.build(from: reports)
        XCTAssertEqual(comparison.reports.count, AuditComparison.maximumReports)
        XCTAssertEqual(comparison.reports.map(\.client.name), [
            "Client 0", "Client 1", "Client 2", "Client 3",
        ])
    }

    // MARK: - Metric matrix

    /// Two reports — the matrix has one entry per metric, each entry
    /// is a 2-element array in selection order. Locks the
    /// "scoreboard reads the matrix in column order" contract that
    /// the UI relies on.
    func test_metricMatrix_preservesSelectionOrder() {
        let stripe = makeReport(
            name: "Stripe",
            scoring: .init(overall: 92, performance: 88, seo: 90, security: 95, brand: 80, mobile: 85)
        )
        let mollie = makeReport(
            name: "Mollie",
            scoring: .init(overall: 70, performance: 60, seo: 72, security: 78, brand: 65, mobile: 70)
        )
        let comparison = AuditComparisonBuilder.build(from: [stripe, mollie])
        XCTAssertEqual(comparison.metricMatrix[.overall],     [92, 70])
        XCTAssertEqual(comparison.metricMatrix[.performance], [88, 60])
        XCTAssertEqual(comparison.metricMatrix[.seo],         [90, 72])
        XCTAssertEqual(comparison.metricMatrix[.security],    [95, 78])
        XCTAssertEqual(comparison.metricMatrix[.brand],       [80, 65])
        XCTAssertEqual(comparison.metricMatrix[.mobile],      [85, 70])
    }

    // MARK: - Leaders + tie-break

    /// Per-metric leader index lands on the participant with the
    /// highest score. Each metric is judged independently — Stripe
    /// can win performance while Mollie wins brand.
    func test_leaders_pickHighestScorePerMetric() {
        let stripe = makeReport(
            name: "Stripe",
            scoring: .init(overall: 80, performance: 95, seo: 70, security: 90, brand: 60, mobile: 75)
        )
        let mollie = makeReport(
            name: "Mollie",
            scoring: .init(overall: 75, performance: 70, seo: 80, security: 60, brand: 92, mobile: 80)
        )
        let comparison = AuditComparisonBuilder.build(from: [stripe, mollie])
        XCTAssertEqual(comparison.leaders[.overall],     0)
        XCTAssertEqual(comparison.leaders[.performance], 0)
        XCTAssertEqual(comparison.leaders[.seo],         1)
        XCTAssertEqual(comparison.leaders[.security],    0)
        XCTAssertEqual(comparison.leaders[.brand],       1)
        XCTAssertEqual(comparison.leaders[.mobile],      1)
    }

    /// Ties resolve to the first participant in selection order so
    /// the badge lands where the user expects (primary wins ties).
    func test_leaders_tieBreaksByFirstWins() {
        let a = makeReport(name: "A", overall: 80)
        let b = makeReport(name: "B", overall: 80)
        let comparison = AuditComparisonBuilder.build(from: [a, b])
        XCTAssertEqual(comparison.leaders[.overall], 0)
    }

    /// All-zero axis is omitted from `leaders` so the UI doesn't
    /// award a "leader" badge for the participant that happened to
    /// be first when nobody scored anything.
    func test_leaders_omitsAllZeroAxis() {
        let a = makeReport(name: "A",
            scoring: .init(overall: 50, performance: 0, seo: 80, security: 70, brand: 60, mobile: 65))
        let b = makeReport(name: "B",
            scoring: .init(overall: 55, performance: 0, seo: 70, security: 75, brand: 50, mobile: 60))
        let comparison = AuditComparisonBuilder.build(from: [a, b])
        XCTAssertNil(comparison.leaders[.performance])
        XCTAssertEqual(comparison.leaders[.overall], 1)
    }

    // MARK: - Quick Wins overlap

    /// A Quick Win that appears in 2+ reports surfaces in the
    /// overlap list with the original casing of the first sighting
    /// and the indices in ascending order.
    func test_overlap_surfacesSharedQuickWinAcrossReports() {
        let win = AuditReport.QuickWin(
            title: "Add HSTS header",
            detail: "Set Strict-Transport-Security on edge.",
            effortDays: 0.5,
            impact: .high
        )
        let a = makeReport(name: "A", quickWins: [win])
        let b = makeReport(name: "B", quickWins: [
            AuditReport.QuickWin(
                title: "  add hsts header  ",
                detail: "different detail",
                effortDays: 1,
                impact: .medium
            )
        ])
        let comparison = AuditComparisonBuilder.build(from: [a, b])
        XCTAssertEqual(comparison.quickWinOverlap.count, 1)
        let entry = comparison.quickWinOverlap[0]
        // First-sighting casing wins.
        XCTAssertEqual(entry.title, "Add HSTS header")
        XCTAssertEqual(entry.reportIndices, [0, 1])
        XCTAssertEqual(entry.occurrenceCount, 2)
    }

    /// A QW present in exactly one report is NOT overlap — only the
    /// shared wins are surfaced (the unique-wins delta is not part
    /// of the v0.32 spec). Defensive duplicate inside the same
    /// report counts as one.
    func test_overlap_excludesUniqueQuickWins() {
        let a = makeReport(name: "A", quickWins: [
            AuditReport.QuickWin(title: "Add HSTS", detail: "", effortDays: 1, impact: .high),
            AuditReport.QuickWin(title: "Add HSTS", detail: "", effortDays: 1, impact: .high), // dup
            AuditReport.QuickWin(title: "Fix CLS",  detail: "", effortDays: 2, impact: .medium),
        ])
        let b = makeReport(name: "B", quickWins: [
            AuditReport.QuickWin(title: "Fix CLS",  detail: "", effortDays: 2, impact: .medium),
            AuditReport.QuickWin(title: "Compress hero image", detail: "", effortDays: 0.5, impact: .high),
        ])
        let comparison = AuditComparisonBuilder.build(from: [a, b])
        XCTAssertEqual(comparison.quickWinOverlap.count, 1)
        XCTAssertEqual(comparison.quickWinOverlap[0].title, "Fix CLS")
    }

    /// Overlap is sorted descending by occurrence count then by
    /// title ascending. Locks the deterministic rendering order so
    /// screenshots + tests stay reproducible.
    func test_overlap_sortsByOccurrenceThenTitle() {
        let everywhere = AuditReport.QuickWin(title: "Compress images", detail: "", effortDays: 1, impact: .high)
        let zPair      = AuditReport.QuickWin(title: "Zebra cache",     detail: "", effortDays: 1, impact: .medium)
        let aPair      = AuditReport.QuickWin(title: "Alpha cache",     detail: "", effortDays: 1, impact: .medium)
        let a = makeReport(name: "A", quickWins: [everywhere, zPair, aPair])
        let b = makeReport(name: "B", quickWins: [everywhere, zPair, aPair])
        let c = makeReport(name: "C", quickWins: [everywhere])  // boosts count for 'everywhere'
        let comparison = AuditComparisonBuilder.build(from: [a, b, c])
        XCTAssertEqual(comparison.quickWinOverlap.count, 3)
        // 'Compress images' = 3 occurrences → first.
        XCTAssertEqual(comparison.quickWinOverlap[0].title, "Compress images")
        // 'Alpha' before 'Zebra' at 2 occurrences each.
        XCTAssertEqual(comparison.quickWinOverlap[1].title, "Alpha cache")
        XCTAssertEqual(comparison.quickWinOverlap[2].title, "Zebra cache")
    }

    // MARK: - Hidden risks differences

    /// A hidden risk present in exactly one report surfaces in the
    /// uniqueHiddenRisks list with the right report index +
    /// severity.
    func test_uniqueRisks_surfaceWhenPresentInExactlyOneReport() {
        let risk = AuditReport.HiddenRisk(
            title: "Expired TLS cert in 30 days",
            detail: "Renew via Let's Encrypt cron.",
            severity: .critical
        )
        let a = makeReport(name: "A", hiddenRisks: [risk])
        let b = makeReport(name: "B", hiddenRisks: [])
        let comparison = AuditComparisonBuilder.build(from: [a, b])
        XCTAssertEqual(comparison.uniqueHiddenRisks.count, 1)
        let entry = comparison.uniqueHiddenRisks[0]
        XCTAssertEqual(entry.title, "Expired TLS cert in 30 days")
        XCTAssertEqual(entry.reportIndex, 0)
        XCTAssertEqual(entry.severity, .critical)
    }

    /// A hidden risk shared across 2 reports is NOT unique — it's
    /// filtered out so the differences section only shows truly
    /// differential risks.
    func test_uniqueRisks_excludesSharedRisks() {
        let shared = AuditReport.HiddenRisk(
            title: "No SPF record", detail: "", severity: .high
        )
        let onlyA = AuditReport.HiddenRisk(
            title: "Stripe webhook unsigned", detail: "", severity: .critical
        )
        let a = makeReport(name: "A", hiddenRisks: [shared, onlyA])
        let b = makeReport(name: "B", hiddenRisks: [shared])
        let comparison = AuditComparisonBuilder.build(from: [a, b])
        XCTAssertEqual(comparison.uniqueHiddenRisks.count, 1)
        XCTAssertEqual(comparison.uniqueHiddenRisks[0].title, "Stripe webhook unsigned")
    }

    /// Unique risks sort by descending severity then by title
    /// ascending. Locks the deterministic rendering order so the
    /// most-urgent risk lands at the top.
    func test_uniqueRisks_sortByDescendingSeverityThenTitle() {
        let critical = AuditReport.HiddenRisk(title: "Critical: TLS expiry", detail: "", severity: .critical)
        let highZ    = AuditReport.HiddenRisk(title: "Zeta SPF gap",         detail: "", severity: .high)
        let highA    = AuditReport.HiddenRisk(title: "Alpha SPF gap",        detail: "", severity: .high)
        let lowB     = AuditReport.HiddenRisk(title: "Beta cookie banner",   detail: "", severity: .low)
        let a = makeReport(name: "A", hiddenRisks: [critical])
        let b = makeReport(name: "B", hiddenRisks: [highZ])
        let c = makeReport(name: "C", hiddenRisks: [highA])
        let d = makeReport(name: "D", hiddenRisks: [lowB])
        let comparison = AuditComparisonBuilder.build(from: [a, b, c, d])
        XCTAssertEqual(comparison.uniqueHiddenRisks.count, 4)
        XCTAssertEqual(comparison.uniqueHiddenRisks[0].title, "Critical: TLS expiry")
        XCTAssertEqual(comparison.uniqueHiddenRisks[1].title, "Alpha SPF gap")
        XCTAssertEqual(comparison.uniqueHiddenRisks[2].title, "Zeta SPF gap")
        XCTAssertEqual(comparison.uniqueHiddenRisks[3].title, "Beta cookie banner")
    }

    // MARK: - Normalize + rank helpers

    /// Normalize key folds casing + trims whitespace so two
    /// near-identical titles collide deterministically.
    func test_normalize_isCaseFoldedAndTrimmed() {
        XCTAssertEqual(
            AuditComparisonBuilder.normalize("  Add HSTS Header  "),
            AuditComparisonBuilder.normalize("add hsts header")
        )
        XCTAssertEqual(AuditComparisonBuilder.normalize(""), "")
        XCTAssertEqual(AuditComparisonBuilder.normalize("   "), "")
    }

    /// Severity rank ordering — critical > high > medium > low.
    /// Drives both the unique-risks sort order and the per-row
    /// severity glyph colour in the UI.
    func test_severityRank_ordering() {
        XCTAssertGreaterThan(
            AuditComparisonBuilder.rank(of: .critical),
            AuditComparisonBuilder.rank(of: .high)
        )
        XCTAssertGreaterThan(
            AuditComparisonBuilder.rank(of: .high),
            AuditComparisonBuilder.rank(of: .medium)
        )
        XCTAssertGreaterThan(
            AuditComparisonBuilder.rank(of: .medium),
            AuditComparisonBuilder.rank(of: .low)
        )
    }

    // MARK: - Helpers

    private func makeReport(
        name: String,
        overall: Int = 70,
        scoring: AuditReport.Scoring? = nil,
        quickWins: [AuditReport.QuickWin] = [],
        hiddenRisks: [AuditReport.HiddenRisk] = []
    ) -> AuditReport {
        let resolvedScoring = scoring ?? AuditReport.Scoring(
            overall: overall,
            performance: overall,
            seo: overall,
            security: overall,
            brand: overall,
            mobile: overall
        )
        return AuditReport(
            client: AuditClient(
                url: URL(string: "https://\(name.lowercased().replacingOccurrences(of: " ", with: "-")).com")!,
                name: name
            ),
            generatedAt: .now,
            persona: .saasB2B,
            scoring: resolvedScoring,
            performance: nil,
            findings: nil,
            synthesis: "",
            quickWins: quickWins,
            strategicBets: [],
            hiddenRisks: hiddenRisks,
            pitch: "",
            mockups: []
        )
    }
}
