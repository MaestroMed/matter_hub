import XCTest
@testable import AuditKit

/// v0.24 — Covers the pure `BattleReport.derive(from:)` builder
/// that powers the per-metric podium in `BattleSheet` and in the
/// Battle section of the client portal HTML. Network-driven
/// behaviour (the parallel TaskGroup) is intentionally left
/// untested — every assertion here is on the pure value
/// derivation so the suite stays deterministic.
final class BattleReportTests: XCTestCase {

    // MARK: - Fixture helpers

    private func client(_ host: String) -> AuditClient {
        AuditClient(url: URL(string: "https://\(host)")!, name: host)
    }

    private func participant(
        host: String,
        scoring: AuditReport.Scoring
    ) -> BattleController.Participant {
        let c = client(host)
        let report = AuditReport(
            client: c,
            persona: .saasB2B,
            scoring: scoring,
            performance: nil,
            synthesis: "synth",
            quickWins: [],
            strategicBets: [],
            pitch: "pitch"
        )
        return BattleController.Participant(
            client: c,
            report: report,
            phase: .completed
        )
    }

    private func unresolved(host: String) -> BattleController.Participant {
        BattleController.Participant(client: client(host), phase: .probing)
    }

    private func failed(host: String) -> BattleController.Participant {
        BattleController.Participant(
            client: client(host),
            error: "boom",
            phase: .failed
        )
    }

    private func scoring(
        overall: Int = 0, perf: Int = 0, seo: Int = 0,
        security: Int = 0, brand: Int = 0, mobile: Int = 0
    ) -> AuditReport.Scoring {
        AuditReport.Scoring(
            overall: overall,
            performance: perf,
            seo: seo,
            security: security,
            brand: brand,
            mobile: mobile
        )
    }

    // MARK: - Winners derivation

    /// Two participants, distinct scores — the higher one wins
    /// each metric. The most basic battle: Stripe vs Mollie.
    func test_winners_derivePerMetricForTwoContenders() {
        let stripe = participant(host: "stripe.com", scoring: scoring(
            overall: 88, perf: 92, seo: 80, security: 95, brand: 87, mobile: 90
        ))
        let mollie = participant(host: "mollie.com", scoring: scoring(
            overall: 70, perf: 75, seo: 88, security: 60, brand: 72, mobile: 78
        ))
        let report = BattleReport.derive(from: [stripe, mollie])

        XCTAssertEqual(report.winners[.overall]?.displayName,     "stripe.com")
        XCTAssertEqual(report.winners[.performance]?.displayName, "stripe.com")
        XCTAssertEqual(report.winners[.seo]?.displayName,         "mollie.com")
        XCTAssertEqual(report.winners[.security]?.displayName,    "stripe.com")
        XCTAssertEqual(report.winners[.brand]?.displayName,       "stripe.com")
        XCTAssertEqual(report.winners[.mobile]?.displayName,      "stripe.com")
    }

    /// Ties resolve deterministically by participant order — the
    /// first one in the input list wins the metric. Mirrors the on-
    /// screen rendering order (primary first, competitors after).
    func test_ties_areBrokenByFirstInList() {
        let a = participant(host: "a.com", scoring: scoring(overall: 80, perf: 80))
        let b = participant(host: "b.com", scoring: scoring(overall: 80, perf: 80))
        let report = BattleReport.derive(from: [a, b])
        XCTAssertEqual(report.winners[.overall]?.displayName, "a.com")
        XCTAssertEqual(report.winners[.performance]?.displayName, "a.com")
    }

    /// When every resolved participant scored 0 on a metric, that
    /// metric stays out of the winners table — the podium row
    /// renders an em dash instead of awarding a meaningless badge.
    func test_allZeroMetric_returnsNoWinner() {
        let a = participant(host: "a.com", scoring: scoring(overall: 50, perf: 0))
        let b = participant(host: "b.com", scoring: scoring(overall: 60, perf: 0))
        let report = BattleReport.derive(from: [a, b])
        XCTAssertNil(report.winners[.performance])
        // The overall axis still has a winner — independence check.
        XCTAssertEqual(report.winners[.overall]?.displayName, "b.com")
    }

    /// One participant — they win every axis where they scored
    /// above zero. The radar still renders a single polygon and
    /// the podium awards them all six trophies.
    func test_singleParticipant_winsEveryNonZeroMetric() {
        let solo = participant(host: "solo.com", scoring: scoring(
            overall: 70, perf: 60, seo: 50, security: 40, brand: 30, mobile: 20
        ))
        let report = BattleReport.derive(from: [solo])
        for metric in BattleReport.Metric.allCases {
            XCTAssertEqual(
                report.winners[metric]?.displayName,
                "solo.com",
                "Expected solo to win \(metric.rawValue)"
            )
        }
    }

    /// Four participants × six metrics → at most 24 winner entries,
    /// and every winning client comes from the input list. Locks
    /// the "real-world battle" shape so a regression in
    /// `derive(from:)` showing up as a wrong-sized winners map
    /// surfaces as a test failure.
    func test_fourParticipants_winnersAreAllFromInput() {
        let s = participant(host: "stripe.com",   scoring: scoring(overall: 88, perf: 92, seo: 80, security: 95, brand: 87, mobile: 90))
        let a = participant(host: "adyen.com",    scoring: scoring(overall: 86, perf: 90, seo: 78, security: 92, brand: 84, mobile: 88))
        let m = participant(host: "mollie.com",   scoring: scoring(overall: 70, perf: 75, seo: 88, security: 60, brand: 72, mobile: 78))
        let c = participant(host: "checkout.com", scoring: scoring(overall: 80, perf: 82, seo: 70, security: 86, brand: 79, mobile: 81))
        let report = BattleReport.derive(from: [s, a, m, c])

        XCTAssertLessThanOrEqual(report.winners.count, 6)
        let allowedHosts: Set<String> = ["stripe.com", "adyen.com", "mollie.com", "checkout.com"]
        for (_, winner) in report.winners {
            XCTAssertTrue(allowedHosts.contains(winner.displayName))
        }
    }

    /// Unresolved (still-probing) and failed participants are
    /// excluded from the comparison — a failed audit can't
    /// accidentally win an axis because it left `report = nil`,
    /// and a still-running one shouldn't claim a trophy mid-flight.
    func test_unresolvedAndFailedParticipants_areExcluded() {
        let live = participant(host: "live.com", scoring: scoring(overall: 50))
        let stillRunning = unresolved(host: "running.com")
        let dead = failed(host: "dead.com")
        let report = BattleReport.derive(from: [stillRunning, live, dead])
        XCTAssertEqual(report.winners[.overall]?.displayName, "live.com")
        for metric in BattleReport.Metric.allCases where metric != .overall {
            XCTAssertNil(
                report.winners[metric],
                "Expected no winner on \(metric.rawValue) — all-zero axis"
            )
        }
    }
}
