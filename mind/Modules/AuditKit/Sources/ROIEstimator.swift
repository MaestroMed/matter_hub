import Foundation
import Intelligence
import GraphCore   // MINDTelemetry

/// v0.25 — ROI Calculator.
///
/// Numbers convert. The ROI Calculator is the literal selling
/// argument: for each Quick Win in an audit, Claude estimates the
/// monthly €€€ revenue impact (conversion lift × estimated traffic
/// × estimated ARPU). The client sees the per-QW number inline AND
/// a hero "Total ROI estimé" card above the Quick Wins section.
///
/// Architecture:
/// - `ROIPromptBuilder` (pure namespace) — turns an
///   `(AuditReport, ClientContext)` pair into the prompt string +
///   parses the JSON response. Exercised by `ROIEstimatorTests`
///   without ever touching the network.
/// - `ROIEstimator` (actor) — wraps the `CloudIntelligence`
///   facade so the network call hops off the MainActor. Soft-fails
///   to `[:]` on any error so a missing-key install or a network
///   blackout never sinks the audit completion banner.
/// - `ClientContext` (Sendable value) — optional industry + traffic
///   + ARPU signals the caller can attach before kicking off the
///   estimator. Defaults to `unknown` so the estimator works from
///   the audit alone (Claude falls back to industry priors).
/// - `ROIEstimate` (Sendable value) — one per Quick Win, keyed by
///   `QuickWin.id` so `AuditController` can fold them back into the
///   live report by matching IDs.
///
/// Why an actor (not `@MainActor`): the HTTP round trip
/// + JSON parse routinely takes 6-12s. Pinning that to the main
/// actor would block UI ticks (probe state animations, scroll). The
/// actor isolation gives us serial estimator access without dragging
/// the request onto the MainActor queue.
public actor ROIEstimator {
    /// Shared singleton — the host app reaches the estimator from
    /// `AuditController.kickOffROIEstimation`. Tests inject their
    /// own instance with a stubbed `CloudIntelligence`.
    public static let shared = ROIEstimator()

    /// Pluggable LLM facade so tests can swap `CloudIntelligence`
    /// for a deterministic stub. `CloudIntelligence` is
    /// `@MainActor` so we hold an `@unchecked Sendable` box around
    /// it — every call hops back to the MainActor.
    public let intelligence: CloudIntelligenceHandle

    public init(intelligence: CloudIntelligenceHandle = .live) {
        self.intelligence = intelligence
    }

    /// Estimate ROI for every Quick Win in the report. Returns a
    /// `[QuickWin.id: ROIEstimate]` dictionary so the caller can
    /// fold the values back into `report.quickWins[i]` without
    /// caring about ordering. Soft-fails to `[:]` on any error so
    /// the audit completion banner is never blocked on a hot LLM
    /// path.
    public func estimate(
        report: AuditReport,
        clientContext: ClientContext = .unknown
    ) async throws -> [UUID: ROIEstimate] {
        guard !report.quickWins.isEmpty else { return [:] }
        let prompt = ROIPromptBuilder.build(report: report, context: clientContext)
        let host = report.client.url.host(percentEncoded: false)
            ?? report.client.url.absoluteString
        await telemetryInfo(
            "roi.estimation.started",
            data: [
                "host": host,
                "quickWins": String(report.quickWins.count),
            ]
        )
        let response: String
        do {
            response = try await intelligence.complete(prompt)
        } catch {
            await telemetryWarning(
                "roi.estimation.failed",
                data: [
                    "host": host,
                    "stage": "network",
                    "reason": error.localizedDescription,
                ]
            )
            return [:]
        }
        let raw = ROIPromptBuilder.stripFences(response)
        guard let data = raw.data(using: .utf8) else {
            await telemetryWarning(
                "roi.estimation.failed",
                data: ["host": host, "stage": "encode"]
            )
            return [:]
        }
        let payload: ROIPromptBuilder.Payload
        do {
            payload = try JSONDecoder().decode(
                ROIPromptBuilder.Payload.self,
                from: data
            )
        } catch {
            await telemetryWarning(
                "roi.estimation.failed",
                data: [
                    "host": host,
                    "stage": "decode",
                    "reason": String(describing: error),
                ]
            )
            return [:]
        }
        let result = ROIPromptBuilder.mapPayload(payload, into: report.quickWins)
        await telemetryInfo(
            "roi.estimation.completed",
            data: [
                "host": host,
                "estimates": String(result.count),
                "total_eur": String(result.values
                    .map(\.monthlyRevenueImpactEUR)
                    .reduce(0, +)),
            ]
        )
        return result
    }

    // MARK: - Telemetry MainActor bridges

    /// `MINDTelemetry.info` is `@MainActor` but the actor itself is
    /// not — hop to MainActor for every breadcrumb so the call
    /// sites read cleanly without sprinkling `Task { @MainActor }`
    /// blocks around every error path.
    private func telemetryInfo(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.info(name, data: data) }
    }

    private func telemetryWarning(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.warning(name, data: data) }
    }
}

// MARK: - Pluggable Intelligence handle (test seam)

/// Minimal handle the estimator depends on. Production path uses
/// the real `CloudIntelligence`; tests inject a stub. `Sendable`
/// because the actor calls it from a non-isolated context.
public struct CloudIntelligenceHandle: Sendable {
    public let complete: @Sendable (_ prompt: String) async throws -> String

    public init(complete: @escaping @Sendable (_ prompt: String) async throws -> String) {
        self.complete = complete
    }

    /// Production wiring — bridges to the `@MainActor`
    /// `CloudIntelligence.complete`. The MainActor hop is required
    /// because `CloudIntelligence` is `@MainActor`-isolated (the
    /// Keychain read for the API key must happen on the main
    /// thread). The URLSession `await` inside `.complete(prompt:)`
    /// suspends MainActor execution, so the audit-sheet animation
    /// is never blocked for more than a `URLSession` callback's
    /// worth of work.
    public static let live: CloudIntelligenceHandle = .init { prompt in
        let task = await MainActor.run { () -> Task<String, Error> in
            let client = CloudIntelligence()
            return Task { @MainActor in
                try await client.complete(prompt: prompt)
            }
        }
        return try await task.value
    }
}

// MARK: - Client context

/// Optional grounding signals. Every field is nullable so the
/// caller can attach just an industry guess, or just an ARPU, or
/// nothing at all. The prompt builder branches on each axis.
public struct ClientContext: Sendable, Equatable {
    public let industry: String?
    public let estimatedMonthlyTraffic: Int?
    public let estimatedARPU_EUR: Int?

    public init(
        industry: String? = nil,
        estimatedMonthlyTraffic: Int? = nil,
        estimatedARPU_EUR: Int? = nil
    ) {
        self.industry = industry
        self.estimatedMonthlyTraffic = estimatedMonthlyTraffic
        self.estimatedARPU_EUR = estimatedARPU_EUR
    }

    /// Convenience: no signals attached. Claude infers everything
    /// from the audit + its industry priors.
    public static let unknown = ClientContext()
}

// MARK: - ROI estimate value

/// One ROI estimate for one Quick Win. Surfaces the monthly impact,
/// the confidence level, and a short 1-2 sentence reasoning string
/// the methodology modal renders verbatim for transparency.
public struct ROIEstimate: Sendable, Equatable, Hashable {
    public let quickWinID: UUID
    public let monthlyRevenueImpactEUR: Int
    public let confidence: AuditReport.ConfidenceLevel
    public let reasoning: String

    public init(
        quickWinID: UUID,
        monthlyRevenueImpactEUR: Int,
        confidence: AuditReport.ConfidenceLevel,
        reasoning: String
    ) {
        self.quickWinID = quickWinID
        self.monthlyRevenueImpactEUR = monthlyRevenueImpactEUR
        self.confidence = confidence
        self.reasoning = reasoning
    }
}

// MARK: - Pure prompt builder + payload mapper

/// Namespace housing the pure parts of the estimator: prompt
/// assembly, response fence stripping, JSON decoding shape, and
/// the mapping from "Claude returned N estimates" back into the
/// per-QW dictionary the controller folds into `report.quickWins`.
public enum ROIPromptBuilder {
    /// Cap so a 30-QW audit doesn't blow the token budget. The
    /// AuditSheet renders QWs in priority order, so trimming from
    /// the tail preserves the most impactful items.
    public static let maxQuickWins = 10

    // MARK: Prompt

    /// Build the full prompt string Claude receives. Deterministic
    /// — identical inputs produce byte-identical prompts so the
    /// "regenerate" CTA in a future iteration could hit a cache.
    public static func build(
        report: AuditReport,
        context: ClientContext
    ) -> String {
        let clientName = report.client.displayName
        let host = report.client.url.host(percentEncoded: false)
            ?? report.client.url.absoluteString
        let persona = report.persona.label
        let scoring = report.scoring

        let trimmedWins = selectQuickWins(report.quickWins)
        let winsBlock = trimmedWins.enumerated().map { (idx, win) -> String in
            """
              {
                "id": "\(win.id.uuidString)",
                "rank": \(idx + 1),
                "title": "\(escape(win.title))",
                "detail": "\(escape(win.detail))",
                "impact": "\(win.impact.rawValue)",
                "effortDays": \(win.effortDays)
              }
            """
        }.joined(separator: ",\n")

        let industryLine = context.industry?.trimmedNonEmpty
            .map { "- Industry: \($0)" } ?? "- Industry: unknown (infer from URL + persona)"
        let trafficLine = context.estimatedMonthlyTraffic
            .map { "- Estimated monthly traffic: \($0)" }
            ?? "- Estimated monthly traffic: unknown (use industry priors)"
        let arpuLine = context.estimatedARPU_EUR
            .map { "- Estimated ARPU (EUR / customer): \($0)" }
            ?? "- Estimated ARPU (EUR / customer): unknown (use industry priors)"

        return """
        You are the ROI calculator for MIND — a premium audit tool. For every Quick Win below, estimate the monthly EUR revenue impact for the client if they shipped it.

        Client:
          - Name: \(clientName)
          - URL host: \(host)
          - Persona: \(persona)
          - Overall audit score: \(scoring.overall)/100 (performance: \(scoring.performance), seo: \(scoring.seo), security: \(scoring.security), brand: \(scoring.brand), mobile: \(scoring.mobile))

        Client context:
        \(industryLine)
        \(trafficLine)
        \(arpuLine)

        Quick Wins to estimate (in priority order, max \(maxQuickWins)):
        [
        \(winsBlock)
        ]

        Reasoning approach for each Quick Win:
          1. Estimate a conversion-lift percentage (or revenue-protected percentage for security/compliance items). Be realistic — most quick wins move 0.5%-5%, not 30%.
          2. Multiply by estimated monthly traffic × estimated ARPU (when both grounded), or by an industry-prior monthly revenue baseline (when not).
          3. Cap the per-win impact at 30 000 EUR/month so a single optimistic estimate doesn't dominate the hero total.
          4. Assign a confidence level:
             - "high" when 2+ signals are grounded (industry + traffic, or industry + ARPU, or all three).
             - "medium" when 1 signal is grounded.
             - "low" when zero signals are grounded (pure industry prior).
          5. Write 1-2 short sentences explaining the formula you used so the user can sanity-check the number in the methodology modal. Plain text, no markdown.

        Reply STRICTLY with valid JSON, no backticks, no prose before or after, no markdown. Exact schema:

        {
          "estimates": [
            {
              "id": "<UUID — must echo the Quick Win id verbatim>",
              "monthlyRevenueImpactEUR": <integer EUR, 0..30000>,
              "confidence": "low" | "medium" | "high",
              "reasoning": "<1-2 sentences explaining the formula>"
            }
          ]
        }

        Rules:
          - Every Quick Win in the input list must have exactly one estimate in the output, with the same id.
          - Integers only for `monthlyRevenueImpactEUR` (no decimals, no strings).
          - Reasoning must reference at least one of: the conversion lift %, the traffic figure, the ARPU figure, or the industry baseline.
          - No additional fields outside the schema. No text outside the JSON object.
        """
    }

    /// Cap the QW list so a noisy audit doesn't blow the token
    /// budget. Preserves priority order (top N).
    public static func selectQuickWins(
        _ wins: [AuditReport.QuickWin]
    ) -> [AuditReport.QuickWin] {
        Array(wins.prefix(maxQuickWins))
    }

    // MARK: Response parsing

    /// Strip fenced-code wrappers Claude occasionally adds even
    /// when asked for raw JSON. Mirrors `ClaudeSynthesizer`'s
    /// helper so the two stay in lock-step.
    public static func stripFences(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        return trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// JSON shape the estimator decodes the response into.
    /// Public so the test suite can build its own response strings.
    public struct Payload: Codable, Equatable, Sendable {
        public let estimates: [Estimate]

        public struct Estimate: Codable, Equatable, Sendable {
            public let id: String
            public let monthlyRevenueImpactEUR: Int
            public let confidence: String
            public let reasoning: String

            public init(
                id: String,
                monthlyRevenueImpactEUR: Int,
                confidence: String,
                reasoning: String
            ) {
                self.id = id
                self.monthlyRevenueImpactEUR = monthlyRevenueImpactEUR
                self.confidence = confidence
                self.reasoning = reasoning
            }
        }

        public init(estimates: [Estimate]) {
            self.estimates = estimates
        }
    }

    /// Fold a decoded payload back into a `[QuickWin.id: ROIEstimate]`
    /// dictionary the controller can apply on the MainActor.
    /// Unknown IDs are dropped silently — Claude occasionally
    /// hallucinates an extra id and we'd rather lose the badge than
    /// crash the audit flow. Negative impacts are clamped to 0,
    /// values > 30k EUR are clamped down so a single optimistic
    /// estimate can't dominate the hero total.
    public static func mapPayload(
        _ payload: Payload,
        into quickWins: [AuditReport.QuickWin]
    ) -> [UUID: ROIEstimate] {
        let knownIDs = Set(quickWins.map(\.id))
        var out: [UUID: ROIEstimate] = [:]
        for est in payload.estimates {
            guard let uuid = UUID(uuidString: est.id),
                  knownIDs.contains(uuid)
            else { continue }
            let clamped = max(0, min(30_000, est.monthlyRevenueImpactEUR))
            let confidence = AuditReport.ConfidenceLevel(rawValue: est.confidence)
                ?? .medium
            out[uuid] = ROIEstimate(
                quickWinID: uuid,
                monthlyRevenueImpactEUR: clamped,
                confidence: confidence,
                reasoning: est.reasoning
            )
        }
        return out
    }

    // MARK: - Aggregation helpers (used by AuditSheet + portal)

    /// Sum of the per-QW monthly impacts. Excludes nil and < 0
    /// entries. Used by the hero card to render "+18 700 €/mo".
    public static func monthlyTotalEUR(for wins: [AuditReport.QuickWin]) -> Int {
        wins.reduce(0) { acc, win in
            acc + max(0, win.estimatedMonthlyRevenueImpactEUR ?? 0)
        }
    }

    /// 12-month annualised total. Mirrors the methodology modal
    /// subtitle ("ROI estimé sur 12 mois").
    public static func annualisedTotalEUR(for wins: [AuditReport.QuickWin]) -> Int {
        monthlyTotalEUR(for: wins) * 12
    }

    /// Confidence aggregate = the **most conservative** of the
    /// per-QW confidence levels with a non-nil impact. A hero card
    /// claiming "high confidence" when one of the estimates was
    /// "low" would be dishonest, so we take the floor.
    /// Returns nil when no QW has a confidence value (the hero
    /// card hides the confidence pill in that case).
    public static func aggregateConfidence(
        for wins: [AuditReport.QuickWin]
    ) -> AuditReport.ConfidenceLevel? {
        let levels = wins.compactMap { win -> AuditReport.ConfidenceLevel? in
            // Only consider QWs that actually contribute to the
            // total (have a non-nil impact). A QW with a confidence
            // tag but a nil impact shouldn't drag the aggregate
            // down.
            guard win.estimatedMonthlyRevenueImpactEUR != nil else { return nil }
            return win.confidence
        }
        guard !levels.isEmpty else { return nil }
        // Rank low < medium < high; aggregate = min.
        let rank: [AuditReport.ConfidenceLevel: Int] = [.low: 0, .medium: 1, .high: 2]
        return levels.min { (rank[$0] ?? 1) < (rank[$1] ?? 1) }
    }

    /// True iff at least one QW has a non-nil monthly impact. The
    /// AuditSheet hero card + the portal hero card are mounted
    /// only when this is true.
    public static func hasAnyEstimate(in wins: [AuditReport.QuickWin]) -> Bool {
        wins.contains { ($0.estimatedMonthlyRevenueImpactEUR ?? 0) > 0 }
    }

    // MARK: - Helpers

    private static func escape(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

private extension String {
    /// nil when the trimmed string is empty, the trimmed string
    /// otherwise. Used by the prompt builder so an explicitly
    /// blank industry string doesn't surface as `"Industry: "`.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
