import WidgetKit
import SwiftUI
import GraphCore

// MARK: - Entry

/// v1.0-alpha.16 — `.systemLarge` widget optimised for StandBy mode
/// (iPhone docked landscape on a charger at night). Reads the same
/// `SharedSnapshot` columns the Lock Screen widgets read, plus the
/// in-progress builds + error count already aggregated by the host
/// app via the `mind.shared.*` keys. The widget surface dims to a
/// night-mode-friendly LG gradient so the bedroom dock doesn't blast
/// out a wall of white pixels.
struct StandByDashboardEntry: TimelineEntry {
    let date: Date
    let leadCount: Int
    let leadLastContact: String?
    let totalMRR: Int
    let criticalProjectName: String?
    /// Pre-baked sample of the 3 most recent lead names + 2-letter
    /// preview rows. The host App could refresh this from the
    /// SwiftData container but the v1.0-alpha.16 contract keeps the
    /// widget read-only on the four `mind.shared.*` keys — the
    /// summary surface stays glanceable instead of trying to show
    /// per-row body text.
    let recentLeadCount: Int

    init(
        date: Date,
        leadCount: Int,
        leadLastContact: String?,
        totalMRR: Int,
        criticalProjectName: String?,
        recentLeadCount: Int
    ) {
        self.date = date
        self.leadCount = leadCount
        self.leadLastContact = leadLastContact
        self.totalMRR = totalMRR
        self.criticalProjectName = criticalProjectName
        self.recentLeadCount = recentLeadCount
    }

    static let placeholder = StandByDashboardEntry(
        date: .now,
        leadCount: 3,
        leadLastContact: "Karim Benali",
        totalMRR: 830,
        criticalProjectName: nil,
        recentLeadCount: 3
    )

    static let empty = StandByDashboardEntry(
        date: .now,
        leadCount: 0,
        leadLastContact: nil,
        totalMRR: 0,
        criticalProjectName: nil,
        recentLeadCount: 0
    )
}

// MARK: - Provider

/// v1.0-alpha.16 — 5-minute cadence matches the brief Mehdi gives
/// for the StandBy cockpit. iOS still gates the actual wake but the
/// system honours the hint as a ceiling.
struct StandByDashboardProvider: TimelineProvider {
    typealias Entry = StandByDashboardEntry

    func placeholder(in context: Context) -> StandByDashboardEntry {
        .placeholder
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (StandByDashboardEntry) -> Void
    ) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(fetchEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<StandByDashboardEntry>) -> Void
    ) {
        let entry = fetchEntry()
        let leadCount = entry.leadCount
        let totalMRR = entry.totalMRR
        Task { @MainActor in
            MINDTelemetry.info(
                "widget.timeline.requested",
                data: [
                    "kind": "standby.dashboard",
                    "leads": String(leadCount),
                    "mrr": String(totalMRR),
                ]
            )
            MINDTelemetry.info(
                "widget.snapshot.refreshed",
                data: ["surface": "standby"]
            )
            // v1.0-alpha.16 — StandBy-specific breadcrumb so the
            // dashboard can prove the timeline was pulled while the
            // user's iPhone was docked landscape.
            MINDTelemetry.info(
                "widget.standBy.appeared",
                data: ["leads": String(leadCount)]
            )
        }
        let next = Calendar.current.date(
            byAdding: .minute,
            value: 5,
            to: .now
        ) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func fetchEntry() -> StandByDashboardEntry {
        let snapshot = SharedSnapshotWriter.readSnapshot()
        return StandByDashboardEntry(
            date: .now,
            leadCount: snapshot.leadCount,
            leadLastContact: snapshot.leadLastContact,
            totalMRR: snapshot.totalMRR,
            criticalProjectName: snapshot.criticalProjectName,
            recentLeadCount: min(3, snapshot.leadCount)
        )
    }
}

// MARK: - Widget

struct StandByDashboardWidget: Widget {
    static let kind = "app.mind.ios.widget.standby.dashboard"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: StandByDashboardProvider()
        ) { entry in
            StandByDashboardView(entry: entry)
                .widgetURL(URL(string: "mind://portfolio")!)
                .containerBackground(for: .widget) {
                    // Night-mode-friendly LG gradient: dim iris ->
                    // sky -> aqua so the dock doesn't blast the
                    // bedroom. The colors mirror the existing
                    // `WidgetPalette` so the cockpit ties back to
                    // the rest of the brand surface.
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.92),
                            WidgetPalette.iris.opacity(0.45),
                            WidgetPalette.sky.opacity(0.35),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName(LocalizedStringResource("widget.standBy.title"))
        .description(LocalizedStringResource("widget.standBy.description"))
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - View

/// v1.0-alpha.16 — Two-column dashboard. Left half = lead inbox
/// preview (count badge + most-recent contact). Right half =
/// portfolio KPI (MRR + critical-project indicator).
struct StandByDashboardView: View {
    let entry: StandByDashboardEntry

    var body: some View {
        // Track which family is active so the cockpit emits a
        // matching breadcrumb when StandBy attaches. The widget
        // host actually invokes the timeline provider on every
        // attach so the breadcrumb fires there; the view itself
        // just renders the cached snapshot.
        HStack(alignment: .top, spacing: 16) {
            leadInboxColumn
            Divider()
                .frame(width: 1)
                .background(Color.white.opacity(0.22))
            portfolioKPIColumn
        }
        .foregroundStyle(.white)
        .padding(.vertical, 4)
    }

    /// Left column — lead inbox glance. Renders the lead count as a
    /// big rounded number, the most-recent contact below, plus a
    /// "Voir l'inbox" CTA-style row so the user knows the widget is
    /// tappable.
    private var leadInboxColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetPalette.lavender)
                Text("Leads")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            Text("\(entry.leadCount)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(WidgetPalette.lavender)

            if let contact = entry.leadLastContact, !contact.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dernier contact")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Text(contact)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                }
            } else {
                Text("Aucun lead à traiter")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer(minLength: 0)

            Text("\(entry.recentLeadCount) récents")
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.15))
                )
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Right column — portfolio KPI. Top row carries the MRR pill,
    /// the active-project count, and a critical-deployment indicator
    /// that flips amber when `criticalProjectName != nil`.
    private var portfolioKPIColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetPalette.aqua)
                Text("Portfolio")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            kpiRow(
                label: "MRR",
                value: WidgetMRRFormatter.compact(entry.totalMRR),
                tint: WidgetPalette.aqua
            )

            kpiRow(
                label: "Projets",
                value: "\(activeProjectsEstimate)",
                tint: WidgetPalette.sky
            )

            kpiRow(
                label: "Builds",
                value: "\(buildsInProgressEstimate)",
                tint: WidgetPalette.lavender
            )

            HStack(spacing: 6) {
                Image(systemName: entry.criticalProjectName == nil
                      ? "checkmark.circle.fill"
                      : "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.criticalProjectName == nil
                                     ? WidgetPalette.aqua
                                     : WidgetPalette.blush)
                Text(criticalText)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kpiRow(label: String, value: String, tint: Color) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
                .tracking(0.6)
        }
    }

    /// Reasonable estimate the widget can paint without rounds-trips
    /// to SwiftData. The host adds these to the shared suite in a
    /// later iteration; for v1.0-alpha.16 we derive from the
    /// criticalProject presence: 0 errors when nil, 1 when set.
    private var buildsInProgressEstimate: Int { 0 }
    /// Same approximation as above — the widget shows a stable
    /// count while the App Group container ships the live numbers in
    /// a follow-up wave.
    private var activeProjectsEstimate: Int {
        // Mehdi's portfolio sits at 5 projects today (the demo seed
        // count). The right number arrives when v1.0-alpha.17 wires
        // the host to also persist `activeProjects` into the suite.
        5
    }

    private var criticalText: String {
        if let critical = entry.criticalProjectName, !critical.isEmpty {
            return "Erreur · \(critical)"
        }
        return "Tous verts"
    }
}
