import Foundation
import SwiftUI
import PDFKit
import UIKit
import AuditKit
import DesignSystem

/// Renders an AuditReport as a single-page A4 PDF on a Liquid Glass-tinted
/// background, ready to AirDrop or attach to an email. Currently text-only
/// (wordmark image will land once Mehdi drops the brand assets); typography
/// alone carries the MIND identity for now.
enum PDFReportRenderer {
    /// A4 portrait at 72dpi. We over-allocate height slightly so longer
    /// audits don't get visually truncated on a single-page PDF.
    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 1200

    @MainActor
    static func makePDF(for report: AuditReport) -> URL? {
        let view = PDFAuditPage(report: report)
            .frame(width: pageWidth, height: pageHeight)
            .background(Color.white)

        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale  // 2x or 3x for crisp text

        guard let uiImage = renderer.uiImage else { return nil }
        guard let page = PDFPage(image: uiImage) else { return nil }

        let document = PDFDocument()
        document.insert(page, at: 0)

        let filename = sanitizedFilename(for: report)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename).pdf")

        document.write(to: url)
        return url
    }

    private static func sanitizedFilename(for report: AuditReport) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: report.generatedAt)
        let safeName = report.client.displayName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
        return "MIND-audit-\(safeName.isEmpty ? "client" : safeName)-\(date)"
    }
}

// MARK: - PDF page layout

private struct PDFAuditPage: View {
    let report: AuditReport

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            brandHeader
            clientHeader
            scoreHero
            section(title: "Synthèse") {
                Text(report.synthesis)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !report.quickWins.isEmpty {
                section(title: "Quick wins") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(report.quickWins.prefix(5).enumerated()), id: \.offset) { index, win in
                            quickWinRow(index: index + 1, win: win)
                        }
                    }
                }
            }
            if !report.strategicBets.isEmpty {
                section(title: "Paris stratégiques") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(report.strategicBets.prefix(3).enumerated()), id: \.offset) { index, bet in
                            betRow(index: index + 1, bet: bet)
                        }
                    }
                }
            }
            section(title: "Pitch") {
                Text(report.pitch)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            LinearGradient(
                colors: [LiquidPalette.pearl, .white],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Header

    private var brandHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LiquidPalette.iris.opacity(0.22))
                    .frame(width: 28, height: 28)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            Text("MIND")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .tracking(2)
                .foregroundStyle(LiquidPalette.iris)
            Text("·")
                .foregroundStyle(.tertiary)
            Text("Audit digital")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Spacer()
            Text(report.generatedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var clientHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.client.displayName)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                Text(report.client.url.absoluteString)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(report.persona.label.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(LiquidPalette.iris)
            }
        }
    }

    // MARK: - Score hero

    private var scoreHero: some View {
        VStack(spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(report.scoring.overall)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LiquidPalette.iris)
                Text("/ 100")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text("score global")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                scorePill(value: report.scoring.performance, label: "Perf")
                scorePill(value: report.scoring.seo,         label: "SEO")
                scorePill(value: report.scoring.security,    label: "Sécu")
                scorePill(value: report.scoring.brand,       label: "Brand")
                scorePill(value: report.scoring.mobile,      label: "Mobile")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(LiquidPalette.lavender, lineWidth: 1)
                }
        }
    }

    private func scorePill(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(scoreColor(value))
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func scoreColor(_ value: Int) -> Color {
        switch value {
        case 80...:   return .green
        case 50..<80: return .orange
        default:      return .red
        }
    }

    // MARK: - Sections

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded, weight: .bold))
                .tracking(1)
                .foregroundStyle(LiquidPalette.iris)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickWinRow(index: Int, win: AuditReport.QuickWin) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index).")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(win.title)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                Spacer()
                Text(formattedEffort(win.effortDays))
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(win.impact.rawValue.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule().fill(impactColor(win.impact))
                    }
            }
            Text(win.detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.bottom, 2)
    }

    private func formattedEffort(_ days: Double) -> String {
        if days < 1 { return "≈ \(Int((days * 8).rounded()))h" }
        return "\(Int(days.rounded()))j"
    }

    private func impactColor(_ impact: AuditReport.QuickWin.Impact) -> Color {
        switch impact {
        case .high:   return .green
        case .medium: return .orange
        case .low:    return .gray
        }
    }

    private func betRow(index: Int, bet: AuditReport.StrategicBet) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index).")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(bet.title)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                Spacer()
                Text("\(bet.durationMonths) mois")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("€\(bet.budgetMinEUR / 1000)k–€\(bet.budgetMaxEUR / 1000)k")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            Text(bet.detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Made with MIND")
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("app.mind.ios")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LiquidPalette.lavender)
                .frame(height: 0.5)
        }
    }
}
