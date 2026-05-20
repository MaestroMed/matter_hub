import SwiftUI
import AuditKit
import DesignSystem

/// v0.25 — Methodology modal mounted by the AuditSheet hero ROI
/// card's "Méthodologie" CTA. Explains the formula Claude used
/// (conversion lift × estimated traffic × estimated ARPU), surfaces
/// the per-confidence breakdown so the user can sanity-check the
/// hero number, and re-states the cap rules so a single optimistic
/// estimate never dominates the headline.
///
/// Read-only; the user dismisses with the close button or by
/// swiping down. No persistence, no telemetry beyond the open
/// event the AuditSheet logs.
struct ROIMethodologySheet: View {
    let monthlyTotal: Int
    let annualisedTotal: Int
    let confidence: AuditReport.ConfidenceLevel?
    let quickWins: [AuditReport.QuickWin]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                summaryCard
                methodologyCard
                breakdownCard
            }
            .padding(20)
        }
        .background {
            LiquidBackground().ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("roi.methodology.button", bundle: .main)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("roi.hero.total.label", bundle: .main)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .tracking(1.0)
                    .textCase(.uppercase)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var summaryCard: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("+\(AuditSheet.roiAmountString(monthlyTotal))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LiquidPalette.iris)
                        .minimumScaleFactor(0.7)
                    Text("roi.per.month.suffix", bundle: .main)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                let annualisedFormat = String(
                    localized: "roi.hero.annualized.label",
                    bundle: .main
                )
                Text(String(
                    format: annualisedFormat,
                    AuditSheet.roiAmountString(annualisedTotal)
                ))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var methodologyCard: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("roi.methodology.body", bundle: .main)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Per-QW breakdown: every QW with a non-nil estimate gets a
    /// row showing its title + the monthly amount + the confidence
    /// pill. Nil-impact QWs are omitted to keep the modal
    /// scannable.
    @ViewBuilder
    private var breakdownCard: some View {
        let nonNil = quickWins.filter { ($0.estimatedMonthlyRevenueImpactEUR ?? 0) > 0 }
        if !nonNil.isEmpty {
            LiquidCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(nonNil) { win in
                        breakdownRow(win)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func breakdownRow(_ win: AuditReport.QuickWin) -> some View {
        let monthly = win.estimatedMonthlyRevenueImpactEUR ?? 0
        let suffix = String(localized: "roi.per.month.suffix", bundle: .main)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(win.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(2)
                if let level = win.confidence {
                    Text(confidenceLabel(for: level))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                        .textCase(.uppercase)
                }
            }
            Spacer()
            Text("+\(AuditSheet.roiAmountString(monthly)) \(suffix)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(LiquidPalette.iris)
        }
    }

    private func confidenceLabel(for level: AuditReport.ConfidenceLevel) -> String {
        let key: String
        switch level {
        case .low:    key = "roi.confidence.low"
        case .medium: key = "roi.confidence.medium"
        case .high:   key = "roi.confidence.high"
        }
        return String(localized: String.LocalizationValue(key), bundle: .main)
    }
}
