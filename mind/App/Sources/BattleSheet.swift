import SwiftUI
import AuditKit
import DesignSystem
import GraphCore

/// v0.24 — Audit Battle Mode UI.
///
/// One sheet covers three phases: form (compose the 4 contenders),
/// running (4 LiquidCards side-by-side, each ticking its 13 probes
/// in real time), completed (a radar chart over all 4 polygons + a
/// per-metric podium row with a winner badge). HomeView presents
/// it via the secondary CTA on the audit card.
///
/// Cinematic in the "premium SaaS demo" way: dark Liquid Glass
/// background, iris/aqua palette across the polygons, smooth
/// SwiftUI transitions between phases. No animations during
/// `prefers-reduced-motion` (LiquidMetrics already gates this in
/// the shared primitives).
struct BattleSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var battle = BattleController()
    @State private var primaryURL: String = ""
    @State private var competitorInput: String = ""
    @State private var competitors: [String] = []
    @State private var validationMessage: String?
    @FocusState private var primaryFocused: Bool

    /// Stable colour palette used to colour the polygons + the
    /// participant chip backgrounds. Indices map to participant
    /// order (primary first). 4 entries cover the max battle size.
    private let palette: [Color] = [
        LiquidPalette.iris,
        LiquidPalette.aqua,
        LiquidPalette.sky,
        LiquidPalette.blush,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .animation(.smooth, value: battle.phase)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .onAppear {
            if primaryURL.isEmpty {
                primaryFocused = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("battle.title", bundle: .main)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.7)
                .lineLimit(2)
                .foregroundStyle(LiquidGradient.aurora)
            Text("battle.subtitle", bundle: .main)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch battle.phase {
        case .idle:    formCard
        case .running: runningGrid
        case .completed: resultView
        }
    }

    // MARK: - Form (.idle)

    private var formCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 18) {
                primaryField
                competitorChips
                addCompetitorField
                if let validationMessage {
                    Text(validationMessage)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LiquidButton(
                    title: String(localized: "battle.cta.start", bundle: .main),
                    systemImage: "bolt.horizontal.fill",
                    haptic: .select
                ) {
                    startBattle()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
        }
    }

    private var primaryField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("battle.form.primary.label", bundle: .main)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            TextField(
                String(localized: "battle.form.primary.placeholder", bundle: .main),
                text: $primaryURL
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .focused($primaryFocused)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .onChange(of: primaryURL) { _, newValue in
                refreshCompetitorSuggestions(for: newValue)
            }
        }
    }

    private var competitorChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("battle.form.competitors.label", bundle: .main)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if competitors.isEmpty {
                Text("battle.form.competitors.empty", bundle: .main)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(Array(competitors.enumerated()), id: \.element) { _, host in
                        chip(for: host)
                    }
                }
            }
        }
    }

    private func chip(for host: String) -> some View {
        Button {
            removeCompetitor(host)
        } label: {
            HStack(spacing: 6) {
                Text(host)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                Image(systemName: "xmark.circle.fill")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(LiquidPalette.iris.opacity(0.4), lineWidth: 1)
                    }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private var addCompetitorField: some View {
        HStack(spacing: 10) {
            TextField(
                String(localized: "battle.form.add.competitor", bundle: .main),
                text: $competitorInput
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .onSubmit { commitCompetitorInput() }

            Button {
                commitCompetitorInput()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            .disabled(competitorInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Running (.running)

    private var runningGrid: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("battle.running.label", bundle: .main)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(battle.participants.enumerated()), id: \.element.id) { idx, participant in
                        participantRunningCard(
                            participant: participant,
                            color: palette[idx % palette.count]
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func participantRunningCard(
        participant: BattleController.Participant,
        color: Color
    ) -> some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(participant.client.displayName)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                }
                ForEach(AuditController.ProbeKind.allCases, id: \.self) { kind in
                    probeRow(
                        kind: kind,
                        state: participant.probeStates[kind] ?? .running
                    )
                }
                if let error = participant.error {
                    Text(error)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .padding(16)
            .frame(width: 220)
        }
    }

    private func probeRow(
        kind: AuditController.ProbeKind,
        state: AuditController.ProbeState
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(kind.label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            stateDot(state: state)
        }
    }

    private func stateDot(state: AuditController.ProbeState) -> some View {
        let color: Color = {
            switch state {
            case .running: return .yellow
            case .ok:      return .green
            case .failed:  return .red
            }
        }()
        return Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay {
                if case .running = state {
                    Circle()
                        .stroke(color.opacity(0.4), lineWidth: 1)
                        .scaleEffect(1.8)
                        .opacity(0.5)
                }
            }
    }

    // MARK: - Completed (.completed)

    private var resultView: some View {
        let report = battle.snapshot
        return VStack(alignment: .leading, spacing: 20) {
            radarCard(report: report)
            podiumCard(report: report)
            participantsLegend
        }
    }

    private func radarCard(report: BattleReport) -> some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("battle.radar.title", bundle: .main)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                RadarChartView(
                    series: radarSeries(),
                    axes: BattleReport.Metric.allCases.map { $0.label }
                )
                .frame(height: 320)
            }
            .padding(20)
        }
    }

    private func radarSeries() -> [RadarChartView.Series] {
        battle.participants.enumerated().map { idx, participant in
            let color = palette[idx % palette.count]
            let values: [Int] = BattleReport.Metric.allCases.map { metric in
                guard let report = participant.report else { return 0 }
                return BattleReport.scoreValue(metric, in: report.scoring)
            }
            return RadarChartView.Series(
                id: participant.id,
                label: participant.client.displayName,
                values: values,
                color: color
            )
        }
    }

    private func podiumCard(report: BattleReport) -> some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("battle.podium.title", bundle: .main)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                ForEach(BattleReport.Metric.allCases, id: \.self) { metric in
                    podiumRow(metric: metric, winner: report.winners[metric])
                }
            }
            .padding(20)
        }
    }

    private func podiumRow(metric: BattleReport.Metric, winner: AuditClient?) -> some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(metric.stringKey), bundle: .main)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 110, alignment: .leading)
            Spacer()
            if let winner {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                    Text(winner.displayName)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                    Text("battle.winner.badge", bundle: .main)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            Capsule().fill(LiquidPalette.iris)
                        }
                }
            } else {
                Text("—")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var participantsLegend: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(battle.participants.enumerated()), id: \.element.id) { idx, participant in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(palette[idx % palette.count])
                            .frame(width: 10, height: 10)
                        Text(participant.client.displayName)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Spacer()
                        if let report = participant.report {
                            Text("\(report.scoring.overall)/100")
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else if participant.error != nil {
                            Text("battle.legend.failed", bundle: .main)
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Actions

    private func startBattle() {
        validationMessage = nil
        let trimmed = primaryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let primaryAudit = makeClient(from: trimmed) else {
            validationMessage = String(localized: "battle.form.validation.invalidURL", bundle: .main)
            return
        }
        let competitorClients = competitors.compactMap { makeClient(from: $0) }
        battle.run(primary: primaryAudit, competitors: competitorClients)
    }

    private func makeClient(from raw: String) -> AuditClient? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme: String = {
            if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
                return trimmed
            }
            return "https://\(trimmed)"
        }()
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return AuditClient(url: url)
    }

    private func refreshCompetitorSuggestions(for raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let host: String = {
            if let url = URL(string: trimmed.lowercased().hasPrefix("http") ? trimmed : "https://\(trimmed)"),
               let h = url.host {
                return CompetitorLookup.normalise(h)
            }
            return CompetitorLookup.normalise(trimmed)
        }()
        let suggestions = CompetitorLookup.competitors(for: host)
        if !suggestions.isEmpty && competitors.isEmpty {
            competitors = suggestions
        }
    }

    private func commitCompetitorInput() {
        let trimmed = competitorInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalised = CompetitorLookup.normalise(trimmed)
        if !competitors.contains(normalised) {
            competitors.append(normalised)
        }
        competitorInput = ""
    }

    private func removeCompetitor(_ host: String) {
        competitors.removeAll { $0 == host }
    }
}

// MARK: - FlowLayout

/// Simple wrapping HStack used for the competitor chip row. Pulled
/// inline (rather than reaching into DesignSystem) so the chip row
/// remains a BattleSheet-local concern — no other module needs it.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let s = subview.sizeThatFits(.unspecified)
            if rowWidth + s.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX
        for subview in subviews {
            let s = subview.sizeThatFits(.unspecified)
            if x + s.width > maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: s.width, height: s.height)
            )
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
