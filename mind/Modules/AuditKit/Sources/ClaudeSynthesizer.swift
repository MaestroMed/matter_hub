import Foundation
import Intelligence

public enum ClaudeSynthesizerError: Error, LocalizedError, Sendable {
    case decodingFailed(String, rawResponse: String)

    public var errorDescription: String? {
        switch self {
        case .decodingFailed(let message, _):
            return "Synthesis JSON invalide: \(message.prefix(160))"
        }
    }
}

/// Bridges the audit pipeline to the Anthropic Messages API. Asks Claude to
/// produce a strictly-typed JSON payload describing the audit, then maps it
/// back into an `AuditReport`. Persona-aware: the system prompt explains
/// the three buyer profiles Mehdi targets so the recommendations get
/// phrased for the right room.
@MainActor
public final class ClaudeSynthesizer {
    private let cloud: CloudIntelligence

    public init(cloud: CloudIntelligence? = nil) {
        let configured = cloud ?? CloudIntelligence()
        configured.maxTokens = 4096
        self.cloud = configured
    }

    public func synthesize(
        for client: AuditClient,
        performance: AuditReport.PerformanceMetrics?
    ) async throws -> AuditReport {
        let prompt = buildPrompt(client: client, performance: performance)
        let response = try await cloud.complete(prompt: prompt)
        let json = stripFences(response)

        guard let data = json.data(using: .utf8) else {
            throw ClaudeSynthesizerError.decodingFailed(
                "could not encode response to UTF-8",
                rawResponse: response
            )
        }

        do {
            let payload = try JSONDecoder().decode(ClaudePayload.self, from: data)
            return payload.toReport(client: client, performance: performance)
        } catch {
            throw ClaudeSynthesizerError.decodingFailed(
                String(describing: error),
                rawResponse: response
            )
        }
    }

    // MARK: - Prompt

    private func buildPrompt(
        client: AuditClient,
        performance: AuditReport.PerformanceMetrics?
    ) -> String {
        let perfBlock: String
        if let p = performance {
            perfBlock = """
            Mesures Lighthouse (mobile):
              - performance score: \(p.performanceScore)/100
              - SEO score: \(p.seoScore)/100
              - accessibilité score: \(p.accessibilityScore)/100
              - best-practices score: \(p.bestPracticesScore)/100
              - LCP: \(p.largestContentfulPaintSeconds.map { String(format: "%.2fs", $0) } ?? "n/a")
              - INP: \(p.interactionToNextPaintMs.map { "\($0) ms" } ?? "n/a")
              - CLS: \(p.cumulativeLayoutShift.map { String(format: "%.3f", $0) } ?? "n/a")
            """
        } else {
            perfBlock = "Mesures Lighthouse: indisponibles (probe en échec, raisonne à partir de tes connaissances générales)."
        }

        return """
        Tu es l'auditeur digital intégré de MIND. Tu produis un audit complet d'un prospect potentiel pour Mehdi — développeur iOS premium et studio one-man.

        Client à auditer:
          - URL: \(client.url.absoluteString)
          - Nom fourni: \(client.name ?? "(inconnu — infère depuis l'URL et tes connaissances)")

        \(perfBlock)

        Trois personae cibles principalement:
          - "saasB2B" → startup SaaS B2B type Stripe, Linear, Vercel, scale-up tech
          - "tpePme"  → TPE/PME locale (artisan, retail, restaurant indépendant)
          - "lifestyleDTC" → marque fashion / lifestyle / DTC brand-driven
          - "other"   → tout ce qui ne rentre pas clairement

        Adapte les recommandations à la persona:
          - saasB2B → app mobile native iOS, performance at scale, design partner long terme, refonte design system
          - tpePme  → quick wins SEO local + Google My Business, refonte light, site rapide, formulaire de capture lead
          - lifestyleDTC → cohérence visuelle cross-platform, social commerce, app premium, packaging digital
          - other   → propose ce qui colle au contexte réel du client

        Tu réponds STRICTEMENT avec un JSON valide, sans backticks, sans texte avant ni après, sans markdown autour. Schéma exact:

        {
          "persona": "saasB2B" | "tpePme" | "lifestyleDTC" | "other",
          "scoring": {
            "overall": int 0-100,
            "performance": int 0-100,
            "seo": int 0-100,
            "security": int 0-100,
            "brand": int 0-100,
            "mobile": int 0-100
          },
          "synthesis": string markdown 300-500 mots: qui ils sont, USP, business model, audience cible, maturité digitale, frictions clés, opportunités saillantes,
          "quickWins": [
            { "title": string court, "detail": string 1-2 phrases, "effortDays": float (0.5, 1, 2, 5, etc.), "impact": "low" | "medium" | "high" }
          ] (3-5 items),
          "strategicBets": [
            { "title": string court, "detail": string 1-2 phrases, "durationMonths": int, "budgetMinEUR": int, "budgetMaxEUR": int }
          ] (1-3 items),
          "pitch": string 8-10 lignes d'email cold prêt à envoyer, ton humain, mentionne 2 frictions concrètes vues dans l'audit + une proposition concrète, signe "Mehdi"
        }

        Important:
          - Aucun caractère hors du JSON.
          - Tous les nombres sont des nombres bruts (pas de string "85").
          - Tous les champs sont obligatoires.
        """
    }

    private func stripFences(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        let withoutOpening = trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        return withoutOpening.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - JSON shapes returned by Claude

private struct ClaudePayload: Decodable {
    let persona: String
    let scoring: ScoringPayload
    let synthesis: String
    let quickWins: [QuickWinPayload]
    let strategicBets: [StrategicBetPayload]
    let pitch: String

    struct ScoringPayload: Decodable {
        let overall: Int
        let performance: Int
        let seo: Int
        let security: Int
        let brand: Int
        let mobile: Int
    }

    struct QuickWinPayload: Decodable {
        let title: String
        let detail: String
        let effortDays: Double
        let impact: String
    }

    struct StrategicBetPayload: Decodable {
        let title: String
        let detail: String
        let durationMonths: Int
        let budgetMinEUR: Int
        let budgetMaxEUR: Int
    }

    func toReport(
        client: AuditClient,
        performance: AuditReport.PerformanceMetrics?
    ) -> AuditReport {
        AuditReport(
            client: client,
            persona: AuditReport.Persona(rawValue: persona) ?? .other,
            scoring: AuditReport.Scoring(
                overall: scoring.overall,
                performance: scoring.performance,
                seo: scoring.seo,
                security: scoring.security,
                brand: scoring.brand,
                mobile: scoring.mobile
            ),
            performance: performance,
            synthesis: synthesis,
            quickWins: quickWins.map {
                AuditReport.QuickWin(
                    title: $0.title,
                    detail: $0.detail,
                    effortDays: $0.effortDays,
                    impact: AuditReport.QuickWin.Impact(rawValue: $0.impact) ?? .medium
                )
            },
            strategicBets: strategicBets.map {
                AuditReport.StrategicBet(
                    title: $0.title,
                    detail: $0.detail,
                    durationMonths: $0.durationMonths,
                    budgetMinEUR: $0.budgetMinEUR,
                    budgetMaxEUR: $0.budgetMaxEUR
                )
            },
            pitch: pitch
        )
    }
}
