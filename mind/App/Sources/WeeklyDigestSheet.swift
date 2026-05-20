import SwiftUI
import DesignSystem
import GraphCore

/// v0.16 — Expanded weekly digest, opened by tapping the Bilan de la
/// semaine card on HomeView. Shows the three big counters as a refresher
/// at the top, the narrative (if any), the highlighted captures (each
/// row tappable → opens NodeDetailView via `onSelectNode`), and the
/// list of completed focus sessions with planned/actual durations.
///
/// Kept dependency-free of the rest of HomeView so it can be re-used by
/// any future "weekly retrospective" surface (Watch complication, widget
/// deep link). The caller hands in the digest, the focus sessions for
/// the same week, and a node-selection callback — everything else is
/// pure layout.
struct WeeklyDigestSheet: View {
    let digest: WeeklyDigest
    let nodes: [Node]
    let focusSessions: [FocusSessionRecord]
    let onSelectNode: (Node) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Maps the digest's highlighted titles back to their backing Node
    /// so a tap can route through `NodeDetailView`. Falls back to nil
    /// when the title can't be matched (e.g. user just renamed the
    /// node between digest computation and detail-sheet open), in
    /// which case the row is rendered non-interactively.
    private func node(for title: String) -> Node? {
        nodes.first { $0.title == title }
    }

    /// Captures/notes created within the digest's window, deduplicated
    /// against the same kindRaw filter used by the builder. Used by the
    /// "Captures of the week" section so the sheet shows every weekly
    /// capture (not just the 5 highlighted on the card).
    private var weeklyCaptureNodes: [Node] {
        nodes
            .filter {
                ($0.kindRaw == NodeKind.capture.rawValue
                    || $0.kindRaw == NodeKind.note.rawValue)
                    && $0.createdAt >= digest.weekOf
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var weeklyFocusSessions: [FocusSessionRecord] {
        focusSessions
            .filter { $0.completedAt >= digest.weekOf }
            .sorted { $0.completedAt > $1.completedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerCard
                    summaryCard
                    capturesSection
                    focusSection
                }
                .padding(20)
                .padding(.bottom, 60)
            }
            .background {
                LiquidBackground()
                    .ignoresSafeArea()
            }
            .navigationTitle(Text("home.weekly.detail.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        LiquidHaptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        LiquidCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Self.formatWeekHeader(digest.weekOf))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                if let narrative = digest.narrative, !narrative.isEmpty {
                    Text(narrative)
                        .font(.system(.body, design: .rounded))
                        .italic()
                        .foregroundStyle(.primary)
                        .lineLimit(6)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("home.weekly.narrative.fallback")
                        .font(.system(.body, design: .rounded))
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "home.weekly.detail.summary.header").uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 4)

            LiquidCard(cornerRadius: 22) {
                HStack(spacing: 0) {
                    summaryColumn(
                        value: "\(digest.captureCount)",
                        labelKey: "home.weekly.captures",
                        tint: LiquidPalette.iris
                    )
                    summaryDivider
                    summaryColumn(
                        value: "\(digest.auditCount)",
                        labelKey: "home.weekly.audits",
                        tint: .purple
                    )
                    summaryDivider
                    summaryColumn(
                        value: Self.formatFocus(hours: digest.focusHours),
                        labelKey: "home.weekly.focusHours",
                        tint: .green
                    )
                }
                .padding(18)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func summaryColumn(
        value: String,
        labelKey: String.LocalizationValue,
        tint: Color
    ) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(String(localized: labelKey).uppercased())
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(width: 1, height: 32)
    }

    private var capturesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "home.weekly.detail.captures.header").uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 4)

            if weeklyCaptureNodes.isEmpty {
                LiquidCard(cornerRadius: 20) {
                    Text("home.weekly.detail.empty")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(weeklyCaptureNodes) { node in
                        captureRow(node: node)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func captureRow(node: Node) -> some View {
        Button {
            LiquidHaptics.tap()
            onSelectNode(node)
        } label: {
            LiquidCard(cornerRadius: 18) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.iris.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: iconName(for: node))
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(node.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func iconName(for node: Node) -> String {
        switch node.kindRaw {
        case NodeKind.capture.rawValue: return "drop.fill"
        case NodeKind.note.rawValue:    return "doc.text.fill"
        case NodeKind.audit.rawValue:   return "magnifyingglass"
        default:                        return "circle.fill"
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "home.weekly.detail.focus.header").uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 4)

            if weeklyFocusSessions.isEmpty {
                LiquidCard(cornerRadius: 20) {
                    Text("—")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(weeklyFocusSessions, id: \.id) { record in
                        focusRow(record: record)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func focusRow(record: FocusSessionRecord) -> some View {
        LiquidCard(cornerRadius: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LiquidPalette.aqua.opacity(0.30))
                        .frame(width: 30, height: 30)
                    Image(systemName: "brain.head.profile")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.intention.isEmpty ? "Deep Focus" : record.intention)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(record.completedAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(Self.formatDuration(seconds: record.actualDurationSeconds))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(LiquidPalette.iris)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Formatters

    /// "Semaine du 12 mai" / "Week of May 12". Uses the user's locale
    /// so the FR build shows the FR label without us having to ship a
    /// separate template per language.
    private static func formatWeekHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = nil
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        let day = formatter.string(from: date)
        if Locale.current.language.languageCode?.identifier == "fr" {
            return "Semaine du \(day)"
        }
        return "Week of \(day)"
    }

    /// `2h32` for hours >= 1, `45 min` otherwise, `—` for zero so an
    /// empty week never reads as `0h00`.
    private static func formatFocus(hours: Double) -> String {
        guard hours > 0 else { return "—" }
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h\(String(format: "%02d", m))"
        }
        return "\(m) min"
    }

    /// Compact `45 min` / `1h20` for a single focus session row.
    private static func formatDuration(seconds: Double) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h\(String(format: "%02d", m))"
        }
        return "\(m) min"
    }
}
