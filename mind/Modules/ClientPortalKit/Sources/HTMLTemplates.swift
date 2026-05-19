import Foundation
import AuditKit

/// Pure HTML/CSS/JS string builders. Every helper is `static`, takes
/// value-type inputs, and returns a String — no IO, no UIKit, no
/// global state. The output is glued together by
/// `ClientPortalBuilder.generateSite(for:brand:)` and the tests
/// assert directly on substring presence.
///
/// Design philosophy
/// -----------------
/// The portal is a single `index.html` file. CSS is inlined in one
/// `<style>` block (no external stylesheet). The only outbound
/// network request is the Google Fonts preconnect — and it's
/// optional, the Apple system stack fallback covers iOS / macOS
/// readers without ever needing the network. There is **zero JS
/// framework** — the gauge animation + intersection observer are
/// vanilla ES2020 in a single inline `<script>` tag.
///
/// Aesthetic: Liquid Glass — dark gradient hero (iris → navy →
/// black), backdrop-filter blur on cards, scroll-driven fade-up on
/// section entry, scroll-snap horizontal timeline for strategic
/// bets, alert-style red-tinted hidden-risk cards, full-bleed pitch
/// quote with consultant byline. Honours `prefers-color-scheme` so
/// a light-mode reader gets a soft cream palette instead of the
/// dark gradient, and `prefers-reduced-motion` so the gauge fills
/// snap to their final values rather than animating.
public enum HTMLTemplates {

    // MARK: - Top-level envelope

    /// Builds the full `index.html` document for the given report +
    /// brand. The result already contains the `<!doctype html>` +
    /// `<html>` envelope so the writer can drop it on disk as-is.
    public static func indexHTML(
        for report: AuditReport,
        brand: BrandSettings
    ) -> String {
        let title = escape(report.client.displayName)
        let lang = "fr"
        let bodyHTML = [
            heroSection(report: report, brand: brand),
            scoringSection(report: report, brand: brand),
            synthesisSection(report: report),
            visionSection(report: report),
            quickWinsSection(report: report),
            strategicBetsSection(report: report),
            hiddenRisksSection(report: report),
            pitchSection(report: report, brand: brand),
            contactSection(report: report, brand: brand),
            footerSection(report: report, brand: brand),
        ].joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="\(lang)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <meta name="color-scheme" content="dark light">
        <meta name="theme-color" content="#0B0820" media="(prefers-color-scheme: dark)">
        <meta name="theme-color" content="#F7F6FA" media="(prefers-color-scheme: light)">
        <title>Audit MIND — \(title)</title>
        <meta name="description" content="Audit digital de \(title) — réalisé par \(escape(brand.consultantName)).">
        <meta property="og:title" content="Audit MIND — \(title)">
        <meta property="og:description" content="Audit digital — score \(report.scoring.overall)/100">
        <meta property="og:type" content="website">
        <link rel="preconnect" href="https://fonts.googleapis.com" crossorigin>
        <style>\(inlineCSS(brand: brand))</style>
        </head>
        <body>
        \(bodyHTML)
        <script>\(inlineJS())</script>
        </body>
        </html>
        """
    }

    // MARK: - Sections

    public static func heroSection(
        report: AuditReport,
        brand: BrandSettings
    ) -> String {
        let name = escape(report.client.displayName)
        let consultant = escape(brand.consultantName)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale(identifier: "fr_FR")
        let date = escape(dateFormatter.string(from: report.generatedAt))
        let persona = escape(report.persona.label)
        let host = escape(report.client.url.host(percentEncoded: false) ?? report.client.url.absoluteString)

        return """
        <header class="hero" data-parallax="true">
          <div class="hero__gradient" aria-hidden="true"></div>
          <div class="hero__grain" aria-hidden="true"></div>
          <div class="hero__inner">
            <div class="hero__eyebrow">AUDIT DIGITAL · \(persona.uppercased())</div>
            <h1 class="hero__title">\(name)</h1>
            <p class="hero__tagline">Réalisé par <strong>\(consultant)</strong> · \(date)</p>
            <a class="hero__host" href="\(escape(report.client.url.absoluteString))" target="_blank" rel="noopener">\(host) ↗</a>
            <div class="hero__scroll" aria-hidden="true">
              <span></span>
            </div>
          </div>
        </header>
        """
    }

    public static func scoringSection(
        report: AuditReport,
        brand: BrandSettings
    ) -> String {
        let s = report.scoring
        let cards: [(String, Int, String)] = [
            ("Global", s.overall, "Score pondéré"),
            ("Performance", s.performance, "Core Web Vitals"),
            ("SEO", s.seo, "Découvrabilité"),
            ("Sécurité", s.security, "Headers + TLS"),
            ("Brand", s.brand, "OpenGraph + cohérence"),
            ("Mobile", s.mobile, "App store + responsive"),
        ]

        let cardsHTML = cards.map { (label, score, sub) in
            gaugeCard(label: label, score: score, sub: sub)
        }.joined(separator: "\n")

        return """
        <section class="scoring reveal" data-reveal="up">
          <div class="section__header">
            <div class="section__eyebrow">01 — SCORING</div>
            <h2 class="section__title">Vue d'ensemble</h2>
            <p class="section__lead">Six axes mesurés, un score global pondéré sur 100.</p>
          </div>
          <div class="scoring__grid">
            \(cardsHTML)
          </div>
        </section>
        """
    }

    public static func synthesisSection(report: AuditReport) -> String {
        let synth = renderMarkdownLight(report.synthesis)
        return """
        <section class="synthesis reveal" data-reveal="up">
          <div class="section__header">
            <div class="section__eyebrow">02 — SYNTHÈSE</div>
            <h2 class="section__title">Lecture stratégique</h2>
          </div>
          <article class="synthesis__body">
            \(synth)
          </article>
        </section>
        """
    }

    /// v0.23 — Vision section. Renders the 3 GPT Image 2 mockups as
    /// a horizontal CSS scroll-snap gallery sandwiched between the
    /// Synthesis prose and the Quick Wins grid. Each card embeds
    /// its PNG as a base64 `data:` URL so the portal folder stays
    /// single-file self-contained (a future iteration can switch
    /// to sibling assets when the byte cost matters more than the
    /// drop-anywhere convenience).
    ///
    /// Omitted entirely when the report has no mockups — a portal
    /// generated before the user configured their OpenAI key
    /// (or for a flawless site with zero quick wins) skips the
    /// section so the layout doesn't surface an empty band.
    public static func visionSection(report: AuditReport) -> String {
        guard !report.mockups.isEmpty else { return "" }
        let cards = report.mockups.enumerated().map { (idx, mockup) in
            visionCard(index: idx + 1, mockup: mockup)
        }.joined(separator: "\n")

        return """
        <section class="vision reveal" data-reveal="up">
          <div class="section__header">
            <div class="section__eyebrow">02b — VISION</div>
            <h2 class="section__title">Votre site, refait</h2>
            <p class="section__lead">3 rendus IA — chaque mockup applique une recommandation prioritaire.</p>
          </div>
          <div class="vision__gallery">
            \(cards)
          </div>
        </section>
        """
    }

    private static func visionCard(index: Int, mockup: RedesignMockup) -> String {
        let base64 = mockup.imageData.base64EncodedString()
        let title = escape(mockup.title)
        let caption = escape(mockup.quickWinTitle)
        return """
        <article class="vision__card">
          <div class="vision__media">
            <img
              class="vision__img"
              alt="Mockup #\(index) — \(title)"
              src="data:image/png;base64,\(base64)"
              loading="lazy"
              decoding="async" />
          </div>
          <div class="vision__caption">
            <span class="vision__index">#\(index)</span>
            <span class="vision__title">\(title)</span>
            <span class="vision__sub">Recommandation : \(caption)</span>
          </div>
        </article>
        """
    }

    public static func quickWinsSection(report: AuditReport) -> String {
        guard !report.quickWins.isEmpty else { return "" }
        let cards = report.quickWins.enumerated().map { (idx, win) in
            quickWinCard(index: idx + 1, win: win)
        }.joined(separator: "\n")

        return """
        <section class="wins reveal" data-reveal="up">
          <div class="section__header">
            <div class="section__eyebrow">03 — QUICK WINS</div>
            <h2 class="section__title">À déclencher en quelques semaines</h2>
            <p class="section__lead">Impact élevé, effort court — par où commencer.</p>
          </div>
          <div class="wins__grid">
            \(cards)
          </div>
        </section>
        """
    }

    public static func strategicBetsSection(report: AuditReport) -> String {
        guard !report.strategicBets.isEmpty else { return "" }
        let stops = report.strategicBets.enumerated().map { (idx, bet) in
            timelineStop(index: idx + 1, bet: bet)
        }.joined(separator: "\n")

        return """
        <section class="bets reveal" data-reveal="up">
          <div class="section__header">
            <div class="section__eyebrow">04 — PARIS STRATÉGIQUES</div>
            <h2 class="section__title">Le travail de fond</h2>
            <p class="section__lead">Roadmap 3 à 12 mois, ordonnée par valeur.</p>
          </div>
          <div class="bets__timeline" role="list">
            \(stops)
          </div>
        </section>
        """
    }

    public static func hiddenRisksSection(report: AuditReport) -> String {
        guard !report.hiddenRisks.isEmpty else { return "" }
        let cards = report.hiddenRisks.map { risk in
            riskCard(risk: risk)
        }.joined(separator: "\n")

        return """
        <section class="risks reveal" data-reveal="up">
          <div class="section__header">
            <div class="section__eyebrow">05 — RISQUES CACHÉS</div>
            <h2 class="section__title">Ce que vous ne voyez pas</h2>
            <p class="section__lead">Signaux faibles repérés pendant l'audit.</p>
          </div>
          <div class="risks__grid">
            \(cards)
          </div>
        </section>
        """
    }

    public static func pitchSection(
        report: AuditReport,
        brand: BrandSettings
    ) -> String {
        let pitch = escape(report.pitch).replacingOccurrences(of: "\n", with: "<br>")
        let consultant = escape(brand.consultantName)
        let title = escape(brand.consultantTitle)
        let portrait = portraitHTML(brand: brand)

        return """
        <section class="pitch reveal" data-reveal="up">
          <div class="pitch__inner">
            <div class="pitch__quote-mark" aria-hidden="true">"</div>
            <blockquote class="pitch__quote">\(pitch)</blockquote>
            <div class="pitch__byline">
              \(portrait)
              <div class="pitch__byline-text">
                <div class="pitch__byline-name">\(consultant)</div>
                <div class="pitch__byline-title">\(title)</div>
              </div>
            </div>
          </div>
        </section>
        """
    }

    public static func contactSection(
        report: AuditReport,
        brand: BrandSettings
    ) -> String {
        var ctas: [String] = []
        if let url = brand.calendlyURL, !url.isEmpty {
            ctas.append("""
            <a class="cta cta--primary" href="\(escape(url))" target="_blank" rel="noopener">Réserver un appel</a>
            """)
        } else {
            // Placeholder so the layout doesn't collapse on the
            // default-brand case Mehdi forgot to override.
            ctas.append("""
            <a class="cta cta--primary" href="https://calendly.com/" target="_blank" rel="noopener">Réserver un appel</a>
            """)
        }
        if let email = brand.consultantEmail, !email.isEmpty {
            let subject = "Audit — \(report.client.displayName)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            ctas.append("""
            <a class="cta cta--ghost" href="mailto:\(escape(email))?subject=\(subject)">Envoyer un email</a>
            """)
        }

        return """
        <section class="contact reveal" data-reveal="up">
          <div class="contact__inner">
            <h2 class="contact__title">Discutons.</h2>
            <p class="contact__lead">Vous voulez transformer ces recommandations en plan d'action ? Un appel de 30 minutes suffit pour cadrer.</p>
            <div class="contact__ctas">
              \(ctas.joined(separator: "\n"))
            </div>
          </div>
        </section>
        """
    }

    public static func footerSection(
        report: AuditReport,
        brand: BrandSettings
    ) -> String {
        let consultant = escape(brand.consultantName)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = escape(dateFormatter.string(from: report.generatedAt))

        return """
        <footer class="footer">
          <div class="footer__inner">
            <div class="footer__wordmark">MIND</div>
            <div class="footer__meta">
              Audit produit par \(consultant) · généré le \(timestamp)
            </div>
          </div>
        </footer>
        """
    }

    // MARK: - Sub-components

    private static func gaugeCard(label: String, score: Int, sub: String) -> String {
        // SVG circular gauge: radius 54, circumference ~339, the
        // dasharray/dashoffset combo + a CSS transition creates the
        // fill animation when the parent gains the .reveal--in class
        // via the IntersectionObserver. The accessibility label
        // spells out the score for screen readers since the visual
        // text node is purely decorative inside the SVG.
        let pct = max(0, min(100, score))
        let clampedLabel = escape(label)
        let clampedSub = escape(sub)
        return """
        <div class="gauge" data-score="\(pct)" role="figure" aria-label="\(clampedLabel) : \(pct) sur 100">
          <svg viewBox="0 0 120 120" class="gauge__svg" aria-hidden="true">
            <circle cx="60" cy="60" r="54" class="gauge__track"/>
            <circle cx="60" cy="60" r="54" class="gauge__fill" style="--gauge-pct: \(pct);"/>
          </svg>
          <div class="gauge__value">\(pct)</div>
          <div class="gauge__label">\(clampedLabel)</div>
          <div class="gauge__sub">\(clampedSub)</div>
        </div>
        """
    }

    private static func quickWinCard(index: Int, win: AuditReport.QuickWin) -> String {
        let title = escape(win.title)
        let detail = escape(win.detail)
        let impactLabel: String = {
            switch win.impact {
            case .high: return "Impact élevé"
            case .medium: return "Impact moyen"
            case .low: return "Impact faible"
            }
        }()
        let effort = formatEffort(win.effortDays)
        return """
        <article class="win">
          <div class="win__head">
            <span class="win__index">#\(index)</span>
            <span class="win__pill win__pill--\(win.impact.rawValue)">\(impactLabel)</span>
          </div>
          <h3 class="win__title">\(title)</h3>
          <p class="win__detail">\(detail)</p>
          <div class="win__meta">
            <span class="win__effort">⏱ \(effort)</span>
          </div>
        </article>
        """
    }

    private static func timelineStop(index: Int, bet: AuditReport.StrategicBet) -> String {
        let title = escape(bet.title)
        let detail = escape(bet.detail)
        let budget = "€\(bet.budgetMinEUR / 1000)k – €\(bet.budgetMaxEUR / 1000)k"
        let monthsLabel = bet.durationMonths == 1 ? "1 mois" : "\(bet.durationMonths) mois"
        return """
        <article class="bet" role="listitem">
          <div class="bet__index">#\(index)</div>
          <div class="bet__duration">\(monthsLabel)</div>
          <h3 class="bet__title">\(title)</h3>
          <p class="bet__detail">\(detail)</p>
          <div class="bet__budget">\(budget)</div>
        </article>
        """
    }

    private static func riskCard(risk: AuditReport.HiddenRisk) -> String {
        let title = escape(risk.title)
        let detail = escape(risk.detail)
        let severityLabel: String = {
            switch risk.severity {
            case .critical: return "Critique"
            case .high: return "Élevé"
            case .medium: return "Moyen"
            case .low: return "Faible"
            }
        }()
        return """
        <article class="risk risk--\(risk.severity.rawValue)">
          <div class="risk__head">
            <span class="risk__icon" aria-hidden="true">⚠</span>
            <span class="risk__sev">\(severityLabel)</span>
          </div>
          <h3 class="risk__title">\(title)</h3>
          <p class="risk__detail">\(detail)</p>
        </article>
        """
    }

    private static func portraitHTML(brand: BrandSettings) -> String {
        if let data = brand.consultantPhotoData, !data.isEmpty {
            let base64 = data.base64EncodedString()
            return """
            <img class="pitch__portrait" src="data:image/jpeg;base64,\(base64)" alt="\(escape(brand.consultantName))" />
            """
        } else {
            return """
            <div class="pitch__portrait pitch__portrait--initials" aria-hidden="true">\(escape(brand.consultantInitials))</div>
            """
        }
    }

    // MARK: - Light markdown renderer

    /// Bare-minimum markdown → HTML for the synthesis section.
    /// Handles paragraphs (blank-line separated), `# / ##` headings,
    /// `**bold**`, `*italic*`, list items prefixed by `- ` or `* `,
    /// and bare URLs. We deliberately avoid pulling in a full
    /// markdown parser — the synthesis is curated by Claude with a
    /// known sub-grammar and this 30-line helper covers everything
    /// the model emits in practice.
    static func renderMarkdownLight(_ source: String) -> String {
        let blocks = source.components(separatedBy: "\n\n")
        return blocks.map { rawBlock -> String in
            let block = rawBlock.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !block.isEmpty else { return "" }
            if block.hasPrefix("# ") {
                return "<h2 class=\"synthesis__h2\">\(inline(block.dropFirst(2)))</h2>"
            }
            if block.hasPrefix("## ") {
                return "<h3 class=\"synthesis__h3\">\(inline(block.dropFirst(3)))</h3>"
            }
            // Bullet list — every line starts with "- " or "* ".
            let lines = block.components(separatedBy: "\n")
            if lines.allSatisfy({ $0.hasPrefix("- ") || $0.hasPrefix("* ") }) {
                let items = lines.map { l in
                    "<li>\(inline(l.dropFirst(2)))</li>"
                }.joined()
                return "<ul class=\"synthesis__list\">\(items)</ul>"
            }
            return "<p class=\"synthesis__p\">\(inline(block))</p>"
        }.joined(separator: "\n")
    }

    private static func inline(_ source: Substring) -> String {
        inline(String(source))
    }

    private static func inline(_ source: String) -> String {
        var result = escape(source)
        result = applyMarkdownPattern(result, pattern: "**", tag: "strong")
        result = applyMarkdownPattern(result, pattern: "*", tag: "em")
        return result
    }

    private static func applyMarkdownPattern(
        _ source: String,
        pattern: String,
        tag: String
    ) -> String {
        // Naive double-pass: split on the pattern, wrap alternating
        // chunks in the tag. Skipped when the count is even (no
        // closing tag found) so half-formed input renders verbatim.
        let parts = source.components(separatedBy: pattern)
        guard parts.count > 2, parts.count % 2 == 1 else {
            return source
        }
        var output = ""
        for (idx, part) in parts.enumerated() {
            if idx % 2 == 0 {
                output += part
            } else {
                output += "<\(tag)>\(part)</\(tag)>"
            }
        }
        return output
    }

    // MARK: - CSS

    /// Inline CSS for the whole document. ~3 KB minified once gzipped
    /// — well under the 80 KB page-weight target on its own.
    public static func inlineCSS(brand: BrandSettings) -> String {
        let accent = brand.accentColor
        let font = brand.font
        // Note: hex strings are pasted into CSS custom properties so
        // the brand swap is centralised. Hard-coded backdrop blur
        // values give the Liquid Glass look without dragging
        // SwiftUI's `.ultraThinMaterial` into the HTML output.
        return """
        :root{
          --accent:\(accent);
          --accent-2:#A8E6E0;
          --bg-dark-1:#0B0820;
          --bg-dark-2:#13102E;
          --bg-dark-3:#1E184A;
          --bg-light:#F7F6FA;
          --ink:#FFFFFF;
          --ink-dim:rgba(255,255,255,0.66);
          --ink-quiet:rgba(255,255,255,0.42);
          --card:rgba(255,255,255,0.06);
          --card-stroke:rgba(255,255,255,0.10);
          --radius-lg:24px;
          --radius-md:16px;
          --font:\(font);
          --max-w:1080px;
          --max-w-prose:720px;
          --easing:cubic-bezier(0.22,0.61,0.36,1);
        }
        @media (prefers-color-scheme: light){
          :root{
            --bg-dark-1:#F7F6FA;
            --bg-dark-2:#EDE9FB;
            --bg-dark-3:#E1DAF7;
            --ink:#0E0B22;
            --ink-dim:rgba(14,11,34,0.7);
            --ink-quiet:rgba(14,11,34,0.45);
            --card:rgba(255,255,255,0.75);
            --card-stroke:rgba(14,11,34,0.08);
          }
        }
        *{box-sizing:border-box;margin:0;padding:0;}
        html,body{background:var(--bg-dark-1);color:var(--ink);font-family:var(--font);line-height:1.55;-webkit-font-smoothing:antialiased;}
        body{overflow-x:hidden;}
        a{color:inherit;text-decoration:none;}
        ::selection{background:var(--accent);color:#fff;}
        /* Hero */
        .hero{position:relative;min-height:100vh;display:flex;align-items:center;justify-content:center;overflow:hidden;padding:80px 24px;}
        .hero__gradient{position:absolute;inset:-10% -10% -10% -10%;background:radial-gradient(80% 60% at 30% 30%,rgba(168,230,224,0.18) 0%,transparent 60%),radial-gradient(60% 80% at 80% 70%,rgba(107,93,211,0.32) 0%,transparent 70%),linear-gradient(160deg,var(--bg-dark-1) 0%,var(--bg-dark-2) 40%,var(--bg-dark-3) 100%);transform:translate3d(0,0,0);will-change:transform;}
        .hero__grain{position:absolute;inset:0;background-image:radial-gradient(rgba(255,255,255,0.04) 1px,transparent 1px);background-size:3px 3px;mix-blend-mode:overlay;opacity:0.5;pointer-events:none;}
        .hero__inner{position:relative;max-width:var(--max-w);width:100%;text-align:center;}
        .hero__eyebrow{font-size:11px;letter-spacing:0.32em;color:var(--accent-2);font-weight:600;margin-bottom:28px;}
        .hero__title{font-size:clamp(64px,12vw,200px);line-height:0.92;font-weight:900;letter-spacing:-0.04em;margin-bottom:24px;background:linear-gradient(180deg,#fff 0%,var(--accent-2) 120%);-webkit-background-clip:text;background-clip:text;color:transparent;}
        .hero__tagline{font-size:clamp(16px,2vw,22px);color:var(--ink-dim);margin-bottom:24px;}
        .hero__tagline strong{color:var(--ink);font-weight:600;}
        .hero__host{display:inline-block;padding:10px 20px;border-radius:999px;background:var(--card);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border:1px solid var(--card-stroke);color:var(--ink-dim);font-size:13px;letter-spacing:0.02em;transition:background 0.3s var(--easing),transform 0.3s var(--easing);}
        .hero__host:hover{background:rgba(255,255,255,0.12);transform:translateY(-2px);}
        .hero__scroll{position:absolute;bottom:32px;left:50%;transform:translateX(-50%);width:20px;height:32px;border:1.5px solid var(--ink-quiet);border-radius:12px;display:flex;justify-content:center;padding-top:6px;}
        .hero__scroll span{display:block;width:2px;height:6px;background:var(--ink-dim);border-radius:2px;animation:scroll 1.8s ease-in-out infinite;}
        @keyframes scroll{0%{opacity:1;transform:translateY(0);}80%{opacity:0;transform:translateY(12px);}100%{opacity:0;}}
        /* Sections shared */
        section{padding:100px 24px;max-width:var(--max-w);margin:0 auto;}
        .section__header{margin-bottom:48px;text-align:center;}
        .section__eyebrow{font-size:11px;letter-spacing:0.32em;color:var(--accent);font-weight:700;margin-bottom:14px;}
        .section__title{font-size:clamp(32px,5vw,56px);font-weight:700;letter-spacing:-0.025em;line-height:1.05;margin-bottom:16px;}
        .section__lead{color:var(--ink-dim);font-size:clamp(15px,1.8vw,18px);max-width:560px;margin:0 auto;}
        /* Reveal animation */
        .reveal{opacity:0;transform:translateY(40px);transition:opacity 0.9s var(--easing),transform 0.9s var(--easing);}
        .reveal--in{opacity:1;transform:none;}
        @media (prefers-reduced-motion: reduce){
          .reveal{opacity:1;transform:none;transition:none;}
          .hero__scroll span{animation:none;}
        }
        /* Scoring grid */
        .scoring__grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:18px;}
        .gauge{background:var(--card);border:1px solid var(--card-stroke);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border-radius:var(--radius-lg);padding:28px 20px;text-align:center;transition:transform 0.4s var(--easing),background 0.4s var(--easing);}
        .gauge:hover{transform:translateY(-4px);background:rgba(255,255,255,0.10);}
        .gauge__svg{width:120px;height:120px;display:block;margin:0 auto 14px;transform:rotate(-90deg);}
        .gauge__track{fill:none;stroke:var(--card-stroke);stroke-width:8;}
        .gauge__fill{fill:none;stroke:url(#gaugeGrad);stroke:var(--accent);stroke-width:8;stroke-linecap:round;stroke-dasharray:339.3;stroke-dashoffset:339.3;transition:stroke-dashoffset 1.4s var(--easing);}
        .reveal--in .gauge__fill{stroke-dashoffset:calc(339.3 - (339.3 * var(--gauge-pct)) / 100);}
        @media (prefers-reduced-motion: reduce){
          .gauge__fill{transition:none;stroke-dashoffset:calc(339.3 - (339.3 * var(--gauge-pct)) / 100);}
        }
        .gauge__value{font-size:32px;font-weight:800;letter-spacing:-0.02em;line-height:1;}
        .gauge__label{font-size:13px;font-weight:600;color:var(--ink-dim);margin-top:8px;text-transform:uppercase;letter-spacing:0.08em;}
        .gauge__sub{font-size:11px;color:var(--ink-quiet);margin-top:4px;}
        /* Synthesis */
        .synthesis{max-width:var(--max-w-prose);}
        .synthesis .section__header{text-align:left;}
        .synthesis__body{font-size:clamp(16px,1.6vw,19px);color:var(--ink-dim);}
        .synthesis__p{margin-bottom:18px;}
        .synthesis__p strong{color:var(--ink);font-weight:600;}
        .synthesis__h2{font-size:28px;font-weight:700;color:var(--ink);margin:32px 0 14px;letter-spacing:-0.02em;}
        .synthesis__h3{font-size:21px;font-weight:600;color:var(--ink);margin:24px 0 10px;letter-spacing:-0.01em;}
        .synthesis__list{padding-left:18px;margin-bottom:18px;}
        .synthesis__list li{margin-bottom:8px;}
        /* v0.23 — Vision: before/after redesign mockups gallery */
        .vision__gallery{display:flex;gap:18px;overflow-x:auto;scroll-snap-type:x mandatory;padding:8px 4px 24px;-webkit-overflow-scrolling:touch;}
        .vision__gallery::-webkit-scrollbar{height:6px;}
        .vision__gallery::-webkit-scrollbar-thumb{background:var(--card-stroke);border-radius:3px;}
        .vision__card{min-width:320px;max-width:480px;flex:0 0 auto;scroll-snap-align:start;background:var(--card);border:1px solid var(--card-stroke);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border-radius:var(--radius-lg);overflow:hidden;display:flex;flex-direction:column;}
        .vision__media{aspect-ratio:16/9;background:linear-gradient(135deg,rgba(94,91,216,0.20) 0%,rgba(94,233,216,0.18) 100%);overflow:hidden;}
        .vision__img{display:block;width:100%;height:100%;object-fit:cover;}
        .vision__caption{padding:18px 22px 22px;display:flex;flex-direction:column;gap:6px;}
        .vision__index{font-size:11px;color:var(--accent);font-weight:700;letter-spacing:0.08em;}
        .vision__title{font-size:18px;font-weight:600;line-height:1.3;color:var(--ink);letter-spacing:-0.01em;}
        .vision__sub{font-size:13px;color:var(--ink-quiet);}
        /* Quick wins */
        .wins__grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:18px;}
        .win{background:var(--card);border:1px solid var(--card-stroke);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border-radius:var(--radius-lg);padding:26px;transition:transform 0.4s var(--easing),box-shadow 0.4s var(--easing);}
        .win:hover{transform:perspective(900px) rotateX(2deg) translateY(-4px);box-shadow:0 24px 60px rgba(0,0,0,0.4);}
        .win__head{display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;}
        .win__index{font-size:13px;color:var(--ink-quiet);font-weight:600;letter-spacing:0.05em;}
        .win__pill{font-size:11px;font-weight:700;letter-spacing:0.06em;padding:5px 11px;border-radius:999px;text-transform:uppercase;}
        .win__pill--high{background:rgba(168,230,224,0.20);color:#A8E6E0;}
        .win__pill--medium{background:rgba(107,93,211,0.22);color:#C7BBFF;}
        .win__pill--low{background:rgba(255,255,255,0.10);color:var(--ink-dim);}
        .win__title{font-size:18px;font-weight:600;line-height:1.3;margin-bottom:10px;letter-spacing:-0.01em;}
        .win__detail{font-size:14px;color:var(--ink-dim);margin-bottom:18px;}
        .win__meta{display:flex;align-items:center;gap:14px;font-size:12px;color:var(--ink-quiet);}
        /* Strategic bets timeline */
        .bets__timeline{display:flex;gap:18px;overflow-x:auto;scroll-snap-type:x mandatory;padding:8px 4px 24px;-webkit-overflow-scrolling:touch;}
        .bets__timeline::-webkit-scrollbar{height:6px;}
        .bets__timeline::-webkit-scrollbar-thumb{background:var(--card-stroke);border-radius:3px;}
        .bet{min-width:280px;max-width:320px;flex:0 0 auto;scroll-snap-align:start;background:var(--card);border:1px solid var(--card-stroke);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border-radius:var(--radius-lg);padding:26px;display:flex;flex-direction:column;gap:10px;}
        .bet__index{font-size:11px;color:var(--accent);font-weight:700;letter-spacing:0.08em;}
        .bet__duration{font-size:13px;color:var(--ink-quiet);margin-bottom:4px;}
        .bet__title{font-size:19px;font-weight:600;line-height:1.25;letter-spacing:-0.01em;}
        .bet__detail{font-size:14px;color:var(--ink-dim);flex:1;}
        .bet__budget{font-size:13px;color:var(--accent-2);font-weight:600;padding-top:10px;border-top:1px solid var(--card-stroke);}
        /* Hidden risks */
        .risks__grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:18px;}
        .risk{background:linear-gradient(160deg,rgba(255,100,100,0.10) 0%,rgba(255,60,60,0.04) 100%);border:1px solid rgba(255,100,100,0.22);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border-radius:var(--radius-lg);padding:26px;}
        .risk--critical{background:linear-gradient(160deg,rgba(255,40,40,0.20) 0%,rgba(255,40,40,0.06) 100%);border-color:rgba(255,40,40,0.35);}
        .risk__head{display:flex;align-items:center;gap:10px;margin-bottom:14px;}
        .risk__icon{font-size:18px;color:#FFB4B4;}
        .risk__sev{font-size:11px;font-weight:700;color:#FFB4B4;letter-spacing:0.08em;text-transform:uppercase;}
        .risk__title{font-size:18px;font-weight:600;line-height:1.3;margin-bottom:10px;letter-spacing:-0.01em;}
        .risk__detail{font-size:14px;color:var(--ink-dim);}
        /* Pitch */
        .pitch{max-width:var(--max-w-prose);}
        .pitch__inner{position:relative;background:linear-gradient(160deg,rgba(107,93,211,0.18) 0%,rgba(168,230,224,0.10) 100%);border:1px solid var(--card-stroke);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);border-radius:var(--radius-lg);padding:48px 36px;}
        .pitch__quote-mark{position:absolute;top:8px;left:24px;font-size:110px;line-height:1;color:var(--accent-2);opacity:0.30;font-family:Georgia,serif;}
        .pitch__quote{font-size:clamp(17px,1.8vw,21px);color:var(--ink);font-style:italic;line-height:1.55;margin-bottom:32px;position:relative;z-index:1;}
        .pitch__byline{display:flex;align-items:center;gap:14px;}
        .pitch__portrait{width:54px;height:54px;border-radius:50%;object-fit:cover;background:var(--accent);display:flex;align-items:center;justify-content:center;color:#fff;font-weight:700;font-size:18px;letter-spacing:0.04em;}
        .pitch__byline-name{font-size:15px;font-weight:600;color:var(--ink);}
        .pitch__byline-title{font-size:13px;color:var(--ink-quiet);}
        /* Contact */
        .contact{text-align:center;padding-bottom:140px;}
        .contact__title{font-size:clamp(40px,7vw,80px);font-weight:800;letter-spacing:-0.04em;margin-bottom:18px;background:linear-gradient(180deg,#fff 0%,var(--accent-2) 130%);-webkit-background-clip:text;background-clip:text;color:transparent;}
        .contact__lead{font-size:clamp(15px,1.6vw,18px);color:var(--ink-dim);max-width:540px;margin:0 auto 36px;}
        .contact__ctas{display:flex;justify-content:center;flex-wrap:wrap;gap:14px;}
        .cta{display:inline-block;padding:14px 28px;border-radius:999px;font-size:15px;font-weight:600;letter-spacing:0.01em;transition:transform 0.3s var(--easing),background 0.3s var(--easing),box-shadow 0.3s var(--easing);}
        .cta--primary{background:var(--accent);color:#fff;box-shadow:0 12px 32px rgba(107,93,211,0.40);}
        .cta--primary:hover{transform:translateY(-3px);box-shadow:0 18px 44px rgba(107,93,211,0.55);}
        .cta--ghost{background:var(--card);border:1px solid var(--card-stroke);color:var(--ink);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);}
        .cta--ghost:hover{transform:translateY(-3px);background:rgba(255,255,255,0.12);}
        /* Footer */
        .footer{padding:32px 24px 48px;border-top:1px solid var(--card-stroke);max-width:none;}
        .footer__inner{max-width:var(--max-w);margin:0 auto;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:14px;}
        .footer__wordmark{font-size:18px;font-weight:900;letter-spacing:0.32em;color:var(--ink);opacity:0.7;}
        .footer__meta{font-size:12px;color:var(--ink-quiet);}
        /* Responsive */
        @media (max-width:640px){
          .hero{padding:60px 20px;}
          section{padding:64px 20px;}
          .pitch__inner{padding:36px 24px;}
        }
        """
    }

    // MARK: - JS

    /// Inline JS. Single IntersectionObserver flips `.reveal--in` on
    /// each section as it enters the viewport (triggers the SVG
    /// gauge fill + section fade-up via CSS). Hero parallax shifts
    /// the gradient layer slightly on scroll using
    /// `requestAnimationFrame` to stay smooth. No frameworks, no
    /// build step, ~1 KB minified.
    public static func inlineJS() -> String {
        return """
        (function(){
          'use strict';
          var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
          var revealEls = document.querySelectorAll('.reveal');
          if (reduced) {
            revealEls.forEach(function(el){ el.classList.add('reveal--in'); });
          } else if ('IntersectionObserver' in window) {
            var io = new IntersectionObserver(function(entries){
              entries.forEach(function(entry){
                if (entry.isIntersecting) {
                  entry.target.classList.add('reveal--in');
                  io.unobserve(entry.target);
                }
              });
            }, { threshold: 0.16, rootMargin: '0px 0px -10% 0px' });
            revealEls.forEach(function(el){ io.observe(el); });
          } else {
            revealEls.forEach(function(el){ el.classList.add('reveal--in'); });
          }
          // Hero parallax — translate the gradient layer at 0.35x
          // scroll velocity. requestAnimationFrame coalesces scroll
          // events so we never overspend the main thread.
          if (!reduced) {
            var hero = document.querySelector('.hero__gradient');
            if (hero) {
              var ticking = false;
              window.addEventListener('scroll', function(){
                if (!ticking) {
                  window.requestAnimationFrame(function(){
                    var y = window.scrollY * 0.35;
                    hero.style.transform = 'translate3d(0,' + y + 'px,0)';
                    ticking = false;
                  });
                  ticking = true;
                }
              }, { passive: true });
            }
          }
        })();
        """
    }

    // MARK: - Helpers

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'",  with: "&#39;")
    }

    private static func formatEffort(_ days: Double) -> String {
        if days < 1 { return "\(Int((days * 8).rounded())) h" }
        if days < 1.5 { return "1 j" }
        return "\(Int(days.rounded())) j"
    }
}
