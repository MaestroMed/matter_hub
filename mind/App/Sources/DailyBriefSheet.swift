import SwiftUI
import CalendarKit
import DesignSystem
import GraphCore

/// v0.17 — Expanded daily morning brief, opened by tapping the
/// "Brief du matin" card on HomeView. Mirrors the v0.16
/// `WeeklyDigestSheet` structure: header card → summary counters →
/// captures section → focus suggestion footer.
///
/// Each list row routes back to NodeDetailView via the
/// `onSelectNode` callback so the user can dive in from the brief.
/// Kept dependency-free of the rest of HomeView so it can be reused
/// by a future Watch complication / Lock-Screen widget deep link.
struct DailyBriefSheet: View {
    let brief: DailyBrief
    let nodes: [Node]
    let events: [CalendarEvent]
    let onSelectNode: (Node) -> Void
    /// Tapping "Démarrer maintenant" hands the focusSuggestionMinutes
    /// back to the caller so HomeView can start a Deep Focus session
    /// through `FocusController.shared.start(...)`. Optional so existing
    /// call sites (e.g. preview / Lock Screen widget) don't break when
    /// they only render the read-only brief.
    var onStartFocus: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss

    /// Maps a title back to the most recently updated matching Node so
    /// a tap routes to NodeDetailView. nil when no match — the row is
    /// then rendered non-interactively (same fallback contract as
    /// WeeklyDigestSheet).
    private func node(for title: String) -> Node? {
        nodes.first { $0.title == title }
    }

    /// Open task-shaped Nodes, ordered by updatedAt desc. The brief
    /// only counts them; the sheet lists them so the user can tap to
    /// open / mark done in place.
    private var openTaskNodes: [Node] {
        nodes
            .filter { $0.kindRaw == NodeKind.task.rawValue && $0.completedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerCard
                    summaryCard
                    if !events.isEmpty {
                        eventsSection
                    }
                    if !openTaskNodes.isEmpty {
                        tasksSection
                    }
                    if !brief.recentCaptureTitles.isEmpty {
                        capturesSection
                    }
                    focusSuggestionCard
                }
                .padding(20)
                .padding(.bottom, 60)
            }
            .background {
                LiquidBackground()
                    .ignoresSafeArea()
            }
            .navigationTitle(Text("brief.detail.title"))
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
        .onAppear {
            MINDTelemetry.info(
                "brief.opened",
                data: [
                    "meetings": "\(brief.calendarEventCount)",
                    "tasks": "\(brief.openTaskCount)",
                    "captures": "\(brief.recentCaptureTitles.count)",
                ]
            )
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        LiquidCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Self.formatDayHeader(brief.date))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                Text(brief.headline)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "brief.detail.summary.header").uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 4)

            LiquidCard(cornerRadius: 22) {
                HStack(spacing: 0) {
                    summaryColumn(
                        value: "\(brief.calendarEventCount)",
                        labelKey: "brief.detail.summary.meetings",
                        tint: LiquidPalette.iris
                    )
                    summaryDivider
                    summaryColumn(
                        value: "\(brief.openTaskCount)",
                        labelKey: "brief.detail.summary.tasks",
                        tint: .purple
                    )
                    summaryDivider
                    summaryColumn(
                        value: "\(brief.focusSuggestionMinutes)m",
                        labelKey: "brief.detail.summary.focus",
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

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "brief.detail.events.header").uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 10) {
                ForEach(events) { event in
                    LiquidCard(cornerRadius: 18) {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(LiquidPalette.iris.opacity(0.18))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "calendar")
                                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                                    .foregroundStyle(LiquidPalette.iris)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                HStack(spacing: 6) {
                                    Text(event.formattedTime)
                                        .font(.system(.caption2, design: .rounded, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    if let loc = event.location, !loc.isEmpty {
                                        Text("·")
                                            .font(.system(.caption2, design: .rounded))
                                            .foregroundStyle(.tertiary)
                                        Text(loc)
                                            .font(.system(.caption2, design: .rounded))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "brief.detail.tasks.header").uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 10) {
                ForEach(openTaskNodes) { node in
                    detailRow(node: node, icon: "checklist", tint: .green)
                }
            }
        }
    }

    private var capturesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "brief.detail.captures.header").uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 10) {
                ForEach(brief.recentCaptureTitles, id: \.self) { title in
                    if let node = node(for: title) {
                        detailRow(node: node, icon: "drop.fill", tint: LiquidPalette.iris)
                    } else {
                        LiquidCard(cornerRadius: 18) {
                            Text(title)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(node: Node, icon: String, tint: Color) -> some View {
        Button {
            LiquidHaptics.tap()
            onSelectNode(node)
        } label: {
            LiquidCard(cornerRadius: 18) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(tint)
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

    private var focusSuggestionCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.aqua.opacity(0.30))
                            .frame(width: 36, height: 36)
                        Image(systemName: "lightbulb.fill")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "brief.detail.suggestion.header").uppercased())
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                        Text(String(
                            format: String(localized: "brief.detail.suggestion.body"),
                            brief.focusSuggestionMinutes
                        ))
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(4)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let onStartFocus {
                    LiquidButton(
                        title: String(localized: "brief.sheet.start.focus"),
                        systemImage: "play.fill",
                        haptic: .select
                    ) {
                        MINDTelemetry.info(
                            "brief.focus.started.from.brief",
                            data: ["minutes": "\(brief.focusSuggestionMinutes)"]
                        )
                        onStartFocus(brief.focusSuggestionMinutes)
                        dismiss()
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Formatters

    /// "Mardi 19 mai" / "Tuesday May 19" — the user's locale picks the
    /// weekday + month name. Used by the header card under the headline.
    private static func formatDayHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = nil
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date)
    }
}
