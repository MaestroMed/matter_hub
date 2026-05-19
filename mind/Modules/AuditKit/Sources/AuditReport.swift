import Foundation

/// Full output of an audit run: raw measurements + Claude synthesis +
/// actionable spec (quick wins / strategic bets / ready-to-send pitch).
/// Value type all the way down so it crosses the SwiftUI ↔ SwiftData ↔
/// Anthropic-API boundaries with no isolation friction.
public struct AuditReport: Sendable, Codable, Hashable {
    public let client: AuditClient
    public let generatedAt: Date

    /// Persona inferred from the site copy. Drives recommendation phrasing
    /// (a TPE local doesn't need the same advice as a SaaS B2B scale-up).
    public let persona: Persona

    /// Numeric scoring on five axes, plus an overall 0–100 weighted score.
    public let scoring: Scoring

    /// Raw Lighthouse-style performance measurements (only present when
    /// PageSpeed Insights responded successfully).
    public let performance: PerformanceMetrics?

    /// Structured findings from the secondary probes (security headers,
    /// DNS / email infra, domain registration, mobile app presence).
    /// Optional — every section inside is also optional, so a flaky probe
    /// degrades gracefully.
    public let findings: AuditFindings?

    /// Long-form markdown synthesis suitable for rendering as a LiquidCard
    /// inside MIND and as the body of a PDF export.
    public let synthesis: String

    /// 3–5 short-cycle wins the prospect could ship in a few weeks.
    public let quickWins: [QuickWin]

    /// 3–6 high-value strategic bets with rough timeline + budget.
    public let strategicBets: [StrategicBet]

    /// 2–5 hidden / non-obvious risks the prospect probably doesn't know
    /// they're sitting on. Surfaced by Claude after reading the full
    /// audit data. Useful as conversation starter in the pitch.
    public let hiddenRisks: [HiddenRisk]

    /// Cold-email body ready to paste into Mail.app via mailto:. Now
    /// includes three budget tiers (low / mid / high) so Mehdi can
    /// shape the same pitch to different prospect maturity levels.
    public let pitch: String

    /// v0.23 — Generative "before / after" mockups. Up to 3 PNG
    /// images produced by GPT Image 2 visualizing what the site
    /// could look like once the top 3 quick wins are applied.
    /// Empty by default — kept optional so reports synthesised
    /// before v0.23 still decode cleanly and so the field stays
    /// progressively populated (the controller appends mockups as
    /// they arrive without blocking the main audit flow).
    public var mockups: [RedesignMockup]

    public init(
        client: AuditClient,
        generatedAt: Date = .now,
        persona: Persona,
        scoring: Scoring,
        performance: PerformanceMetrics?,
        findings: AuditFindings? = nil,
        synthesis: String,
        quickWins: [QuickWin],
        strategicBets: [StrategicBet],
        hiddenRisks: [HiddenRisk] = [],
        pitch: String,
        mockups: [RedesignMockup] = []
    ) {
        self.client = client
        self.generatedAt = generatedAt
        self.persona = persona
        self.scoring = scoring
        self.performance = performance
        self.findings = findings
        self.synthesis = synthesis
        self.quickWins = quickWins
        self.strategicBets = strategicBets
        self.hiddenRisks = hiddenRisks
        self.pitch = pitch
        self.mockups = mockups
    }

    // MARK: - Codable (backwards-compatible mockups)

    /// v0.23 — Custom decoder so payloads serialised before the
    /// `mockups` field existed still round-trip cleanly. Missing key
    /// → empty array. Every other key keeps the synthesised
    /// behaviour the compiler would have produced.
    private enum CodingKeys: String, CodingKey {
        case client, generatedAt, persona, scoring, performance,
             findings, synthesis, quickWins, strategicBets,
             hiddenRisks, pitch, mockups
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.client        = try c.decode(AuditClient.self, forKey: .client)
        self.generatedAt   = try c.decode(Date.self, forKey: .generatedAt)
        self.persona       = try c.decode(Persona.self, forKey: .persona)
        self.scoring       = try c.decode(Scoring.self, forKey: .scoring)
        self.performance   = try c.decodeIfPresent(PerformanceMetrics.self, forKey: .performance)
        self.findings      = try c.decodeIfPresent(AuditFindings.self, forKey: .findings)
        self.synthesis     = try c.decode(String.self, forKey: .synthesis)
        self.quickWins     = try c.decode([QuickWin].self, forKey: .quickWins)
        self.strategicBets = try c.decode([StrategicBet].self, forKey: .strategicBets)
        self.hiddenRisks   = try c.decodeIfPresent([HiddenRisk].self, forKey: .hiddenRisks) ?? []
        self.pitch         = try c.decode(String.self, forKey: .pitch)
        self.mockups       = try c.decodeIfPresent([RedesignMockup].self, forKey: .mockups) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(client, forKey: .client)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encode(persona, forKey: .persona)
        try c.encode(scoring, forKey: .scoring)
        try c.encodeIfPresent(performance, forKey: .performance)
        try c.encodeIfPresent(findings, forKey: .findings)
        try c.encode(synthesis, forKey: .synthesis)
        try c.encode(quickWins, forKey: .quickWins)
        try c.encode(strategicBets, forKey: .strategicBets)
        try c.encode(hiddenRisks, forKey: .hiddenRisks)
        try c.encode(pitch, forKey: .pitch)
        try c.encode(mockups, forKey: .mockups)
    }

    // MARK: - Nested types

    public enum Persona: String, Sendable, Codable, CaseIterable {
        case saasB2B          // scale-up tech, sells software to other businesses
        case tpePme           // local TPE/PME (artisan, retail, restaurant)
        case lifestyleDTC     // fashion / lifestyle / DTC, brand-driven
        case other            // anything that doesn't match cleanly
    }

    public struct Scoring: Sendable, Codable, Hashable {
        public let overall: Int          // 0–100 weighted
        public let performance: Int
        public let seo: Int
        public let security: Int
        public let brand: Int
        public let mobile: Int

        public init(
            overall: Int,
            performance: Int,
            seo: Int,
            security: Int,
            brand: Int,
            mobile: Int
        ) {
            self.overall = overall
            self.performance = performance
            self.seo = seo
            self.security = security
            self.brand = brand
            self.mobile = mobile
        }
    }

    public struct PerformanceMetrics: Sendable, Codable, Hashable {
        public let performanceScore: Int       // 0–100
        public let seoScore: Int
        public let accessibilityScore: Int
        public let bestPracticesScore: Int
        public let largestContentfulPaintSeconds: Double?
        public let interactionToNextPaintMs: Int?
        public let cumulativeLayoutShift: Double?

        public init(
            performanceScore: Int,
            seoScore: Int,
            accessibilityScore: Int,
            bestPracticesScore: Int,
            largestContentfulPaintSeconds: Double?,
            interactionToNextPaintMs: Int?,
            cumulativeLayoutShift: Double?
        ) {
            self.performanceScore = performanceScore
            self.seoScore = seoScore
            self.accessibilityScore = accessibilityScore
            self.bestPracticesScore = bestPracticesScore
            self.largestContentfulPaintSeconds = largestContentfulPaintSeconds
            self.interactionToNextPaintMs = interactionToNextPaintMs
            self.cumulativeLayoutShift = cumulativeLayoutShift
        }
    }

    public struct QuickWin: Sendable, Codable, Hashable, Identifiable {
        public let id: UUID
        public let title: String
        public let detail: String
        public let effortDays: Double          // 0.5 = half-day, etc.
        public let impact: Impact

        public enum Impact: String, Sendable, Codable, CaseIterable {
            case low
            case medium
            case high
        }

        public init(
            id: UUID = UUID(),
            title: String,
            detail: String,
            effortDays: Double,
            impact: Impact
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.effortDays = effortDays
            self.impact = impact
        }
    }

    public struct StrategicBet: Sendable, Codable, Hashable, Identifiable {
        public let id: UUID
        public let title: String
        public let detail: String
        public let durationMonths: Int
        public let budgetMinEUR: Int
        public let budgetMaxEUR: Int

        public init(
            id: UUID = UUID(),
            title: String,
            detail: String,
            durationMonths: Int,
            budgetMinEUR: Int,
            budgetMaxEUR: Int
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.durationMonths = durationMonths
            self.budgetMinEUR = budgetMinEUR
            self.budgetMaxEUR = budgetMaxEUR
        }
    }

    public struct HiddenRisk: Sendable, Codable, Hashable, Identifiable {
        public let id: UUID
        public let title: String
        public let detail: String
        public let severity: Severity

        public enum Severity: String, Sendable, Codable, CaseIterable {
            case low
            case medium
            case high
            case critical
        }

        public init(
            id: UUID = UUID(),
            title: String,
            detail: String,
            severity: Severity
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.severity = severity
        }
    }
}

public extension AuditReport.Persona {
    var label: String {
        switch self {
        case .saasB2B:      return "SaaS B2B"
        case .tpePme:       return "TPE / PME"
        case .lifestyleDTC: return "Lifestyle / DTC"
        case .other:        return "Other"
        }
    }
}
