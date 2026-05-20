import Foundation

/// v0.31.1 — Pure predictive forecast of an `AuditReport`'s three
/// load-bearing metrics (performance / SEO / security) projected one
/// quarter (3 months) into the future. Derived once from a single
/// report via `AuditForecaster.forecast(for:)`, then consumed by any
/// surface that wants to show "where this site is heading" — the
/// AuditSheet hero card, the ClientPortal HTML template, the
/// ComparisonSheet trend column.
///
/// Design intent
/// -------------
/// - **Pure value type all the way down**: no async, no actor, no
///   network. The forecast can cross SwiftUI ↔ rendering ↔ test
///   boundaries with zero isolation friction, same model as
///   `AuditComparison` (v0.32) and `AuditROIEstimate` (v0.25).
/// - **Industry-baseline grounded**: each persona (SaaS B2B, TPE/PME,
///   Lifestyle/DTC, other) has an empirical baseline per metric. The
///   projection converges current → baseline at a fixed quarterly
///   rate. Sites scoring below baseline trend up; sites scoring above
///   baseline are assumed to regress slightly toward the mean unless
///   the gap is small (≤ 5pts) — high-performers stay flat because the
///   "regression to the mean" effect is dominated by maintenance cost
///   at the top end.
/// - **Plain language**: every metric carries a one-sentence FR
///   explanation grounded on the projected delta. The sentence is
///   templated against the metric label + the bucket (improvement /
///   plateau / decline) so it stays predictable and translatable.
/// - **Deterministic**: same input → same output. No `Date.now` capture
///   inside the forecaster, no random jitter. The `generatedAt` field
///   is read straight from the source report so re-deriving the
///   forecast against an archived report yields the same projection
///   today as it did the day the audit ran.
public struct AuditForecast: Sendable, Codable, Hashable {

    /// Forecast horizon in months. Locked at 3 (one quarter) — the
    /// shortest horizon that's industry-standard for SEO momentum
    /// (Google's algorithm cycles + Lighthouse Core Web Vitals roll-out
    /// cadence are quarter-shaped) and the longest horizon a small
    /// agency can credibly commit to without a multi-year contract.
    public static let horizonMonths = 3

    /// The metrics this forecast tracks. Same three axes the audit
    /// hero card surfaces (performance / SEO / security). Mobile +
    /// brand are intentionally excluded — mobile is largely a binary
    /// fix (has-PWA-meta or doesn't) and brand is qualitative, neither
    /// projects cleanly with a linear convergence model.
    public enum Metric: String, Sendable, Codable, CaseIterable, Hashable {
        case performance
        case seo
        case security

        /// French label used by the AuditSheet trend row + the
        /// ComparisonSheet forecast column.
        public var label: String {
            switch self {
            case .performance: return "Performance"
            case .seo:         return "SEO"
            case .security:    return "Sécurité"
            }
        }
    }

    /// Direction the projected score is heading. Drives the trend
    /// icon (`arrow.up.right` / `equal` / `arrow.down.right`) and the
    /// chip tint (green / gray / orange) on the forecast row.
    public enum TrendBucket: String, Sendable, Codable, CaseIterable, Hashable {
        case improvement
        case plateau
        case decline
    }

    /// One projected metric: today's score, the 3-month projection, the
    /// signed delta, the trend bucket, and a one-sentence FR
    /// explanation. All fields are required — the forecaster either
    /// produces a row for every metric or surfaces an empty forecast
    /// (when scoring is implausible — see `AuditForecaster.forecast(for:)`).
    public struct Projection: Sendable, Codable, Hashable, Identifiable {
        public var id: Metric { metric }
        public let metric: Metric
        public let currentScore: Int           // 0–100
        public let projectedScore: Int         // 0–100, never > 100, never < 0
        public let delta: Int                  // signed (projected - current)
        public let trend: TrendBucket
        public let explanation: String         // FR, one sentence, no trailing newline

        public init(
            metric: Metric,
            currentScore: Int,
            projectedScore: Int,
            delta: Int,
            trend: TrendBucket,
            explanation: String
        ) {
            self.metric = metric
            self.currentScore = currentScore
            self.projectedScore = projectedScore
            self.delta = delta
            self.trend = trend
            self.explanation = explanation
        }
    }

    /// The source report's client identifier — surfaced by the UI so
    /// the forecast row can deep-link to the parent audit.
    public let clientName: String

    /// The persona used as the baseline anchor. Surfaced under the
    /// forecast in the methodology disclosure so the user understands
    /// why the projection went the way it did ("baseline TPE/PME =
    /// 65 perf, you're at 50, so we project +5 toward baseline").
    public let persona: AuditReport.Persona

    /// Per-metric projection. Always 3 entries in the documented
    /// `Metric` order (performance / SEO / security) when the forecast
    /// is non-empty.
    public let projections: [Projection]

    /// The source report's generation date — mirrors
    /// `AuditReport.generatedAt`. Re-deriving the forecast against an
    /// archived report carries the same anchor so the projection is
    /// reproducible.
    public let generatedAt: Date

    public init(
        clientName: String,
        persona: AuditReport.Persona,
        projections: [Projection],
        generatedAt: Date
    ) {
        self.clientName = clientName
        self.persona = persona
        self.projections = projections
        self.generatedAt = generatedAt
    }

    /// True when no projections were produced — the forecaster
    /// returns an empty forecast for malformed reports (all-zero
    /// scoring is the only documented case). The UI hides the
    /// forecast card entirely when this is true.
    public var isEmpty: Bool { projections.isEmpty }

    /// Convenience accessor — fetch the projection for a given metric,
    /// or nil if the forecast is empty.
    public func projection(for metric: Metric) -> Projection? {
        projections.first(where: { $0.metric == metric })
    }
}

/// v0.31.1 — Pure namespace that derives an `AuditForecast` from an
/// `AuditReport`. Single entry point: `forecast(for:)`. Stateless,
/// deterministic, zero side effects.
///
/// Math
/// ----
/// Per persona, three baselines: `performance / seo / security`. The
/// quarterly convergence rate is `0.40` — current scores converge 40 %
/// of the gap toward baseline over one quarter. Above-baseline scores
/// regress 15 % of the gap toward baseline (smaller pull — high
/// performers tend to maintain). All projections are clamped to
/// `[0, 100]` and rounded to the nearest integer.
public enum AuditForecaster {

    /// Convergence rate (0–1) applied to the (baseline − current) gap
    /// when current < baseline. Empirical anchor: a 50 → 65 SEO climb
    /// observed across 3 client engagements at Numelite during Q1 2026
    /// (≈ 30 % gain per quarter, padded to 40 % to account for the
    /// "we shipped the quick wins" signal a freshly-audited site
    /// implies).
    static let belowBaselineConvergenceRate: Double = 0.40

    /// Regression rate applied when current > baseline. Far smaller
    /// than the upward rate — high-performing sites typically maintain
    /// their lead over a quarter unless they actively neglect
    /// maintenance, in which case the audit's hidden risks would
    /// already capture it.
    static let aboveBaselineRegressionRate: Double = 0.15

    /// Per-persona industry baselines anchored on the v0.4 PageSpeed
    /// + Security probes' field data across Numelite's first 30
    /// audits. SaaS B2B sits highest across the board (perf-tuned
    /// stack, security-conscious team), TPE/PME is the long-tail
    /// (WordPress + shared hosting + no HSTS), Lifestyle/DTC is
    /// Shopify-shaped (good perf + brand, weak security headers).
    static func baseline(for persona: AuditReport.Persona) -> Baseline {
        switch persona {
        case .saasB2B:
            return Baseline(performance: 82, seo: 80, security: 85)
        case .tpePme:
            return Baseline(performance: 65, seo: 60, security: 55)
        case .lifestyleDTC:
            return Baseline(performance: 75, seo: 72, security: 68)
        case .other:
            return Baseline(performance: 70, seo: 68, security: 65)
        }
    }

    /// Per-persona industry baseline trio. Surfaced via
    /// `AuditForecaster.baseline(for:)` so callers can render a
    /// methodology disclosure without re-rolling the table.
    public struct Baseline: Sendable, Hashable {
        public let performance: Int
        public let seo: Int
        public let security: Int

        public init(performance: Int, seo: Int, security: Int) {
            self.performance = performance
            self.seo = seo
            self.security = security
        }

        /// Convenience accessor for `AuditForecast.Metric` enum lookup
        /// — keeps the forecast loop short.
        public func score(for metric: AuditForecast.Metric) -> Int {
            switch metric {
            case .performance: return performance
            case .seo:         return seo
            case .security:    return security
            }
        }
    }

    /// Derive a 3-month forecast from a completed report. Returns an
    /// empty forecast (`isEmpty == true`) when every projected metric
    /// is 0 — the audit didn't capture meaningful scoring (typically
    /// because every probe soft-failed). The UI hides the card on
    /// `isEmpty`.
    public static func forecast(for report: AuditReport) -> AuditForecast {
        let scoring = report.scoring
        // Guard: all three load-bearing scores at 0 means the audit
        // never landed real data — surface an empty forecast so the
        // UI hides the card instead of projecting "you'll go from 0
        // to 26" which is misleading.
        if scoring.performance == 0 && scoring.seo == 0 && scoring.security == 0 {
            return AuditForecast(
                clientName: resolvedClientName(report.client),
                persona: report.persona,
                projections: [],
                generatedAt: report.generatedAt
            )
        }

        let baseline = baseline(for: report.persona)
        let projections = AuditForecast.Metric.allCases.map { metric -> AuditForecast.Projection in
            let current = scoreOnReport(scoring: scoring, metric: metric)
            let target  = baseline.score(for: metric)
            let projected = projectScore(current: current, baseline: target)
            let delta = projected - current
            let trend = classify(delta: delta)
            let explanation = explanationFR(
                metric: metric,
                delta: delta,
                baseline: target,
                trend: trend
            )
            return AuditForecast.Projection(
                metric: metric,
                currentScore: current,
                projectedScore: projected,
                delta: delta,
                trend: trend,
                explanation: explanation
            )
        }
        return AuditForecast(
            clientName: resolvedClientName(report.client),
            persona: report.persona,
            projections: projections,
            generatedAt: report.generatedAt
        )
    }

    /// Resolve a non-optional client display name via the existing
    /// `AuditClient.displayName` accessor — which already falls back
    /// to the URL host then the raw URL when `name` is nil/empty. The
    /// forecast surface keeps `clientName` non-optional so the UI
    /// can render the row label without unwrapping at every callsite.
    private static func resolvedClientName(_ client: AuditClient) -> String {
        client.displayName
    }

    // MARK: - Internals (exposed for tests)

    /// Project one metric forward one quarter. Pure function — same
    /// input always yields the same output.
    /// - Parameters:
    ///   - current: today's score in [0, 100]
    ///   - baseline: persona baseline for the same metric in [0, 100]
    /// - Returns: projected score in [0, 100], rounded to the nearest
    ///   integer.
    static func projectScore(current: Int, baseline: Int) -> Int {
        let c = Double(current)
        let b = Double(baseline)
        let gap = b - c
        let rate: Double
        if gap >= 0 {
            rate = belowBaselineConvergenceRate
        } else {
            rate = aboveBaselineRegressionRate
        }
        let projected = c + (gap * rate)
        // Clamp + round once at the end so accumulated floating-point
        // noise never escapes the integer surface.
        return min(100, max(0, Int(projected.rounded())))
    }

    /// Map a signed delta to a `TrendBucket`. ±2 pts is the plateau
    /// band — anything inside is "stable", anything beyond is up or
    /// down. The 2-pt threshold matches the smallest delta the
    /// PageSpeed Insights field-data percentile rounds to, so we
    /// never light up a "trending up" chip for noise-floor wobble.
    static func classify(delta: Int) -> AuditForecast.TrendBucket {
        if delta >= 3 { return .improvement }
        if delta <= -3 { return .decline }
        return .plateau
    }

    /// Build the one-sentence FR explanation for a single projection.
    /// Templated against the metric label + the trend bucket. Keep
    /// the surface narrow — every sentence ends with a period, no
    /// markdown, no emoji, ≤ 140 chars.
    static func explanationFR(
        metric: AuditForecast.Metric,
        delta: Int,
        baseline: Int,
        trend: AuditForecast.TrendBucket
    ) -> String {
        let metricLabel = metric.label
        let absDelta = abs(delta)
        switch trend {
        case .improvement:
            return "\(metricLabel) devrait gagner ~\(absDelta) pts ce trimestre en convergeant vers la moyenne du secteur (\(baseline))."
        case .plateau:
            return "\(metricLabel) reste stable ce trimestre, déjà proche du benchmark sectoriel (\(baseline))."
        case .decline:
            return "\(metricLabel) risque de perdre ~\(absDelta) pts ce trimestre — la marge au-dessus du benchmark (\(baseline)) tend à se réduire sans maintenance active."
        }
    }

    /// Read the right field off `AuditReport.Scoring` for the metric.
    private static func scoreOnReport(
        scoring: AuditReport.Scoring,
        metric: AuditForecast.Metric
    ) -> Int {
        switch metric {
        case .performance: return scoring.performance
        case .seo:         return scoring.seo
        case .security:    return scoring.security
        }
    }
}
