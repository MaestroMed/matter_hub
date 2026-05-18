import SwiftUI
import SwiftData
import AuditKit
import DesignSystem
import GraphCore

struct AuditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var controller = AuditController.shared
    @State private var urlString: String = ""
    @State private var name: String = ""
    @State private var saved: Bool = false
    @State private var pdfURL: URL?
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
                    Text(LocalizedStringKey(report.synthesis))
                        .font(.system(.subheadline, design: .rounded))
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
                Text("\(report.scoring.overall)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LiquidPalette.iris)
                    .contentTransition(.numericText())
                Text("score global / 100")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                scoringRow(report.scoring)
                if let perf = report.performance {
                    perfDetails(perf)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func scoringRow(_ scoring: AuditReport.Scoring) -> some View {
        HStack(spacing: 0) {
            scorePill(value: scoring.performance, label: "Perf")
            scorePill(value: scoring.seo,         label: "SEO")
            scorePill(value: scoring.security,    label: "Sécu")
            scorePill(value: scoring.brand,       label: "Brand")
            scorePill(value: scoring.mobile,      label: "Mobile")
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func scorePill(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(scoreColor(value))
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                        pdfURL = PDFReportRenderer.makePDF(for: report)
                    } label: {
                        Label("PDF", systemImage: "doc.richtext.fill")
                    }
                    if let pdfURL {
                        ShareLink(
                            item: pdfURL,
                            preview: SharePreview("Audit \(report.client.displayName)")
                        ) {
                            Label("Partager", systemImage: "square.and.arrow.up")
                        }
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

    private func persist(_ report: AuditReport) {
        let clientNode = Node(
            kind: .client,
            title: report.client.displayName,
            content: report.client.url.absoluteString,
            tags: [report.persona.rawValue],
            sourceURL: report.client.url.absoluteString
        )
        context.insert(clientNode)

        let auditNode = Node(
            kind: .audit,
            title: "Audit — \(report.client.displayName)",
            content: report.synthesis,
            tags: ["audit", report.persona.rawValue, "score-\(report.scoring.overall)"],
            sourceURL: report.client.url.absoluteString
        )
        context.insert(auditNode)

        let edge = Edge(kind: .derivedFrom, from: auditNode, to: clientNode)
        context.insert(edge)

        try? context.save()
        saved = true
    }
}
