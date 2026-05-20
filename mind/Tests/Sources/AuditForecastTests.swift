import XCTest
@testable import AuditKit

/// v0.31.1 — Locks the pure derivation contract of
/// `AuditForecaster.forecast(for:)`. The forecaster is the single
/// surface every future UI affordance (AuditSheet trend row,
/// ComparisonSheet forecast column, ClientPortal HTML template) reads,
/// so every regression in this file reflects a regression a user
/// would see — wrong delta sign, ghost projection, drifted baseline.
final class AuditForecastTests: XCTestCase {

    // MARK: - Empty / degenerate inputs

    /// A report whose three load-bearing scores are all zero produced
    /// an empty forecast — the audit never landed real data, so the UI
    /// hides the card instead of surfacing a misleading projection.
    func test_forecast_allZeroScoring_returnsEmptyForecast() {
        let report = makeReport(
            persona: .tpePme,
            scoring: .init(overall: 0, performance: 0, seo: 0, security: 0, brand: 0, mobile: 0)
        )
        let forecast = AuditForecaster.forecast(for: report)
        XCTAssertTrue(forecast.isEmpty)
        XCTAssertEqual(forecast.projections.count, 0)
        XCTAssertEqual(forecast.clientName, report.client.displayName)
        XCTAssertEqual(forecast.persona, .tpePme)
        XCTAssertEqual(forecast.generatedAt, report.generatedAt)
    }

    /// A report with at least one non-zero load-bearing score lands a
    /// full 3-projection forecast.
    func test_forecast_nonZeroScoring_returnsThreeProjections() {
        let report = makeReport(
            persona: .saasB2B,
            scoring: .init(overall: 60, performance: 50, seo: 0, security: 70, brand: 60, mobile: 60)
        )
        let forecast = AuditForecaster.forecast(for: report)
        XCTAssertFalse(forecast.isEmpty)
        XCTAssertEqual(forecast.projections.count, 3)
        XCTAssertEqual(
            forecast.projections.map(\.metric),
            [.performance, .seo, .security]
        )
    }

    // MARK: - Persona baselines

    /// Persona baselines are surfaced via the public `baseline(for:)`
    /// helper so the UI can render a methodology disclosure. The
    /// values are the v0.31.1 published anchors — locking them here
    /// makes any silent drift loud.
    func test_baseline_perPersonaReturnsDocumentedValues() {
        let saas = AuditForecaster.baseline(for: .saasB2B)
        XCTAssertEqual(saas.performance, 82)
        XCTAssertEqual(saas.seo, 80)
        XCTAssertEqual(saas.security, 85)

        let tpe = AuditForecaster.baseline(for: .tpePme)
        XCTAssertEqual(tpe.performance, 65)
        XCTAssertEqual(tpe.seo, 60)
        XCTAssertEqual(tpe.security, 55)

        let dtc = AuditForecaster.baseline(for: .lifestyleDTC)
        XCTAssertEqual(dtc.performance, 75)
        XCTAssertEqual(dtc.seo, 72)
        XCTAssertEqual(dtc.security, 68)

        let other = AuditForecaster.baseline(for: .other)
        XCTAssertEqual(other.performance, 70)
        XCTAssertEqual(other.seo, 68)
        XCTAssertEqual(other.security, 65)
    }

    /// `baseline.score(for:)` reads the right field per metric. Keeps
    /// the forecaster loop short and lets the test target lock the
    /// enum-to-field mapping without reaching into private state.
    func test_baseline_scoreAccessor_routesEnumToField() {
        let b = AuditForecaster.Baseline(performance: 11, seo: 22, security: 33)
        XCTAssertEqual(b.score(for: .performance), 11)
        XCTAssertEqual(b.score(for: .seo), 22)
        XCTAssertEqual(b.score(for: .security), 33)
    }

    // MARK: - Convergence math

    /// A site scoring below baseline converges 40 % of the gap upward
    /// over one quarter. TPE/PME baseline perf = 65; current = 50;
    /// gap = +15; projection = 50 + 6 = 56.
    func test_projectScore_belowBaseline_convergesUp() {
        let projected = AuditForecaster.projectScore(current: 50, baseline: 65)
        XCTAssertEqual(projected, 56)  // 50 + (15 * 0.40) = 56.0
    }

    /// A site scoring above baseline regresses 15 % of the gap
    /// downward — high performers maintain their lead with smaller
    /// drift. SaaS B2B baseline perf = 82; current = 95; gap = -13;
    /// projection = 95 + (-13 * 0.15) = 95 - 1.95 = 93.05 → 93.
    func test_projectScore_aboveBaseline_regressesSlightly() {
        let projected = AuditForecaster.projectScore(current: 95, baseline: 82)
        XCTAssertEqual(projected, 93)
    }

    /// A site already at baseline has zero gap → zero projection
    /// change. Locks the "no-op at baseline" invariant.
    func test_projectScore_atBaseline_staysSame() {
        XCTAssertEqual(AuditForecaster.projectScore(current: 65, baseline: 65), 65)
        XCTAssertEqual(AuditForecaster.projectScore(current: 0, baseline: 0), 0)
        XCTAssertEqual(AuditForecaster.projectScore(current: 100, baseline: 100), 100)
    }

    /// Projection is clamped to [0, 100]. A current=98 below a
    /// hypothetical baseline=200 would compute 98 + 40.8 = 138.8 — the
    /// clamp must cap at 100 so the UI never renders an out-of-range
    /// score. The forecaster's documented input range stops at 100
    /// but the clamp guards against future baseline tweaks.
    func test_projectScore_clampsAtUpperBound() {
        XCTAssertEqual(AuditForecaster.projectScore(current: 98, baseline: 200), 100)
    }

    /// Symmetric clamp at the lower bound — a hypothetical
    /// current=2, baseline=-100 should clamp to 0 even though the
    /// math would yield 2 + (-15.3) = -13.3. Same forward-compat
    /// rationale as the upper-bound case.
    func test_projectScore_clampsAtLowerBound() {
        XCTAssertEqual(AuditForecaster.projectScore(current: 2, baseline: -100), 0)
    }

    // MARK: - Trend classification

    /// ±2 pts is plateau, ±3+ pts is up or down — the threshold
    /// matches the smallest meaningful PageSpeed Insights delta.
    func test_classify_thresholdsArePlatoBeyondTwoPoints() {
        XCTAssertEqual(AuditForecaster.classify(delta: 0), .plateau)
        XCTAssertEqual(AuditForecaster.classify(delta: 1), .plateau)
        XCTAssertEqual(AuditForecaster.classify(delta: 2), .plateau)
        XCTAssertEqual(AuditForecaster.classify(delta: -1), .plateau)
        XCTAssertEqual(AuditForecaster.classify(delta: -2), .plateau)
        XCTAssertEqual(AuditForecaster.classify(delta: 3), .improvement)
        XCTAssertEqual(AuditForecaster.classify(delta: 25), .improvement)
        XCTAssertEqual(AuditForecaster.classify(delta: -3), .decline)
        XCTAssertEqual(AuditForecaster.classify(delta: -25), .decline)
    }

    // MARK: - End-to-end forecast shape

    /// TPE/PME site scoring well below baseline projects upward on
    /// every metric. Locks the headline "small business gets upgrade
    /// path" message the UI carries.
    func test_forecast_tpePmeBelowBaseline_allMetricsImprove() {
        let report = makeReport(
            persona: .tpePme,
            scoring: .init(overall: 40, performance: 40, seo: 35, security: 30, brand: 50, mobile: 60)
        )
        let forecast = AuditForecaster.forecast(for: report)
        for projection in forecast.projections {
            XCTAssertEqual(projection.trend, .improvement, "Expected improvement on \(projection.metric)")
            XCTAssertGreaterThan(projection.delta, 0)
            XCTAssertGreaterThan(projection.projectedScore, projection.currentScore)
        }
    }

    /// A site already at its persona baseline plateaus on every
    /// metric (0 delta everywhere).
    func test_forecast_atBaseline_allMetricsPlateau() {
        let baseline = AuditForecaster.baseline(for: .tpePme)
        let report = makeReport(
            persona: .tpePme,
            scoring: .init(
                overall: 60,
                performance: baseline.performance,
                seo: baseline.seo,
                security: baseline.security,
                brand: 60,
                mobile: 60
            )
        )
        let forecast = AuditForecaster.forecast(for: report)
        for projection in forecast.projections {
            XCTAssertEqual(projection.trend, .plateau)
            XCTAssertEqual(projection.delta, 0)
            XCTAssertEqual(projection.projectedScore, projection.currentScore)
        }
    }

    /// A SaaS B2B site scoring above baseline shows a modest decline
    /// trend on metrics where the gap is wide enough to cross the
    /// ±2-pt plateau band. Perf 100 vs baseline 82 → gap -18 → delta
    /// -3 → decline.
    func test_forecast_aboveBaseline_showsDecline() {
        let report = makeReport(
            persona: .saasB2B,
            scoring: .init(overall: 95, performance: 100, seo: 100, security: 100, brand: 90, mobile: 90)
        )
        let forecast = AuditForecaster.forecast(for: report)
        let perf = forecast.projection(for: .performance)
        XCTAssertNotNil(perf)
        XCTAssertEqual(perf?.trend, .decline)
        XCTAssertLessThan(perf?.delta ?? 0, 0)
    }

    /// Forecast lookup helper resolves to the right projection — and
    /// returns nil when the forecast is empty.
    func test_projection_for_returnsRightProjectionOrNil() {
        let report = makeReport(
            persona: .saasB2B,
            scoring: .init(overall: 80, performance: 75, seo: 70, security: 65, brand: 80, mobile: 80)
        )
        let forecast = AuditForecaster.forecast(for: report)
        XCTAssertNotNil(forecast.projection(for: .performance))
        XCTAssertNotNil(forecast.projection(for: .seo))
        XCTAssertNotNil(forecast.projection(for: .security))

        let empty = AuditForecaster.forecast(for: makeReport(
            persona: .saasB2B,
            scoring: .init(overall: 0, performance: 0, seo: 0, security: 0, brand: 0, mobile: 0)
        ))
        XCTAssertNil(empty.projection(for: .performance))
    }

    // MARK: - Plain-language explanations

    /// FR explanation for an improvement bucket reads as "Performance
    /// devrait gagner ~X pts ce trimestre…". Locks the exact opener so
    /// translations don't drift.
    func test_explanationFR_improvementOpener() {
        let sentence = AuditForecaster.explanationFR(
            metric: .performance,
            delta: 5,
            baseline: 65,
            trend: .improvement
        )
        XCTAssertTrue(sentence.hasPrefix("Performance devrait gagner ~5 pts"),
                      "unexpected sentence: \(sentence)")
        XCTAssertTrue(sentence.contains("65"))
        XCTAssertTrue(sentence.hasSuffix("."))
    }

    /// Plateau sentences read as "reste stable…" and carry the
    /// baseline reference.
    func test_explanationFR_plateauOpener() {
        let sentence = AuditForecaster.explanationFR(
            metric: .seo,
            delta: 1,
            baseline: 60,
            trend: .plateau
        )
        XCTAssertTrue(sentence.contains("reste stable"))
        XCTAssertTrue(sentence.contains("60"))
        XCTAssertTrue(sentence.hasSuffix("."))
    }

    /// Decline sentences read as "risque de perdre…" so the user
    /// understands the trend is a risk, not a verdict.
    func test_explanationFR_declineOpener() {
        let sentence = AuditForecaster.explanationFR(
            metric: .security,
            delta: -4,
            baseline: 55,
            trend: .decline
        )
        XCTAssertTrue(sentence.contains("risque de perdre ~4 pts"))
        XCTAssertTrue(sentence.contains("55"))
        XCTAssertTrue(sentence.hasSuffix("."))
    }

    // MARK: - Determinism + Codable

    /// Same input always yields the same output — no Date.now capture
    /// inside the forecaster, no random jitter.
    func test_forecast_isDeterministic() {
        let report = makeReport(
            persona: .lifestyleDTC,
            scoring: .init(overall: 65, performance: 55, seo: 60, security: 50, brand: 70, mobile: 60)
        )
        let a = AuditForecaster.forecast(for: report)
        let b = AuditForecaster.forecast(for: report)
        XCTAssertEqual(a, b)
    }

    /// The forecast value type round-trips through JSON cleanly so
    /// future persistence paths (archive enrichment, ClientPortal
    /// JSON injection) stay safe.
    func test_forecast_codableRoundTrip() throws {
        let report = makeReport(
            persona: .saasB2B,
            scoring: .init(overall: 70, performance: 65, seo: 72, security: 80, brand: 70, mobile: 70)
        )
        let forecast = AuditForecaster.forecast(for: report)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(forecast)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AuditForecast.self, from: data)

        XCTAssertEqual(decoded.clientName, forecast.clientName)
        XCTAssertEqual(decoded.persona, forecast.persona)
        XCTAssertEqual(decoded.projections.count, forecast.projections.count)
        // Spot-check the first projection field-by-field — Equatable on
        // Projection covers the rest.
        XCTAssertEqual(decoded.projections.first, forecast.projections.first)
    }

    // MARK: - Public surface invariants

    /// The horizon is published as 3 months — locking it here makes
    /// any silent change loud (a 6-month or 1-month horizon would
    /// invalidate every methodology disclosure).
    func test_horizonIsThreeMonths() {
        XCTAssertEqual(AuditForecast.horizonMonths, 3)
    }

    /// The metric enum carries exactly the three load-bearing axes —
    /// performance / SEO / security. Mobile + brand are intentionally
    /// excluded. Locks the surface so future contributors don't quietly
    /// expand it without revisiting the convergence math.
    func test_metric_allCasesAreExactlyThree() {
        XCTAssertEqual(
            AuditForecast.Metric.allCases,
            [.performance, .seo, .security]
        )
    }

    // MARK: - Helpers

    private func makeReport(
        persona: AuditReport.Persona,
        scoring: AuditReport.Scoring
    ) -> AuditReport {
        AuditReport(
            client: AuditClient(
                url: URL(string: "https://example.com")!,
                name: "Example"
            ),
            generatedAt: Date(timeIntervalSince1970: 1_715_000_000),
            persona: persona,
            scoring: scoring,
            performance: nil,
            findings: nil,
            synthesis: "",
            quickWins: [],
            strategicBets: [],
            hiddenRisks: [],
            pitch: "",
            mockups: []
        )
    }
}
