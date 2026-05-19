import SwiftUI
import SwiftData
import AuditKit
import ClientPortalKit
import DesignSystem
import GraphCore
import LinearKit
import NotionKit
import Settings
import VisualKit

struct AuditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    /// Optional URL the sheet should pre-fill on appear. Lets callers
    /// (e.g. ClientsView's "Try Stripe / Linear / Notion" empty-state
    /// suggestions, or a deep link from a notification) skip the
    /// keyboard-tap-typing step entirely. nil = blank field.
    let initialURL: String?

    @State private var controller = AuditController.shared
    @State private var urlString: String = ""
    @State private var name: String = ""
    @State private var saved: Bool = false
    @State private var pdfURL: URL?
    @State private var briefMarkdown: String?
    @State private var exportSheetReport: ExportSheetReport?
    @State private var visualBoardReport: VisualBoardReportItem?

    // v0.12 — Per-QuickWin Linear push state. Keyed by win.id so a
    // single in-flight push doesn't disable every other row's button.
    @State private var linearPushingIDs: Set<UUID> = []
    /// QW IDs that have been successfully pushed in this session.
    /// Drives the "Push to Linear" button → "Pushed" pill swap so
    /// Mehdi doesn't accidentally double-push the same QW.
    @State private var linearPushedIDs: Set<UUID> = []
    @State private var linearToast: String?
    @FocusState private var urlFocused: Bool

    init(initialURL: String? = nil) {
        self.initialURL = initialURL
    }

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
            // If the caller passed a starter URL (e.g. ClientsView's
            // demo suggestions), seed it once and skip the keyboard.
            // Only do this when the field is still empty so re-presenting
            // the sheet doesn't clobber the user's typing.
            if let seed = initialURL, urlString.isEmpty {
                urlString = seed
            }
            if controller.report == nil && controller.phase == .idle && urlString.isEmpty {
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
        .alert(String(localized: "audit.export.linear.toast.title", bundle: .main),
               isPresented: Binding(get: { linearToast != nil },
                                    set: { if !$0 { linearToast = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(linearToast ?? "")
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
                Text("audit.header.title")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("audit.header.subtitle")
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
                    fieldLabel(String(localized: "audit.field.url"))
                    TextField(String(localized: "audit.field.urlPlaceholder"), text: $urlString)
                        .textFieldStyle(.plain)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .rounded))
                        .focused($urlFocused)

                    Divider().background(.white.opacity(0.18))

                    fieldLabel(String(localized: "audit.field.name"))
                    TextField("Stripe", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .rounded))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LiquidButton(title: String(localized: "audit.button.start"), systemImage: "magnifyingglass") {
                startAudit()
            }
            .disabled(normalizedURL == nil)
            .opacity(normalizedURL == nil ? 0.45 : 1)

            Text("audit.formHint")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 16) {
            LiquidCard(cornerRadius: 22) {
                VStack(spacing: 22) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(LiquidPalette.iris)
                    Text(controller.progressLabel)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)

                    phaseStepIndicator

                    Text("audit.running.backgroundHint")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "audit.button.cancel")) {
                        controller.cancel()
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }

            probeStatusList

            if controller.hasFailedProbes {
                LiquidButton(
                    title: "\(String(localized: "audit.button.retry")) (\(controller.failedProbes.count))",
                    systemImage: "arrow.counterclockwise",
                    haptic: .select
                ) {
                    controller.retryFailedProbes()
                }
            }
        }
    }

    /// One row per probe — yellow dot while running, green for ok, red
    /// for failed. The list is the source of truth for the per-probe
    /// retry CTA: tapping "Réessayer" re-runs only the rows with red dots.
    @ViewBuilder
    private var probeStatusList: some View {
        if !controller.probeStates.isEmpty {
            LiquidCard(cornerRadius: 18) {
                VStack(spacing: 0) {
                    HStack {
                        Text("audit.probes.list.header")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.8)
                        Spacer()
                        probeSummaryBadge
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                    ForEach(Array(AuditController.ProbeKind.allCases.enumerated()), id: \.element) { index, kind in
                        probeRow(kind: kind, state: controller.probeStates[kind] ?? .running)
                        if index < AuditController.ProbeKind.allCases.count - 1 {
                            Divider()
                                .background(.white.opacity(0.10))
                                .padding(.leading, 46)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var probeSummaryBadge: some View {
        let states = controller.probeStates
        let ok = states.values.filter { $0.isOK }.count
        let failed = states.values.filter { $0.isFailed }.count
        let running = states.values.filter { $0.isRunning }.count
        return HStack(spacing: 8) {
            badgePill(count: ok, color: .green)
            badgePill(count: running, color: .yellow)
            badgePill(count: failed, color: .red)
        }
    }

    @ViewBuilder
    private func badgePill(count: Int, color: Color) -> some View {
        if count > 0 {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text("\(count)")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func probeRow(
        kind: AuditController.ProbeKind,
        state: AuditController.ProbeState
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 28, height: 28)
                Image(systemName: kind.systemImage)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.label)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.85)
                    .lineLimit(2)
                if case .failed(let reason) = state {
                    Text(reason)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.red.opacity(0.85))
                        .lineLimit(3)
                }
            }
            Spacer()
            probeStateDot(state)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func probeStateDot(_ state: AuditController.ProbeState) -> some View {
        switch state {
        case .running:
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.25))
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 8, height: 8)
            }
            .accessibilityLabel(Text("audit.probe.runningAccessibility"))
        case .ok:
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.25))
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
            .accessibilityLabel(Text("audit.probe.okAccessibility"))
        case .failed:
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.25))
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            }
            .accessibilityLabel(Text("audit.probe.failedAccessibility"))
        }
    }

    /// Three-step progress indicator for the audit pipeline:
    /// Probing → Synthesizing → Ready. Each step lights up green
    /// when reached, the current step shows a Liquid Glass pulse,
    /// future steps stay muted. Gives the user a concrete sense of
    /// where the wall-time goes (probes ≈ 80%, synthesis ≈ 20%).
    private var phaseStepIndicator: some View {
        HStack(spacing: 10) {
            phaseStep(
                title: "audit.phase.probing",
                icon: "antenna.radiowaves.left.and.right",
                state: phaseState(for: .probing)
            )
            phaseConnector(reached: controller.phase != .idle && controller.phase != .probing)
            phaseStep(
                title: "audit.phase.synthesizing",
                icon: "sparkles",
                state: phaseState(for: .synthesizing)
            )
            phaseConnector(reached: controller.phase == .completed)
            phaseStep(
                title: "audit.phase.ready",
                icon: "checkmark.seal.fill",
                state: phaseState(for: .completed)
            )
        }
        .padding(.horizontal, 4)
    }

    private enum PhaseDisplayState {
        case pending     // not yet reached
        case active      // currently running
        case done        // completed
    }

    private func phaseState(for target: AuditController.Phase) -> PhaseDisplayState {
        let order: [AuditController.Phase] = [.idle, .probing, .synthesizing, .completed]
        guard let currentIdx = order.firstIndex(of: controller.phase),
              let targetIdx = order.firstIndex(of: target)
        else { return .pending }
        if currentIdx > targetIdx { return .done }
        if currentIdx == targetIdx { return .active }
        return .pending
    }

    @ViewBuilder
    private func phaseStep(
        title: LocalizedStringKey,
        icon: String,
        state: PhaseDisplayState
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(state == .done
                          ? AnyShapeStyle(Color.green.opacity(0.20))
                          : (state == .active
                             ? AnyShapeStyle(LiquidGradient.primary.opacity(0.85))
                             : AnyShapeStyle(Color.white.opacity(0.15))))
                    .frame(width: 36, height: 36)
                Image(systemName: state == .done ? "checkmark" : icon)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(state == .pending ? Color.secondary : .white)
            }
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(state == .pending ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .animation(LiquidMetrics.spring, value: state)
    }

    @ViewBuilder
    private func phaseConnector(reached: Bool) -> some View {
        Rectangle()
            .fill(reached ? AnyShapeStyle(LiquidPalette.iris) : AnyShapeStyle(Color.white.opacity(0.25)))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .animation(LiquidMetrics.spring, value: reached)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            LiquidCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("audit.error.title")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                    }
                    Text(message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("audit.error.checkKeyHint")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LiquidButton(title: String(localized: "audit.button.retry"), systemImage: "arrow.counterclockwise") {
                startAudit()
            }
        }
    }

    // MARK: - Report

    @ViewBuilder
    private func reportView(_ report: AuditReport) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            scoreHeroCard(report)

            if controller.hasFailedProbes {
                failedProbesBanner
            }

            section("Synthèse") {
                LiquidCard(cornerRadius: 18) {
                    MarkdownView(report.synthesis)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !report.quickWins.isEmpty {
                section("Quick wins") {
                    VStack(spacing: 14) {
                        ImpactEffortMatrix(
                            items: report.quickWins.map { win in
                                ImpactEffortMatrix.Item(
                                    id: win.id,
                                    label: win.title,
                                    effortDays: win.effortDays,
                                    impact: impactValue(win.impact)
                                )
                            }
                        )
                        .frame(height: 220)
                        .padding(.horizontal, 4)

                        VStack(spacing: 10) {
                            ForEach(report.quickWins) { quickWinCard($0) }
                        }
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

                    // Hero score is intentionally locked at 44pt
                    // (display-only) so the visual weight stays
                    // consistent inside the 240pt scoring chart.
                    // minimumScaleFactor handles AX5 overflow.
                    VStack(spacing: 0) {
                        Text("\(report.scoring.overall)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(LiquidPalette.iris)
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
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

    private func impactValue(_ impact: AuditReport.QuickWin.Impact) -> ImpactEffortMatrix.Item.Impact {
        switch impact {
        case .high:   return .high
        case .medium: return .medium
        case .low:    return .low
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
                HStack {
                    Text(formatEffort(win.effortDays))
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(LiquidPalette.iris)
                    Spacer()
                    linearPushButton(for: win)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// v0.12 — Mini "Push to Linear" trailing button. Hidden unless
    /// both the token and the default team are configured. While the
    /// push is in flight a `ProgressView` replaces the button so the
    /// other QW rows stay tappable. Once the row succeeds we swap to
    /// a "Pushed" pill — Mehdi can still scroll back and read it but
    /// can't fire a second issue for the same QW from this session.
    @ViewBuilder
    private func linearPushButton(for win: AuditReport.QuickWin) -> some View {
        if LinearTokenStore.read() != nil,
           let teamID = MINDPreferences.currentLinearDefaultTeamID() {
            if linearPushedIDs.contains(win.id) {
                Text("audit.export.linear.button", bundle: .main)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        Capsule(style: .continuous).fill(.ultraThinMaterial)
                    }
            } else if linearPushingIDs.contains(win.id) {
                ProgressView().controlSize(.mini)
            } else {
                Button {
                    pushQuickWinToLinear(win, teamID: teamID)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("audit.export.linear.button", bundle: .main)
                    }
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        Capsule(style: .continuous)
                            .fill(LiquidPalette.iris.opacity(0.14))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(LiquidPalette.iris.opacity(0.55), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pushQuickWinToLinear(_ win: AuditReport.QuickWin, teamID: String) {
        linearPushingIDs.insert(win.id)
        Task {
            do {
                let identifier = try await LinearClient.shared.createIssue(win, teamID: teamID)
                await MainActor.run {
                    linearPushingIDs.remove(win.id)
                    linearPushedIDs.insert(win.id)
                    linearToast = String(
                        format: String(localized: "audit.export.linear.success", bundle: .main),
                        identifier
                    )
                    LiquidHaptics.success()
                    MINDTelemetry.info("linear.issue.created", data: [
                        "surface": "audit.report.row",
                        "identifier": identifier,
                    ])
                }
            } catch {
                await MainActor.run {
                    linearPushingIDs.remove(win.id)
                    linearToast = String(
                        format: String(localized: "audit.export.linear.error", bundle: .main),
                        String(describing: error)
                    )
                    LiquidHaptics.error()
                    MINDTelemetry.warning("linear.issue.failed", data: [
                        "surface": "audit.report.row",
                        "error": String(describing: error),
                    ])
                }
            }
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
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(severityColor(risk.severity))
                    Text(risk.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .minimumScaleFactor(0.85)
                        .lineLimit(3)
                    Spacer()
                    severityBadge(risk.severity)
                }
                Text(risk.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
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
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .minimumScaleFactor(0.85)
                        .lineLimit(2)
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

    /// Surfaced inside the report view when ≥1 probe failed during
    /// the most recent run. Reuses the AuditController retry contract:
    /// only failed probes re-fetch, successful results stay cached.
    private var failedProbesBanner: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("\(controller.failedProbes.count) sonde(s) en échec")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                Text(failedProbeLabels)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                LiquidButton(
                    title: "Réessayer les sondes en échec",
                    systemImage: "arrow.counterclockwise",
                    haptic: .select
                ) {
                    controller.retryFailedProbes()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var failedProbeLabels: String {
        controller.failedProbes.map(\.label).joined(separator: " · ")
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

        // v0.11 — Notion sync state. URL of the freshly-created page
        // doubles as both "the sync completed" flag and the value the
        // success toast surfaces to the user.
        @State private var notionPageURL: String?
        @State private var notionSyncing: Bool = false
        @State private var notionError: String?

        /// Computed: show the Sync to Notion row only when the user
        /// has both pasted an integration token (Keychain) and a
        /// database ID (UserDefaults). Otherwise the row would always
        /// land on an error and clutter the export sheet.
        private var notionConfigured: Bool {
            NotionTokenStore.read() != nil
            && MINDPreferences.currentNotionDatabaseID() != nil
        }

        // v0.12 — Linear bulk sync state. Three tristate values share
        // the same alert binding the same way Notion's URL/error pair
        // does: linearSuccess (created identifiers joined) drives the
        // success path, linearPartial (created, failed) drives the
        // "x/y" toast, linearError drives the hard-failure path.
        @State private var linearSuccess: String?
        @State private var linearPartial: (created: Int, failed: Int)?
        @State private var linearError: String?
        @State private var linearBulkSyncing: Bool = false

        /// Same gating contract as `notionConfigured` — both the
        /// personal API key (Keychain) and the default team UUID
        /// (UserDefaults) must be set for the bulk row to render.
        private var linearConfigured: Bool {
            LinearTokenStore.read() != nil
            && MINDPreferences.currentLinearDefaultTeamID() != nil
        }

        // v0.21 — Client Portal generation state. The Generate button
        // disables itself + shows a spinner while the PortalWriter
        // actor is mid-write; the resulting folder URL is held in
        // `portalFolderURL` and drives a follow-up success sheet that
        // surfaces both "Open in Files" and "Share folder" buttons.
        @State private var portalGenerating: Bool = false
        @State private var portalFolderURL: URL?
        @State private var portalError: String?
        @State private var portalShareItem: PortalShareItem?

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

                    if notionConfigured {
                        notionSyncRow
                    }

                    if linearConfigured && !report.quickWins.isEmpty {
                        linearBulkRow
                    }

                    // v0.21 — Client Portal generator. Always visible
                    // (no token / opt-in required) because the output
                    // is a local folder, not a remote sync.
                    clientPortalRow
                }
                .padding(20)
                .padding(.bottom, 32)
            }
            .background { LiquidBackground().ignoresSafeArea() }
            // v0.21 — Success bottom sheet after the portal generates.
            // Sheet binding fires from `portalFolderURL` instead of
            // a Bool so the URL is available inside the sheet's
            // closure without an Optional unwrap dance.
            .sheet(item: $portalShareItem) { item in
                PortalSuccessSheet(folderURL: item.url) {
                    portalShareItem = nil
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
            .alert(String(localized: "audit.export.portal.error.title", bundle: .main),
                   isPresented: Binding(get: { portalError != nil },
                                        set: { if !$0 { portalError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(portalError ?? "")
            }
            .alert(String(localized: "audit.export.notion.toast.title", bundle: .main),
                   isPresented: Binding(get: { notionPageURL != nil || notionError != nil },
                                        set: { if !$0 { notionPageURL = nil; notionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                if let url = notionPageURL {
                    Text(String(format: String(localized: "audit.export.notion.success", bundle: .main), url))
                } else if let err = notionError {
                    Text(String(format: String(localized: "audit.export.notion.error", bundle: .main), err))
                }
            }
            .alert(String(localized: "audit.export.linear.toast.title", bundle: .main),
                   isPresented: Binding(
                    get: { linearSuccess != nil || linearPartial != nil || linearError != nil },
                    set: { if !$0 { linearSuccess = nil; linearPartial = nil; linearError = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let ids = linearSuccess {
                    Text(String(format: String(localized: "audit.export.linear.success", bundle: .main), ids))
                } else if let partial = linearPartial {
                    Text(String(format: String(localized: "audit.export.linear.partial", bundle: .main),
                                partial.created, partial.failed))
                } else if let err = linearError {
                    Text(String(format: String(localized: "audit.export.linear.error", bundle: .main), err))
                }
            }
        }

        /// v0.11 — Sync to Notion row. Mirrors the visual rhythm of the
        /// markdown / PDF / HTML / JSON rows but the trailing action is
        /// an async network call rather than a `ShareLink`. We branch
        /// inline because `exportRow(…)` is keyed off "do I have a file
        /// URL yet?" — the Notion case has no file URL, only a
        /// remote page URL.
        @ViewBuilder
        private var notionSyncRow: some View {
            LiquidCard(cornerRadius: 18) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.iris.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("audit.export.notion.title", bundle: .main)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .minimumScaleFactor(0.85)
                            .lineLimit(2)
                        Text("audit.export.notion.subtitle", bundle: .main)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if notionSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(action: syncToNotion) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                    }
                }
                .padding(16)
            }
        }

        private func syncToNotion() {
            guard let dbID = MINDPreferences.currentNotionDatabaseID() else { return }
            notionSyncing = true
            notionError = nil
            notionPageURL = nil
            Task {
                do {
                    let url = try await NotionClient.shared.createAuditPage(report, in: dbID)
                    await MainActor.run {
                        notionSyncing = false
                        notionPageURL = url
                        LiquidHaptics.success()
                        MINDTelemetry.info("notion.page.created", data: [
                            "surface": "audit.export",
                            "client": report.client.displayName,
                        ])
                    }
                } catch {
                    await MainActor.run {
                        notionSyncing = false
                        notionError = String(describing: error)
                        LiquidHaptics.error()
                        MINDTelemetry.warning("notion.page.failed", data: [
                            "surface": "audit.export",
                            "error": String(describing: error),
                        ])
                    }
                }
            }
        }

        /// v0.12 — "Push all QW to Linear" bulk row. Shares the row
        /// rhythm of `notionSyncRow` so the export sheet stays
        /// visually consistent across the two integrations. Hidden
        /// when there are zero Quick Wins (an empty bulk would just
        /// no-op and confuse the user).
        @ViewBuilder
        private var linearBulkRow: some View {
            LiquidCard(cornerRadius: 18) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.iris.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "checklist")
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("audit.export.linear.title", bundle: .main)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .minimumScaleFactor(0.85)
                            .lineLimit(2)
                        Text("audit.export.linear.subtitle", bundle: .main)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if linearBulkSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(action: pushAllQuickWinsToLinear) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                    }
                }
                .padding(16)
            }
        }

        private func pushAllQuickWinsToLinear() {
            guard let teamID = MINDPreferences.currentLinearDefaultTeamID() else { return }
            linearBulkSyncing = true
            linearError = nil
            linearSuccess = nil
            linearPartial = nil
            Task {
                do {
                    let result = try await LinearClient.shared.createIssuesBulk(
                        report.quickWins,
                        teamID: teamID
                    )
                    await MainActor.run {
                        linearBulkSyncing = false
                        if result.failures.isEmpty {
                            linearSuccess = result.createdIdentifiers.joined(separator: ", ")
                            LiquidHaptics.success()
                        } else {
                            linearPartial = (
                                created: result.createdIdentifiers.count,
                                failed: result.failures.count
                            )
                            LiquidHaptics.warning()
                        }
                        MINDTelemetry.info("linear.bulk.completed", data: [
                            "surface": "audit.export",
                            "created": "\(result.createdIdentifiers.count)",
                            "failed": "\(result.failures.count)",
                            "client": report.client.displayName,
                        ])
                    }
                } catch {
                    await MainActor.run {
                        linearBulkSyncing = false
                        linearError = String(describing: error)
                        LiquidHaptics.error()
                        MINDTelemetry.warning("linear.bulk.failed", data: [
                            "surface": "audit.export",
                            "error": String(describing: error),
                        ])
                    }
                }
            }
        }

        // MARK: - v0.21 Client Portal row + success flow

        /// Always-visible row that triggers a one-shot generate-then-
        /// share-folder pipeline. Distinct from the Notion / Linear
        /// rows because the output isn't a single file the user can
        /// `ShareLink(item:)` directly — it's a *folder* the user
        /// drag-drops onto Vercel / Cloudflare Pages, so we present
        /// a follow-up sheet with two actions: "Open in Files" and
        /// "Share folder" (UIActivityViewController).
        @ViewBuilder
        private var clientPortalRow: some View {
            LiquidCard(cornerRadius: 18) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.iris.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "globe.americas.fill")
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("audit.export.portal.title", bundle: .main)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .minimumScaleFactor(0.85)
                            .lineLimit(2)
                        Text("audit.export.portal.subtitle", bundle: .main)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if portalGenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(action: generateClientPortal) {
                            Image(systemName: "sparkles")
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                    }
                }
                .padding(16)
            }
        }

        private func generateClientPortal() {
            portalGenerating = true
            portalError = nil
            // Capture the report into the task so we don't reach back
            // into `self` from a non-isolated context.
            let snapshot = report
            Task {
                let archive = ClientPortalBuilder.generateSite(for: snapshot)
                MINDTelemetry.info("clientPortal.generated", data: [
                    "client": snapshot.client.displayName,
                    "bytes": "\(archive.totalBytes)",
                    "files": "\(archive.files.count)",
                ])
                let destinationRoot = portalDestinationRoot()
                do {
                    let folderURL = try await PortalWriter().write(
                        archive: archive,
                        under: destinationRoot
                    )
                    await MainActor.run {
                        portalGenerating = false
                        portalFolderURL = folderURL
                        portalShareItem = PortalShareItem(url: folderURL)
                        LiquidHaptics.success()
                    }
                } catch {
                    await MainActor.run {
                        portalGenerating = false
                        portalError = String(describing: error)
                        LiquidHaptics.error()
                        MINDTelemetry.error("clientPortal.write.failed", data: [
                            "error": String(describing: error),
                        ])
                    }
                }
            }
        }

        /// Resolved at call site so tests can override via DI later. The
        /// canonical location is `~/Documents/client-portals/` — the
        /// "Files" app picks the folder up automatically because the
        /// app target ships with `UISupportsDocumentBrowser` +
        /// `LSSupportsOpeningDocumentsInPlace`.
        private func portalDestinationRoot() -> URL {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            return docs.appendingPathComponent("client-portals", isDirectory: true)
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
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .minimumScaleFactor(0.85)
                            .lineLimit(2)
                        Text(subtitle)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if let url {
                        ShareLink(item: url, preview: SharePreview(title)) {
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.system(.callout, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                    } else {
                        Button(action: action) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(.title3, design: .rounded, weight: .semibold))
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

        // v0.21 — Identifiable wrapper for the success sheet. SwiftUI
        // sheet(item:) needs Identifiable; URL is not, hence the
        // one-field box that carries `id = UUID()` for free.
        fileprivate struct PortalShareItem: Identifiable {
            let id = UUID()
            let url: URL
        }
    }

    // v0.21 — Portal success bottom sheet. Two buttons:
    // 1. "Open in Files" — `UIApplication.open(_:)` with `shareddocuments://`
    //    scheme so the system Files app jumps into the generated folder.
    // 2. "Share folder" — UIActivityViewController source list of the
    //    folder URL, lets Mehdi AirDrop / Mail / iCloud Drive the
    //    whole directory to the client or a Vercel deploy.
    fileprivate struct PortalSuccessSheet: View {
        let folderURL: URL
        let onDismiss: () -> Void

        @State private var showingShareController = false

        var body: some View {
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("audit.export.portal.success.title", bundle: .main)
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                            Text(folderURL.lastPathComponent)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { onDismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LiquidCard(cornerRadius: 18) {
                        VStack(spacing: 14) {
                            Image(systemName: "globe.americas.fill")
                                .font(.system(size: 46))
                                .foregroundStyle(LiquidPalette.iris)
                                .padding(.top, 22)
                            Text("audit.export.portal.success.body", bundle: .main)
                                .font(.system(.subheadline, design: .rounded))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 22)
                                .padding(.bottom, 4)
                            Text(folderURL.path)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .padding(.horizontal, 22)
                                .padding(.bottom, 18)
                        }
                    }

                    Button(action: openInFiles) {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text("audit.export.portal.success.openInFiles", bundle: .main)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    ShareLink(item: folderURL) {
                        HStack {
                            Image(systemName: "square.and.arrow.up.fill")
                            Text("audit.export.portal.success.share", bundle: .main)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        MINDTelemetry.info("clientPortal.shared", data: [
                            "folder": folderURL.lastPathComponent,
                        ])
                    })
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background { LiquidBackground().ignoresSafeArea() }
        }

        private func openInFiles() {
            // shareddocuments:// is the documented scheme for jumping
            // straight into the app's Documents directory inside the
            // Files app. We rewrite the file:// URL to use that scheme
            // and let UIApplication route it.
            guard var components = URLComponents(url: folderURL, resolvingAgainstBaseURL: false) else { return }
            components.scheme = "shareddocuments"
            guard let openURL = components.url else { return }
            UIApplication.shared.open(openURL)
            MINDTelemetry.info("clientPortal.opened", data: [
                "folder": folderURL.lastPathComponent,
            ])
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
