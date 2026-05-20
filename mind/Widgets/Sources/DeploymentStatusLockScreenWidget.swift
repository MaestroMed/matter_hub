import WidgetKit
import SwiftUI
import GraphCore

// MARK: - Entry

/// v1.0-alpha.16 — `.accessoryInline` family surfaces the
/// portfolio's most pressing deployment status on the Lock Screen's
/// inline complication slot (next to the date / above the clock,
/// depending on the user's Lock Screen layout). Reads the
/// `criticalProjectName` column the host App refreshes — nil
/// collapses to the "all green" branch via the formatter.
struct DeploymentStatusLockScreenEntry: TimelineEntry {
    let date: Date
    let criticalProjectName: String?
    /// Fallback name surfaced when every project is healthy. The
    /// host can override this via the host-side refresh path; the
    /// default keeps "AZ Construction" so an unconfigured install
    /// still renders something familiar.
    let defaultProjectName: String

    static let placeholder = DeploymentStatusLockScreenEntry(
        date: .now,
        criticalProjectName: nil,
        defaultProjectName: "AZ Construction"
    )

    static let empty = DeploymentStatusLockScreenEntry(
        date: .now,
        criticalProjectName: nil,
        defaultProjectName: "AZ Construction"
    )

    init(
        date: Date,
        criticalProjectName: String?,
        defaultProjectName: String
    ) {
        self.date = date
        self.criticalProjectName = criticalProjectName
        self.defaultProjectName = defaultProjectName
    }
}

// MARK: - Provider

struct DeploymentStatusLockScreenProvider: TimelineProvider {
    typealias Entry = DeploymentStatusLockScreenEntry

    func placeholder(in context: Context) -> DeploymentStatusLockScreenEntry {
        .placeholder
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (DeploymentStatusLockScreenEntry) -> Void
    ) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(fetchEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<DeploymentStatusLockScreenEntry>) -> Void
    ) {
        let entry = fetchEntry()
        let critical = entry.criticalProjectName ?? "<none>"
        Task { @MainActor in
            MINDTelemetry.info(
                "widget.timeline.requested",
                data: [
                    "kind": "deployment.status",
                    "critical": critical,
                ]
            )
        }
        let next = Calendar.current.date(
            byAdding: .minute,
            value: 15,
            to: .now
        ) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func fetchEntry() -> DeploymentStatusLockScreenEntry {
        let snapshot = SharedSnapshotWriter.readSnapshot()
        return DeploymentStatusLockScreenEntry(
            date: .now,
            criticalProjectName: snapshot.criticalProjectName,
            defaultProjectName: "AZ Construction"
        )
    }
}

// MARK: - Widget

/// v1.0-alpha.16 — Inline status row. Tapping deep-links to the
/// portfolio sheet via `mind://portfolio` so the user can dive
/// straight into the failing project's detail row when something
/// goes red.
struct DeploymentStatusLockScreenWidget: Widget {
    static let kind = "app.mind.ios.widget.lockscreen.deployment"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: DeploymentStatusLockScreenProvider()
        ) { entry in
            DeploymentStatusLockScreenView(entry: entry)
                .widgetURL(URL(string: "mind://portfolio")!)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName(LocalizedStringResource("widget.deployment.title"))
        .description(LocalizedStringResource("widget.deployment.description"))
        .supportedFamilies([.accessoryInline])
    }
}

// MARK: - View

struct DeploymentStatusLockScreenView: View {
    let entry: DeploymentStatusLockScreenEntry

    var body: some View {
        // `.accessoryInline` is a single line, system-rendered next
        // to the date. The formatter returns "<Name> ✓" or
        // "<Name> ⚠️" depending on the critical-project flag.
        Text(
            WidgetDeploymentFormatter.inlineLine(
                criticalProjectName: entry.criticalProjectName,
                defaultProjectName: entry.defaultProjectName
            )
        )
    }
}
