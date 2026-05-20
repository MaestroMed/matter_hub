import SwiftUI
import SwiftData
import BootstrapKit
import DesignSystem
import GraphCore
import ProjectHealthKit

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
        .refreshable {
            await refreshAllProjects()
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

    /// v1.0-alpha.9 — Pull-to-refresh handler. Re-fans every project
    /// with a `vercelProjectID` through `PortfolioHealthAggregator`'s
    /// fresh-fetch path. Heart-beat haptic on start + success haptic
    /// on finish.
    private func refreshAllProjects() async {
        await MainActor.run {
            LiquidHaptics.tap()
            MINDTelemetry.info("projects.pulldown.refresh",
                               data: ["count": "\(projects.count)"])
        }
        let identities = projects.map { project in
            ProjectIdentity(
                id: project.id,
                vercelProjectID: project.vercelProjectID,
                githubRepo: project.githubRepo,
                host: project.host
            )
        }
        _ = await PortfolioHealthAggregator.shared.refreshAndSnapshot(for: identities)
        await MainActor.run {
            LiquidHaptics.success()
        }
    }
}

// MARK: - ProjectCard

private struct ProjectCard: View {
    let project: Project

    /// v1.0-alpha.8 — Latest health pulse loaded from
    /// `HealthPulseStore` on appear. nil until the async hydration
    /// returns, which the dot reads as `.unknown`.
    @State private var healthPulse: HealthPulse?

    /// v1.0-alpha.9 — Latest Vercel deployment state, hydrated from
    /// `ProjectHealthCache.shared` on `.task`. nil until the cache
    /// read returns; the pill renders the gray "—" sentinel in that
    /// case.
    @State private var deploymentState: String?

    var body: some View {
        LiquidCard(cornerRadius: 20) {
            ZStack(alignment: .topTrailing) {
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

                // v1.0-alpha.9 — Deployment pill anchored to the
                // top-right corner. Renders nothing for the "unknown"
                // bucket on a project the cache hasn't seen yet.
                if let state = deploymentState {
                    deploymentPill(for: state)
                        .padding(.top, 8)
                        .padding(.trailing, 12)
                }
            }
        }
        .task(id: project.id) {
            // Hydrate the dot lazily — we never block the render on
            // the disk read, and a fresh pulse from background probing
            // shows up on the next `task` cycle. The cache mirror
            // inside `HealthPulseStore` keeps this O(1) after the
            // first hit.
            healthPulse = await HealthPulseStore.shared.load(projectID: project.id)
            // v1.0-alpha.9 — Cache hit only; the per-project sheet's
            // fan-out fetcher is the canonical refresh path, so we
            // never burn a Vercel API call on the list view.
            if let bundle = await ProjectHealthCache.shared.bundle(for: project.id) {
                deploymentState = bundle.latestDeployment?.state.uppercased()
            }
        }
    }

    @ViewBuilder
    private func deploymentPill(for rawState: String) -> some View {
        let metadata = deploymentPillMetadata(for: rawState)
        HStack(spacing: 4) {
            Circle()
                .fill(metadata.tint)
                .frame(width: 6, height: 6)
                .opacity(metadata.pulsing ? 0.8 : 1.0)
            Text(verbatim: metadata.label)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(metadata.tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule(style: .continuous)
                .fill(metadata.tint.opacity(0.14))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(metadata.tint.opacity(0.30), lineWidth: 0.8)
                }
        }
    }

    private struct DeploymentPillMetadata {
        let label: String
        let tint: Color
        let pulsing: Bool
    }

    private func deploymentPillMetadata(for rawState: String) -> DeploymentPillMetadata {
        switch rawState {
        case "READY":
            return DeploymentPillMetadata(
                label: String(localized: "project.card.deploymentPill.ready"),
                tint: .green,
                pulsing: false
            )
        case "BUILDING", "QUEUED", "INITIALIZING":
            return DeploymentPillMetadata(
                label: String(localized: "project.card.deploymentPill.building"),
                tint: .orange,
                pulsing: true
            )
        case "ERROR":
            return DeploymentPillMetadata(
                label: String(localized: "project.card.deploymentPill.error"),
                tint: .red,
                pulsing: false
            )
        default:
            return DeploymentPillMetadata(
                label: String(localized: "project.card.deploymentPill.unknown"),
                tint: .gray,
                pulsing: false
            )
        }
    }

    private var avatar: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.22))
                    .frame(width: 48, height: 48)
                Text(String(project.name.first ?? "?").uppercased())
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(accent)
            }
            // v1.0-alpha.8 — Site health pulse dot anchored on the
            // avatar's top-right corner. Stays a tiny coloured circle
            // when present, fully invisible when `.unknown` so a
            // never-probed project doesn't pollute the list with
            // gray dots.
            if let status = healthPulse?.status, status != .unknown {
                Circle()
                    .fill(healthDotColor(for: status))
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(.background, lineWidth: 2)
                    }
                    .offset(x: 2, y: -2)
                    .accessibilityLabel(Text(status.localizationKey))
            }
        }
        .frame(width: 48, height: 48)
    }

    /// Maps a `HealthStatus` bucket to its dot tint. Kept inside the
    /// card view so the colour vocabulary stays co-located with the
    /// thing rendering it (and so a future palette tweak is a one-
    /// liner here, not a search-and-replace).
    private func healthDotColor(for status: HealthStatus) -> Color {
        switch status {
        case .online:   return .green
        case .degraded: return .orange
        case .error:    return .red
        case .offline:  return .red
        case .unknown:  return .gray
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
