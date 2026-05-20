import XCTest
@testable import GraphCore

/// v1.0-alpha.13 — Locks the pure parts of the Sales Velocity
/// dashboard. The SwiftUI rendering itself is exercised by the
/// vision-verify simulator screenshot; the math + bucket shape is
/// covered here.
final class SalesVelocityCalculatorTests: XCTestCase {

    // MARK: - Fixtures

    @MainActor
    private func makeProject(
        name: String = "Acme",
        host: String = "acme.com",
        mrr: Int = 0,
        contractType: ProjectContractType = .oneshot,
        lifecycleStage: ProjectLifecycleStage = .active,
        startedDaysAgo: Int = 30
    ) -> Project {
        let calendar = Calendar(identifier: .gregorian)
        let startedAt = calendar.date(byAdding: .day, value: -startedDaysAgo, to: .now) ?? .now
        return Project(
            name: name,
            host: host,
            contractType: contractType,
            monthlyRecurringRevenueEUR: mrr,
            oneShotRevenueEUR: 0,
            lifecycleStage: lifecycleStage,
            startedAt: startedAt
        )
    }

    @MainActor
    private func makeLead(
        status: LeadStatus = .new,
        receivedDaysAgo: Int = 0
    ) -> Lead {
        let calendar = Calendar(identifier: .gregorian)
        let receivedAt = calendar.date(byAdding: .day, value: -receivedDaysAgo, to: .now) ?? .now
        return Lead(
            receivedAt: receivedAt,
            status: status
        )
    }

    // MARK: - MRR history

    @MainActor
    func test_monthlyMRRHistory_emptyProjects_returns12Zeros() {
        let history = SalesVelocityCalculator.monthlyMRRHistory(projects: [])
        XCTAssertEqual(history.count, 12)
        for point in history {
            XCTAssertEqual(point.mrrEUR, 0)
        }
    }

    @MainActor
    func test_monthlyMRRHistory_singleRetainerAtCurrentMonth() {
        let project = makeProject(
            mrr: 500,
            contractType: .retainer,
            startedDaysAgo: 0
        )
        let history = SalesVelocityCalculator.monthlyMRRHistory(projects: [project])
        XCTAssertEqual(history.count, 12)
        // The latest point (last in the array) must reflect the
        // active retainer's MRR.
        XCTAssertEqual(history.last?.mrrEUR, 500)
    }

    @MainActor
    func test_monthlyMRRHistory_oneshotProjectsExcluded() {
        let retainer1 = makeProject(mrr: 300, contractType: .retainer, startedDaysAgo: 0)
        let retainer2 = makeProject(mrr: 200, contractType: .retainer, startedDaysAgo: 0)
        let oneshot   = makeProject(mrr: 10_000, contractType: .oneshot, startedDaysAgo: 0)
        let history = SalesVelocityCalculator.monthlyMRRHistory(
            projects: [retainer1, retainer2, oneshot]
        )
        XCTAssertEqual(history.last?.mrrEUR, 500,
                       "Oneshot rows must never contribute to MRR")
    }

    @MainActor
    func test_monthlyMRRHistory_ordersAscendingByDate() {
        let project = makeProject(mrr: 100, contractType: .retainer, startedDaysAgo: 365)
        let history = SalesVelocityCalculator.monthlyMRRHistory(projects: [project])
        guard history.count >= 2 else {
            XCTFail("Expected ≥ 2 history points")
            return
        }
        for i in 1 ..< history.count {
            XCTAssertLessThanOrEqual(
                history[i - 1].monthStart,
                history[i].monthStart,
                "MRR history must be ordered oldest → newest"
            )
        }
    }

    // MARK: - Weekly leads

    @MainActor
    func test_weeklyLeads_emptyLeads_returns12Zeros() {
        let points = SalesVelocityCalculator.weeklyLeads(leads: [])
        XCTAssertEqual(points.count, 12)
        for point in points {
            XCTAssertEqual(point.count, 0)
        }
    }

    @MainActor
    func test_weeklyLeads_currentWeekLeadCountsOnLatestBucket() {
        let lead = makeLead(receivedDaysAgo: 0)
        let points = SalesVelocityCalculator.weeklyLeads(leads: [lead])
        XCTAssertEqual(points.count, 12)
        XCTAssertEqual(points.last?.count, 1)
    }

    @MainActor
    func test_weeklyLeads_distributesAcrossWeeks() {
        let recent = makeLead(receivedDaysAgo: 2)
        let older = makeLead(receivedDaysAgo: 20)
        let points = SalesVelocityCalculator.weeklyLeads(leads: [recent, older])
        // Sum equals total leads regardless of bucket boundary
        // gymnastics.
        let sum = points.reduce(0) { $0 + $1.count }
        XCTAssertEqual(sum, 2)
    }

    // MARK: - Conversion rate

    @MainActor
    func test_conversionRate_fourWonOutOfTen_returns0_4() {
        var leads: [Lead] = []
        for _ in 0 ..< 4 { leads.append(makeLead(status: .won, receivedDaysAgo: 1)) }
        for _ in 0 ..< 4 { leads.append(makeLead(status: .lost, receivedDaysAgo: 2)) }
        for _ in 0 ..< 2 { leads.append(makeLead(status: .new, receivedDaysAgo: 3)) }
        let rate = SalesVelocityCalculator.conversionRate(leads: leads, lastWeeks: 4)
        XCTAssertEqual(rate, 0.4, accuracy: 0.001)
    }

    @MainActor
    func test_conversionRate_emptyLeads_returns0() {
        let rate = SalesVelocityCalculator.conversionRate(leads: [])
        XCTAssertEqual(rate, 0.0)
    }

    @MainActor
    func test_conversionRate_allSpam_returns0() {
        let leads = (0 ..< 5).map { _ in makeLead(status: .spam, receivedDaysAgo: 1) }
        let rate = SalesVelocityCalculator.conversionRate(leads: leads)
        XCTAssertEqual(rate, 0.0,
                       "Spam-only window must return 0 — every lead excluded from processed bucket")
    }

    // MARK: - Funnel distribution

    @MainActor
    func test_funnelDistribution_sumsToLeadsCount() {
        let leads = [
            makeLead(status: .new),
            makeLead(status: .new),
            makeLead(status: .contacted),
            makeLead(status: .qualified),
            makeLead(status: .won),
            makeLead(status: .lost),
            makeLead(status: .spam),
        ]
        let funnel = SalesVelocityCalculator.funnelDistribution(leads: leads)
        let sum = funnel.reduce(0) { $0 + $1.count }
        XCTAssertEqual(sum, leads.count)
    }

    @MainActor
    func test_funnelDistribution_everyStageNonNegative() {
        let leads = (0 ..< 3).map { _ in makeLead(status: .new) }
        let funnel = SalesVelocityCalculator.funnelDistribution(leads: leads)
        for stage in funnel {
            XCTAssertGreaterThanOrEqual(stage.count, 0)
        }
    }

    @MainActor
    func test_funnelDistribution_returnsAllSixStagesEvenWhenEmpty() {
        let funnel = SalesVelocityCalculator.funnelDistribution(leads: [])
        XCTAssertEqual(funnel.count, 6,
                       "Funnel must always render 6 stages: new/contacted/qualified/won/lost/spam")
        for stage in funnel {
            XCTAssertEqual(stage.count, 0)
        }
    }

    @MainActor
    func test_funnelDistribution_isDeterministicForSameInput() {
        let leads = [
            makeLead(status: .new),
            makeLead(status: .won),
        ]
        let a = SalesVelocityCalculator.funnelDistribution(leads: leads)
        let b = SalesVelocityCalculator.funnelDistribution(leads: leads)
        // Compare ignoring UUIDs — count-by-stage shape must match.
        XCTAssertEqual(
            a.map { [$0.stage: $0.count] },
            b.map { [$0.stage: $0.count] }
        )
    }
}
