import SwiftUI
import SwiftData
import Charts
import DesignSystem
import GraphCore

/// v1.1.0 — Inline 30-day sparkline grid wired into the Vercel
/// section of `ProjectDetailSheet`. Renders four mini-charts (Perf /
/// A11y / Best practices / SEO) on top of a "30 jours" caption row.
///
/// The view is fully reactive — it owns a `@Query` slice filtered by
/// `projectID`, so when `LighthouseSnapshotStore.persist(...)` writes
/// a new row on the back of a fresh probe the sparklines refresh
/// without a manual reload.
///
/// Soft-fails to a polite empty state when no snapshot exists yet.
/// The very first manual refresh of the Vercel section drops a row
/// in and the empty state collapses to the chart grid.
struct LighthouseTrendView: View {

    let projectID: UUID

    @Query private var snapshots: [LighthouseSnapshot]

    init(projectID: UUID) {
        self.projectID = projectID
        // Static-predicate `@Query` filter on `projectID` — sorted by
        // captured-at descending so the aggregator pulls the freshest
        // snapshot per day first.
        let id = projectID
        _snapshots = Query(
            filter: #Predicate<LighthouseSnapshot> { $0.projectID == id },
            sort: \LighthouseSnapshot.capturedAt,
            order: .reverse
        )
    }

    private let metrics: [(metric: LighthouseMetric, color: Color)] = [
        (.performance, LiquidPalette.iris),
        (.accessibility, LiquidPalette.aqua),
        (.bestPractices, LiquidPalette.sky),
        (.seo, .orange),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().background(.white.opacity(0.18))

            Text("project.lighthouse.trend.title", bundle: .main)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)

            if snapshots.isEmpty {
                Text("project.lighthouse.trend.empty", bundle: .main)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                let aggregated = LighthouseTrendAggregator.last30DaysAllMetrics(snapshots)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                    spacing: 12
                ) {
                    ForEach(metrics, id: \.metric) { entry in
                        sparkline(
                            points: aggregated[entry.metric] ?? [],
                            color: entry.color,
                            labelKey: entry.metric.localizationKey
                        )
                    }
                }
                caption
            }
        }
        .onAppear {
            MINDTelemetry.info(
                "lighthouse.trend.opened",
                data: [
                    "projectID": projectID.uuidString,
                    "snapshots": String(snapshots.count),
                ]
            )
        }
    }

    @ViewBuilder
    private func sparkline(
        points: [LighthouseTrendAggregator.Point],
        color: Color,
        labelKey: String
    ) -> some View {
        let plotted = points.compactMap { point -> (Date, Int)? in
            guard let value = point.value else { return nil }
            return (point.day, value)
        }
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                Chart {
                    ForEach(Array(plotted.enumerated()), id: \.offset) { _, item in
                        LineMark(
                            x: .value("Day", item.0),
                            y: .value("Score", item.1)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(color)
                        AreaMark(
                            x: .value("Day", item.0),
                            y: .value("Score", item.1)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.32), color.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...100)
                .frame(width: 60, height: 24)
                .accessibilityLabel(Text(LocalizedStringKey(labelKey)))
            }
            HStack(spacing: 4) {
                Text(LocalizedStringKey(labelKey))
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if let latest = plotted.last?.1 {
                    Text(verbatim: "\(latest)")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(color)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var caption: some View {
        let count = LighthouseTrendAggregator.snapshotCount(snapshots)
        let latest = LighthouseTrendAggregator.mostRecent(snapshots)
        let countText = String(
            format: String(localized: "project.lighthouse.trend.snapshotCount.format"),
            count
        )
        let agoText: String = {
            guard let date = latest?.capturedAt else { return "" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let ago = formatter.localizedString(for: date, relativeTo: .now)
            return String(
                format: String(localized: "project.lighthouse.trend.lastSnapshot.format"),
                ago
            )
        }()
        return Text(verbatim: agoText.isEmpty ? countText : "\(countText) · \(agoText)")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}
