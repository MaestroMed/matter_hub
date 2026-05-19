import Foundation

/// v0.27 — Lead Scoring Engine.
///
/// A `LeadScore` answers a single question for Mehdi every morning:
/// **which prospect should I call next?** Each client/prospect Node
/// gets a 0–100 number with three sub-scores (ICP fit, buying signals,
/// engagement) and 3-5 plain-language reasoning bullets so the score
/// is never a black box.
///
/// Value type all the way down so it crosses the SwiftUI ↔
/// SwiftData ↔ Anthropic-API boundaries with no isolation friction —
/// same shape as `AuditReport.Scoring` (v0.21+).
///
/// Three sub-scores
/// ----------------
/// * `icpFit` (0–40) — does this prospect look like the kind of
///   client Mehdi closes? Industry tags, known SaaS host table,
///   whether an audit is already attached.
/// * `buyingSignals` (0–40) — is there pain that justifies a call
///   right now? Audit sweet-spot scores (60–85 → consulting fit),
///   weak security/perf surfaces (low score → tangible pain),
///   funding / hiring mentions in recent notes.
/// * `engagement` (0–20) — has Mehdi actually touched this node
///   recently? Reads `Node.lastAccessedAt` to surface cold-but-
///   important leads.
///
/// Total is `icpFit + buyingSignals + engagement`, clamped to
/// 0…100. `LeadTemperature.from(_:)` projects the integer onto
/// three colour-coded bands (hot / warm / cold) that drive the
/// `LeadScoreBadge` UI in `ClientsView` and the "Top leads 🔥" card
/// in `HomeView`.
public struct LeadScore: Sendable, Equatable, Codable, Hashable {
    /// Overall score, 0…100. Computed as the clamped sum of the
    /// three sub-scores. Higher = more reason to act today.
    public let total: Int

    /// ICP fit contribution, 0…40. Maps "does this prospect look
    /// like the kind Mehdi closes" to a number.
    public let icpFit: Int

    /// Buying-signals contribution, 0…40. Captures "is there
    /// tangible pain or a recent trigger that justifies the call".
    public let buyingSignals: Int

    /// Engagement contribution, 0…20. Reads `lastAccessedAt` so
    /// stale-but-important leads don't fade off the radar.
    public let engagement: Int

    /// When the score was computed. Useful for caching layers (v0.27.1)
    /// and for the breakdown modal — "score calculé il y a 12 min"
    /// is a load-bearing trust signal.
    public let computedAt: Date

    /// 3–5 plain-language bullets explaining the score. Surfaced
    /// verbatim in the breakdown modal so the user can audit the
    /// heuristic.
    public let reasoning: [String]

    public init(
        total: Int,
        icpFit: Int,
        buyingSignals: Int,
        engagement: Int,
        computedAt: Date = .now,
        reasoning: [String]
    ) {
        // Defensive clamping at the value-type boundary so callers
        // can't construct an out-of-range score (e.g. via a future
        // AI path that returns 150). Sub-scores are clamped to
        // their natural ceilings; the total is recomputed from the
        // already-clamped sub-scores so the contract `total ==
        // icpFit + buyingSignals + engagement` (within [0,100])
        // holds without any caller juggling.
        let clampedICP = max(0, min(40, icpFit))
        let clampedBuy = max(0, min(40, buyingSignals))
        let clampedEng = max(0, min(20, engagement))
        // We always trust the sub-scores for the canonical sum so
        // that the contract `total == icpFit + buyingSignals +
        // engagement` (clamped to [0, 100]) holds regardless of
        // what the caller passed in. The `total` parameter is kept
        // in the public signature so `Codable` round-trips remain
        // ergonomic; it's accepted but normalised at the boundary.
        let _ = total
        self.total = max(0, min(100, clampedICP + clampedBuy + clampedEng))
        self.icpFit = clampedICP
        self.buyingSignals = clampedBuy
        self.engagement = clampedEng
        self.computedAt = computedAt
        self.reasoning = reasoning
    }

    /// Empty / never-scored placeholder. Used by the UI's nil-check
    /// branches when a Node has no detectable signal yet (newly
    /// captured, no audit, no tags, never opened). Surfaces as a
    /// cold ❄️ badge — distinct from "score not yet computed".
    public static let zero: LeadScore = LeadScore(
        total: 0,
        icpFit: 0,
        buyingSignals: 0,
        engagement: 0,
        computedAt: .distantPast,
        reasoning: ["Aucun signal détecté pour l'instant."]
    )

    /// Convenience — the temperature band this score projects to.
    public var temperature: LeadTemperature {
        LeadTemperature.from(total)
    }
}

/// v0.27 — Three colour-coded bands a `LeadScore` projects to.
///
/// `LeadTemperature.from(_:)` is the only sanctioned way to derive
/// the band from a raw integer — every UI site reads from this
/// function so a future tweak to the thresholds (e.g. shifting the
/// hot cut-off from 80 to 85) lands in exactly one place.
public enum LeadTemperature: String, Sendable, Codable, CaseIterable, Equatable {
    /// 80+ — call today. Iris-red gradient capsule, 🔥 emoji.
    case hot
    /// 50–79 — call this week. Orange capsule, ☀️ emoji.
    case warm
    /// < 50 — let cool. Sky-blue capsule, ❄️ emoji.
    case cold

    /// Project an integer score onto the three bands. Boundaries
    /// inclusive at the low end:
    ///
    /// * `80...` → `.hot`
    /// * `50...79` → `.warm`
    /// * `0..<50` → `.cold` (and any negative input falls here too)
    public static func from(_ total: Int) -> LeadTemperature {
        switch total {
        case 80...:  return .hot
        case 50...:  return .warm
        default:     return .cold
        }
    }

    /// Single-character emoji surfaced in the badge + card title.
    /// Kept on the enum so a localization change can't drift the
    /// glyph out of the `LeadScoreBadge` and the "Top leads" header.
    public var emoji: String {
        switch self {
        case .hot:  return "🔥"
        case .warm: return "☀️"
        case .cold: return "❄️"
        }
    }
}
