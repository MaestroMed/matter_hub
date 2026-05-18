import SwiftUI
import SwiftData
import AuditKit
import DesignSystem
import GraphCore
import VisualKit

struct AuditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var controller = AuditController.shared
    @State private var urlString: String = ""
    @State private var name: String = ""
    @State private var saved: Bool = false
    @State private var pdfURL: URL?
    @State private var briefMarkdown: String?
    @State private var exportSheetReport: ExportSheetReport?
    @State private var visualBoardReport: VisualBoardReportItem?
    @FocusState private var urlFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .animation(.smooth, value: controller.phase)
        }
        .background {
            LiquidBackground().ignoresSafeArea()
        }
        .onAppear {
            if controller.report == nil && controller.phase == .idle {
                urlFocused = true
            }
        }
        .sheet(item: Binding(
            get: { briefMarkdown.map { BriefPreviewItem(markdown: $0) } },
            set: { briefMarkdown = $0?.markdown }
        )) { item in
            BriefPreviewSheet(markdown: item.markdown)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $exportSheetReport) { item in
            ExportSheet(report: item.report)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $visualBoardReport) { item in
            VisualBoardView(report: item.report)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private struct ExportSheetReport: Identifiable {
        let id = UUID()
        let report: AuditReport
    }

    private struct VisualBoardReportItem: Identifiable {
        let id = UUID()
        let report: AuditReport
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Audit client")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("Du domaine au pitch en quelques minutes.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if controller.isRunning {
                    controller.cancel()
                }
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Branching content

    @ViewBuilder
    private var content: some View {
        if let report = controller.report, controller.phase == .completed {
            reportView(report)
        } else if controller.isRunning {
            runningView
        } else if let error = controller.error, controller.phase == .failed {
            errorView(error)
        } else {
            formView
        }
    }

    // MARK: - Form

    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            LiquidCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    fieldLabel("URL du site")
                    TextField("stripe.com ou https://stripe.com", text: $urlString)
                        .textFieldStyle(.plain)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .rounded))
                        .focused($urlFocused)

                    Divider().background(.white.opacity(0.18))

                    fieldLabel("Nom (optionnel)")
                    TextField("Stripe", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .rounded))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LiquidButton(title: "Lancer l'audit", systemImage: "magnifyingglass") {
                startAudit()
            }
            .disabled(normalizedURL == nil)
            .opacity(normalizedURL == nil ? 0.45 : 1)

            Text("Mesure Lighthouse + synthèse Claude. Compte ~2 min sur un site moyen.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Running

    private var runningView: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(LiquidPalette.iris)
                Text(controller.progressLabel)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("Tu peux fermer la sheet, l'audit continue en arrière-plan.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Annuler") {
                    controller.cancel()
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            LiquidCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Audit en échec")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                    }
                    Text(message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Vérifie que ta clé Anthropic est bien renseignée dans Settings.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LiquidButton(title: "Réessayer", systemImage: "arrow.counterclockwise") {
                startAudit()
            }
        }
    }

    // MARK: - Report

    @ViewBuilder
    private func reportView(_ report: AuditReport) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            scoreHeroCard(report)

            section("Synthèse") {
                LiquidCard(cornerRadius: 18) {
                    MarkdownView(report.synthesis)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !report.quickWins.isEmpty {
                section("Quick wins") {
                    VStack(spacing: 10) {
                        ForEach(report.quickWins) { quickWinCard($0) }
                    }
                }
            }

            if !report.strategicBets.isEmpty {
                section("Paris stratégiques") {
                    VStack(spacing: 10) {
                        ForEach(report.strategicBets) { strategicBetCard($0) }
                    }
                }
            }

            if !report.hiddenRisks.isEmpty {
                section("Risques cachés") {
                    VStack(spacing: 10) {
                        ForEach(report.hiddenRisks) { hiddenRiskCard($0) }
                    }
                }
            }

            if let findings = report.findings, findings.hasAnyData {
                section("Détails techniques") {
                    VStack(spacing: 10) {
                        findingsCards(findings)
                    }
                }
            }

            section("Pitch prêt à envoyer") {
                pitchCard(report)
            }

            saveBar(for: report)
        }
    }

    private func scoreHeroCard(_ report: AuditReport) -> some View {
        LiquidCard(cornerRadius: 24) {
            VStack(spacing: 14) {
                Text(report.client.displayName)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(report.persona.label.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .tracking(1.2)

                ZStack {
                    RadialScoreChart(
                        performance: report.scoring.performance,
                        seo: report.scoring.seo,
                        security: report.scoring.security,
                        brand: report.scoring.brand,
                        mobile: report.scoring.mobile
                    )
                    .frame(height: 240)

                    VStack(spacing: 0) {
                        Text("\(report.scoring.overall)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(LiquidPalette.iris)
                            .contentTransition(.numericText())
                        Text("/ 100")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let perf = report.performance {
                    perfDetails(perf)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func scoreColor(_ value: Int) -> Color {
        switch value {
        case 80...:   return .green
        case 50..<80: return .orange
        default:      return .red
        }
    }

    @ViewBuilder
    private func perfDetails(_ p: AuditReport.PerformanceMetrics) -> some View {
        HStack(spacing: 14) {
            if let lcp = p.largestContentfulPaintSeconds {
                metricBadge(label: "LCP", value: String(format: "%.1fs", lcp))
            }
            if let inp = p.interactionToNextPaintMs {
                metricBadge(label: "INP", value: "\(inp) ms")
            }
            if let cls = p.cumulativeLayoutShift {
                metricBadge(label: "CLS", value: String(format: "%.2f", cls))
            }
        }
        .padding(.top, 8)
    }

    private func metricBadge(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func quickWinCard(_ win: AuditReport.QuickWin) -> some View {
        LiquidCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(win.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Spacer()
                    impactBadge(win.impact)
                }
                Text(win.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(formatEffort(win.effortDays))
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(LiquidPalette.iris)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func impactBadge(_ impact: AuditReport.QuickWin.Impact) -> some View {
        let color: Color = {
            switch impact {
            case .high:   return .green
            case .medium: return .orange
            case .low:    return .gray
            }
        }()
        return Text(impact.rawValue.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(color.opacity(0.85))
            }
    }

    private func formatEffort(_ days: Double) -> String {
        if days < 1   { return "≈ \(Int((days * 8).rounded())) h" }
        if days < 1.5 { return "1 jour" }
        return "\(Int(days.rounded())) jours"
    }

    @ViewBuilder
    private func hiddenRiskCard(_ risk: AuditReport.HiddenRisk) -> some View {
        LiquidCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(severityColor(risk.severity))
                    Text(risk.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Spacer()
                    severityBadge(risk.severity)
                }
                Text(risk.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func severityBadge(_ severity: AuditReport.HiddenRisk.Severity) -> some View {
        Text(severity.rawValue.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(severityColor(severity).opacity(0.88))
            }
    }

    private func severityColor(_ severity: AuditReport.HiddenRisk.Severity) -> Color {
        switch severity {
        case .low:      return .gray
        case .medium:   return .orange
        case .high:     return .red
        case .critical: return .purple
        }
    }

    @ViewBuilder
    private func findingsCards(_ findings: AuditFindings) -> some View {
        if let security = findings.security {
            findingCard(
                icon: "lock.shield.fill",
                title: "Sécurité headers",
                tint: securityTint(security.grade),
                lines: [
                    "Grade \(security.grade) · score \(security.score)/100",
                    "TLS \(security.tlsValid ? "valide" : "invalide")",
                    security.presentHeaders.isEmpty
                        ? "aucun header sécurité"
                        : "présents : \(security.presentHeaders.prefix(3).joined(separator: ", "))",
                    security.missingHeaders.isEmpty
                        ? nil
                        : "manquants : \(security.missingHeaders.prefix(3).joined(separator: ", "))",
                ]
            )
        }

        if let email = findings.email {
            findingCard(
                icon: "envelope.fill",
                title: "Infra email",
                tint: email.hasSPF && email.hasDMARC ? .green : .orange,
                lines: [
                    "Provider : \(email.provider ?? "inconnu")",
                    "SPF \(email.hasSPF ? "✓" : "✗")  ·  DMARC \(email.hasDMARC ? "✓" : "✗")",
                ]
            )
        }

        if let domain = findings.domain {
            let age = domain.ageYears.map { String(format: "%.1f", $0) + " ans" } ?? "n/a"
            findingCard(
                icon: "globe",
                title: "Domaine",
                tint: LiquidPalette.iris,
                lines: [
                    "Registrar : \(domain.registrar ?? "inconnu")",
                    "Âge : \(age)",
                ]
            )
        }

        if let mobile = findings.mobile {
            if mobile.hasIOSApp {
                let rating = mobile.averageRating.map { String(format: "%.1f", $0) + "★" } ?? "n/a"
                let count = mobile.ratingCount.map { "\($0) avis" } ?? "0 avis"
                findingCard(
                    icon: "apple.logo",
                    title: "App iOS",
                    tint: .green,
                    lines: [
                        "« \(mobile.appName ?? "?") » par \(mobile.sellerName ?? "?")",
                        "\(rating) · \(count)",
                    ]
                )
            } else {
                findingCard(
                    icon: "apple.logo",
                    title: "App iOS",
                    tint: .orange,
                    lines: ["Aucune app native — opportunité claire"]
                )
            }
        }

        if let schema = findings.schema {
            let types = schema.detectedTypes.isEmpty ? "aucun" : schema.detectedTypes.prefix(4).joined(separator: ", ")
            findingCard(
                icon: "curlybraces",
                title: "Schema.org",
                tint: schema.hasJSONLD ? .green : .red,
                lines: [
                    schema.hasJSONLD ? "JSON-LD présent" : "JSON-LD ABSENT",
                    "Types : \(types)",
                ]
            )
        }

        if let og = findings.openGraph {
            findingCard(
                icon: "square.on.square.dashed",
                title: "OpenGraph",
                tint: og.completenessScore >= 80 ? .green : (og.completenessScore >= 50 ? .orange : .red),
                lines: [
                    "Complétude \(og.completenessScore)/100",
                    [og.hasTitle ? "title✓" : "title✗",
                     og.hasDescription ? "desc✓" : "desc✗",
                     og.hasImage ? "image✓" : "image✗",
                     og.hasType ? "type✓" : "type✗",
                     og.hasTwitterCard ? "twitter✓" : "twitter✗"].joined(separator: " · "),
                ]
            )
        }

        if let crawl = findings.crawlability {
            findingCard(
                icon: "magnifyingglass.circle.fill",
                title: "Crawlability",
                tint: crawl.hasRobotsTxt && crawl.hasSitemap ? .green : .orange,
                lines: [
                    "robots.txt : \(crawl.hasRobotsTxt ? "présent" : "ABSENT")",
                    "sitemap.xml : \(crawl.hasSitemap ? "présent" : "ABSENT")\(crawl.sitemapURLCount.map { " (\($0) URLs)" } ?? "")",
                ]
            )
        }

        if let comp = findings.compliance {
            findingCard(
                icon: "checkmark.shield.fill",
                title: "Compliance",
                tint: comp.hasCookieBanner && comp.hasPrivacyLink ? .green : .orange,
                lines: [
                    "Cookie banner : \(comp.hasCookieBanner ? "présent" : "ABSENT")\(comp.cookieProvider.map { " (\($0))" } ?? "")",
                    "Privacy : \(comp.hasPrivacyLink ? "✓" : "✗")  ·  CGU : \(comp.hasTermsLink ? "✓" : "✗")",
                ]
            )
        }

        if let analytics = findings.analytics {
            let providers = analytics.providers.isEmpty ? "aucun" : analytics.providers.prefix(3).joined(separator: ", ")
            findingCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "Analytics",
                tint: analytics.hasAnyAnalytics ? .green : .orange,
                lines: [
                    "SDKs : \(providers)",
                    "Error tracking : \(analytics.hasErrorTracking ? "✓" : "✗")",
                ]
            )
        }

        if let payment = findings.payment {
            let processors = payment.processors.isEmpty ? "aucun" : payment.processors.joined(separator: ", ")
            findingCard(
                icon: "creditcard.fill",
                title: "Payment",
                tint: payment.hasMonetization ? .green : .gray,
                lines: [
                    "Processors : \(processors)",
                    payment.hasPayWall ? "Pay-wall détecté" : "Pas de pay-wall",
                ]
            )
        }

        if let cdn = findings.cdn {
            findingCard(
                icon: "cloud.fill",
                title: "CDN / Hosting",
                tint: LiquidPalette.iris,
                lines: [
                    "Provider : \(cdn.provider ?? "inconnu / non détecté")",
                    cdn.serverHeader.map { "Server : \($0)" } ?? "Server : n/a",
                ]
            )
        }

        if let trust = findings.trust {
            if let score = trust.trustpilotScore, let count = trust.trustpilotReviewCount {
                findingCard(
                    icon: "star.fill",
                    title: "Trustpilot",
                    tint: score >= 4.0 ? .green : (score >= 3.0 ? .orange : .red),
                    lines: [
                        String(format: "%.1f", score) + "★ · \(count) avis",
                    ]
                )
            } else {
                findingCard(
                    icon: "star",
                    title: "Trustpilot",
                    tint: .gray,
                    lines: ["Pas de profile public détecté"]
                )
            }
        }
    }

    private func findingCard(
        icon: String,
        title: String,
        tint: Color,
        lines: [String?]
    ) -> some View {
        LiquidCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.18))
                            .frame(width: 30, height: 30)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Spacer()
                }
                ForEach(lines.compactMap { $0 }, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func securityTint(_ grade: String) -> Color {
        switch grade {
        case "A+", "A": return .green
        case "B":       return .orange
        case "C", "D":  return .orange
        default:        return .red
        }
    }

    @ViewBuilder
    private func strategicBetCard(_ bet: AuditReport.StrategicBet) -> some View {
        LiquidCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(bet.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(bet.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label("\(bet.durationMonths) mois", systemImage: "calendar")
                    Label(budgetLabel(bet), systemImage: "eurosign.circle")
                }
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(LiquidPalette.iris)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func budgetLabel(_ bet: AuditReport.StrategicBet) -> String {
        let min = bet.budgetMinEUR / 1000
        let max = bet.budgetMaxEUR / 1000
        return "€\(min)k – €\(max)k"
    }

    @ViewBuilder
    private func pitchCard(_ report: AuditReport) -> some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(report.pitch)
                    .font(.system(.subheadline, design: .rounded))
                    .textSelection(.enabled)
                HStack(spacing: 18) {
                    Button {
                        UIPasteboard.general.string = report.pitch
                    } label: {
                        Label("Copier", systemImage: "doc.on.doc.fill")
                    }
                    if let url = mailtoURL(for: report) {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Mail", systemImage: "envelope.fill")
                        }
                    }
                    Button {
                        exportSheetReport = ExportSheetReport(report: report)
                    } label: {
                        Label("Exporter", systemImage: "square.and.arrow.up.on.square.fill")
                    }
                    Button {
                        briefMarkdown = ClaudeCodeBriefBuilder.build(from: report)
                    } label: {
                        Label("Brief Claude Code", systemImage: "terminal.fill")
                    }
                    Button {
                        visualBoardReport = VisualBoardReportItem(report: report)
                    } label: {
                        Label("Maquetter le futur", systemImage: "sparkles")
                    }
                    Spacer()
                }
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(LiquidPalette.iris)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func saveBar(for report: AuditReport) -> some View {
        if saved {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LiquidPalette.iris)
                Text("Sauvegardé dans le graphe.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Nouvel audit") {
                    resetForNewAudit()
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(LiquidPalette.iris)
            }
            .padding(.top, 6)
        } else {
            LiquidButton(title: "Sauvegarder dans MIND", systemImage: "drop.fill") {
                persist(report)
            }
        }
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, 4)
            content()
        }
    }

    private var normalizedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        return URL(string: candidate)
    }

    private func startAudit() {
        guard let url = normalizedURL else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = AuditClient(
            url: url,
            name: trimmedName.isEmpty ? nil : trimmedName
        )
        controller.run(for: client)
        saved = false
        pdfURL = nil
        urlFocused = false
    }

    private func resetForNewAudit() {
        controller.cancel()
        urlString = ""
        name = ""
        saved = false
        pdfURL = nil
        urlFocused = true
    }

    private func mailtoURL(for report: AuditReport) -> URL? {
        let subject = "Audit MIND — \(report.client.displayName)"
        var components = URLComponents(string: "mailto:")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: report.pitch),
        ]
        return components?.url
    }

    // MARK: - Export sheet

    private struct ExportSheet: View {
        @Environment(\.dismiss) private var dismiss
        let report: AuditReport

        @State private var markdownURL: URL?
        @State private var jsonURL: URL?
        @State private var htmlURL: URL?
        @State private var pdfURL: URL?

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Exporter l'audit")
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                            Text(report.client.displayName)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    exportRow(
                        icon: "doc.text",
                        title: "Markdown",
                        subtitle: "Pour Notion, Linear, Obsidian, Bear",
                        url: markdownURL,
                        action: prepareMarkdown
                    )

                    exportRow(
                        icon: "doc.richtext.fill",
                        title: "PDF brandé",
                        subtitle: "Une page A4, score hero, quick wins, pitch",
                        url: pdfURL,
                        action: preparePDF
                    )

                    exportRow(
                        icon: "envelope.fill",
                        title: "Email HTML",
                        subtitle: "Email stylé à coller directement",
                        url: htmlURL,
                        action: prepareHTML
                    )

                    exportRow(
                        icon: "curlybraces",
                        title: "JSON",
                        subtitle: "Pour Make, Zapier, n8n, intégration tierce",
                        url: jsonURL,
                        action: prepareJSON
                    )
                }
                .padding(20)
                .padding(.bottom, 32)
            }
            .background { LiquidBackground().ignoresSafeArea() }
        }

        @ViewBuilder
        private func exportRow(
            icon: String,
            title: String,
            subtitle: String,
            url: URL?,
            action: @escaping () -> Void
        ) -> some View {
            LiquidCard(cornerRadius: 18) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.iris.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(subtitle)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url {
                        ShareLink(item: url, preview: SharePreview(title)) {
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                    } else {
                        Button(action: action) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                    }
                }
                .padding(16)
            }
        }

        // MARK: - Prepare each format

        private func prepareMarkdown() {
            let text = AuditExporter.markdown(from: report)
            markdownURL = writeTemp(text: text, ext: "md", prefix: "MIND-audit")
        }

        private func preparePDF() {
            pdfURL = PDFReportRenderer.makePDF(for: report)
        }

        private func prepareHTML() {
            let html = AuditExporter.htmlEmail(from: report)
            htmlURL = writeTemp(text: html, ext: "html", prefix: "MIND-audit")
        }

        private func prepareJSON() {
            guard let data = AuditExporter.json(from: report) else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("MIND-audit-\(report.client.id.uuidString.prefix(8)).json")
            try? data.write(to: url)
            jsonURL = url
        }

        private func writeTemp(text: String, ext: String, prefix: String) -> URL? {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(prefix)-\(report.client.id.uuidString.prefix(8)).\(ext)")
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch {
                return nil
            }
        }
    }

    // MARK: - Brief preview

    private struct BriefPreviewItem: Identifiable {
        let id = UUID()
        let markdown: String
    }

    private struct BriefPreviewSheet: View {
        @Environment(\.dismiss) private var dismiss
        let markdown: String

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Brief Claude Code")
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                            Text("Prêt à coller dans une session Claude Code.")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = markdown
                        } label: {
                            Label("Copier", systemImage: "doc.on.doc.fill")
                        }
                        ShareLink(item: markdown) {
                            Label("Partager", systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)

                    LiquidCard(cornerRadius: 18) {
                        MarkdownView(markdown)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background { LiquidBackground().ignoresSafeArea() }
        }
    }

    private func persist(_ report: AuditReport) {
        let clientNode = Node(
            kind: .client,
            title: report.client.displayName,
            content: report.client.url.absoluteString,
            tags: [report.persona.rawValue],
            sourceURL: report.client.url.absoluteString
        )
        context.insert(clientNode)
        clientNode.refreshEmbedding()

        let auditNode = Node(
            kind: .audit,
            title: "Audit — \(report.client.displayName)",
            content: report.synthesis,
            tags: ["audit", report.persona.rawValue, "score-\(report.scoring.overall)"],
            sourceURL: report.client.url.absoluteString
        )
        context.insert(auditNode)
        auditNode.refreshEmbedding()

        let edge = Edge(kind: .derivedFrom, from: auditNode, to: clientNode)
        context.insert(edge)

        try? context.save()
        saved = true
    }
}
