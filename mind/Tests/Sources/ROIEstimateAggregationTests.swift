import XCTest
@testable import AuditKit

/// v0.25 — Locks the pure aggregation helpers used by the
/// AuditSheet hero card + the Client Portal HTML hero card.
/// Every helper takes `[AuditReport.QuickWin]` and returns a
/// derived value — no IO, no actors, no async. These four tests
/// pin the contract end-to-end so a future refactor of either
/// hero rendering surface keeps the same headline numbers.
final class ROIEstimateAggregationTests: XCTestCase {

    // MARK: - Helpers

    private func qw(
        monthly: Int?,
        confidence: AuditReport.ConfidenceLevel? = nil
    ) -> AuditReport.QuickWin {
        AuditReport.QuickWin(
            title: "QW",
            detail: "—",
            effortDays: 1,
            impact: .medium,
            estimatedMonthlyRevenueImpactEUR: monthly,
            confidence: confidence
        )
    }

    // MARK: - The four pure aggregation contracts

    /// Total = sum of per-QW non-nil impacts. The hero card reads
    /// this verbatim so any drift here surfaces directly in the
    /// "+€18 700/mo" headline.
    func test_total_isSumOfPerQuickWinMonthlyImpacts() {
        let wins = [
            qw(monthly: 2_400),
            qw(monthly: 6_300),
            qw(monthly: 10_000),
        ]
        XCTAssertEqual(ROIPromptBuilder.monthlyTotalEUR(for: wins), 18_700)
    }

    /// Annualised = monthly total × 12. The methodology modal
    /// surfaces this on the same modal as the hero number.
    func test_annualised_isMonthlyTotalTimesTwelve() {
        let wins = [qw(monthly: 1_500), qw(monthly: 2_000)]
        XCTAssertEqual(ROIPromptBuilder.annualisedTotalEUR(for: wins), 3_500 * 12)
    }

    /// Nil-impact QWs are skipped — a slow LLM that hasn't
    /// returned yet for one QW must not drop the total to zero
    /// or surface a placeholder in the hero.
    func test_total_excludesNilImpactsFromSum() {
        let wins = [
            qw(monthly: nil),
            qw(monthly: 4_000),
            qw(monthly: nil),
            qw(monthly: 1_000),
        ]
        XCTAssertEqual(ROIPromptBuilder.monthlyTotalEUR(for: wins), 5_000)
    }

    /// Aggregate confidence = the minimum across non-nil-impact
    /// QWs. A hero card claiming "high confidence" when one of
    /// the estimates was "low" would be dishonest, so we take
    /// the floor — `.low` < `.medium` < `.high`.
    func test_confidenceAggregate_isMinAcrossNonNilWins() {
        let wins = [
            qw(monthly: 4_000, confidence: .high),
            qw(monthly: 2_000, confidence: .low),
            qw(monthly: 1_000, confidence: .medium),
            // A nil-impact win with a confidence value must NOT
            // drag the aggregate down — only contributing wins
            // count.
            qw(monthly: nil, confidence: .low),
        ]
        XCTAssertEqual(
            ROIPromptBuilder.aggregateConfidence(for: wins),
            .low,
            "Aggregate must be the floor of the contributing wins' confidence"
        )
    }
}
