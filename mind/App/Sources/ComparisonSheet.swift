import SwiftUI
import AuditKit
import DesignSystem
import GraphCore  // MINDTelemetry

/// v0.32 — Audit comparisons (multi-target).
///
/// Lets Mehdi pick 2–4 previously-audited clients and see a side-by-
/// side scoreboard (6 metrics × N clients), the Quick Wins that
/// appear in 2+ reports, and the Hidden Risks unique to a single
/// report. The picker reads from `AuditReportArchive.shared` which
/// `AuditController` auto-populates on every completed audit.
///
/// The sheet has two phases: **picker** and **comparison**. The
/// picker shows every archived report with a multi-select checkbox.
/// Tapping "Comparer" builds an `AuditComparison` from the selection
/// and switches to the comparison view. From there a "Modifier la
/// sélection" button returns to the picker so Mehdi can swap clients
/// without dismissing the whole sheet.
struct ComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Hydrated reports loaded from `AuditReportArchive` on appear.
    /// Empty until the first `.task { }` finishes. The picker shows
    /// a "Aucun audit archivé" hint while empty.
    @State private var archivedReports: [AuditReport] = []

    /// Selected client IDs in pick order so the comparison columns
    /// render in the same order Mehdi tapped them. Capped at
    /// `AuditComparison.maximumReports` (4) at tap time.
    @State private var selectedIDs: [UUID] = []

    /// Built once the user taps "Comparer". When nil the picker is
    /// shown; when non-nil the comparison view is shown.
    @State private var comparison: AuditComparison?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let comparison {
                        comparisonView(comparison)
                    } else {
                        pickerView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .animation(.smooth, value: comparison)
            }
            .background {
                LiquidBackground().ignoresSafeArea()
            }
            .navigationTitle("comparison.title")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("comparison.close") { dismiss() }
                }
            }
        }
        .task {
            await loadArchivedReports()
        }
    }

    // MARK: - Picker view

    @ViewBuilder
    private var pickerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("comparison.picker.headline")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Text("comparison.picker.subtitle")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }

        if archivedReports.isEmpty {
            emptyArchiveCard
        } else {
            VStack(spacing: 12) {
                ForEach(archivedReports, id: \.client.id) { report in
                    pickerRow(for: report)
                }
            }

            LiquidButton(
                title: compareButtonTitle,
                systemImage: "rectangle.split.3x1",
                haptic: .select
            ) {
                buildComparison()
            }
            .disabled(selectedIDs.count < AuditComparison.minimumReports)
            .opacity(selectedIDs.count < AuditComparison.minimumReports ? 0.55 : 1.0)
            .padding(.top, 8)
        }
    }

    private var compareButtonTitle: String {
        let count = selectedIDs.count
        if count < AuditComparison.minimumReports {
            return String(
                format: NSLocalizedString(
                    "comparison.compare.cta.disabled",
                    comment: ""
                ),
                count
            )
        }
        return String(
            format: NSLocalizedString(
                "comparison.compare.cta",
                comment: ""
            ),
            count
        )
    }

    private var emptyArchiveCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .center, spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris.opacity(0.85))
                Text("comparison.empty.title")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("comparison.empty.subtitle")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private func pickerRow(for report: AuditReport) -> some View {
        let id = report.client.id
        let isSelected = selectedIDs.contains(id)
        let selectionIndex = selectedIDs.firstIndex(of: id)
        return Button {
            toggleSelection(id)
        } label: {
            LiquidCard(cornerRadius: 18) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                isSelected
                                    ? LiquidPalette.iris.opacity(0.85)
                                    : LiquidPalette.iris.opacity(0.12)
                            )
                            .frame(width: 36, height: 36)
                        if let selectionIndex {
                            Text("\(selectionIndex + 1)")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "circle")
                                .font(.system(.headline))
                                .foregroundStyle(LiquidPalette.iris.opacity(0.6))
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.client.displayName)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(secondaryLabel(for: report))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    scoreBadge(report.scoring.overall)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    private func secondaryLabel(for report: AuditReport) -> String {
        let host = report.client.url.host(percentEncoded: false) ?? ""
        let date = relativeDate(report.generatedAt)
        if host.isEmpty { return date }
        return "\(host) • \(date)"
    }

    private func scoreBadge(_ score: Int) -> some View {
        Text("\(score)")
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(scoreColor(score).opacity(0.9))
            )
    }

    // MARK: - Comparison view

    @ViewBuilder
    private func comparisonView(_ comparison: AuditComparison) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("comparison.results.headline")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text(
                String(
                    format: NSLocalizedString(
                        "comparison.results.subtitle",
                        comment: ""
                    ),
                    comparison.reports.count
                )
            )
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.secondary)
        }

        clientLegendCard(comparison)
        scoreboardCard(comparison)
        overlapCard(comparison)
        differencesCard(comparison)

        LiquidButton(
            title: NSLocalizedString(
                "comparison.back.cta",
                comment: ""
            ),
            systemImage: "arrow.uturn.left",
            haptic: .tap
        ) {
            self.comparison = nil
        }
        .padding(.top, 12)
    }

    private func clientLegendCard(_ comparison: AuditComparison) -> some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("comparison.legend.title")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(comparison.reports.enumerated()), id: \.element.client.id) { idx, report in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(legendColor(for: idx))
                            .frame(width: 12, height: 12)
                        Text("\(idx + 1). \(report.client.displayName)")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(report.client.url.host(percentEncoded: false) ?? "")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(16)
        }
    }

    private func scoreboardCard(_ comparison: AuditComparison) -> some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("comparison.scoreboard.title")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                ForEach(AuditComparison.Metric.allCases, id: \.self) { metric in
                    metricRow(metric, comparison: comparison)
                }
            }
            .padding(16)
        }
    }

    private func metricRow(
        _ metric: AuditComparison.Metric,
        comparison: AuditComparison
    ) -> some View {
        let scores = comparison.metricMatrix[metric] ?? []
        let leaderIndex = comparison.leaders[metric]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(metric.label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let leaderIndex {
                    Text(
                        String(
                            format: NSLocalizedString(
                                "comparison.leader.label",
                                comment: ""
                            ),
                            leaderIndex + 1
                        )
                    )
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.aqua)
                }
            }
            HStack(spacing: 8) {
                ForEach(Array(scores.enumerated()), id: \.offset) { idx, score in
                    scoreChip(
                        index: idx,
                        score: score,
                        isLeader: idx == leaderIndex
                    )
                }
            }
        }
    }

    private func scoreChip(index: Int, score: Int, isLeader: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(legendColor(for: index))
                .frame(width: 8, height: 8)
            Text("\(score)")
                .font(.system(.subheadline, design: .rounded, weight: isLeader ? .bold : .medium))
                .foregroundStyle(isLeader ? Color.white : Color.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(
                    isLeader
                        ? LiquidPalette.aqua.opacity(0.85)
                        : Color.primary.opacity(0.06)
                )
        )
    }

    private func overlapCard(_ comparison: AuditComparison) -> some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("comparison.overlap.title")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                if comparison.quickWinOverlap.isEmpty {
                    Text("comparison.overlap.empty")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(comparison.quickWinOverlap) { entry in
                        overlapRow(entry)
                    }
                }
            }
            .padding(16)
        }
    }

    private func overlapRow(_ entry: AuditComparison.OverlapEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(LiquidPalette.iris)
                .font(.system(.subheadline))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    ForEach(entry.reportIndices, id: \.self) { idx in
                        Text("#\(idx + 1)")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(legendColor(for: idx))
                            )
                    }
                    Text(
                        String(
                            format: NSLocalizedString(
                                "comparison.overlap.count",
                                comment: ""
                            ),
                            entry.occurrenceCount
                        )
                    )
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func differencesCard(_ comparison: AuditComparison) -> some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("comparison.differences.title")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                if comparison.uniqueHiddenRisks.isEmpty {
                    Text("comparison.differences.empty")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(comparison.uniqueHiddenRisks) { entry in
                        differenceRow(entry)
                    }
                }
            }
            .padding(16)
        }
    }

    private func differenceRow(_ entry: AuditComparison.UniqueRiskEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(severityColor(entry.severity))
                .font(.system(.subheadline))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text("#\(entry.reportIndex + 1)")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(legendColor(for: entry.reportIndex))
                        )
                    Text(severityLabel(entry.severity))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(severityColor(entry.severity))
                }
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ id: UUID) {
        if let existing = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: existing)
        } else if selectedIDs.count < AuditComparison.maximumReports {
            selectedIDs.append(id)
            LiquidHaptics.select()
        } else {
            // Cap reached — light a soft warning haptic so Mehdi
            // notices the silent ignore.
            LiquidHaptics.warning()
        }
    }

    private func buildComparison() {
        let selectedReports = selectedIDs.compactMap { id in
            archivedReports.first { $0.client.id == id }
        }
        let built = AuditComparisonBuilder.build(from: selectedReports)
        comparison = built
        MINDTelemetry.info(
            "audit.comparison.built",
            data: [
                "count": String(built.reports.count),
                "overlap": String(built.quickWinOverlap.count),
                "uniqueRisks": String(built.uniqueHiddenRisks.count),
            ]
        )
    }

    private func loadArchivedReports() async {
        let reports = await AuditReportArchive.shared.allReports()
        await MainActor.run {
            self.archivedReports = reports
        }
    }

    // MARK: - Visual helpers

    /// Per-column accent colour. 4 distinct hues so the user can
    /// trace a row across the scoreboard at a glance.
    private func legendColor(for index: Int) -> Color {
        switch index % 4 {
        case 0: return LiquidPalette.iris
        case 1: return LiquidPalette.aqua
        case 2: return LiquidPalette.lavender
        default: return LiquidPalette.sky
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return LiquidPalette.aqua
        case 60..<80: return LiquidPalette.iris
        case 40..<60: return LiquidPalette.lavender
        default: return LiquidPalette.blush
        }
    }

    private func severityColor(_ severity: AuditReport.HiddenRisk.Severity) -> Color {
        switch severity {
        case .low:      return LiquidPalette.aqua
        case .medium:   return LiquidPalette.iris
        case .high:     return LiquidPalette.lavender
        case .critical: return LiquidPalette.blush
        }
    }

    private func severityLabel(_ severity: AuditReport.HiddenRisk.Severity) -> String {
        switch severity {
        case .low:      return NSLocalizedString("comparison.severity.low", comment: "")
        case .medium:   return NSLocalizedString("comparison.severity.medium", comment: "")
        case .high:     return NSLocalizedString("comparison.severity.high", comment: "")
        case .critical: return NSLocalizedString("comparison.severity.critical", comment: "")
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
