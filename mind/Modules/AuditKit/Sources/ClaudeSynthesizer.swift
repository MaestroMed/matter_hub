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

/// Bridges the audit pipeline to the Anthropic Messages API. Feeds Claude
/// the raw measurements (Lighthouse + 12 structured findings sections),
/// forces a strict JSON response shape, and maps it back into a rich
/// `AuditReport`. Persona-aware: the system prompt explains the three
/// buyer profiles Mehdi targets so the recommendations get phrased for
/// the right room.
@MainActor
public final class ClaudeSynthesizer {
    private let cloud: CloudIntelligence

    public init(cloud: CloudIntelligence? = nil) {
        let configured = cloud ?? CloudIntelligence()
        configured.maxTokens = 8192  // expanded prompt → richer report
        self.cloud = configured
    }

    public func synthesize(
        for client: AuditClient,
        performance: AuditReport.PerformanceMetrics?,
        findings: AuditFindings? = nil
    ) async throws -> AuditReport {
        let prompt = buildPrompt(
            client: client,
            performance: performance,
            findings: findings
        )
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
            return payload.toReport(
                client: client,
                performance: performance,
                findings: findings
            )
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
        performance: AuditReport.PerformanceMetrics?,
        findings: AuditFindings?
    ) -> String {
        let perfBlock = performanceBlock(performance)
        let findingsBlock = self.findingsBlock(findings)

        return """
        Tu es l'auditeur digital ultra-complet de MIND. Tu produis un audit world-class d'un prospect potentiel pour Mehdi — développeur iOS premium / studio one-man qui cherche à transformer la maturité digitale de ses clients.

        Client à auditer:
          - URL: \(client.url.absoluteString)
          - Nom fourni: \(client.name ?? "(inconnu — infère depuis l'URL et tes connaissances)")

        \(perfBlock)

        \(findingsBlock)

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

        Règles de scoring (sois rigoureux, base-toi sur les mesures réelles):
          - "performance" → reflète le score Lighthouse performance
          - "seo" → s'aligne sur Lighthouse SEO + complétude OG + Schema.org + sitemap
          - "security" → reflète le grade des headers (A+/A → 90-100, B → 70-85, C → 55-70, D → 40-55, F → <40)
          - "brand" → cohérence visuelle, OG presence, Schema, brand recognition générale
          - "mobile" → présence app native iOS (mobile=20 si pas d'app, +30-40 si app présente, +10-20 selon rating)
          - "overall" → moyenne pondérée raisonnable

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
          "synthesis": string markdown 800-1500 mots structuré en sections avec headings ##:
            ## Identité (qui ils sont, USP, business model, audience cible)
            ## Maturité digitale (état actuel par axe avec citations des mesures)
            ## Frictions repérées (UX, copy, formulaires, perf, conversion)
            ## Opportunités saillantes (ce qui change tout, classé par impact)
            ## Risques cachés (ce que le prospect ignore probablement)
            ## Verdict (one-liner final)
            Cite explicitement les mesures de l'audit quand elles renforcent un point. Utilise des - bullets, des **emphases**, des [liens](url) markdown.,
          "quickWins": [
            { "title": string court, "detail": string 1-2 phrases, "effortDays": float (0.5, 1, 2, 5, etc.), "impact": "low" | "medium" | "high" }
          ] (10 à 15 items, classés par ROI décroissant),
          "strategicBets": [
            { "title": string court, "detail": string 1-2 phrases, "durationMonths": int, "budgetMinEUR": int, "budgetMaxEUR": int }
          ] (3 à 6 items, propose 1 mission low budget + 1 mid + 1 high + éventuellement option premium),
          "hiddenRisks": [
            { "title": string court, "detail": string 1-2 phrases qui expliquent l'enjeu, "severity": "low" | "medium" | "high" | "critical" }
          ] (2 à 5 items: trucs non-évidents que le prospect ignore probablement — dette technique invisible, dépendance cachée, GDPR risk, perte de revenu silencieuse, etc.),
          "pitch": string 10-15 lignes d'email cold prêt à envoyer, ton humain et précis. Mentionne 2-3 frictions concrètes vues dans l'audit (avec les chiffres réels), propose 3 options de mission (low / mid / high budget en référence aux strategicBets), termine par un CTA simple (un slot de visio). Signe "Mehdi"
        }

        Important:
          - Aucun caractère hors du JSON.
          - Tous les nombres sont des nombres bruts (pas de string "85").
          - Tous les champs sont obligatoires.
          - synthesis doit être substantiel (800-1500 mots), pas un résumé.
        """
    }

    private func performanceBlock(_ p: AuditReport.PerformanceMetrics?) -> String {
        guard let p else {
            return "Mesures Lighthouse: indisponibles (probe en échec, raisonne à partir de tes connaissances générales)."
        }
        return """
        Mesures Lighthouse (mobile):
          - performance score: \(p.performanceScore)/100
          - SEO score: \(p.seoScore)/100
          - accessibilité score: \(p.accessibilityScore)/100
          - best-practices score: \(p.bestPracticesScore)/100
          - LCP: \(p.largestContentfulPaintSeconds.map { String(format: "%.2fs", $0) } ?? "n/a")
          - INP: \(p.interactionToNextPaintMs.map { "\($0) ms" } ?? "n/a")
          - CLS: \(p.cumulativeLayoutShift.map { String(format: "%.3f", $0) } ?? "n/a")
        """
    }

    private func findingsBlock(_ findings: AuditFindings?) -> String {
        guard let findings, findings.hasAnyData else {
            return "Sondes complémentaires: aucune donnée structurée."
        }

        var lines: [String] = ["Sondes complémentaires (12 sections):"]

        if let security = findings.security {
            let present = security.presentHeaders.isEmpty ? "aucun" : security.presentHeaders.joined(separator: ", ")
            let missing = security.missingHeaders.isEmpty ? "aucun" : security.missingHeaders.joined(separator: ", ")
            lines.append("""
              SÉCURITÉ
              - grade headers: \(security.grade) (\(security.score)/100), TLS \(security.tlsValid ? "valide" : "invalide")
              - présents: \(present)
              - manquants: \(missing)
            """)
        }

        if let email = findings.email {
            let mxLine = email.mxHosts.isEmpty
                ? "aucun MX trouvé"
                : email.mxHosts.prefix(3).joined(separator: ", ")
            lines.append("""
              EMAIL
              - provider: \(email.provider ?? "inconnu")
              - MX: \(mxLine)
              - SPF: \(email.hasSPF ? "OK" : "MANQUANT") · DMARC: \(email.hasDMARC ? "OK" : "MANQUANT")
            """)
        }

        if let domain = findings.domain {
            let age = domain.ageYears.map { String(format: "%.1f", $0) + " ans" } ?? "n/a"
            lines.append("""
              DOMAINE
              - registrar: \(domain.registrar ?? "inconnu")
              - âge: \(age)
            """)
        }

        if let mobile = findings.mobile {
            if mobile.hasIOSApp {
                let rating = mobile.averageRating.map { String(format: "%.1f", $0) + "★" } ?? "n/a"
                let reviews = mobile.ratingCount.map { "\($0) avis" } ?? "0 avis"
                lines.append("""
                  MOBILE
                  - App iOS: « \(mobile.appName ?? "?") » par \(mobile.sellerName ?? "?") (\(mobile.primaryGenre ?? "?")) — \(rating), \(reviews)
                """)
            } else {
                lines.append("""
                  MOBILE
                  - App iOS: AUCUNE trouvée sur l'App Store — opportunité native potentielle
                """)
            }
        }

        if let schema = findings.schema {
            let types = schema.detectedTypes.isEmpty ? "aucun" : schema.detectedTypes.joined(separator: ", ")
            lines.append("""
              SCHEMA.ORG
              - JSON-LD: \(schema.hasJSONLD ? "présent" : "ABSENT")
              - types détectés: \(types)
            """)
        }

        if let og = findings.openGraph {
            let parts = [
                "og:title=\(og.hasTitle ? "✓" : "✗")",
                "og:description=\(og.hasDescription ? "✓" : "✗")",
                "og:image=\(og.hasImage ? "✓" : "✗")",
                "og:type=\(og.hasType ? "✓" : "✗")",
                "twitter:card=\(og.hasTwitterCard ? "✓" : "✗")",
            ].joined(separator: " ")
            lines.append("""
              OPENGRAPH
              - complétude: \(og.completenessScore)/100
              - \(parts)
            """)
        }

        if let crawl = findings.crawlability {
            let smapCount = crawl.sitemapURLCount.map { " (\($0) URLs)" } ?? ""
            lines.append("""
              CRAWLABILITY
              - robots.txt: \(crawl.hasRobotsTxt ? "présent" : "ABSENT"), autorise tout: \(crawl.allowsAllCrawlers ? "oui" : "non")
              - sitemap.xml: \(crawl.hasSitemap ? "présent\(smapCount)" : "ABSENT")
            """)
        }

        if let comp = findings.compliance {
            lines.append("""
              COMPLIANCE
              - banner cookies: \(comp.hasCookieBanner ? "présent" : "ABSENT") · vendor: \(comp.cookieProvider ?? "inconnu / custom")
              - privacy: \(comp.hasPrivacyLink ? "lien présent" : "ABSENT") · CGU: \(comp.hasTermsLink ? "lien présent" : "ABSENT")
            """)
        }

        if let analytics = findings.analytics {
            let providers = analytics.providers.isEmpty ? "aucun" : analytics.providers.joined(separator: ", ")
            lines.append("""
              ANALYTICS
              - SDKs: \(providers)
              - error-tracking: \(analytics.hasErrorTracking ? "présent" : "ABSENT")
            """)
        }

        if let payment = findings.payment {
            let processors = payment.processors.isEmpty ? "aucun" : payment.processors.joined(separator: ", ")
            lines.append("""
              PAYMENT
              - processors: \(processors)
              - pay-wall détecté: \(payment.hasPayWall ? "oui" : "non")
            """)
        }

        if let cdn = findings.cdn {
            lines.append("""
              CDN / HOSTING
              - provider: \(cdn.provider ?? "inconnu / non détecté")
              - server header: \(cdn.serverHeader ?? "n/a")
            """)
        }

        if let trust = findings.trust {
            if let score = trust.trustpilotScore, let count = trust.trustpilotReviewCount {
                lines.append("""
                  TRUST
                  - Trustpilot: \(String(format: "%.1f", score))/5 (\(count) avis)
                """)
            } else {
                lines.append("""
                  TRUST
                  - Trustpilot: pas de profile trouvé
                """)
            }
        }

        return lines.joined(separator: "\n\n")
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
    let hiddenRisks: [HiddenRiskPayload]?
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

    struct HiddenRiskPayload: Decodable {
        let title: String
        let detail: String
        let severity: String
    }

    func toReport(
        client: AuditClient,
        performance: AuditReport.PerformanceMetrics?,
        findings: AuditFindings?
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
            findings: findings,
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
            hiddenRisks: (hiddenRisks ?? []).map {
                AuditReport.HiddenRisk(
                    title: $0.title,
                    detail: $0.detail,
                    severity: AuditReport.HiddenRisk.Severity(rawValue: $0.severity) ?? .medium
                )
            },
            pitch: pitch
        )
    }
}
