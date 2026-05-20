import WidgetKit
import SwiftUI
import GraphCore

// MARK: - Entry

/// v1.0-alpha.16 — Surfaces the portfolio's monthly recurring
/// revenue on iOS 26 Lock Screen's `.accessoryCircular` family. The
/// host App refreshes the underlying value via
/// `SharedSnapshotWriter.refresh(...)` on every `.active` scene
/// phase, sourcing the same `ProjectMRR.total(of:)` HomeView already
/// reads.
struct PortfolioMRRLockScreenEntry: TimelineEntry {
    let date: Date
    let totalMRR: Int

    static let placeholder = PortfolioMRRLockScreenEntry(
        date: .now,
        totalMRR: SharedSnapshot.placeholder.totalMRR
    )

    static let empty = PortfolioMRRLockScreenEntry(date: .now, totalMRR: 0)

    init(date: Date, totalMRR: Int) {
        self.date = date
        self.totalMRR = totalMRR
    }
}

// MARK: - Provider

/// v1.0-alpha.16 — Same 15-min cadence as the lead-inbox widget so
/// both glyphs land on the same wake. iOS itself decides whether to
/// honour the next-update hint; the cadence ceiling is what
/// matters.
struct PortfolioMRRLockScreenProvider: TimelineProvider {
    typealias Entry = PortfolioMRRLockScreenEntry

    func placeholder(in context: Context) -> PortfolioMRRLockScreenEntry {
        .placeholder
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PortfolioMRRLockScreenEntry) -> Void
    ) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(fetchEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<PortfolioMRRLockScreenEntry>) -> Void
    ) {
        let entry = fetchEntry()
        let totalMRR = entry.totalMRR
        Task { @MainActor in
            MINDTelemetry.info(
                "widget.timeline.requested",
                data: [
                    "kind": "portfolio.mrr",
                    "mrr": String(totalMRR),
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

    private func fetchEntry() -> PortfolioMRRLockScreenEntry {
        let snapshot = SharedSnapshotWriter.readSnapshot()
        return PortfolioMRRLockScreenEntry(
            date: .now,
            totalMRR: snapshot.totalMRR
        )
    }
}

// MARK: - Widget

/// v1.0-alpha.16 — Single `.accessoryCircular` family showing the
/// MRR pill in compact form ("830€", "1.2k€"). Tapping deep-links to
/// the portfolio sheet via `mind://portfolio`.
struct PortfolioMRRLockScreenWidget: Widget {
    static let kind = "app.mind.ios.widget.lockscreen.mrr"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: PortfolioMRRLockScreenProvider()
        ) { entry in
            PortfolioMRRLockScreenView(entry: entry)
                .widgetURL(URL(string: "mind://portfolio")!)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName(LocalizedStringResource("widget.portfolioMRR.title"))
        .description(LocalizedStringResource("widget.portfolioMRR.description"))
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - View

/// v1.0-alpha.16 — `.accessoryCircular` glyph budget is tight (a
/// 3-character monospace glyph at 18pt fits comfortably). The
/// formatter compresses anything above 1000€ to a "k€" form so the
/// ring stays readable.
struct PortfolioMRRLockScreenView: View {
    let entry: PortfolioMRRLockScreenEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "eurosign.circle")
                    .font(.system(size: 9, weight: .semibold))
                    .widgetAccentable()
                Text(formattedMRR)
                    .font(.system(
                        size: glyphSize,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
    }

    /// Pure pass-through to the GraphCore-side formatter so unit
    /// tests can pin the boundaries.
    private var formattedMRR: String {
        WidgetMRRFormatter.compact(entry.totalMRR)
    }

    /// Drop from 16pt to 13pt when the formatted string is 4+ chars
    /// so the wider tokens ("1.2k€", "12k€", "120k€") fit inside
    /// the system's circular glyph budget.
    private var glyphSize: CGFloat {
        formattedMRR.count >= 5 ? 13 : 16
    }
}
