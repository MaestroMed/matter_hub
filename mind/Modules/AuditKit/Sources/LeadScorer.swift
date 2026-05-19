import Foundation
import GraphCore   // for Node, NodeKind, MINDTelemetry

/// v0.27 — Lead Scoring Engine.
///
/// Two paths:
///
/// * `LeadScorer.heuristic(node:)` — PURE function, fast, deterministic,
///   no network. Reads tags / URL / attached audit / `lastAccessedAt`
///   and projects them onto a 0–100 score in ~50µs. Safe to call on
///   every `ClientsView` re-render.
/// * `LeadScorer.aiEnhanced(node:cloud:)` — optional cloud round-trip
///   that asks Claude to enrich the heuristic with the actual content
///   of recent notes. Falls back to the heuristic on any network /
///   parsing failure so the UI never spins forever.
///
/// Both paths land on the same `LeadScore` value type, so the UI
/// (`LeadScoreBadge`, "Top leads" card, breakdown modal) is path-
/// agnostic. v0.27.1 will persist the AI-enhanced result in a
/// `leadScoreCache` field; v0.27 keeps everything in-memory and
/// recomputes on every render (cheap via heuristic).
public enum LeadScorer {

    // MARK: - Heuristic (pure, deterministic, no network)

    /// Pure scoring path. Reads stable attributes of a `Node` and
    /// projects them onto a 0–100 score. Deterministic for the same
    /// input: identical Nodes produce identical scores, byte-for-byte.
    ///
    /// Reads (from `Node`):
    /// - `tags`            — drives ICP fit + buying-signals triggers
    /// - `content`         — URL host check + free-text keyword pass
    /// - `lastAccessedAt`  — engagement recency
    /// - `incoming` edges  — does an audit exist? what's the score?
    ///
    /// Does NOT read `createdAt` directly (would couple the score to
    /// install age) — engagement is `lastAccessedAt`-only.
    public static func heuristic(node: Node) -> LeadScore {
        compute(input: input(from: node))
    }

    /// Core pure function — the place every test asserts against.
    /// Caller passes a `LeadScoreInput` (the value-type lift of a
    /// `Node`) so tests don't have to spin up a SwiftData stack.
    public static func compute(input: LeadScoreInput) -> LeadScore {
        var icpFit = 0
        var buyingSignals = 0
        var engagement = 0
        var reasoning: [String] = []

        // ----- ICP fit (0…40) -------------------------------------
        //
        // Industry / persona tags. A prospect that already self-
        // identifies as "saasB2B" or "fintech" is the exact ICP for
        // Mehdi's consulting work — push them high. "lifestyleDTC"
        // is workable; "tpePme" lands lower.
        let tagsLower = Set(input.tags.map { $0.lowercased() })
        let saasTags: Set<String> = ["saasb2b", "saas-b2b", "saas"]
        let fintechTags: Set<String> = ["fintech", "payments", "banking"]
        let dtcTags: Set<String> = ["lifestyledtc", "dtc", "ecommerce", "retail"]
        let tpeTags: Set<String> = ["tpepme", "tpe", "pme", "local"]

        if !saasTags.isDisjoint(with: tagsLower) {
            icpFit += 22
            reasoning.append("ICP : SaaS B2B (+22)")
        }
        if !fintechTags.isDisjoint(with: tagsLower) {
            icpFit += 12
            reasoning.append("ICP : industrie fintech (+12)")
        }
        if !dtcTags.isDisjoint(with: tagsLower) {
            icpFit += 8
            reasoning.append("ICP : lifestyle / DTC (+8)")
        }
        if !tpeTags.isDisjoint(with: tagsLower) {
            icpFit += 4
            reasoning.append("ICP : TPE / PME (+4)")
        }

        // Known-SaaS host: a quick allowlist of hosts whose homepage
        // signals a high-fit prospect. Not exhaustive — that's the
        // AI-enhanced path's job — but covers the obvious ones so
        // the heuristic doesn't underrate Stripe / Linear / Notion
        // / etc. in the demo data.
        if let host = input.urlHost, isKnownSaaSHost(host) {
            icpFit += 10
            reasoning.append("Hôte connu (SaaS table) (+10)")
        }

        // Audit attached → real funnel signal. Mehdi already invested
        // a probe round, so the prospect is by definition pre-qualified.
        if input.hasAuditAttached {
            icpFit += 10
            reasoning.append("Audit déjà attaché (+10)")
        }

        // ----- Buying signals (0…40) ------------------------------
        //
        // Audit overall score 60–85 is the sweet spot for consulting:
        // they have a real site (so they care), but it's not so
        // perfect that there's nothing to fix. Below 60 → too much
        // pain to onboard; above 85 → no headroom for impact.
        if let overall = input.auditOverallScore {
            if overall >= 60 && overall <= 85 {
                buyingSignals += 20
                reasoning.append("Audit score \(overall) — sweet spot consulting (+20)")
            } else if overall < 60 {
                buyingSignals += 10
                reasoning.append("Audit score \(overall) — fortes douleurs (+10)")
            } else {
                reasoning.append("Audit score \(overall) — peu de marge (+0)")
            }
        }

        // Pain surfaces: low security OR low performance score → a
        // tangible "we should call them" trigger. Capped at +10
        // total so two low surfaces don't double-count.
        var painAdded = 0
        if let security = input.auditSecurityScore, security < 60 {
            painAdded = max(painAdded, 10)
            reasoning.append("Sécurité faible (score \(security)) (+10)")
        }
        if let performance = input.auditPerformanceScore, performance < 60 {
            painAdded = max(painAdded, 10)
            reasoning.append("Perf faible (score \(performance)) (+10)")
        }
        buyingSignals += painAdded

        // Free-text triggers in notes / tags. "funding", "raised",
        // "hiring", "launch" are the standard "they're spending
        // money this quarter" signals.
        let triggers = ["funding", "raised", "hiring", "embauche", "launch", "levée"]
        let haystack = (input.content + " " + input.tags.joined(separator: " ")).lowercased()
        if triggers.contains(where: { haystack.contains($0) }) {
            buyingSignals += 10
            reasoning.append("Trigger récent détecté (funding / hiring / launch) (+10)")
        }

        // ----- Engagement (0…20) ----------------------------------
        //
        // Reads `lastAccessedAt`. Inside 7 days → fresh in mind.
        // 8–30 days → still warm. > 30 days or never opened → cold.
        if let lastAccessed = input.lastAccessedAt {
            let days = daysSince(lastAccessed, now: input.now)
            if days <= 7 {
                engagement += 20
                reasoning.append("Consulté il y a ≤ 7 jours (+20)")
            } else if days <= 30 {
                engagement += 10
                reasoning.append("Consulté il y a ≤ 30 jours (+10)")
            } else {
                reasoning.append("Inactif depuis > 30 jours (+0)")
            }
        } else {
            reasoning.append("Jamais consulté (+0)")
        }

        // Guarantee non-empty reasoning so the breakdown modal never
        // renders an empty list. The init clamps total/sub-scores.
        if reasoning.isEmpty {
            reasoning = ["Aucun signal détecté pour l'instant."]
        }

        let score = LeadScore(
            total: icpFit + buyingSignals + engagement,
            icpFit: icpFit,
            buyingSignals: buyingSignals,
            engagement: engagement,
            computedAt: input.now,
            reasoning: reasoning
        )

        return score
    }

    // MARK: - AI-enhanced path (optional, falls back on failure)

    /// Cloud-enhanced score. Lifts the heuristic's reasoning into a
    /// prompt and asks Claude to re-rank the prospect against the
    /// full text of the attached notes / audit synthesis. The
    /// returned score lands in the same `LeadScore` shape so every
    /// UI site is path-agnostic.
    ///
    /// Soft-fails to the heuristic on any error (no key, network down,
    /// malformed JSON). v0.27 keeps this opt-in: callers only reach
    /// for `aiEnhanced` when the heuristic has already been displayed
    /// and the user explicitly asked for a re-score (Settings tap,
    /// "Re-score with AI" button in the breakdown modal, etc.).
    public static func aiEnhanced(
        node: Node,
        cloud: CloudIntelligenceHandle = .live
    ) async -> LeadScore {
        let baseline = heuristic(node: node)
        // Build a tight prompt: heuristic + node content + tag list.
        // We deliberately do NOT include `lastAccessedAt` in the
        // prompt — that's a private signal we want the heuristic to
        // own, not Claude to second-guess. The model is asked to
        // adjust the ICP fit + buying signals based on free-text
        // content alone.
        let prompt = aiPrompt(baseline: baseline, node: node)
        do {
            let response = try await cloud.complete(prompt)
            if let enriched = parseAIResponse(response, baseline: baseline) {
                await telemetryInfo(
                    "lead.score.ai.enriched",
                    data: [
                        "host": Self.hostOrEmpty(node),
                        "totalBefore": String(baseline.total),
                        "totalAfter": String(enriched.total),
                    ]
                )
                return enriched
            }
        } catch {
            await telemetryWarning(
                "lead.score.ai.failed",
                data: [
                    "host": Self.hostOrEmpty(node),
                    "reason": error.localizedDescription,
                ]
            )
        }
        return baseline
    }

    // MARK: - Node → LeadScoreInput lift

    /// Maps a SwiftData `Node` to a pure value-type input. Lives in
    /// AuditKit because the score is owned here; keeping the lift
    /// in this file means the heuristic is the only thing that
    /// knows the field-by-field projection.
    public static func input(from node: Node) -> LeadScoreInput {
        let host = Self.urlHost(of: node)
        // Walk incoming edges to find the freshest audit Node so we
        // can read the persisted score tags (`score-<int>`, etc.).
        let freshAudit = (node.incoming ?? [])
            .compactMap { $0.from }
            .filter { $0.kindRaw == NodeKind.audit.rawValue }
            .sorted { $0.createdAt > $1.createdAt }
            .first

        let overall = freshAudit.flatMap(Self.auditTagInt(prefix: "score-"))
        let security = freshAudit.flatMap(Self.auditTagInt(prefix: "security-"))
        let perf = freshAudit.flatMap(Self.auditTagInt(prefix: "perf-"))

        return LeadScoreInput(
            tags: node.tags,
            content: node.content,
            urlHost: host,
            lastAccessedAt: node.lastAccessedAt,
            hasAuditAttached: freshAudit != nil,
            auditOverallScore: overall,
            auditSecurityScore: security,
            auditPerformanceScore: perf,
            now: .now
        )
    }

    // MARK: - Helpers

    /// Allowlist of hostnames known to belong to high-ICP SaaS B2B
    /// prospects. Kept small on purpose — the AI path can stretch
    /// beyond this. Hosts compared case-insensitive, stripped of
    /// "www." prefix. Update sparingly.
    private static let knownSaaSHosts: Set<String> = [
        "stripe.com",
        "linear.app",
        "notion.so",
        "notion.com",
        "figma.com",
        "vercel.com",
        "cloudflare.com",
        "github.com",
        "gitlab.com",
        "datadoghq.com",
        "anthropic.com",
        "openai.com",
        "supabase.com",
        "supabase.co",
        "twilio.com",
    ]

    static func isKnownSaaSHost(_ host: String) -> Bool {
        let normalized = host
            .lowercased()
            .replacingOccurrences(of: "www.", with: "")
        return knownSaaSHosts.contains(normalized)
    }

    private static func urlHost(of node: Node) -> String? {
        guard let url = URL(string: node.content),
              let host = url.host(percentEncoded: false) else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private static func hostOrEmpty(_ node: Node) -> String {
        urlHost(of: node) ?? ""
    }

    /// Parses a single tag of the shape `prefix-<integer>` off the
    /// freshest audit Node (e.g. `score-72`, `security-45`). Returns
    /// nil when the prefix isn't present.
    private static func auditTagInt(prefix: String) -> (Node) -> Int? {
        return { node in
            node.tags
                .first { $0.hasPrefix(prefix) }
                .flatMap { Int($0.dropFirst(prefix.count)) }
        }
    }

    static func daysSince(_ date: Date, now: Date) -> Int {
        let interval = now.timeIntervalSince(date)
        guard interval >= 0 else { return 0 }
        return Int(interval / (24 * 3600))
    }

    // MARK: - AI prompt

    static func aiPrompt(baseline: LeadScore, node: Node) -> String {
        // Compact, deterministic prompt. Claude returns a JSON object
        // of the same shape so the parser stays a one-pass JSONDecoder.
        let host = urlHost(of: node) ?? ""
        let tags = node.tags.joined(separator: ", ")
        return """
        You are MIND's Lead Scoring re-ranker. Read a prospect's notes
        and the baseline heuristic score; return a refined LeadScore
        for the same prospect.

        Prospect
        --------
        Name: \(node.title)
        Host: \(host)
        Tags: \(tags)
        Notes (truncated): \(node.content.prefix(800))

        Baseline (heuristic)
        --------------------
        total: \(baseline.total)
        icpFit: \(baseline.icpFit) (max 40)
        buyingSignals: \(baseline.buyingSignals) (max 40)
        engagement: \(baseline.engagement) (max 20, do not change)

        Output schema (JSON, no prose, no markdown fences):
        {
          "icpFit": <0..40>,
          "buyingSignals": <0..40>,
          "reasoning": ["3-5 short bullets in French"]
        }
        """
    }

    static func parseAIResponse(
        _ response: String,
        baseline: LeadScore
    ) -> LeadScore? {
        struct Payload: Decodable {
            let icpFit: Int
            let buyingSignals: Int
            let reasoning: [String]
        }
        // Strip whitespace + optional ```json fences.
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .split(separator: "\n")
                .dropFirst()
                .dropLast()
                .joined(separator: "\n")
        }
        guard let data = cleaned.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !payload.reasoning.isEmpty
        else { return nil }
        let icp = max(0, min(40, payload.icpFit))
        let buy = max(0, min(40, payload.buyingSignals))
        return LeadScore(
            total: icp + buy + baseline.engagement,
            icpFit: icp,
            buyingSignals: buy,
            engagement: baseline.engagement,
            computedAt: .now,
            reasoning: payload.reasoning
        )
    }
}

/// v0.27 — Pure value-type lift of the `Node` fields the heuristic
/// reads. Living right next to `LeadScorer` so the lift is the only
/// place that knows the projection. Tests construct one directly so
/// they never have to spin up a SwiftData container.
public struct LeadScoreInput: Sendable, Equatable {
    public let tags: [String]
    public let content: String
    public let urlHost: String?
    public let lastAccessedAt: Date?
    public let hasAuditAttached: Bool
    public let auditOverallScore: Int?
    public let auditSecurityScore: Int?
    public let auditPerformanceScore: Int?
    public let now: Date

    public init(
        tags: [String] = [],
        content: String = "",
        urlHost: String? = nil,
        lastAccessedAt: Date? = nil,
        hasAuditAttached: Bool = false,
        auditOverallScore: Int? = nil,
        auditSecurityScore: Int? = nil,
        auditPerformanceScore: Int? = nil,
        now: Date = .now
    ) {
        self.tags = tags
        self.content = content
        self.urlHost = urlHost
        self.lastAccessedAt = lastAccessedAt
        self.hasAuditAttached = hasAuditAttached
        self.auditOverallScore = auditOverallScore
        self.auditSecurityScore = auditSecurityScore
        self.auditPerformanceScore = auditPerformanceScore
        self.now = now
    }
}

// MARK: - Telemetry shims

/// Module-level helpers that hop telemetry calls onto the MainActor.
/// Same pattern as `OutreachEmailGenerator`'s `telemetryInfo` — keeps
/// the actor-isolated paths from having to know that MINDTelemetry is
/// `@MainActor`.
@MainActor
private func telemetryInfoMain(_ name: String, data: [String: String]) {
    MINDTelemetry.info(name, data: data)
}

@MainActor
private func telemetryWarningMain(_ name: String, data: [String: String]) {
    MINDTelemetry.warning(name, data: data)
}

private func telemetryInfo(_ name: String, data: [String: String]) async {
    await telemetryInfoMain(name, data: data)
}

private func telemetryWarning(_ name: String, data: [String: String]) async {
    await telemetryWarningMain(name, data: data)
}
