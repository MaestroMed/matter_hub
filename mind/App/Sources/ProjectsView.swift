import SwiftUI
import SwiftData
import BootstrapKit
import DesignSystem
import GraphCore

/// v1.0-alpha.3 — Project-first replacement for ClientsView's tab
/// slot. Query backed by the new `Project` @Model, with search +
/// sort segmented control + a "+" CTA wiring `NewProjectSheet`.
///
/// Each row is an 88pt-tall ProjectCard:
/// - 48pt avatar circle with the name initial (project's primary
///   color)
/// - Middle column: name (bold) + host (mono caption) + stack badge
/// - Right column: MRR pill (`€X/mo` for retainer, `Forfait €Y` for
///   oneshot) + lifecycle dot.
///
/// Tap → ProjectDetailSheet. The legacy `ClientsView` stays compiled
/// for the cron-resurrection edge case but no longer owns the tab —
/// `RootView.content`'s `.clients` case now routes here.
struct ProjectsView: View {
    @Query(sort: \Project.lastActivityAt, order: .reverse)
    private var projects: [Project]

    @State private var searchText: String = ""
    @State private var sortKey: ProjectSorter.SortKey = .activityDescending
    @State private var selectedProject: Project?
    @State private var presentingNewProject: Bool = false

    private var filtered: [Project] {
        let filtered = ProjectSorter.filter(projects, query: searchText)
        return ProjectSorter.sort(filtered, by: sortKey)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                searchField
                if !projects.isEmpty {
                    sortPicker
                }
                if filtered.isEmpty {
                    emptyCard
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { project in
                            Button {
                                LiquidHaptics.select()
                                selectedProject = project
                            } label: {
                                ProjectCard(project: project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.top, 40)
            .padding(.bottom, 120)
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailSheet(project: project)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $presentingNewProject) {
            // v1.0-alpha.6 — Replace the basic NewProjectSheet with
            // the BootstrapWizardSheet, which is the full 3-step
            // scaffolder. The minimal sheet stays compiled for any
            // path that still wants the lightweight form.
            BootstrapWizardSheet(onProjectCreated: { project in
                selectedProject = project
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("project.list.title")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                Text(verbatim: subtitle)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                LiquidHaptics.select()
                presentingNewProject = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("project.new.title"))
        }
    }

    private var subtitle: String {
        let count = projects.count
        let active = ProjectMRR.activeCount(in: projects)
        let mrr = ProjectMRR.total(of: projects)
        if count == 0 {
            return String(localized: "project.list.subtitle.empty")
        }
        let format = String(localized: "project.list.subtitle.format")
        return String(format: format, count, active, mrr)
    }

    private var searchField: some View {
        LiquidCard(cornerRadius: 18) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    String(localized: "project.list.search.placeholder"),
                    text: $searchText
                )
                .textFieldStyle(.plain)
                .font(.system(.body, design: .rounded))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var sortPicker: some View {
        Picker(
            String(localized: "project.list.sort.label"),
            selection: Binding(
                get: { sortKey },
                set: { newValue in
                    sortKey = newValue
                    MINDTelemetry.info(
                        "project.list.sortChanged",
                        data: ["sort": newValue.rawValue]
                    )
                }
            )
        ) {
            Text(String(localized: "project.list.sort.activity")).tag(ProjectSorter.SortKey.activityDescending)
            Text(String(localized: "project.list.sort.mrr")).tag(ProjectSorter.SortKey.mrrDescending)
            Text(String(localized: "project.list.sort.alpha")).tag(ProjectSorter.SortKey.alphabetical)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 4)
    }

    private var emptyCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 40))
                    .foregroundStyle(LiquidGradient.primary)
                Text("project.list.empty.title")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text("project.list.empty.detail")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - ProjectCard

private struct ProjectCard: View {
    let project: Project

    var body: some View {
        LiquidCard(cornerRadius: 20) {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: project.name)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text(verbatim: project.host)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        stackBadge
                        lifecycleDot
                    }
                }
                Spacer(minLength: 8)
                mrrPill
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(minHeight: 88)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.22))
                .frame(width: 48, height: 48)
            Text(String(project.name.first ?? "?").uppercased())
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(accent)
        }
    }

    private var accent: Color {
        Color(hex: project.primaryColor) ?? LiquidPalette.iris
    }

    private var stackBadge: some View {
        Text(stackLabel.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(accent.opacity(0.14))
            }
    }

    private var stackLabel: String {
        switch project.stackEnum {
        case .nextjs:     return "Next.js"
        case .wordpress:  return "WordPress"
        case .shopify:    return "Shopify"
        case .staticSite: return "Static"
        case .other:      return "Custom"
        }
    }

    private var lifecycleDot: some View {
        let tint: Color
        switch project.lifecycleStageEnum {
        case .active:      tint = .green
        case .maintenance: tint = .orange
        case .discovery:   tint = LiquidPalette.sky
        case .archived:    tint = .gray
        }
        return HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(verbatim: project.lifecycleStageEnum.rawValue.capitalized)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    private var mrrPill: some View {
        let isRetainer = project.contractTypeEnum == .retainer
        let label: String
        if isRetainer {
            label = ProjectMRR.formatEUR(project.monthlyRecurringRevenueEUR)
        } else {
            let format = String(localized: "project.list.oneshot.format")
            label = String(format: format, project.oneShotRevenueEUR)
        }
        return Text(verbatim: label)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(accent.opacity(0.92))
            }
    }
}
