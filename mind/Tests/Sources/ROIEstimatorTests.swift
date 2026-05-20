import XCTest
@testable import AuditKit

/// v0.25 — Locks the pure `ROIPromptBuilder` shipped with the ROI
/// Calculator. The `ROIEstimator` actor's HTTP path cannot be
/// exercised from a hosted unit test (no Anthropic key in CI), so
/// the contract covered here is everything observable from the
/// builder: the prompt body, the QW cap, the placeholder
/// fallbacks, the JSON payload mapping, and the determinism of
/// the formatter for identical inputs.
final class ROIEstimatorTests: XCTestCase {

    // MARK: - Fixtures

    private func sampleClient(
        name: String? = "Acme Corp",
        host: String = "acme.com"
    ) -> AuditClient {
        AuditClient(
            url: URL(string: "https://\(host)")!,
            name: name
        )
    }

    private func sampleScoring() -> AuditReport.Scoring {
        AuditReport.Scoring(
            overall: 72, performance: 68, seo: 75,
            security: 88, brand: 70, mobile: 60
        )
    }

    private func sampleReport(
        clientName: String? = "Acme Corp",
        host: String = "acme.com",
        winCount: Int = 3,
        winIDs: [UUID]? = nil
    ) -> AuditReport {
        let wins: [AuditReport.QuickWin] = (0..<winCount).map { idx in
            let id = winIDs?[idx] ?? UUID()
            return AuditReport.QuickWin(
                id: id,
                title: "Quick win \(idx + 1)",
                detail: "Detail of win \(idx + 1) — concrete action to ship.",
                effortDays: Double(idx + 1) * 0.5,
                impact: (idx == 0) ? .high : (idx == 1 ? .medium : .low)
            )
        }
        return AuditReport(
            client: sampleClient(name: clientName, host: host),
            persona: .saasB2B,
            scoring: sampleScoring(),
            performance: nil,
            synthesis: "Synthesis copy.",
            quickWins: wins,
            strategicBets: [],
            pitch: "Hi team,\n\nMehdi"
        )
    }

    // MARK: - Prompt builder — structural anchors

    /// The prompt must surface the client identity so Claude
    /// grounds the ROI in the actual prospect, not a generic SaaS
    /// average.
    func test_build_includesClientNameAndHost() {
        let prompt = ROIPromptBuilder.build(
            report: sampleReport(),
            context: .unknown
        )
        XCTAssertTrue(prompt.contains("Acme Corp"),
                      "Client name must appear in the prompt body")
        XCTAssertTrue(prompt.contains("acme.com"),
                      "Host must appear in the prompt body")
    }

    /// Every Quick Win title must be threaded into the prompt
    /// verbatim — that's what Claude uses to attribute the
    /// per-win conversion lift.
    func test_build_includesAllQuickWinTitles() {
        let prompt = ROIPromptBuilder.build(
            report: sampleReport(winCount: 5),
            context: .unknown
        )
        for idx in 1...5 {
            XCTAssertTrue(
                prompt.contains("Quick win \(idx)"),
                "QW #\(idx) title must appear in the prompt body"
            )
        }
    }

    /// The response must be JSON-only. Locking the "JSON" clause
    /// + the schema shape prevents a future prompt edit from
    /// silently breaking the decoder.
    func test_build_asksForJSONOutput() {
        let prompt = ROIPromptBuilder.build(
            report: sampleReport(),
            context: .unknown
        )
        XCTAssertTrue(prompt.contains("STRICTLY with valid JSON"),
                      "Prompt must instruct the model to return JSON only")
        XCTAssertTrue(prompt.contains("\"monthlyRevenueImpactEUR\""),
                      "Schema field name must be locked in the prompt")
        XCTAssertTrue(prompt.contains("\"confidence\""),
                      "Schema field name must be locked in the prompt")
    }

    /// When an industry hint is provided, it must appear so
    /// Claude tilts its estimate toward the right baseline.
    func test_build_includesIndustryWhenProvided() {
        let prompt = ROIPromptBuilder.build(
            report: sampleReport(),
            context: ClientContext(industry: "fintech")
        )
        XCTAssertTrue(prompt.contains("fintech"),
                      "Provided industry must appear in the context block")
    }

    /// Both traffic and ARPU must appear verbatim when provided,
    /// so Claude can ground the estimate instead of guessing.
    func test_build_includesTrafficAndARPUWhenProvided() {
        let prompt = ROIPromptBuilder.build(
            report: sampleReport(),
            context: ClientContext(
                industry: "saas-b2b",
                estimatedMonthlyTraffic: 42_000,
                estimatedARPU_EUR: 89
            )
        )
        XCTAssertTrue(prompt.contains("42000"),
                      "Estimated traffic must be rendered as a raw integer in the prompt")
        XCTAssertTrue(prompt.contains("89"),
                      "Estimated ARPU must be rendered as a raw integer in the prompt")
    }

    /// When context is nil, the prompt must fall back to the
    /// "unknown — infer" placeholders so Claude knows to use
    /// industry priors instead of a literal "unknown" string.
    func test_build_fallsBackToUnknownPlaceholdersWhenContextNil() {
        let prompt = ROIPromptBuilder.build(
            report: sampleReport(),
            context: .unknown
        )
        XCTAssertTrue(prompt.contains("Industry: unknown"),
                      "Industry must fall back to 'unknown' placeholder")
        XCTAssertTrue(prompt.contains("Estimated monthly traffic: unknown"),
                      "Traffic must fall back to 'unknown' placeholder")
        XCTAssertTrue(prompt.contains("Estimated ARPU (EUR / customer): unknown"),
                      "ARPU must fall back to 'unknown' placeholder")
    }

    /// More than `maxQuickWins` quick wins → the selector caps at
    /// the configured maximum so a noisy audit doesn't blow the
    /// token budget. Priority order is preserved.
    func test_selectQuickWins_capsAtMaximum() {
        let wins = (0..<15).map { idx in
            AuditReport.QuickWin(
                title: "QW \(idx)",
                detail: "Detail \(idx)",
                effortDays: 1,
                impact: .medium
            )
        }
        let selected = ROIPromptBuilder.selectQuickWins(wins)
        XCTAssertEqual(selected.count, ROIPromptBuilder.maxQuickWins,
                       "Selector must hard-cap at \(ROIPromptBuilder.maxQuickWins) wins")
        XCTAssertEqual(selected.first?.title, "QW 0",
                       "Selector must preserve priority order — top N = first N")
    }

    /// Empty Quick Wins list returns an empty array — the
    /// estimator short-circuits on this case before even firing
    /// the network call.
    func test_selectQuickWins_emptyReturnsEmpty() {
        XCTAssertTrue(ROIPromptBuilder.selectQuickWins([]).isEmpty)
    }

    /// The prompt must be deterministic for identical inputs.
    /// Future caching depends on this property; a non-deterministic
    /// builder would silently bust the cache on every call.
    func test_build_isDeterministicForSameInput() {
        let id = UUID()
        let report = sampleReport(winCount: 3, winIDs: [id, id, id])
        let context = ClientContext(
            industry: "fintech",
            estimatedMonthlyTraffic: 1_000,
            estimatedARPU_EUR: 50
        )
        let a = ROIPromptBuilder.build(report: report, context: context)
        let b = ROIPromptBuilder.build(report: report, context: context)
        XCTAssertEqual(a, b,
                       "Builder must be pure — identical inputs → identical prompt")
    }

    /// Caps stay enforced in the prompt body itself — the "max 10"
    /// substring is what reminds Claude not to extrapolate over
    /// missing QWs.
    func test_build_includesMaxQuickWinsHintInPrompt() {
        let prompt = ROIPromptBuilder.build(
            report: sampleReport(),
            context: .unknown
        )
        XCTAssertTrue(
            prompt.contains("max \(ROIPromptBuilder.maxQuickWins)"),
            "Prompt must reference the QW cap so Claude knows how many to estimate"
        )
    }

    // MARK: - Aggregation helpers

    /// Total = sum of every non-nil monthly impact. Mirrors what
    /// the hero card renders, so a regression here would silently
    /// drift the "+€18 700/mo" headline.
    func test_aggregation_totalIsSumOfNonNilImpacts() {
        let wins = [
            quickWin(monthly: 2_400),
            quickWin(monthly: 6_300),
            quickWin(monthly: 10_000),
        ]
        XCTAssertEqual(ROIPromptBuilder.monthlyTotalEUR(for: wins), 18_700)
    }

    /// Annualised = monthly total × 12. The methodology modal +
    /// the portal subtitle both consume this value.
    func test_aggregation_annualisedIsMonthlyTimesTwelve() {
        let wins = [
            quickWin(monthly: 2_400),
            quickWin(monthly: 6_300),
        ]
        let monthly = ROIPromptBuilder.monthlyTotalEUR(for: wins)
        XCTAssertEqual(ROIPromptBuilder.annualisedTotalEUR(for: wins), monthly * 12)
        XCTAssertEqual(ROIPromptBuilder.annualisedTotalEUR(for: wins), 104_400)
    }

    /// Nil impacts are excluded from the sum. A QW that the
    /// estimator hasn't reached yet (slow LLM, dropped network)
    /// must not deflate the total to zero.
    func test_aggregation_excludesNilImpactsFromSum() {
        let wins = [
            quickWin(monthly: 4_000),
            quickWin(monthly: nil),
            quickWin(monthly: 1_000),
        ]
        XCTAssertEqual(ROIPromptBuilder.monthlyTotalEUR(for: wins), 5_000)
    }

    /// Confidence aggregate = the most conservative level. A
    /// hero card claiming "high confidence" when one estimate is
    /// "low" would be dishonest, so we take the floor.
    func test_aggregation_confidenceIsMinAcrossNonNilWins() {
        let wins = [
            quickWin(monthly: 4_000, confidence: .high),
            quickWin(monthly: 1_000, confidence: .low),
            quickWin(monthly: 2_000, confidence: .medium),
        ]
        XCTAssertEqual(
            ROIPromptBuilder.aggregateConfidence(for: wins),
            .low,
            "Aggregate confidence must be the most conservative across non-nil wins"
        )
    }

    // MARK: - Payload mapping

    /// Decoded payload maps cleanly into a `[UUID: ROIEstimate]`
    /// dictionary so the controller can fold values back into the
    /// live report by id.
    func test_mapPayload_foldsKnownIDsIntoEstimates() {
        let id = UUID()
        let wins = [
            AuditReport.QuickWin(
                id: id,
                title: "T", detail: "D",
                effortDays: 1, impact: .high
            )
        ]
        let payload = ROIPromptBuilder.Payload(estimates: [
            .init(
                id: id.uuidString,
                monthlyRevenueImpactEUR: 2_400,
                confidence: "high",
                reasoning: "1.5% lift × 10k traffic × 16 EUR ARPU."
            )
        ])
        let mapped = ROIPromptBuilder.mapPayload(payload, into: wins)
        XCTAssertEqual(mapped[id]?.monthlyRevenueImpactEUR, 2_400)
        XCTAssertEqual(mapped[id]?.confidence, .high)
    }

    /// Unknown IDs in the payload are dropped silently (Claude
    /// occasionally hallucinates an extra id; we'd rather lose
    /// the badge than crash the audit flow).
    func test_mapPayload_dropsUnknownIDs() {
        let known = UUID()
        let wins = [AuditReport.QuickWin(
            id: known, title: "T", detail: "D",
            effortDays: 1, impact: .medium
        )]
        let payload = ROIPromptBuilder.Payload(estimates: [
            .init(id: UUID().uuidString,
                  monthlyRevenueImpactEUR: 5_000,
                  confidence: "high",
                  reasoning: "—"),
            .init(id: known.uuidString,
                  monthlyRevenueImpactEUR: 1_000,
                  confidence: "medium",
                  reasoning: "—"),
        ])
        let mapped = ROIPromptBuilder.mapPayload(payload, into: wins)
        XCTAssertEqual(mapped.count, 1,
                       "Unknown UUIDs must be dropped from the mapping")
        XCTAssertNotNil(mapped[known])
    }

    /// Impacts > 30 000 EUR / month are clamped down so a single
    /// optimistic estimate can't dominate the hero total.
    func test_mapPayload_clampsImpactsAboveCap() {
        let id = UUID()
        let wins = [AuditReport.QuickWin(
            id: id, title: "T", detail: "D",
            effortDays: 1, impact: .high
        )]
        let payload = ROIPromptBuilder.Payload(estimates: [
            .init(id: id.uuidString,
                  monthlyRevenueImpactEUR: 999_999,
                  confidence: "high",
                  reasoning: "—")
        ])
        let mapped = ROIPromptBuilder.mapPayload(payload, into: wins)
        XCTAssertEqual(mapped[id]?.monthlyRevenueImpactEUR, 30_000,
                       "Estimates above 30k EUR/mo must be clamped down")
    }

    // MARK: - Helpers

    private func quickWin(
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
}
