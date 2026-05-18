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

    /// Long-form markdown synthesis suitable for rendering as a LiquidCard
    /// inside MIND and as the body of a PDF export.
    public let synthesis: String

    /// 3–5 short-cycle wins the prospect could ship in a few weeks.
    public let quickWins: [QuickWin]

    /// 1–3 high-value strategic bets with rough timeline + budget.
    public let strategicBets: [StrategicBet]

    /// 8–10 line cold-email body ready to paste into Mail.app via mailto:.
    public let pitch: String

    public init(
        client: AuditClient,
        generatedAt: Date = .now,
        persona: Persona,
        scoring: Scoring,
        performance: PerformanceMetrics?,
        synthesis: String,
        quickWins: [QuickWin],
        strategicBets: [StrategicBet],
        pitch: String
    ) {
        self.client = client
        self.generatedAt = generatedAt
        self.persona = persona
        self.scoring = scoring
        self.performance = performance
        self.synthesis = synthesis
        self.quickWins = quickWins
        self.strategicBets = strategicBets
        self.pitch = pitch
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
