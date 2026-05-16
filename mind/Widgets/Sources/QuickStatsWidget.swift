import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
import GraphCore

// MARK: - Configuration intent

struct QuickStatsConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Quick Stats"
    static let description = IntentDescription(
        "Live count of thoughts in your second brain, plus your latest one."
    )

    init() {}
}

// MARK: - Entry + provider

struct QuickStatsEntry: TimelineEntry {
    let date: Date
    let noteCount: Int
    let captureCount: Int
    let lastTitle: String?
    let lastPreview: String?

    var totalCount: Int { noteCount + captureCount }

    static let placeholder = QuickStatsEntry(
        date: .now,
        noteCount: 12,
        captureCount: 7,
        lastTitle: "Something worth remembering",
        lastPreview: "A spark from this morning, captured before it slipped."
    )
}

struct QuickStatsProvider: AppIntentTimelineProvider {
    typealias Intent = QuickStatsConfigurationIntent
    typealias Entry = QuickStatsEntry

    func placeholder(in context: Context) -> QuickStatsEntry {
        .placeholder
    }

    func snapshot(
        for configuration: QuickStatsConfigurationIntent,
        in context: Context
    ) async -> QuickStatsEntry {
        context.isPreview ? .placeholder : await fetchEntry()
    }

    func timeline(
        for configuration: QuickStatsConfigurationIntent,
        in context: Context
    ) async -> Timeline<QuickStatsEntry> {
        let entry = await fetchEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(next))
    }

    @MainActor
    private func fetchEntry() -> QuickStatsEntry {
        let context = ModelContext(GraphCore.sharedContainer)
        let descriptor = FetchDescriptor<Node>(
            sortBy: [SortDescriptor(\Node.updatedAt, order: .reverse)]
        )
        let nodes = (try? context.fetch(descriptor)) ?? []
        let notes = nodes.filter { $0.kindRaw == "note" }.count
        let captures = nodes.filter { $0.kindRaw == "capture" }.count
        let head = nodes.first
        return QuickStatsEntry(
            date: .now,
            noteCount: notes,
            captureCount: captures,
            lastTitle: head?.title,
            lastPreview: head?.content.isEmpty == false ? head?.content : nil
        )
    }
}

// MARK: - Widget

struct QuickStatsWidget: Widget {
    let kind = "app.mind.ios.widget.quickstats"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: QuickStatsConfigurationIntent.self,
            provider: QuickStatsProvider()
        ) { entry in
            QuickStatsView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPalette.background
                }
        }
        .configurationDisplayName("Quick Stats")
        .description("How full your second brain is right now.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - View

struct QuickStatsView: View {
    let entry: QuickStatsEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  small
            case .systemMedium: medium
            case .systemLarge:  large
            default:            small
            }
        }
        .foregroundStyle(renderingMode == .fullColor ? .primary : .primary)
    }

    private var brandHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 13, weight: .semibold))
                .widgetAccentable()
            Text("MIND")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .tracking(1.0)
        }
        .foregroundStyle(.secondary)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            brandHeader
            Spacer()
            Text("\(entry.totalCount)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .widgetAccentable()
                .contentTransition(.numericText())
            Text(entry.totalCount == 1 ? "thought" : "thoughts")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                brandHeader
                Spacer(minLength: 2)
                Text("\(entry.totalCount)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .widgetAccentable()
                    .contentTransition(.numericText())
                HStack(spacing: 14) {
                    statPill(label: "Notes", value: entry.noteCount)
                    statPill(label: "Captures", value: entry.captureCount)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let title = entry.lastTitle {
                Divider()
                    .background(.white.opacity(0.35))
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAST")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.0)
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(3)
                    if let preview = entry.lastPreview {
                        Text(preview)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                brandHeader
                Spacer()
                Text(entry.date.formatted(.dateTime.hour().minute()))
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 0) {
                statColumn(value: entry.noteCount, label: "Notes")
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 1, height: 36)
                statColumn(value: entry.captureCount, label: "Captures")
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 1, height: 36)
                statColumn(value: entry.totalCount, label: "Total")
            }

            if let title = entry.lastTitle {
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAST THOUGHT")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.0)
                    Text(title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .lineLimit(2)
                    if let preview = entry.lastPreview {
                        Text(preview)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statPill(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func statColumn(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .widgetAccentable()
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(1.0)
        }
        .frame(maxWidth: .infinity)
    }
}
