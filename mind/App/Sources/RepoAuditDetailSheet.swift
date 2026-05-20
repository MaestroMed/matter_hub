import SwiftUI
import AuditKit
import DesignSystem
import GraphCore

/// v1.0-alpha.10 — Inline result sheet for the `RepositoryAuditProbe`
/// when launched directly from `ProjectDetailSheet → Actions →
/// Auditer le code source` (without the 13-probe URL flow). Reads the
/// same `RepositoryAuditFindings` shape the AuditSheet's "Code source"
/// section renders — pulled into its own file because this sheet
/// stands alone and we want the AuditSheet code path to stay
/// untouched.
struct RepoAuditDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let findings: RepositoryAuditFindings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                summaryCard
                if !findings.outdatedDependencies.isEmpty {
                    outdatedCard
                }
                if !findings.securitySignals.isEmpty {
                    securityCard
                }
                quickRowsCard
            }
            .padding(20)
            .padding(.bottom, 60)
        }
        .background { LiquidBackground().ignoresSafeArea() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("audit.section.repo.title")
                .font(.system(.title2, design: .rounded, weight: .semibold))
            Text(verbatim: findings.framework ?? "Framework non détecté")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var summaryCard: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    gradePill
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: findings.framework ?? "Framework non détecté")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Text(verbatim: subtitle)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if !findings.summary.isEmpty {
                    MarkdownView(findings.summary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var subtitle: String {
        let pm = findings.packageManager ?? String(
            localized: "audit.section.repo.subtitle.pm.unknown"
        )
        let strict = findings.typescriptStrict
            ? String(localized: "audit.section.repo.ts.strict")
            : String(localized: "audit.section.repo.ts.loose")
        return "\(pm) · \(strict)"
    }

    private var gradePill: some View {
        Text(verbatim: findings.overallGrade)
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .foregroundStyle(gradeColor)
            .frame(width: 64, height: 64)
            .background {
                Circle().fill(gradeColor.opacity(0.18))
            }
            .overlay {
                Circle().strokeBorder(gradeColor.opacity(0.42), lineWidth: 1.5)
            }
            .accessibilityLabel(
                String(
                    format: String(localized: "audit.section.repo.grade.accessibility"),
                    findings.overallGrade
                )
            )
    }

    private var gradeColor: Color {
        switch findings.overallGrade {
        case "A+":  return LiquidPalette.iris
        case "A":   return .green
        case "B":   return .orange
        case "C":   return .orange
        case "D":   return .red
        case "F":   return .red
        default:    return .gray
        }
    }

    private var outdatedCard: some View {
        LiquidCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("audit.section.repo.outdated.title")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                ForEach(findings.outdatedDependencies.prefix(12), id: \.name) { dep in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: dep.name)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                            Text(verbatim: "\(dep.installed) → \(dep.latest)")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                        if dep.majorBehind >= 1 {
                            Text(
                                String(
                                    format: String(localized: "audit.section.repo.outdated.major.format"),
                                    dep.majorBehind
                                )
                            )
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background { Capsule().fill(Color.red.opacity(0.2)) }
                            .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var securityCard: some View {
        LiquidCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("audit.section.repo.security.title")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                ForEach(Array(findings.securitySignals.enumerated()), id: \.offset) { (_, signal) in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(severityColor(signal.severity))
                            .frame(width: 10, height: 10)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: signal.detail)
                                .font(.system(.subheadline, design: .rounded))
                            if let path = signal.filePath {
                                Text(verbatim: path)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text(severityLabel(signal.severity))
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(severityColor(signal.severity))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "high":   return .red
        case "medium": return .orange
        case "low":    return .yellow
        default:       return .gray
        }
    }

    private func severityLabel(_ severity: String) -> String {
        switch severity {
        case "high":   return String(localized: "audit.section.repo.security.severity.high")
        case "medium": return String(localized: "audit.section.repo.security.severity.medium")
        case "low":    return String(localized: "audit.section.repo.security.severity.low")
        default:       return severity.capitalized
        }
    }

    private var quickRowsCard: some View {
        LiquidCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                quickRow(icon: "checkmark.shield.fill", label: ciLabel)
                quickRow(icon: "testtube.2", label: testsLabel)
                quickRow(icon: "shippingbox.fill", label: bundleLabel)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quickRow(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(LiquidPalette.iris)
                .frame(width: 24)
            Text(verbatim: label)
                .font(.system(.subheadline, design: .rounded))
            Spacer()
        }
    }

    private var ciLabel: String {
        let ci = findings.ciSignals
        if !ci.hasWorkflows {
            return String(localized: "audit.section.repo.ci.none")
        }
        let workflowFormat = String(localized: "audit.section.repo.ci.workflows")
        var parts: [String] = [String(format: workflowFormat, ci.workflowCount)]
        if ci.hasTestWorkflow {
            parts.append(String(localized: "audit.section.repo.ci.test"))
        }
        if ci.hasDeployWorkflow {
            parts.append(String(localized: "audit.section.repo.ci.deploy"))
        }
        return parts.joined(separator: " · ")
    }

    private var testsLabel: String {
        let tests = findings.testCoverage
        if !tests.hasTestDirectory {
            return String(localized: "audit.section.repo.tests.none")
        }
        let countFormat = String(localized: "audit.section.repo.tests.count.format")
        var line = String(format: countFormat, tests.testFiles)
        if let framework = tests.testFramework {
            let frameworkFormat = String(localized: "audit.section.repo.tests.framework.format")
            line += " · " + String(format: frameworkFormat, framework)
        }
        return line
    }

    private var bundleLabel: String {
        let bundle = findings.bundleSignals
        if bundle.heavyDependencies.isEmpty {
            return String(localized: "audit.section.repo.bundle.clean")
        }
        let heavyFormat = String(localized: "audit.section.repo.bundle.heavy")
        var line = String(format: heavyFormat, bundle.heavyDependencies.count)
        if let kb = bundle.estimatedKB {
            let sizeFormat = String(localized: "audit.section.repo.bundle.size.format")
            line += " · " + String(format: sizeFormat, kb)
        }
        return line
    }
}
