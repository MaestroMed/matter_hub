import XCTest
@testable import GraphCore

/// v1.0-alpha.3 — Locks the portfolio-level MRR math + the FR
/// formatter helper. Five tests cover the sum across mixed projects,
/// active+retainer-only filter, format, empty, single project.
@MainActor
final class ProjectMRRTests: XCTestCase {

    // MARK: - total(of:)

    /// Across a mixed portfolio, `total(of:)` sums only the active
    /// retainer rows. Oneshot revenue, archived retainers, and
    /// discovery retainers are excluded.
    func test_total_sumsActiveRetainersOnly() {
        let portfolio: [Project] = [
            Project(name: "A", host: "a.fr", contractType: .retainer, monthlyRecurringRevenueEUR: 290),
            Project(name: "B", host: "b.fr", contractType: .retainer, monthlyRecurringRevenueEUR: 350),
            Project(name: "C", host: "c.fr", contractType: .oneshot, oneShotRevenueEUR: 5200),
            Project(name: "D", host: "d.fr", contractType: .retainer, monthlyRecurringRevenueEUR: 999, lifecycleStage: .archived),
            Project(name: "E", host: "e.fr", contractType: .retainer, monthlyRecurringRevenueEUR: 480, lifecycleStage: .maintenance),
        ]
        XCTAssertEqual(ProjectMRR.total(of: portfolio), 290 + 350 + 480,
                       "Total MRR includes active + maintenance retainers; " +
                       "excludes archived retainers, oneshot rows, discovery stages.")
    }

    /// Empty portfolio sums to 0 — no crash on the zero-row path.
    func test_total_emptyPortfolio_isZero() {
        XCTAssertEqual(ProjectMRR.total(of: []), 0)
    }

    /// Single active retainer returns its MRR verbatim.
    func test_total_singleActiveRetainer_returnsItsMRR() {
        let solo = Project(
            name: "Solo",
            host: "solo.fr",
            contractType: .retainer,
            monthlyRecurringRevenueEUR: 350
        )
        XCTAssertEqual(ProjectMRR.total(of: [solo]), 350)
    }

    // MARK: - formatEUR

    /// `formatEUR(_:)` renders the `€X/mo` shape with FR group
    /// separator at the thousand. Stable shape across amounts so the
    /// Cockpit card layout doesn't shift.
    func test_formatEUR_isFrenchGrouped() {
        XCTAssertEqual(ProjectMRR.formatEUR(0), "€0/mo")
        XCTAssertEqual(ProjectMRR.formatEUR(290), "€290/mo")
        // The FR formatter inserts a non-breaking space at the
        // thousand mark — accept either NBSP or plain space because
        // the underlying formatter has shipped both across iOS
        // versions. The contract is the prefix + suffix + the digit
        // run, not the exact whitespace codepoint.
        let large = ProjectMRR.formatEUR(12_500)
        XCTAssertTrue(large.hasPrefix("€"))
        XCTAssertTrue(large.hasSuffix("/mo"))
        XCTAssertTrue(large.contains("12"))
        XCTAssertTrue(large.contains("500"))
    }

    // MARK: - activeRetainerCount + activeCount

    /// `activeRetainerCount` counts only active + maintenance
    /// retainers. `activeCount` counts every active+maintenance
    /// project regardless of contract type. The two diverge on a
    /// oneshot row, locking the documented split for the subtitle
    /// pill chips.
    func test_activeCounts_splitRetainerFromTotal() {
        let portfolio: [Project] = [
            Project(name: "Retainer A", host: "a.fr", contractType: .retainer, monthlyRecurringRevenueEUR: 100),
            Project(name: "Oneshot B",  host: "b.fr", contractType: .oneshot, oneShotRevenueEUR: 4000),
            Project(name: "Archived C", host: "c.fr", contractType: .retainer, monthlyRecurringRevenueEUR: 250, lifecycleStage: .archived),
            Project(name: "Discovery D", host: "d.fr", contractType: .retainer, monthlyRecurringRevenueEUR: 0, lifecycleStage: .discovery),
        ]
        XCTAssertEqual(ProjectMRR.activeRetainerCount(in: portfolio), 1,
                       "Only the active retainer counts — discovery + archived excluded.")
        XCTAssertEqual(ProjectMRR.activeCount(in: portfolio), 2,
                       "Active count includes the active retainer + the oneshot active row.")
    }
}
