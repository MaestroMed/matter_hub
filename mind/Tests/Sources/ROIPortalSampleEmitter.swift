import XCTest
import Foundation
@testable import AuditKit
@testable import ClientPortalKit

/// v0.25 — One-shot emitter that writes a sample Client Portal HTML
/// to `mind/screenshots/v0.25-portal.html`. The portal contains an
/// AuditReport whose Quick Wins are pre-populated with placeholder
/// `estimatedMonthlyRevenueImpactEUR` + `confidence` values so the
/// reader can verify the ROI hero card (giant FR-formatted total,
/// 12-month annualised subtitle, confidence pill) and the per-QW
/// inline badges render end-to-end without needing a real Anthropic
/// key.
///
/// Run via:
///   xcodebuild test -only-testing:MINDTests/ROIPortalSampleEmitter
///
/// The test asserts on a few critical substrings so a regression
/// in the ROI template surfaces here instead of as a silent
/// zero-byte artefact.
final class ROIPortalSampleEmitter: XCTestCase {

    func test_emitROIPortalSample() throws {
        let client = AuditClient(
            url: URL(string: "https://acme-fintech.com")!,
            name: "Acme Fintech"
        )
        let scoring = AuditReport.Scoring(
            overall: 68,
            performance: 62,
            seo: 71,
            security: 82,
            brand: 65,
            mobile: 55
        )
        // 5 placeholder Quick Wins covering the full impact / effort
        // matrix. ROI numbers chosen so the hero card lands on a
        // headline-friendly "+18 700 €/mois" (2 400 + 6 300 + 4 200
        // + 3 800 + 2 000) with an aggregate "high" confidence.
        let wins: [AuditReport.QuickWin] = [
            .init(
                title: "Ajouter un CTA principal au-dessus de la ligne de flottaison",
                detail: "Le hero actuel n'a pas de CTA visible sans scroll — c'est la priorité conversion.",
                effortDays: 0.5,
                impact: .high,
                estimatedMonthlyRevenueImpactEUR: 2_400,
                confidence: .high
            ),
            .init(
                title: "Refondre la page tarifs pour clarifier l'offre",
                detail: "La grille mélange features et limites — distille-la en 3 colonnes lisibles.",
                effortDays: 2,
                impact: .high,
                estimatedMonthlyRevenueImpactEUR: 6_300,
                confidence: .medium
            ),
            .init(
                title: "Compresser les images du parcours d'inscription",
                detail: "Le LCP frôle 4 s sur mobile — les PNG non optimisés coûtent 70 % du temps.",
                effortDays: 1,
                impact: .medium,
                estimatedMonthlyRevenueImpactEUR: 4_200,
                confidence: .high
            ),
            .init(
                title: "Ajouter le tracking d'événements clés via PostHog ou Plausible",
                detail: "Impossible de mesurer l'impact d'un changement sans télémétrie produit.",
                effortDays: 1.5,
                impact: .medium,
                estimatedMonthlyRevenueImpactEUR: 3_800,
                confidence: .medium
            ),
            .init(
                title: "Activer HSTS et compléter la Content-Security-Policy",
                detail: "Note B sur securityheaders.com — un quick win sécurité à zéro effort produit.",
                effortDays: 0.5,
                impact: .low,
                estimatedMonthlyRevenueImpactEUR: 2_000,
                confidence: .low
            ),
        ]
        let report = AuditReport(
            client: client,
            persona: .saasB2B,
            scoring: scoring,
            performance: nil,
            findings: nil,
            synthesis: """
            # Identité
            Acme Fintech est une plateforme B2B de paiements internationaux. Audit-jouet pour la vision-verify du module ROI Calculator v0.25.

            ## Lecture stratégique
            - **Forces** : SEO solide, sécurité honorable.
            - **Frictions** : conversion sous-optimisée (CTA invisible above-the-fold), mobile en retard.
            - **Levier #1** : refonte du parcours d'inscription.
            """,
            quickWins: wins,
            strategicBets: [],
            hiddenRisks: [],
            pitch: """
            Hi Acme team,

            J'ai audité acme-fintech.com — voici ce qui ressort.

            En appliquant les 5 quick wins identifiés ci-dessus, l'impact mensuel projeté est de +18 700 €/mois (soit ~224 400 € sur 12 mois).

            Trois options :
              1. Refondre la page d'accueil (€8k, 2 semaines)
              2. Refondre tout le parcours d'inscription (€18k, 6 semaines)
              3. Partenariat design system (€36k, 3 mois)

            Un slot de visio cette semaine ?

            — Mehdi
            """
        )

        let html = HTMLTemplates.indexHTML(
            for: report,
            brand: .default,
            battle: nil
        )

        let outPath = ProcessInfo.processInfo.environment["MIND_ROI_SAMPLE_PATH"]
            ?? "/Users/mehdinafaa/Developer/matter_hub/mind/screenshots/v0.25-portal.html"
        let url = URL(fileURLWithPath: outPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(html.utf8).write(to: url, options: .atomic)
        print("ROI portal sample written to: \(outPath) (\(html.utf8.count) bytes)")

        // Sanity asserts so a regression in the ROI template
        // surfaces here, not silently as a missing hero card.
        XCTAssertTrue(html.contains("<!doctype html>"))
        XCTAssertTrue(html.contains("acme-fintech.com"))
        XCTAssertTrue(html.contains("ROI"),
                      "Portal must contain the ROI eyebrow somewhere")
        XCTAssertTrue(html.contains("Impact financier estimé"),
                      "Portal must render the ROI hero section title")
        // The roi__amount data attribute drives the count-up
        // animation; if it's missing the hero stays at 0.
        XCTAssertTrue(html.contains("data-roi-target="),
                      "ROI hero card must surface the count-up target attribute")
        XCTAssertTrue(html.contains("win__roi"),
                      "Per-QW ROI badge class must appear on at least one card")
        XCTAssertTrue(html.contains("18\u{00A0}700\u{00A0}€"),
                      "Hero total must read 18 700 € (sum of the 5 placeholders)")
    }
}
