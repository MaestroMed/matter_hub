import XCTest
@testable import AuditKit

/// v0.27 — Locks the pure parts of the Lead Scoring Engine:
/// `LeadScorer.compute(input:)` (and the `LeadTemperature.from` band
/// projection). The SwiftData lift (`LeadScorer.input(from:)`) is
/// exercised end-to-end via the simulator screenshot — these tests
/// hit the value-type path directly so they run in <50ms total and
/// never touch a CloudKit container.
final class LeadScorerTests: XCTestCase {

    // MARK: - Fixtures

    /// Reference clock used by every test. Locking it to a known
    /// instant means `daysSince(...)` computations are stable across
    /// machines / CI runs.
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 24 * 3600)
    }

    private func bareInput(
        tags: [String] = [],
        content: String = "",
        urlHost: String? = nil,
        lastAccessedAt: Date? = nil,
        hasAuditAttached: Bool = false,
        auditOverallScore: Int? = nil,
        auditSecurityScore: Int? = nil,
        auditPerformanceScore: Int? = nil
    ) -> LeadScoreInput {
        LeadScoreInput(
            tags: tags,
            content: content,
            urlHost: urlHost,
            lastAccessedAt: lastAccessedAt,
            hasAuditAttached: hasAuditAttached,
            auditOverallScore: auditOverallScore,
            auditSecurityScore: auditSecurityScore,
            auditPerformanceScore: auditPerformanceScore,
            now: now
        )
    }

    // MARK: - Edge cases (empty input / clamps)

    /// An empty Node (no tags, no content, never opened, no audit)
    /// scores zero. Reasoning still non-empty so the breakdown modal
    /// never renders an empty list.
    func test_emptyInput_scoresZero() {
        let score = LeadScorer.compute(input: bareInput())
        XCTAssertEqual(score.total, 0)
        XCTAssertEqual(score.icpFit, 0)
        XCTAssertEqual(score.buyingSignals, 0)
        XCTAssertEqual(score.engagement, 0)
        XCTAssertFalse(score.reasoning.isEmpty, "reasoning bullets must never be empty")
    }

    /// Total caps at 100 even when every dimension is maxed out.
    /// Locks the clamping contract at the `LeadScore.init` boundary.
    func test_totalClampsAt100() {
        // Tags hit ICP +20 (saasB2B) +10 (fintech) +8 (DTC) = 38,
        // plus known host (+10) plus audit attached (+10) → 58.
        // ICP caps at 40 in the init.
        let input = bareInput(
            tags: ["saasB2B", "fintech", "ecommerce"],
            content: "We just announced funding and are hiring.",
            urlHost: "stripe.com",
            lastAccessedAt: daysAgo(1),
            hasAuditAttached: true,
            auditOverallScore: 72,
            auditSecurityScore: 40,
            auditPerformanceScore: 50
        )
        let score = LeadScorer.compute(input: input)
        XCTAssertLessThanOrEqual(score.total, 100, "total must clamp at 100")
        XCTAssertLessThanOrEqual(score.icpFit, 40)
        XCTAssertLessThanOrEqual(score.buyingSignals, 40)
        XCTAssertLessThanOrEqual(score.engagement, 20)
    }

    /// Even with absurd input on every axis, the total never exceeds
    /// 100. Belt-and-suspenders for the clamp.
    func test_oversizedInput_clampsAt100() {
        let input = bareInput(
            tags: ["saasB2B", "fintech", "dtc", "saas", "payments"],
            content: "funding hiring launch raised levée embauche",
            urlHost: "linear.app",
            lastAccessedAt: now,
            hasAuditAttached: true,
            auditOverallScore: 75,
            auditSecurityScore: 30,
            auditPerformanceScore: 30
        )
        let score = LeadScorer.compute(input: input)
        XCTAssertEqual(score.total, 100)
    }

    // MARK: - ICP fit dimension

    /// A prospect tagged `saasB2B` + `fintech` should easily clear
    /// 30 on the ICP fit axis. Tests the additive +20/+10 contribution.
    func test_icpFit_fintechSaasB2B() {
        let input = bareInput(tags: ["saasB2B", "fintech"])
        let score = LeadScorer.compute(input: input)
        XCTAssertGreaterThan(score.icpFit, 30, "ICP fit must exceed 30 for fintech + SaaS B2B")
    }

    /// A known SaaS host alone adds +10 to ICP fit, even without
    /// matching industry tags.
    func test_icpFit_knownSaasHostAdds10() {
        let baselineNoHost = LeadScorer.compute(input: bareInput())
        let withHost = LeadScorer.compute(input: bareInput(urlHost: "stripe.com"))
        XCTAssertEqual(withHost.icpFit - baselineNoHost.icpFit, 10)
    }

    /// The host check is case-insensitive AND strips the `www.`
    /// prefix the same way `ClientsView.host(of:)` does. Without
    /// this, prospects captured via the Share Extension (which
    /// keeps `www.`) would silently underrate.
    func test_icpFit_knownSaasHost_isCaseInsensitiveAndStripsWww() {
        let upper = LeadScorer.compute(input: bareInput(urlHost: "WWW.Stripe.com"))
        let lower = LeadScorer.compute(input: bareInput(urlHost: "stripe.com"))
        XCTAssertEqual(upper.icpFit, lower.icpFit)
    }

    /// An unknown host does NOT add the +10. Locks the allowlist
    /// boundary — adding a new host to the table must be intentional.
    func test_icpFit_unknownHost_doesNotAddBonus() {
        let withUnknown = LeadScorer.compute(input: bareInput(urlHost: "random-blog-2026.example"))
        let bare = LeadScorer.compute(input: bareInput())
        XCTAssertEqual(withUnknown.icpFit, bare.icpFit)
    }

    /// Having an audit already attached adds +10. Locks the funnel-
    /// signal contribution so an audit Mehdi ran on Tuesday surfaces
    /// the prospect higher on Wednesday's call list.
    func test_icpFit_auditAttachedAdds10() {
        let withoutAudit = LeadScorer.compute(input: bareInput())
        let withAudit = LeadScorer.compute(input: bareInput(hasAuditAttached: true))
        XCTAssertEqual(withAudit.icpFit - withoutAudit.icpFit, 10)
    }

    // MARK: - Buying signals dimension

    /// Audit overall 75 sits inside the 60..=85 sweet spot for
    /// consulting and should add +20 to buyingSignals.
    func test_buyingSignals_sweetSpotScore75() {
        let input = bareInput(hasAuditAttached: true, auditOverallScore: 75)
        let score = LeadScorer.compute(input: input)
        XCTAssertGreaterThanOrEqual(score.buyingSignals, 20)
    }

    /// Audit overall 92 is above the sweet-spot ceiling — no
    /// headroom to sell against. Should NOT add the +20 sweet-spot
    /// bonus.
    func test_buyingSignals_aboveSweetSpot_noBonus() {
        let above = LeadScorer.compute(input: bareInput(hasAuditAttached: true, auditOverallScore: 92))
        let baseline = LeadScorer.compute(input: bareInput(hasAuditAttached: true))
        XCTAssertEqual(above.buyingSignals, baseline.buyingSignals)
    }

    /// Low security score (<60) is a tangible pain trigger and
    /// surfaces +10. Two low surfaces still cap at +10 total so the
    /// pain doesn't double-count.
    func test_buyingSignals_painSurfacesCapAt10() {
        let oneLow = LeadScorer.compute(input: bareInput(auditSecurityScore: 30))
        let twoLow = LeadScorer.compute(input: bareInput(
            auditSecurityScore: 30,
            auditPerformanceScore: 30
        ))
        XCTAssertEqual(oneLow.buyingSignals, twoLow.buyingSignals,
                       "pain surfaces must cap at +10 total")
    }

    /// "funding" / "hiring" / "launch" keywords in content add +10
    /// to buyingSignals. The substring match is case-insensitive.
    func test_buyingSignals_triggerKeywordsAdd10() {
        let withTrigger = LeadScorer.compute(input: bareInput(
            content: "Just closed a Series B — FUNDING officially announced."
        ))
        let withoutTrigger = LeadScorer.compute(input: bareInput(content: "neutral copy"))
        XCTAssertGreaterThan(withTrigger.buyingSignals, withoutTrigger.buyingSignals)
    }

    // MARK: - Engagement dimension

    /// Last opened within 24h → full engagement (+20).
    func test_engagement_lastAccessedToday_full20() {
        let input = bareInput(lastAccessedAt: now.addingTimeInterval(-3600))
        let score = LeadScorer.compute(input: input)
        XCTAssertEqual(score.engagement, 20)
    }

    /// Last opened 60 days ago → engagement 0. The lead's gone cold.
    func test_engagement_lastAccessed60DaysAgo_zero() {
        let input = bareInput(lastAccessedAt: daysAgo(60))
        let score = LeadScorer.compute(input: input)
        XCTAssertEqual(score.engagement, 0)
    }

    /// Last opened 21 days ago → mid-band (+10). Locks the 8–30 day
    /// "still warm" window.
    func test_engagement_lastAccessed21DaysAgo_mid10() {
        let input = bareInput(lastAccessedAt: daysAgo(21))
        let score = LeadScorer.compute(input: input)
        XCTAssertEqual(score.engagement, 10)
    }

    /// Never opened → engagement 0. Distinct branch from "opened 60
    /// days ago" so the reasoning bullet is different.
    func test_engagement_neverOpened_zero() {
        let input = bareInput(lastAccessedAt: nil)
        let score = LeadScorer.compute(input: input)
        XCTAssertEqual(score.engagement, 0)
        XCTAssertTrue(score.reasoning.contains(where: { $0.contains("Jamais") }),
                       "Never-opened prospects must surface that explicitly in reasoning")
    }

    // MARK: - Determinism + reasoning contract

    /// Same input → same score, byte-for-byte (modulo `computedAt`
    /// which is the only thing the function reads from the clock,
    /// and which we pin via `now`).
    func test_determinism_sameInputSameScore() {
        let input = bareInput(
            tags: ["saasB2B"],
            content: "funding announcement",
            urlHost: "stripe.com",
            lastAccessedAt: daysAgo(2),
            hasAuditAttached: true,
            auditOverallScore: 70
        )
        let a = LeadScorer.compute(input: input)
        let b = LeadScorer.compute(input: input)
        XCTAssertEqual(a.total, b.total)
        XCTAssertEqual(a.icpFit, b.icpFit)
        XCTAssertEqual(a.buyingSignals, b.buyingSignals)
        XCTAssertEqual(a.engagement, b.engagement)
        XCTAssertEqual(a.reasoning, b.reasoning)
    }

    /// Two structurally different prospects produce different scores.
    /// Locks the function isn't accidentally constant.
    func test_twoDifferentInputs_yieldDifferentScores() {
        let cold = LeadScorer.compute(input: bareInput())
        let hot = LeadScorer.compute(input: bareInput(
            tags: ["saasB2B", "fintech"],
            content: "Series A announced",
            urlHost: "linear.app",
            lastAccessedAt: now,
            hasAuditAttached: true,
            auditOverallScore: 75
        ))
        XCTAssertNotEqual(cold.total, hot.total)
        XCTAssertGreaterThan(hot.total, cold.total)
    }

    /// Reasoning bullets always carry at least one entry — the
    /// breakdown modal relies on this contract.
    func test_reasoning_alwaysNonEmpty() {
        for input in [
            bareInput(),
            bareInput(tags: ["saasB2B"]),
            bareInput(lastAccessedAt: now),
            bareInput(hasAuditAttached: true, auditOverallScore: 88),
        ] {
            let score = LeadScorer.compute(input: input)
            XCTAssertFalse(score.reasoning.isEmpty,
                           "reasoning must never be empty for any input")
        }
    }

    // MARK: - LeadTemperature boundaries

    /// Boundary table: 0 → cold, 49 → cold, 50 → warm, 79 → warm,
    /// 80 → hot, 100 → hot. Locks the cut-offs so a future tweak
    /// (e.g. lifting `hot` to 85) shows up as a deliberate change
    /// in one test file rather than a silent UI shift.
    func test_leadTemperature_boundaryTable() {
        XCTAssertEqual(LeadTemperature.from(0), .cold)
        XCTAssertEqual(LeadTemperature.from(49), .cold)
        XCTAssertEqual(LeadTemperature.from(50), .warm)
        XCTAssertEqual(LeadTemperature.from(79), .warm)
        XCTAssertEqual(LeadTemperature.from(80), .hot)
        XCTAssertEqual(LeadTemperature.from(100), .hot)
    }

    /// Negative input still resolves to .cold — defensive against
    /// the future AI path returning a clamped-but-not-floored value.
    func test_leadTemperature_negativeIsCold() {
        XCTAssertEqual(LeadTemperature.from(-5), .cold)
    }

    /// Each temperature carries a fixed emoji. Locks the glyph so a
    /// renderer can't drift hot from 🔥 to 🌶️ in the badge without
    /// the test screaming.
    func test_leadTemperature_emojiGlyphs() {
        XCTAssertEqual(LeadTemperature.hot.emoji, "🔥")
        XCTAssertEqual(LeadTemperature.warm.emoji, "☀️")
        XCTAssertEqual(LeadTemperature.cold.emoji, "❄️")
    }

    /// The convenience accessor on `LeadScore` matches what the
    /// static projector returns. Two paths, one source of truth.
    func test_leadScore_temperatureMatchesProjector() {
        let warm = LeadScore(
            total: 65,
            icpFit: 30,
            buyingSignals: 20,
            engagement: 15,
            reasoning: ["test"]
        )
        XCTAssertEqual(warm.temperature, LeadTemperature.from(warm.total))
    }
}
