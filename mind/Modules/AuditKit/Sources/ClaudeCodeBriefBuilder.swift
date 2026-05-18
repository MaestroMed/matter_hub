import Foundation

/// Turns an AuditReport into a ready-to-paste prompt for Claude Code:
/// context, mission, recommended stack, architecture, design system,
/// commit-by-commit roadmap, quick wins, constraints, hidden risks.
///
/// Pure string composition — every section is conditional on the
/// findings actually present, so a barebones audit produces a short
/// brief and a rich audit produces a long one.
public enum ClaudeCodeBriefBuilder {

    public static func build(from report: AuditReport) -> String {
        var sections: [String] = []

        sections.append(headerSection(report))
        sections.append(contextSection(report))
        sections.append(missionSection(report))
        sections.append(stackSection(report))
        sections.append(designSystemSection(report))
        sections.append(architectureSection(report))
        sections.append(roadmapSection(report))
        sections.append(quickWinsSection(report))
        if !report.strategicBets.isEmpty {
            sections.append(strategicBetsSection(report))
        }
        sections.append(constraintsSection(report))
        if !report.hiddenRisks.isEmpty {
            sections.append(hiddenRisksSection(report))
        }
        sections.append(outputExpectedSection(report))

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Sections

    private static func headerSection(_ report: AuditReport) -> String {
        let date = report.generatedAt.formatted(date: .long, time: .omitted)
        return """
        # Brief Claude Code SOTA — \(report.client.displayName)

        > Auto-généré par MIND le \(date) à partir de l'audit digital de \(report.client.url.absoluteString).
        > Colle ce brief tel-quel à Claude Code, ou découpe section-par-section pour itérer plus finement.
        """
    }

    private static func contextSection(_ report: AuditReport) -> String {
        var lines: [String] = ["## Context"]
        lines.append("- **Client** : \(report.client.displayName)")
        lines.append("- **URL** : \(report.client.url.absoluteString)")
        lines.append("- **Persona** : \(report.persona.label)")
        lines.append("- **Score actuel** : \(report.scoring.overall)/100 (perf \(report.scoring.performance) · seo \(report.scoring.seo) · sécu \(report.scoring.security) · brand \(report.scoring.brand) · mobile \(report.scoring.mobile))")
        if let perf = report.performance {
            if let lcp = perf.largestContentfulPaintSeconds {
                lines.append("- **Core Web Vitals actuels** : LCP \(String(format: "%.1f", lcp))s" +
                             (perf.interactionToNextPaintMs.map { ", INP \($0)ms" } ?? "") +
                             (perf.cumulativeLayoutShift.map { ", CLS \(String(format: "%.2f", $0))" } ?? ""))
            }
        }
        if let cdn = report.findings?.cdn?.provider {
            lines.append("- **Stack hosting détecté** : \(cdn)")
        }
        if let analytics = report.findings?.analytics, analytics.hasAnyAnalytics {
            lines.append("- **Analytics en place** : \(analytics.providers.joined(separator: ", "))")
        }
        if let payment = report.findings?.payment, !payment.processors.isEmpty {
            lines.append("- **Processeurs de paiement** : \(payment.processors.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private static func missionSection(_ report: AuditReport) -> String {
        let topGoals = report.quickWins
            .prefix(3)
            .map { "  - \($0.title)" }
            .joined(separator: "\n")
        return """
        ## Mission

        Refonte digitale complète pour amener **\(report.client.displayName)** au niveau state-of-the-art 2026.

        Objectifs prioritaires (court terme) :
        \(topGoals.isEmpty ? "  - (aucun quick win détecté)" : topGoals)

        Le client est au stade \(maturityLabel(report.scoring.overall)). L'audit MIND identifie un potentiel d'amélioration significatif sur \(weakAxesSummary(report)).
        """
    }

    private static func stackSection(_ report: AuditReport) -> String {
        var stack: [String] = ["## Stack recommandée\n"]
        switch report.persona {
        case .saasB2B:
            stack.append("- **Frontend** : Next.js 16 (App Router + Server Components + RSC streaming)")
            stack.append("- **Styling** : Tailwind CSS 4 + shadcn/ui (radix-based)")
            stack.append("- **Auth** : better-auth (sessions JWT + magic links + SSO ready)")
            stack.append("- **Database** : PostgreSQL via Supabase (RLS activé)")
            stack.append("- **ORM** : Drizzle (type-safe, edge-compatible)")
            stack.append("- **Payment** : Stripe (subscriptions + usage-based billing si pertinent)")
            stack.append("- **Email transactionnel** : Resend (DKIM + SPF auto-configurés)")
            stack.append("- **Analytics** : Plausible ou PostHog (RGPD-friendly, self-hostable)")
            stack.append("- **Error tracking** : Sentry")
            stack.append("- **Hosting** : Vercel (Edge runtime) ou Cloudflare Pages")
            stack.append("- **Mobile** : Swift 6 / SwiftUI / iOS 26 (si MIND propose une app native)")
        case .tpePme:
            stack.append("- **Frontend** : Astro 5 (statique by default, islands pour interactivité)")
            stack.append("- **Styling** : Tailwind CSS 4 + composants custom")
            stack.append("- **CMS** : Astro Content Collections ou Sanity (free tier)")
            stack.append("- **Forms** : Formspree ou Resend Forms (lead capture)")
            stack.append("- **Analytics** : Plausible (simple, RGPD, ~9€/mois)")
            stack.append("- **Hosting** : Cloudflare Pages (gratuit) ou Vercel Hobby")
            stack.append("- **SEO local** : Google Business Profile + Schema.org LocalBusiness")
            stack.append("- **Email transactionnel** : Brevo (300/jour gratuits)")
        case .lifestyleDTC:
            stack.append("- **Frontend e-commerce** : Shopify Hydrogen ou Medusa (headless)")
            stack.append("- **Styling** : Tailwind CSS 4 + animations Framer Motion 12")
            stack.append("- **CMS / DAM** : Sanity Studio (visuals lourds, multi-locale)")
            stack.append("- **Payment** : Stripe + Shop Pay + Klarna (BNPL)")
            stack.append("- **Email + reviews** : Klaviyo (lifecycle automations)")
            stack.append("- **Search** : Algolia ou Typesense (instant search)")
            stack.append("- **Hosting** : Vercel Pro (edge cache pour catalog)")
            stack.append("- **Mobile** : app native iOS premium (Swift 6 / SwiftUI / iOS 26)")
        case .other:
            stack.append("- **Frontend** : Next.js 16 ou Astro 5 selon le besoin")
            stack.append("- **Styling** : Tailwind CSS 4 + shadcn/ui")
            stack.append("- **Hosting** : Vercel ou Cloudflare Pages")
            stack.append("- **Analytics** : Plausible (RGPD by default)")
            stack.append("- **Monitoring** : Sentry")
        }
        return stack.joined(separator: "\n")
    }

    private static func designSystemSection(_ report: AuditReport) -> String {
        return """
        ## Design system (à valider avec brand audit)

        - **Couleurs primaires** : palette à dériver du logo existant — proposer 3 variantes
        - **Typographie** : SF Pro Rounded (Apple ecosystem) ou Inter (universal web)
        - **Spacing** : système 4pt (4, 8, 12, 16, 24, 32, 48, 64)
        - **Border radius** : continuous squircles 12-24pt pour les cards, capsules pour les CTA
        - **Shadows** : soft, jamais drop-shadow agressif — y=2, blur=8, opacity=0.05
        - **Motion** : Framer Motion spring 300/30 par défaut, easing custom pour les hero
        - **Dark mode** : obligatoire dès le jour 1, palette équilibrée pas juste invert
        """
    }

    private static func architectureSection(_ report: AuditReport) -> String {
        var arch: [String] = ["## Architecture proposée\n"]
        switch report.persona {
        case .saasB2B:
            arch.append("""
            ### Routes
            - `/` — homepage marketing avec hero + features + social proof + pricing teaser
            - `/pricing` — 3 plans + comparaison + FAQ
            - `/customers` — case studies
            - `/blog` — content marketing (collections statiques)
            - `/docs` — documentation produit
            - `/login` `/signup` `/forgot-password` — auth
            - `/app/**` — dashboard authentifié (Server Components)

            ### Modules
            - `app/(marketing)/` — pages publiques, SSG
            - `app/(auth)/` — flow auth
            - `app/(app)/` — produit authentifié
            - `components/ui/` — design system primitives
            - `components/marketing/` — sections marketing réutilisables
            - `lib/db/` — schéma Drizzle + queries
            - `lib/billing/` — Stripe helpers
            - `lib/auth/` — better-auth config + middleware
            """)
        case .tpePme:
            arch.append("""
            ### Pages
            - `/` — homepage avec hero + services + témoignages + zone de chalandise
            - `/services/[slug]` — fiche service détaillée
            - `/about` — qui sommes-nous + équipe + valeurs
            - `/contact` — formulaire court (3 champs max) + carte + horaires
            - `/blog` — actualités locales + SEO local

            ### Modules
            - `src/layouts/` — layouts Astro
            - `src/components/` — Hero, ServiceCard, ContactForm, MapBlock
            - `src/content/services/*.md` — contenu services en markdown
            - `src/content/blog/*.md` — posts blog
            """)
        case .lifestyleDTC:
            arch.append("""
            ### Routes
            - `/` — homepage avec hero produit + nouveautés + lookbook
            - `/shop/[collection]` — collections (PLP)
            - `/product/[handle]` — fiches produit (PDP) avec galerie + variants + reviews
            - `/cart` `/checkout` — Shop Pay accelerated
            - `/journal` — content éditorial (lifestyle)
            - `/account/**` — espace client

            ### Modules
            - `app/(shop)/` — pages e-commerce
            - `app/(content)/` — éditorial
            - `components/product/` — Gallery, VariantPicker, BuyButton, Reviews
            - `components/marketing/` — Lookbook, NewsletterBlock, Instagram feed
            - `lib/shopify/` — Storefront API client (GraphQL)
            """)
        case .other:
            arch.append("Architecture à proposer au démarrage selon les besoins métier réels.")
        }
        return arch.joined(separator: "\n")
    }

    private static func roadmapSection(_ report: AuditReport) -> String {
        var roadmap: [String] = ["## Roadmap commit-par-commit\n"]

        roadmap.append("""
        ### Phase 0 — Setup (jour 1)
        - `pnpm create` avec le framework choisi
        - Tailwind 4 + shadcn/ui init + composants de base
        - Configurer Sentry + Plausible scripts
        - Setup ESLint, Prettier, Husky pre-commit
        - Pages stubs : Privacy Policy, CGU, Mentions légales (RGPD)
        - Variables d'env documentées dans `.env.example`
        """)

        if !report.quickWins.isEmpty {
            let topWins = report.quickWins
                .prefix(5)
                .enumerated()
                .map { idx, win in "- **\(idx + 1). \(win.title)** (effort \(formattedEffort(win.effortDays)), impact \(win.impact.rawValue)) — \(win.detail)" }
                .joined(separator: "\n")
            roadmap.append("""
            ### Phase 1 — Quick wins (semaine 1-2)
            \(topWins)
            """)
        }

        roadmap.append("""
        ### Phase 2 — Refonte SEO + brand cohérence (semaine 3-4)
        - Schema.org JSON-LD sur toutes les pages (Organization, BreadcrumbList, FAQPage si pertinent)
        - OpenGraph + Twitter Card sur chaque template
        - Sitemap.xml dynamique + robots.txt allowant tout sauf admin
        - Redirections 301 si refonte d'arbo
        - Audit Core Web Vitals : cible ≥ 95 / 95 / 95 / 95 Lighthouse
        """)

        if !report.strategicBets.isEmpty {
            let bets = report.strategicBets
                .prefix(3)
                .enumerated()
                .map { idx, bet in "- **\(idx + 1). \(bet.title)** (\(bet.durationMonths) mois, €\(bet.budgetMinEUR / 1000)k–€\(bet.budgetMaxEUR / 1000)k) — \(bet.detail)" }
                .joined(separator: "\n")
            roadmap.append("""
            ### Phase 3 — Features stratégiques (mois 2-N)
            \(bets)
            """)
        }

        return roadmap.joined(separator: "\n\n")
    }

    private static func quickWinsSection(_ report: AuditReport) -> String {
        guard !report.quickWins.isEmpty else { return "## Quick wins\n\n(aucun détecté)" }
        var section = ["## Quick wins (liste complète)\n"]
        for (idx, win) in report.quickWins.enumerated() {
            let impact = win.impact.rawValue
            section.append("""
            ### \(idx + 1). \(win.title)
            - **Effort** : \(formattedEffort(win.effortDays))
            - **Impact** : \(impact)
            - **Détail** : \(win.detail)
            """)
        }
        return section.joined(separator: "\n\n")
    }

    private static func strategicBetsSection(_ report: AuditReport) -> String {
        var section = ["## Paris stratégiques (full briefs)\n"]
        for (idx, bet) in report.strategicBets.enumerated() {
            section.append("""
            ### \(idx + 1). \(bet.title)
            - **Durée** : \(bet.durationMonths) mois
            - **Budget** : €\(bet.budgetMinEUR / 1000)k – €\(bet.budgetMaxEUR / 1000)k
            - **Détail** : \(bet.detail)
            """)
        }
        return section.joined(separator: "\n\n")
    }

    private static func constraintsSection(_ report: AuditReport) -> String {
        return """
        ## Constraints non-négociables

        - **Performance** : LCP < 2.5s, INP < 200ms, CLS < 0.1, mesurés au p75 sur mobile
        - **SEO** : Lighthouse SEO score ≥ 95, sitemap.xml + robots.txt + Schema.org sur toutes les pages
        - **Accessibilité** : WCAG 2.2 AA sur les composants principaux, axe-core 0 erreur critique
        - **Sécurité** : headers HSTS + CSP + X-Frame-Options + Referrer-Policy + Permissions-Policy, grade A+
        - **RGPD** : cookie banner conforme (consent before non-essential), privacy policy à jour, droit à l'effacement implémenté
        - **Code quality** : TypeScript strict, ESLint pas de warning, Prettier, tests sur les chemins critiques (auth + paiement)
        - **Observabilité** : logs structurés JSON, error tracking en prod dès le J1, métriques business basiques
        - **Déploiement** : rollback < 2 min, CI passe avant merge, preview deployments par PR
        """
    }

    private static func hiddenRisksSection(_ report: AuditReport) -> String {
        var section = ["## Risques cachés identifiés par l'audit MIND\n"]
        section.append("Ces points méritent une attention dès la Phase 0 — ils peuvent bloquer la mission si laissés sans traitement.")
        section.append("")
        for risk in report.hiddenRisks {
            section.append("- **[\(risk.severity.rawValue.uppercased())] \(risk.title)** — \(risk.detail)")
        }
        return section.joined(separator: "\n")
    }

    private static func outputExpectedSection(_ report: AuditReport) -> String {
        let topGoals = report.quickWins
            .prefix(3)
            .map { "- ✅ \($0.title)" }
            .joined(separator: "\n")
        return """
        ## Output expected (critères d'acceptation)

        À la fin de la mission, le projet doit :
        \(topGoals.isEmpty ? "- (à définir avec le client)" : topGoals)
        - ✅ Atteindre un score Lighthouse global ≥ 90 sur les 4 catégories (perf, a11y, SEO, best practices)
        - ✅ Avoir un README utilisable (install, dev, test, deploy)
        - ✅ Avoir des tests unitaires sur les chemins critiques métier
        - ✅ Être déployé en production avec un domaine custom + SSL + redirections OK
        - ✅ Respecter toutes les Constraints non-négociables listées plus haut

        ## Format de réponse attendu

        Pour chaque commit, produire :
        1. Un commit message structuré (titre court + body explicatif)
        2. La liste des fichiers touchés
        3. Un mini-changelog dans CHANGELOG.md
        4. Un screenshot ou GIF de la feature livrée si pertinent

        À toi de jouer.
        """
    }

    // MARK: - Helpers

    private static func maturityLabel(_ overall: Int) -> String {
        switch overall {
        case 80...:   return "déjà mature digitalement"
        case 60..<80: return "à un niveau acceptable mais avec marge de progression"
        case 40..<60: return "à un niveau encore basique"
        default:      return "à un niveau de maturité digitale faible"
        }
    }

    private static func weakAxesSummary(_ report: AuditReport) -> String {
        let axes: [(String, Int)] = [
            ("la performance",     report.scoring.performance),
            ("le SEO",             report.scoring.seo),
            ("la sécurité",        report.scoring.security),
            ("le brand",           report.scoring.brand),
            ("la présence mobile", report.scoring.mobile),
        ]
        let weak = axes.filter { $0.1 < 70 }.map(\.0)
        if weak.isEmpty { return "des optimisations fines de chaque axe" }
        if weak.count == 1 { return weak[0] }
        let last = weak.last ?? ""
        let head = weak.dropLast().joined(separator: ", ")
        return "\(head) et \(last)"
    }

    private static func formattedEffort(_ days: Double) -> String {
        if days < 1 { return "\(Int((days * 8).rounded()))h" }
        if days < 1.5 { return "1 jour" }
        return "\(Int(days.rounded())) jours"
    }
}
