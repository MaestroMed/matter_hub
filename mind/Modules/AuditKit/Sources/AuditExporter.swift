import Foundation

/// Pure-function exporters that turn an `AuditReport` into shareable
/// payloads — Markdown for Notion/Linear/Obsidian, JSON for
/// Make/Zapier/n8n pipelines, HTML for a polished email body.
///
/// PDF export already lives in the App target as `PDFReportRenderer`
/// because it depends on PDFKit + SwiftUI ImageRenderer; the three
/// formats here stay framework-pure (Foundation only) so they're
/// reusable from a future Watch / Mac target without dragging UIKit.
public enum AuditExporter {

    // MARK: - Markdown

    public static func markdown(from report: AuditReport) -> String {
        var sections: [String] = []

        sections.append("""
        # Audit MIND — \(report.client.displayName)

        > Généré le \(report.generatedAt.formatted(date: .long, time: .shortened))
        > URL : \(report.client.url.absoluteString)
        > Persona : \(report.persona.label)
        > Score global : **\(report.scoring.overall) / 100**
        """)

        sections.append("""
        ## Scoring

        | Axe         | Score |
        | ----------- | ----- |
        | Performance | \(report.scoring.performance) |
        | SEO         | \(report.scoring.seo) |
        | Sécurité    | \(report.scoring.security) |
        | Brand       | \(report.scoring.brand) |
        | Mobile      | \(report.scoring.mobile) |
        | **Global**  | **\(report.scoring.overall)** |
        """)

        if let perf = report.performance {
            sections.append("""
            ## Core Web Vitals

            - Performance Lighthouse : \(perf.performanceScore)/100
            - SEO Lighthouse : \(perf.seoScore)/100
            - Accessibilité : \(perf.accessibilityScore)/100
            - Best practices : \(perf.bestPracticesScore)/100
            - LCP : \(perf.largestContentfulPaintSeconds.map { String(format: "%.2fs", $0) } ?? "n/a")
            - INP : \(perf.interactionToNextPaintMs.map { "\($0) ms" } ?? "n/a")
            - CLS : \(perf.cumulativeLayoutShift.map { String(format: "%.3f", $0) } ?? "n/a")
            """)
        }

        sections.append("## Synthèse\n\n\(report.synthesis)")

        if !report.quickWins.isEmpty {
            var block = "## Quick wins\n"
            for (idx, win) in report.quickWins.enumerated() {
                block += "\n\(idx + 1). **\(win.title)** *(\(formatEffort(win.effortDays)), impact \(win.impact.rawValue))* — \(win.detail)"
            }
            sections.append(block)
        }

        if !report.strategicBets.isEmpty {
            var block = "## Paris stratégiques\n"
            for (idx, bet) in report.strategicBets.enumerated() {
                block += "\n\(idx + 1). **\(bet.title)** *(\(bet.durationMonths) mois, €\(bet.budgetMinEUR / 1000)k–€\(bet.budgetMaxEUR / 1000)k)* — \(bet.detail)"
            }
            sections.append(block)
        }

        if !report.hiddenRisks.isEmpty {
            var block = "## Risques cachés\n"
            for risk in report.hiddenRisks {
                block += "\n- **[\(risk.severity.rawValue.uppercased())] \(risk.title)** — \(risk.detail)"
            }
            sections.append(block)
        }

        if let findings = report.findings, findings.hasAnyData {
            sections.append(findingsMarkdown(findings))
        }

        sections.append("## Pitch prêt à envoyer\n\n\(report.pitch)")

        sections.append("""
        ---
        *Audit produit par MIND — app.mind.ios*
        """)

        return sections.joined(separator: "\n\n")
    }

    private static func findingsMarkdown(_ f: AuditFindings) -> String {
        var lines: [String] = ["## Détails techniques"]

        if let security = f.security {
            lines.append("""
            - **Sécurité** : grade \(security.grade) (\(security.score)/100), TLS \(security.tlsValid ? "valide" : "invalide"). Headers manquants : \(security.missingHeaders.isEmpty ? "aucun" : security.missingHeaders.joined(separator: ", "))
            """)
        }
        if let email = f.email {
            lines.append("""
            - **Email** : provider \(email.provider ?? "inconnu") · SPF \(email.hasSPF ? "✓" : "✗") · DMARC \(email.hasDMARC ? "✓" : "✗")
            """)
        }
        if let domain = f.domain {
            let age = domain.ageYears.map { String(format: "%.1f", $0) + " ans" } ?? "n/a"
            lines.append("- **Domaine** : registrar \(domain.registrar ?? "inconnu") · âge \(age)")
        }
        if let mobile = f.mobile {
            if mobile.hasIOSApp {
                let rating = mobile.averageRating.map { String(format: "%.1f", $0) + "★" } ?? "n/a"
                lines.append("- **App iOS** : « \(mobile.appName ?? "?") » (\(rating), \(mobile.ratingCount ?? 0) avis)")
            } else {
                lines.append("- **App iOS** : aucune — opportunité native potentielle")
            }
        }
        if let schema = f.schema {
            let types = schema.detectedTypes.isEmpty ? "aucun" : schema.detectedTypes.joined(separator: ", ")
            lines.append("- **Schema.org** : JSON-LD \(schema.hasJSONLD ? "présent" : "ABSENT") · types : \(types)")
        }
        if let og = f.openGraph {
            lines.append("- **OpenGraph** : complétude \(og.completenessScore)/100")
        }
        if let crawl = f.crawlability {
            let smap = crawl.hasSitemap ? "présent\(crawl.sitemapURLCount.map { " (\($0) URLs)" } ?? "")" : "ABSENT"
            lines.append("- **Crawlability** : robots.txt \(crawl.hasRobotsTxt ? "présent" : "ABSENT") · sitemap.xml \(smap)")
        }
        if let comp = f.compliance {
            lines.append("- **Compliance** : cookie banner \(comp.hasCookieBanner ? "présent" : "ABSENT")\(comp.cookieProvider.map { " (\($0))" } ?? "") · privacy \(comp.hasPrivacyLink ? "✓" : "✗") · CGU \(comp.hasTermsLink ? "✓" : "✗")")
        }
        if let analytics = f.analytics {
            let providers = analytics.providers.isEmpty ? "aucun" : analytics.providers.joined(separator: ", ")
            lines.append("- **Analytics** : \(providers) · error tracking \(analytics.hasErrorTracking ? "✓" : "✗")")
        }
        if let payment = f.payment {
            let processors = payment.processors.isEmpty ? "aucun" : payment.processors.joined(separator: ", ")
            lines.append("- **Payment** : \(processors)\(payment.hasPayWall ? " · pay-wall détecté" : "")")
        }
        if let cdn = f.cdn {
            lines.append("- **CDN / Hosting** : \(cdn.provider ?? "inconnu")\(cdn.serverHeader.map { " (server: \($0))" } ?? "")")
        }
        if let trust = f.trust, let score = trust.trustpilotScore, let count = trust.trustpilotReviewCount {
            lines.append("- **Trustpilot** : \(String(format: "%.1f", score))★ (\(count) avis)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON

    public static func json(from report: AuditReport) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(report)
    }

    // MARK: - HTML email

    public static func htmlEmail(from report: AuditReport) -> String {
        let topWins = report.quickWins.prefix(5).enumerated().map { idx, win in
            "<li><strong>\(escape(win.title))</strong> <em>(\(formatEffort(win.effortDays)), impact \(escape(win.impact.rawValue)))</em><br>\(escape(win.detail))</li>"
        }.joined()

        let topBets = report.strategicBets.prefix(3).enumerated().map { idx, bet in
            "<li><strong>\(escape(bet.title))</strong> <em>(\(bet.durationMonths) mois, €\(bet.budgetMinEUR / 1000)k–€\(bet.budgetMaxEUR / 1000)k)</em><br>\(escape(bet.detail))</li>"
        }.joined()

        let pitchHTML = escape(report.pitch).replacingOccurrences(of: "\n", with: "<br>")

        return """
        <!doctype html>
        <html lang="fr">
        <head>
        <meta charset="utf-8">
        <title>Audit MIND — \(escape(report.client.displayName))</title>
        </head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,'SF Pro Rounded',Inter,Helvetica,Arial,sans-serif;background:#F7F6FA;color:#1a1a1a;line-height:1.55;margin:0;padding:24px 16px;">
          <table role="presentation" cellpadding="0" cellspacing="0" align="center" style="max-width:640px;margin:0 auto;background:#FFFFFF;border-radius:18px;overflow:hidden;box-shadow:0 12px 36px rgba(60,40,160,0.08);">
            <tr>
              <td style="padding:32px 32px 8px;border-bottom:1px solid rgba(183,171,255,0.4);">
                <div style="font-size:11px;letter-spacing:2px;color:#6B5DD3;font-weight:600;">MIND · AUDIT DIGITAL</div>
                <h1 style="margin:6px 0 0;font-size:28px;color:#1a1a1a;font-weight:600;">\(escape(report.client.displayName))</h1>
                <div style="margin-top:4px;font-size:14px;color:#666;">\(escape(report.client.url.absoluteString)) · \(escape(report.persona.label))</div>
              </td>
            </tr>
            <tr>
              <td style="padding:24px 32px;">
                <div style="display:inline-block;padding:8px 14px;border-radius:999px;background:linear-gradient(135deg,#D7CBFF,#A8E6E0);color:#1a1a1a;font-weight:700;font-size:18px;">
                  Score global : \(report.scoring.overall) / 100
                </div>
                <p style="margin-top:18px;color:#444;font-size:14px;">
                  Perf <strong>\(report.scoring.performance)</strong> · SEO <strong>\(report.scoring.seo)</strong> · Sécu <strong>\(report.scoring.security)</strong> · Brand <strong>\(report.scoring.brand)</strong> · Mobile <strong>\(report.scoring.mobile)</strong>
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding:0 32px 24px;">
                <h2 style="font-size:16px;color:#6B5DD3;letter-spacing:0.8px;text-transform:uppercase;margin:0 0 12px;">Top 5 quick wins</h2>
                <ol style="padding-left:18px;color:#333;font-size:14px;">\(topWins)</ol>
              </td>
            </tr>
            \((topBets.isEmpty ? "" : """
            <tr>
              <td style="padding:0 32px 24px;">
                <h2 style="font-size:16px;color:#6B5DD3;letter-spacing:0.8px;text-transform:uppercase;margin:0 0 12px;">Paris stratégiques</h2>
                <ol style="padding-left:18px;color:#333;font-size:14px;">\(topBets)</ol>
              </td>
            </tr>
            """))
            <tr>
              <td style="padding:0 32px 32px;">
                <h2 style="font-size:16px;color:#6B5DD3;letter-spacing:0.8px;text-transform:uppercase;margin:0 0 12px;">Proposition</h2>
                <div style="padding:18px;background:#F7F6FA;border-radius:12px;color:#222;font-size:14px;">\(pitchHTML)</div>
              </td>
            </tr>
            <tr>
              <td style="padding:12px 32px 24px;text-align:center;font-size:11px;color:#999;border-top:1px solid rgba(0,0,0,0.06);">
                Audit produit par MIND · app.mind.ios
              </td>
            </tr>
          </table>
        </body>
        </html>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Helpers

    private static func formatEffort(_ days: Double) -> String {
        if days < 1 { return "\(Int((days * 8).rounded())) h" }
        if days < 1.5 { return "1 j" }
        return "\(Int(days.rounded())) j"
    }
}
