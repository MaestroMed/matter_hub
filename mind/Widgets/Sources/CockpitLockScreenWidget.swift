import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
import GraphCore

// MARK: - Entry

/// v1.0-alpha.16 — Cockpit Lock Screen widget entry. Wraps the pure
/// `CockpitWidgetSnapshot` value type (defined in GraphCore so the
/// test target can exercise the formatters without linking WidgetKit)
/// with the `date: Date` field WidgetKit's `TimelineEntry` requires.
struct CockpitLockScreenEntry: TimelineEntry {
    let snapshot: CockpitWidgetSnapshot

    var date: Date { snapshot.date }
    var newLeadCount: Int { snapshot.newLeadCount }

    static let placeholder = CockpitLockScreenEntry(snapshot: .placeholder)
    static let empty = CockpitLockScreenEntry(snapshot: .empty)
}

// MARK: - Configuration intent

struct CockpitLockScreenConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "MIND Cockpit on Lock Screen"
    static let description = IntentDescription(
        "New leads + active projects + portfolio MRR from your Numelite cockpit, glanceable on the Lock Screen."
    )

    init() {}
}

// MARK: - Provider

/// v1.0-alpha.16 — Provider for the Cockpit Lock Screen widget.
/// Reads the cockpit data spine (`Project` + `Lead`) via the shared
/// `GraphCore.sharedContainer`, then folds the result into a pure
/// `CockpitWidgetSnapshot` the SwiftUI body renders. Mirrors the
/// timeline cadence the v0.27.1 `LockScreenProvider` uses (1-hour
/// refresh, same as `QuickStatsProvider`) so all three widget surfaces
/// stay coherent on the same Lock Screen.
struct CockpitLockScreenProvider: AppIntentTimelineProvider {
    typealias Intent = CockpitLockScreenConfigurationIntent
    typealias Entry = CockpitLockScreenEntry

    func placeholder(in context: Context) -> CockpitLockScreenEntry {
        .placeholder
    }

    func snapshot(
        for configuration: CockpitLockScreenConfigurationIntent,
        in context: Context
    ) async -> CockpitLockScreenEntry {
        context.isPreview ? .placeholder : await fetchEntry()
    }

    /// Refreshes once an hour aligned to the QuickStatsProvider +
    /// LockScreenProvider cadence so all three widgets reflect the same
    /// graph snapshot. The system can still call us back earlier on a
    /// Timeline reload from the app (HomeView's pull-to-refresh fires
    /// `WidgetCenter.shared.reloadTimelines(...)`).
    func timeline(
        for configuration: CockpitLockScreenConfigurationIntent,
        in context: Context
    ) async -> Timeline<CockpitLockScreenEntry> {
        let entry = await fetchEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(next))
    }

    @MainActor
    private func fetchEntry() -> CockpitLockScreenEntry {
        let context = ModelContext(GraphCore.sharedContainer)

        // New leads (status == "new"), newest first.
        let leadDescriptor = FetchDescriptor<Lead>(
            predicate: #Predicate<Lead> { $0.status == "new" },
            sortBy: [SortDescriptor(\Lead.receivedAt, order: .reverse)]
        )
        let leads = (try? context.fetch(leadDescriptor)) ?? []

        // All projects — filter in-memory to the active / maintenance
        // slice (matches HomeView's `activeProjects` projection).
        let projectDescriptor = FetchDescriptor<Project>()
        let projects = (try? context.fetch(projectDescriptor)) ?? []
        let active = projects.filter {
            $0.lifecycleStageEnum == .active ||
            $0.lifecycleStageEnum == .maintenance
        }
        let totalMRR = active.reduce(0) { $0 + $1.monthlyRecurringRevenueEUR }

        let head = leads.first
        let headName: String? = {
            guard let name = head?.contactName, !name.isEmpty else { return nil }
            return name
        }()
        let headProject: String? = {
            guard let project = head?.project, !project.name.isEmpty else { return nil }
            return project.name
        }()

        if leads.isEmpty && active.isEmpty {
            return .empty
        }

        return CockpitLockScreenEntry(snapshot: CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: leads.count,
            activeProjectsCount: active.count,
            totalMRR_EUR: totalMRR,
            lastLeadContactName: headName,
            lastLeadProjectName: headProject
        ))
    }
}

// MARK: - Widget

/// v1.0-alpha.16 — Cockpit Lock Screen widget. Two accessory families
/// per the v1.0-alpha.15+ spec (rectangular + inline):
///
///   - `.accessoryRectangular` : two-line glance with the new-lead
///     count headline and the most recent contact's name + project on
///     the body. Empty-inbox fallback surfaces the portfolio MRR
///     summary so the widget still carries actionable info on the
///     idle day.
///   - `.accessoryInline`      : single-line text rendered next to the
///     date on the StandBy + Lock Screen surfaces. Always brand-
///     prefixed with the lead count.
///
/// Tapping deep-links to `mind://leads`, which `RootView.onOpenURL`
/// routes to the Home tab where the lead inbox card sits at the top
/// of the scroll.
struct CockpitLockScreenWidget: Widget {
    /// Kind string is the widget's stable identifier. Apps that re-
    /// render timelines via `WidgetCenter.shared.reloadTimelines(...)`
    /// reference this exact string, so it intentionally lives here as
    /// a typed constant instead of a magic string scattered across the
    /// codebase.
    static let kind = "app.mind.ios.widget.cockpit.lockscreen"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: CockpitLockScreenConfigurationIntent.self,
            provider: CockpitLockScreenProvider()
        ) { entry in
            CockpitLockScreenWidgetView(entry: entry)
                .widgetURL(CockpitWidgetFormatter.deepLinkURL)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("MIND Cockpit")
        .description("New leads + portfolio MRR on the Lock Screen.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

// MARK: - View

struct CockpitLockScreenWidgetView: View {
    let entry: CockpitLockScreenEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        default:
            // Defensive fallback if iOS ever invokes us with an
            // unknown family. Matches the inline rendering so the
            // widget stays legible inside the StandBy stack.
            inline
        }
    }

    /// Rectangular complication. Two lines, top-leading anchored so
    /// the system clock above stays vertically stable on iPhone.
    /// Empty inbox falls back to the MRR summary on the body so the
    /// widget still surfaces something actionable on the idle day.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text(CockpitWidgetFormatter.rectangularHeader(for: entry.snapshot))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            Text(CockpitWidgetFormatter.rectangularBody(for: entry.snapshot))
                .font(.system(.footnote, design: .rounded))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inline complication — a single line shown next to the date on
    /// the Lock Screen. Always carries the brand-prefixed lead count so
    /// the reader knows which app the row belongs to.
    private var inline: some View {
        Text(CockpitWidgetFormatter.inlineBody(for: entry.snapshot))
    }
}
