import SwiftUI

/// v1.0-alpha.17 — Portfolio glance tab on the Apple Watch. Three KPI
/// rows the consultant checks at a glance — leads today, MRR, build
/// errors. Reads the `mind.watch.portfolio` snapshot the iPhone host
/// last pushed via `WatchConnectivityBridge` (offline-first via the
/// shared App Group).
struct WatchPortfolioGlance: View {

    @State private var kpi: WatchPortfolioKPI = WatchSharedSnapshot.readPortfolio()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header
                if isEmpty {
                    emptyState
                } else {
                    row(
                        symbol: "tray.full.fill",
                        title: "watch.portfolio.leads".watchLocalized,
                        value: WatchKPIFormatter.leadCount(kpi.leadsToday)
                    )
                    row(
                        symbol: "eurosign.circle.fill",
                        title: "watch.portfolio.mrr".watchLocalized,
                        value: WatchKPIFormatter.compactEUR(kpi.mrrEUR)
                    )
                    row(
                        symbol: "exclamationmark.triangle.fill",
                        title: "watch.portfolio.errors".watchLocalized,
                        value: errorBadge(kpi.buildErrors)
                    )
                }
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Portfolio")
        .onAppear {
            kpi = WatchSharedSnapshot.readPortfolio()
        }
    }

    private var isEmpty: Bool {
        kpi == .empty
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.headline)
            Text("watch.tab.portfolio.title".watchLocalized)
                .font(.headline)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func row(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
        )
    }

    private func errorBadge(_ count: Int) -> String {
        if count <= 0 {
            return "OK"
        }
        return WatchKPIFormatter.errorCount(count)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("watch.empty.portfolio".watchLocalized)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
