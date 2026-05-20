import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
import GraphCore

// MARK: - Entry

/// v0.27.1 — Lock Screen widget entry. Wraps the pure
/// `LockScreenEntrySnapshot` value type (defined in GraphCore so the
/// test target can exercise the formatters without linking WidgetKit)
/// with the `date: Date` field WidgetKit's `TimelineEntry` requires.
struct LockScreenEntry: TimelineEntry {
    let snapshot: LockScreenEntrySnapshot

    var date: Date { snapshot.date }
    var totalCount: Int { snapshot.totalCount }
    var lastTitle: String? { snapshot.lastTitle }

    static let placeholder = LockScreenEntry(snapshot: .placeholder)
    static let empty = LockScreenEntry(snapshot: .empty)
}

// MARK: - Configuration intent

struct LockScreenConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "MIND on Lock Screen"
    static let description = IntentDescription(
        "Glanceable counter, latest thought, and one-tap capture from your Lock Screen."
    )

    init() {}
}

// MARK: - Provider

struct LockScreenProvider: AppIntentTimelineProvider {
    typealias Intent = LockScreenConfigurationIntent
    typealias Entry = LockScreenEntry

    func placeholder(in context: Context) -> LockScreenEntry {
        .placeholder
    }

    func snapshot(
        for configuration: LockScreenConfigurationIntent,
        in context: Context
    ) async -> LockScreenEntry {
        context.isPreview ? .placeholder : await fetchEntry()
    }

    /// Refreshes once an hour aligned to the QuickStatsProvider cadence,
    /// so both widgets reflect the same Node graph snapshot. The system
    /// can still call us back earlier on a Timeline reload from the app.
    func timeline(
        for configuration: LockScreenConfigurationIntent,
        in context: Context
    ) async -> Timeline<LockScreenEntry> {
        let entry = await fetchEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(next))
    }

    @MainActor
    private func fetchEntry() -> LockScreenEntry {
        let context = ModelContext(GraphCore.sharedContainer)
        let descriptor = FetchDescriptor<Node>(
            sortBy: [SortDescriptor(\Node.updatedAt, order: .reverse)]
        )
        guard let nodes = try? context.fetch(descriptor), !nodes.isEmpty else {
            return .empty
        }
        let total = nodes.filter { $0.kindRaw == "note" || $0.kindRaw == "capture" }.count
        let head = nodes.first
        let lastTitle = (head?.title.isEmpty == false) ? head?.title : nil
        return LockScreenEntry(snapshot: LockScreenEntrySnapshot(
            date: .now,
            totalCount: total,
            lastTitle: lastTitle
        ))
    }
}

// MARK: - Widget

/// v0.27.1 — Three Lock Screen / Always-On accessory families:
///
///   - `.accessoryCircular`    : ring dial with the total Node count
///     centred. Reads as the at-a-glance "how full is my brain right
///     now" complication. Single tap deep-links to `mind://lock`.
///   - `.accessoryRectangular` : two-line glance with the latest
///     thought title and the same total count. The Lock Screen below
///     the clock fits two accessoryRectangular slots; this widget
///     pairs cleanly with a Focus complication when one is live.
///   - `.accessoryInline`      : single-line text rendered next to
///     the date on the StandBy + Lock Screen surfaces.
///
/// All three families render through a single SwiftUI view dispatched
/// on `widgetFamily` (same model `QuickStatsWidget` uses for system*
/// families). The `widgetURL(...)` call routes to the same handler
/// the app-side `mind://` scheme parses — RootView's `.onOpenURL`
/// posts the URL onto the deep-link bus.
struct LockScreenWidget: Widget {
    /// Kind string is the widget's stable identifier. Apps that
    /// re-render timelines via `WidgetCenter.shared.reloadTimelines(...)`
    /// reference this exact string, so it intentionally lives here as
    /// a typed constant instead of a magic string scattered across
    /// the codebase.
    static let kind = "app.mind.ios.widget.lockscreen"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: LockScreenConfigurationIntent.self,
            provider: LockScreenProvider()
        ) { entry in
            LockScreenWidgetView(entry: entry)
                .widgetURL(LockScreenWidgetFormatter.deepLinkURL)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("MIND")
        .description("Glance at your brain — count + last thought on the Lock Screen.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

// MARK: - View

struct LockScreenWidgetView: View {
    let entry: LockScreenEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
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

    /// Circular complication. Single-digit and two-digit counts get a
    /// 18pt rounded mono glyph; three-digit counts (rare) drop to
    /// 14pt so the number fits inside the system's
    /// `.accessoryCircular` glyph budget.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 9, weight: .semibold))
                    .widgetAccentable()
                Text(LockScreenWidgetFormatter.formatCount(entry.totalCount))
                    .font(.system(
                        size: entry.totalCount >= 100 ? 14 : 18,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    /// Rectangular complication. Two lines, top-leading anchored so
    /// the system clock above stays vertically stable on iPhone.
    /// Falls back to a friendly "Tap to capture" CTA on an empty
    /// graph.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text(LockScreenWidgetFormatter.rectangularHeader(for: entry.snapshot))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            if let title = entry.lastTitle, !title.isEmpty {
                Text(title)
                    .font(.system(.footnote, design: .rounded))
                    .lineLimit(2)
            } else {
                Text("Tap to capture")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inline complication — a single line shown next to the date on
    /// the Lock Screen. Always carries the brand-prefixed count so
    /// the reader knows which app the row belongs to.
    private var inline: some View {
        Text(LockScreenWidgetFormatter.inlineBody(for: entry.snapshot))
    }
}
