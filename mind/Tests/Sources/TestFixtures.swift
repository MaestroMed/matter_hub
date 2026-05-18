import Foundation
@testable import AuditKit

/// Shared fixtures so tests stay focused on the unit under test
/// instead of repeating 50 lines of boilerplate building an
/// AuditReport from scratch.
enum TestFixtures {
    static func sampleClient(name: String? = "Stripe") -> AuditClient {
        AuditClient(
            url: URL(string: "https://stripe.com")!,
            name: name
        )
    }

    static func samplePerformance() -> AuditReport.PerformanceMetrics {
        AuditReport.PerformanceMetrics(
            performanceScore: 82,
            seoScore: 91,
            accessibilityScore: 88,
            bestPracticesScore: 100,
            largestContentfulPaintSeconds: 1.82,
            interactionToNextPaintMs: 142,
            cumulativeLayoutShift: 0.04
        )
    }

    static func sampleFindings() -> AuditFindings {
        AuditFindings(
            security: SecurityFindings(
                grade: "A+",
                score: 95,
                presentHeaders: ["Strict-Transport-Security", "Content-Security-Policy"],
                missingHeaders: [],
                tlsValid: true
            ),
            email: EmailFindings(
                provider: "Google Workspace",
                mxHosts: ["aspmx.l.google.com"],
                hasSPF: true,
                hasDMARC: true
            ),
            domain: DomainFindings(
                registrar: "MarkMonitor",
                createdAt: Date(timeIntervalSince1970: 1_104_537_600), // 2005-01-01
                ageYears: 21.3
            ),
            mobile: MobileFindings(
                hasIOSApp: true,
                appName: "Stripe Dashboard",
                sellerName: "Stripe, Inc.",
                averageRating: 4.7,
                ratingCount: 12_300,
                primaryGenre: "Business"
            )
        )
    }

    static func sampleReport(
        scoringOverall: Int = 87,
        quickWinsCount: Int = 3,
        strategicBetsCount: Int = 2,
        hiddenRisksCount: Int = 1
    ) -> AuditReport {
        let wins = sampleQuickWins(count: quickWinsCount)
        let bets = sampleStrategicBets(count: strategicBetsCount)
        let risks = sampleHiddenRisks(count: hiddenRisksCount)
        let scoring = AuditReport.Scoring(
            overall: scoringOverall,
            performance: 80,
            seo: 90,
            security: 95,
            brand: 85,
            mobile: 88
        )
        return AuditReport(
            client: sampleClient(),
            persona: .saasB2B,
            scoring: scoring,
            performance: samplePerformance(),
            findings: sampleFindings(),
            synthesis: "## Identité\nStripe is the world's leading payments infrastructure.\n\n## Maturité digitale\nMature on every axis but mobile has room.",
            quickWins: wins,
            strategicBets: bets,
            hiddenRisks: risks,
            pitch: "Hi team,\n\nFollowing my audit of stripe.com…\n\n— Mehdi"
        )
    }

    // MARK: - Per-component builders (extracted to keep the Swift type
    // checker happy on `sampleReport` — the inline `.map` versions
    // tripped "unable to type-check this expression in reasonable time").

    private static func sampleQuickWins(count: Int) -> [AuditReport.QuickWin] {
        var out: [AuditReport.QuickWin] = []
        for idx in 0..<count {
            let impact: AuditReport.QuickWin.Impact = (idx == 0) ? .high : (idx == 1 ? .medium : .low)
            let win = AuditReport.QuickWin(
                title: "Quick win \(idx + 1)",
                detail: "Detail of quick win \(idx + 1) — explain what to ship.",
                effortDays: Double(idx + 1) * 0.5,
                impact: impact
            )
            out.append(win)
        }
        return out
    }

    private static func sampleStrategicBets(count: Int) -> [AuditReport.StrategicBet] {
        var out: [AuditReport.StrategicBet] = []
        for idx in 0..<count {
            let bet = AuditReport.StrategicBet(
                title: "Strategic bet \(idx + 1)",
                detail: "Why this bet matters and what it unlocks.",
                durationMonths: 3 + idx,
                budgetMinEUR: (idx + 1) * 15_000,
                budgetMaxEUR: (idx + 1) * 30_000
            )
            out.append(bet)
        }
        return out
    }

    private static func sampleHiddenRisks(count: Int) -> [AuditReport.HiddenRisk] {
        var out: [AuditReport.HiddenRisk] = []
        for idx in 0..<count {
            let risk = AuditReport.HiddenRisk(
                title: "Hidden risk \(idx + 1)",
                detail: "What is silently going wrong.",
                severity: .high
            )
            out.append(risk)
        }
        return out
    }
}
