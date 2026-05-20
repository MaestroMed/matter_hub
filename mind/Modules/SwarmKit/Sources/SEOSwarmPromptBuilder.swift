import Foundation

/// v1.0-alpha.7 — Pure prompt assembly + response parsing for the
/// SEO Swarm Orchestrator. Lives in its own namespace so every test
/// exercises this path without touching the network.
///
/// Two prompts: `systemPrompt()` is constant (FR senior SEO copywriter
/// instructions) and `pagePrompt(project:service:zone:)` is the per-
/// page brief Claude receives. The response parser decodes the JSON
/// payload into a `SwarmPage`.
public enum SEOSwarmPromptBuilder {

    /// FR senior SEO copywriter persona. Constant per swarm — every
    /// per-page request prepends this so Claude stays in voice
    /// across the matrix. Same shape as `OutreachPromptBuilder` and
    /// `ROIPromptBuilder` for consistency.
    public static func systemPrompt() -> String {
        return """
        Tu es un copywriter SEO senior FR avec 12 ans d'expérience dans le marketing local pour les artisans, agences et PME françaises. Tu écris en français impeccable, sans anglicismes, sans tournures corporate, sans superlatifs creux. Tu connais l'intention de recherche locale Google ("verriere puteaux", "escalier métallique 92") et la structure d'une page locale qui convertit (H1 ancré sur la requête, paragraphe d'accroche zone-spécifique, preuves de proximité, FAQ, schéma LocalBusiness).

        Règles de copy:
        - Aucune fabrication de chiffres, de prix, de témoignages clients ou de certifications.
        - Mentions locales: nomme la commune, son département, et au moins un repère géographique réel ou démographique vérifiable (ne JAMAIS inventer un quartier qui n'existe pas).
        - Densité de mots-clés naturelle, pas de bourrage. Une mention exacte de la requête principale dans le H1, deux à trois variantes dans les sous-titres.
        - Format Markdown standard pour le corps (## pour H2, ### pour H3, listes à puces). Pas de HTML, pas de fenced code blocks, pas de citation bloquante.
        - JSON-LD strictement valide: schéma `LocalBusiness` + `Service` + `areaServed` (City), encodés inline dans une string JSON sérialisée.

        Tu réponds STRICTEMENT en JSON valide, sans backticks, sans prose avant ou après, sans markdown wrapper.
        """
    }

    /// Per-page prompt. Folds the project identity, the service slug,
    /// and the zone block into a single brief Claude expands into a
    /// 1500-2500 word FR page. The output must round-trip through
    /// `Payload` below.
    public static func pagePrompt(
        project: SwarmProjectContext,
        service: String,
        zone: SwarmZone
    ) -> String {
        let trimmedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeService = trimmedService.isEmpty ? "Services" : trimmedService
        let serviceLabel = humanize(slug: safeService)

        // Population line is optional — when present, the prompt asks
        // Claude to ground the copy with the demographic context; when
        // absent, no fabrication is allowed.
        let populationLine: String
        if let pop = zone.population, pop > 0 {
            populationLine = "- Population de \(zone.displayName) : ~\(pop) habitants (à mentionner UNE fois dans l'introduction pour ancrer la dimension locale)."
        } else {
            populationLine = "- Population de \(zone.displayName) : non fournie (NE PAS inventer de chiffre démographique)."
        }

        let route = "/\(safeService.lowercased())/\(zone.slug)"

        return """
        \(systemPrompt())

        Projet client:
          - Nom : \(project.name)
          - Site : \(project.host)

        Page à générer:
          - Service ciblé : \(serviceLabel) (slug `\(safeService.lowercased())`)
          - Zone géographique : \(zone.displayName) (département \(zone.departmentCode), slug `\(zone.slug)`)
          - Route attendue : \(route)
        \(populationLine)

        Objectifs SEO:
          - Intention de recherche dominante : "\(serviceLabel.lowercased()) \(zone.displayName.lowercased())".
          - Mots-clés secondaires : "\(serviceLabel.lowercased()) \(zone.departmentCode)", "artisan \(serviceLabel.lowercased()) \(zone.displayName.lowercased())", "devis \(serviceLabel.lowercased()) \(zone.displayName.lowercased())".

        Tu génères:
          - `title` : balise <title> SEO, max 60 caractères, format "\(serviceLabel) \(zone.displayName) (\(zone.departmentCode)) — \(project.name)".
          - `metaDescription` : 150-160 caractères, copie persuasive avec call-to-action explicite (devis gratuit, intervention rapide à \(zone.displayName)).
          - `h1` : H1 conversationnel ancré sur la requête, max 70 caractères, sans répéter exactement le title.
          - `bodyMarkdown` : entre 1500 et 2500 mots en français, structure recommandée:
              1. Introduction (~150 mots) — nomme \(zone.displayName) (\(zone.departmentCode)) dès la 1ère phrase, contextualise le besoin.
              2. ## Pourquoi choisir \(project.name) pour votre projet \(serviceLabel.lowercased()) à \(zone.displayName) — preuves de proximité, sans inventer de certifications.
              3. ## Notre approche \(serviceLabel.lowercased()) à \(zone.displayName) — détail technique du service, 2-3 sous-titres ###.
              4. ## Étapes d'un projet type — liste numérotée 4-6 étapes.
              5. ## Zones d'intervention autour de \(zone.displayName) — nomme 3-4 communes limitrophes RÉELLES du département \(zone.departmentCode).
              6. ## Questions fréquentes — 4 à 6 paires Q/R en FAQ schema-ready.
              7. Conclusion + CTA explicite "Demander un devis \(serviceLabel.lowercased()) à \(zone.displayName)".
          - `jsonLD` : string JSON sérialisée d'un objet `{ "@context": "https://schema.org", "@graph": [...] }` contenant exactement:
              - Un nœud `LocalBusiness` (name = \(project.name), url = https://\(project.host)\(route), areaServed = { "@type": "City", "name": "\(zone.displayName)" }).
              - Un nœud `Service` (name = "\(serviceLabel) à \(zone.displayName)", areaServed = City \(zone.displayName), provider référencée vers le LocalBusiness ci-dessus via @id).
            Le champ `jsonLD` est une STRING contenant le JSON sérialisé, pas un objet.

        Réponds STRICTEMENT avec ce JSON, rien d'autre:

        {
          "title": "...",
          "metaDescription": "...",
          "h1": "...",
          "bodyMarkdown": "...",
          "jsonLD": "..."
        }

        Règles dures:
          - Aucun champ supplémentaire en dehors du schéma.
          - Aucun texte hors de l'objet JSON.
          - Pas de fenced code blocks autour du JSON.
          - `bodyMarkdown` est un string JSON-échappé (les `\\n` réels sont autorisés, ils seront sérialisés en `\\\\n`).
        """
    }

    // MARK: - Response parsing

    /// JSON shape the parser decodes the Claude response into. Public
    /// so test suites can construct their own response strings.
    public struct Payload: Codable, Equatable, Sendable {
        public let title: String
        public let metaDescription: String
        public let h1: String
        public let bodyMarkdown: String
        public let jsonLD: String

        public init(
            title: String,
            metaDescription: String,
            h1: String,
            bodyMarkdown: String,
            jsonLD: String
        ) {
            self.title = title
            self.metaDescription = metaDescription
            self.h1 = h1
            self.bodyMarkdown = bodyMarkdown
            self.jsonLD = jsonLD
        }
    }

    /// Strip fenced-code wrappers Claude occasionally adds even when
    /// asked for raw JSON. Mirrors `OutreachPromptBuilder.stripFences`.
    public static func stripFences(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        return trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode the response into a fresh `SwarmPage`. Returns nil when
    /// the JSON can't be decoded — the orchestrator soft-fails the
    /// page rather than the whole job in that case.
    public static func parse(
        response: String,
        service: String,
        zone: SwarmZone,
        tokensUsed: Int = 0
    ) -> SwarmPage? {
        let raw = stripFences(response)
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        let safeService = service.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let route = "/\(safeService.isEmpty ? "services" : safeService)/\(zone.slug)"
        return SwarmPage(
            serviceSlug: safeService.isEmpty ? "services" : safeService,
            zoneSlug: zone.slug,
            route: route,
            title: payload.title,
            metaDescription: payload.metaDescription,
            h1: payload.h1,
            bodyMarkdown: payload.bodyMarkdown,
            jsonLD: payload.jsonLD,
            tokensUsed: tokensUsed
        )
    }

    // MARK: - Helpers

    /// Pretty-prints a slug as a French service label. `verriere` →
    /// `Verrière`, `garde-corps` → `Garde corps`. Best-effort — the
    /// prompt also accepts already-humanised input.
    static func humanize(slug: String) -> String {
        if slug.isEmpty { return slug }
        if slug.first?.isUppercase == true { return slug }
        let dashed = slug.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard let first = dashed.first else { return dashed }
        return String(first).uppercased() + dashed.dropFirst()
    }
}

/// v1.0-alpha.7 — Lightweight value type the prompt builder consumes
/// in place of the SwiftData `Project` model. Lets `SwarmKit` stay
/// pure (no GraphCore Project dependency on its prompt path) and
/// makes the prompt builder hermetic for tests.
///
/// The App layer projects a live `Project` into a `SwarmProjectContext`
/// via the convenience init below.
public struct SwarmProjectContext: Sendable, Equatable, Hashable {
    public let id: UUID
    public let name: String
    public let host: String

    public init(id: UUID, name: String, host: String) {
        self.id = id
        self.name = name
        self.host = host
    }
}
