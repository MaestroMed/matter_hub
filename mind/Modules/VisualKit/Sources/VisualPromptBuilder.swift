import Foundation
import AuditKit
import Intelligence

public enum VisualPromptBuilderError: Error, LocalizedError, Sendable {
    case claudeFailed(String)
    case noPromptsReturned

    public var errorDescription: String? {
        switch self {
        case .claudeFailed(let message): return "Claude: \(message.prefix(140))"
        case .noPromptsReturned: return "Claude n'a pas renvoyé de prompts utilisables."
        }
    }
}

/// Uses Claude to compose N world-class GPT Image 2 prompts per
/// category (logo / homepage / lifestyle photo / app screen),
/// conditioned on the audit persona, the client's stated USP, and the
/// brand signals the audit picked up (palette hints, tone of voice).
///
/// Why through Claude rather than handcrafted templates: the prompt
/// quality is the single biggest lever on the output. A prompt tuned
/// to the prospect's actual industry + maturity beats a generic
/// "modern minimalist logo" template by an order of magnitude.
@MainActor
public final class VisualPromptBuilder {
    private let cloud: CloudIntelligence

    public init(cloud: CloudIntelligence? = nil) {
        let configured = cloud ?? CloudIntelligence()
        configured.maxTokens = 4096
        self.cloud = configured
    }

    public func buildPrompts(
        for report: AuditReport,
        kind: VisualConcept.Kind,
        variants: Int = 3
    ) async throws -> [String] {
        let request = buildClaudeRequest(report: report, kind: kind, variants: variants)
        do {
            let response = try await cloud.complete(prompt: request)
            return parsePrompts(from: response, expecting: variants)
        } catch {
            throw VisualPromptBuilderError.claudeFailed(error.localizedDescription)
        }
    }

    // MARK: - Composing the Claude prompt

    private func buildClaudeRequest(
        report: AuditReport,
        kind: VisualConcept.Kind,
        variants: Int
    ) -> String {
        let categoryBrief = categoryBrief(for: kind)
        return """
        Tu es un directeur artistique world-class spécialiste de visual identity premium. Tu compose des prompts d'image pour GPT Image 2 (OpenAI, lancé en avril 2026 — modèle text-to-image SOTA).

        Contexte client (issu de l'audit MIND):
          - Nom: \(report.client.displayName)
          - URL: \(report.client.url.absoluteString)
          - Persona: \(report.persona.label)
          - Score global: \(report.scoring.overall)/100 (perf \(report.scoring.performance), seo \(report.scoring.seo), brand \(report.scoring.brand))
          - Synthèse: \(report.synthesis.prefix(900))

        Mission: produire \(variants) prompts GPT Image 2 distincts pour la catégorie « \(kind.displayName) » de ce client.

        \(categoryBrief)

        Règles de qualité GPT Image 2 SOTA (2026):
          - Toujours commencer par le style visuel (« ultra-detailed editorial photography », « clean minimalist vector design », « photoréalistic 3D render with subsurface scattering »…)
          - Décrire ensuite la composition, le sujet, les matériaux, la lumière
          - Préciser les couleurs (palette dérivée du brand client si pertinent)
          - Tenir compte du persona (saasB2B premium = épuré minimaliste, tpePme = chaleureux humain, lifestyleDTC = aspirational, other = adapté)
          - Texte dans l'image: quand c'est un logo ou wordmark, mettre le nom EXACT du client entre guillemets doubles
          - Ajouter en queue de prompt: « no watermark, no extra text, no signature, no logo drift »

        Les 3 prompts doivent être visuellement DISTINCTS — exprimer 3 directions différentes (pas 3 variantes mineures du même thème). Pour 3 logos: 3 territoires distincts (ex: typographique / symbole abstrait / monogramme). Pour 3 homepages: 3 vibes différents (ex: éditorial / produit / lifestyle). Etc.

        Tu réponds STRICTEMENT avec ce format, sans préambule, sans markdown, sans backticks:

        ===PROMPT===
        <prompt 1 complet, 60-140 mots>
        ===PROMPT===
        <prompt 2 complet, 60-140 mots>
        ===PROMPT===
        <prompt 3 complet, 60-140 mots>

        Important: exactement \(variants) blocs ===PROMPT===. Aucun autre texte.
        """
    }

    private func categoryBrief(for kind: VisualConcept.Kind) -> String {
        switch kind {
        case .logo:
            return """
            Catégorie « Logo concepts »:
              - Format: app icon iOS 26 squircle 1024×1024, fond neutre clair (pearl) ou gradient subtil
              - Le nom du client doit apparaître dans l'image (texte intégré pour les options typographiques uniquement)
              - Optimisé pour lecture mobile et favicon
              - Vibe premium type Linear, Stripe, Vercel, Apple
            """
        case .homepage:
            return """
            Catégorie « Homepage mockups »:
              - Format: mockup desktop landscape 1536×1024
              - Vue de la home complète avec hero + nav + section produit + footer visible
              - Design system cohérent (palette, typo, composants)
              - Showcase d'un design premium SOTA 2026 (gradients glassmorphism, typography lourde et aérée, micro-interactions implicites)
            """
        case .lifestyle:
            return """
            Catégorie « Photos lifestyle / ambiance »:
              - Format: photographie éditoriale 1536×1024
              - Mettre en scène l'usage du produit/service dans un contexte aspirationnel et crédible
              - Lumière naturelle premium, palette cohérente avec le brand
              - Composition cinéma 35mm ou éditorial Wallpaper magazine
            """
        case .appScreen:
            return """
            Catégorie « App mobile screens »:
              - Format: mockup iPhone screen 1024×1536 portrait
              - Affiche une screen-key de l'app mobile native (home dashboard, feature principale, ou onboarding)
              - Design Liquid Glass iOS 26 (ultraThinMaterial, gradients pastels, capsules continuous)
              - L'iPhone est rendu en floating mockup (pas tenu en main), background propre
            """
        }
    }

    // MARK: - Parsing

    private func parsePrompts(from response: String, expecting count: Int) -> [String] {
        let clean = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = "===PROMPT==="
        let parts = clean
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return [clean] }   // fallback: use the whole response as a single prompt
        if parts.count >= count { return Array(parts.prefix(count)) }
        return parts
    }
}
