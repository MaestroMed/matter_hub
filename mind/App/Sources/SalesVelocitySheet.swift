import SwiftUI
import SwiftData
import Charts
import DesignSystem
import GraphCore

/// v1.0-alpha.13 — Full-screen Velocity dashboard.
///
/// Reached from HomeView's "Vélocité" card tap. Three full-resolution
/// charts stacked vertically:
///
///  1. 12-month MRR line chart (with a target line at 5000€/mo)
///  2. Cumulative leads area chart over 12 weeks
///  3. Funnel stage distribution stacked bar (new / contacted /
///     qualified / won / lost)
///
/// Plus an "Exporter en PDF" button at the bottom that emits a
/// `velocity.exported.pdf` breadcrumb. The actual PDF rendering
/// reuses the same `ImageRenderer`-based path the v0.31 invoice
/// surface uses; for v1.0-alpha.13 we ship the breadcrumb + the
/// telemetry hook so a future Live Activities iteration can hook
/// into the same export pipeline.
struct SalesVelocitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allProjects: [Project]
    @Query private var allLeads: [Lead]

    /// Monthly MRR snapshots over the trailing 12 months.
    private var mrrPoints: [MRRPoint] {
        SalesVelocityCalculator.monthlyMRRHistory(
            projects: allProjects,
            months: 12
        )
    }

    /// Weekly lead counts over the trailing 12 weeks.
    private var weeklyLeads: [WeeklyLeadPoint] {
        SalesVelocityCalculator.weeklyLeads(
            leads: allLeads,
            weeks: 12
        )
    }

    /// Funnel stage distribution across every lead in the database.
    private var funnel: [FunnelStagePoint] {
        SalesVelocityCalculator.funnelDistribution(leads: allLeads)
    }

    /// Cumulative lead-count series derived from `weeklyLeads`, used
    /// by the area chart on the sheet. Mirrors the "total leads
    /// pipeline" you'd see on a CRM dashboard.
    private var cumulativeLeads: [WeeklyLeadPoint] {
        var running = 0
        return weeklyLeads.map { point in
            running += point.count
            return WeeklyLeadPoint(weekStart: point.weekStart, count: running)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                mrrChartCard
                cumulativeLeadsCard
                funnelDistributionCard
                exportRow
            }
            .padding(20)
            .padding(.top, 16)
            .padding(.bottom, 80)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .onAppear {
            MINDTelemetry.info(
                "velocity.sheet.opened",
                data: [
                    "projects": String(allProjects.count),
                    "leads": String(allLeads.count),
                ]
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("velocity.sheet.title")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text(verbatim: subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let mrr = mrrPoints.last?.mrrEUR ?? 0
        let leads = allLeads.count
        let conv = SalesVelocityCalculator.conversionRate(leads: allLeads)
        return "€\(mrr)/mo · \(leads) leads · \(Int(conv * 100))% conversion"
    }

    // MARK: - MRR chart

    private var mrrChartCard: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("home.velocity.chart.mrr")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Chart(mrrPoints) { point in
                    LineMark(
                        x: .value("Month", point.monthStart),
                        y: .value("MRR", point.mrrEUR)
                    )
                    .foregroundStyle(LiquidPalette.iris)
                    .symbol(.circle)
                    RuleMark(y: .value("Target", 5_000))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(LiquidPalette.aqua.opacity(0.7))
                        .annotation(position: .top, alignment: .leading) {
                            Text(
                                String(
                                    format: String(localized: "home.velocity.target.format"),
                                    5_000
                                )
                            )
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(LiquidPalette.aqua)
                        }
                }
                .frame(height: 200)
            }
            .padding(16)
        }
    }

    // MARK: - Cumulative leads chart

    private var cumulativeLeadsCard: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("velocity.cumulative.title")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Chart(cumulativeLeads) { point in
                    AreaMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Leads", point.count)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                LiquidPalette.aqua.opacity(0.55),
                                LiquidPalette.aqua.opacity(0.05),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(height: 180)
            }
            .padding(16)
        }
    }

    // MARK: - Funnel distribution

    private var funnelDistributionCard: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("velocity.funnel.title")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Chart(funnel) { point in
                    BarMark(
                        x: .value("Count", point.count),
                        y: .value("Stage", localizedFunnelLabel(for: point.stage))
                    )
                    .foregroundStyle(tint(forStage: point.stage))
                }
                .frame(height: 200)
            }
            .padding(16)
        }
    }

    // MARK: - Export row

    private var exportRow: some View {
        Button {
            LiquidHaptics.tap()
            MINDTelemetry.info(
                "velocity.exported.pdf",
                data: [
                    "projects": String(allProjects.count),
                    "leads": String(allLeads.count),
                ]
            )
        } label: {
            Label(
                String(localized: "velocity.sheet.export"),
                systemImage: "square.and.arrow.up"
            )
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                Capsule(style: .continuous)
                    .fill(LiquidPalette.iris.opacity(0.95))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func localizedFunnelLabel(for stage: String) -> String {
        switch stage {
        case "new":        return String(localized: "velocity.funnel.new")
        case "contacted":  return String(localized: "velocity.funnel.contacted")
        case "qualified":  return String(localized: "velocity.funnel.qualified")
        case "won":        return String(localized: "velocity.funnel.won")
        case "lost":       return String(localized: "velocity.funnel.lost")
        case "spam":       return String(localized: "velocity.funnel.spam")
        default:           return stage
        }
    }

    private func tint(forStage stage: String) -> Color {
        switch stage {
        case "new":        return LiquidPalette.iris
        case "contacted":  return LiquidPalette.aqua
        case "qualified":  return .orange
        case "won":        return .green
        case "lost":       return .red
        case "spam":       return .gray
        default:           return .gray
        }
    }
}
