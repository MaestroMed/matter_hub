import SwiftUI
import SwiftData
import AuditKit
import ClientPortalKit
import DesignSystem
import GraphCore
import ProjectHealthKit
import SwarmKit
import UIKit

/// v1.0-alpha.3 — Project detail surface. Five sections from top to
/// bottom:
///
/// 1. Header — name, stack badge, MRR pill, host
/// 2. Aperçu — host link, GitHub repo link, last activity timestamp
/// 3. Leads récents — last 5 leads (tap → LeadDetailSheet)
/// 4. Livrables — kind-iconed deliverable rows
/// 5. Actions — launch audit / view all leads / archive
/// 6. Notes — multi-line markdown text editor
struct ProjectDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var project: Project

    /// v1.1.0 — Optional auto-scroll anchor. When the sheet is
    /// presented from the Vercel deep link (`mind://vercel/<id>`)
    /// the host passes `.vercel`; the body wraps itself in a
    /// `ScrollViewReader` and scrolls to the matching section on
    /// appear.
    let initialAnchor: SectionAnchor?

    @State private var notesDraft: String
    @State private var isAuditing: Bool = false
    @State private var isSwarming: Bool = false
    @State private var selectedLead: Lead?
    @State private var showLeadsListSheet: Bool = false
    @State private var showArchiveConfirm: Bool = false

    /// v1.0-alpha.10 — Repo-only audit state. The "Auditer le code
    /// source" action kicks off `RepositoryAuditProbe.shared.run(...)`
    /// directly without the 13-probe URL flow, then surfaces the
    /// result inline via a `RepoAuditDetailSheet` driven by this
    /// state slot. nil = sheet hidden.
    @State private var repoAuditRunning: Bool = false
    @State private var repoAuditResult: RepositoryAuditFindings?
    @State private var repoAuditError: String?

    /// v1.0-alpha.9 — Redeploy flow state. Confirmation alert before
    /// the POST fires, in-flight spinner gate during the call, toast
    /// text that drives the bottom-pinned `redeployToast` view.
    @State private var showRedeployConfirm: Bool = false
    @State private var redeployInFlight: Bool = false
    @State private var redeployToast: ToastMessage?
    /// v1.0-alpha.9 — Share sheet driver for the client portal action.
    @State private var sharePortalURL: URL?

    /// v1.0-alpha.8 — Latest health pulse hydrated from
    /// `HealthPulseStore.shared` on appear. nil until the async load
    /// returns; the overview surface reads that as `.unknown` and
    /// hides the row gracefully.
    @State private var healthPulse: HealthPulse?

    /// v1.0-alpha.8 — Live Vercel deployment + Lighthouse + GitHub
    /// surfaces. Each slot starts nil — the cache hydrates them on
    /// `.task`, then the in-flight fetcher refreshes them in the
    /// background. The matching `*Loading` flag drives the skeleton
    /// state per row, and `*Error` carries a soft error string the
    /// row falls back to when the upstream call fails.
    @State private var latestDeployment: VercelDeployment?
    @State private var lighthouseScore: LighthouseScore?
    @State private var recentCommits: [GitHubCommit] = []
    @State private var repoStats: GitHubRepoStats?
    @State private var vercelLoading: Bool = false
    @State private var githubLoading: Bool = false
    @State private var lighthouseLoading: Bool = false
    @State private var vercelError: String?
    @State private var githubError: String?

    init(project: Project, initialAnchor: SectionAnchor? = nil) {
        self.project = project
        self.initialAnchor = initialAnchor
        _notesDraft = State(initialValue: project.notes)
    }

    /// v1.1.0 — Section identifiers usable by `ScrollViewReader` so
    /// the Vercel push deep link can land the user directly at the
    /// Vercel block without scroll-hunting.
    enum SectionAnchor: String, Hashable {
        case vercel
        case lighthouseTrend
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    overviewSection
                    vercelSection.id(SectionAnchor.vercel)
                    githubSection
                    recentLeadsSection
                    deliverablesSection
                    actionsSection
                    notesSection
                }
                .padding(20)
                .padding(.top, 8)
                .padding(.bottom, 80)
            }
            .onAppear {
                guard let anchor = initialAnchor else { return }
                // Defer the scroll by a tick so the layout completes
                // before the scroll request lands.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                }
                MINDTelemetry.info(
                    "project.detail.autoScroll",
                    data: ["anchor": anchor.rawValue]
                )
            }
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .onAppear {
            MINDTelemetry.info(
                "project.detail.opened",
                data: ["projectID": project.id.uuidString]
            )
        }
        .task(id: project.id) {
            healthPulse = await HealthPulseStore.shared.load(projectID: project.id)
            await hydrateProjectHealth()
            await refreshProjectHealth()
        }
        .sheet(isPresented: $isAuditing) {
            AuditSheet(initialURL: "https://\(project.host)")
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isSwarming) {
            SwarmWizardSheet(initialProject: project)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $selectedLead) { lead in
            LeadDetailSheet(lead: lead)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showLeadsListSheet) {
            ProjectLeadsListSheet(project: project)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .alert(
            String(localized: "project.action.archive.confirm"),
            isPresented: $showArchiveConfirm
        ) {
            Button(String(localized: "project.action.archive"), role: .destructive) {
                project.lifecycleStageEnum = .archived
                project.touchActivity()
                try? context.save()
                dismiss()
            }
            Button(String(localized: "audit.button.cancel"), role: .cancel) {}
        } message: {
            Text(verbatim: project.name)
        }
        .alert(
            String(localized: "project.action.redeploy.confirm.title"),
            isPresented: $showRedeployConfirm
        ) {
            Button(String(localized: "project.action.redeploy"), role: .destructive) {
                MINDTelemetry.info(
                    "vercel.redeploy.confirmed",
                    data: ["projectID": project.id.uuidString]
                )
                Task { await runRedeploy() }
            }
            Button(String(localized: "audit.button.cancel"), role: .cancel) {}
        } message: {
            let format = String(localized: "project.action.redeploy.confirm.body")
            Text(verbatim: String(format: format, project.name))
        }
        .sheet(item: $sharePortalURL.asIdentifiable) { wrapped in
            ProjectPortalShareView(activityItems: [wrapped.url])
        }
        .sheet(item: $repoAuditResult.asRepoAuditItem) { wrapped in
            RepoAuditDetailSheet(findings: wrapped.findings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .overlay(alignment: .bottom) {
            if let toast = redeployToast {
                ToastBanner(message: toast)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: redeployToast)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: project.name)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .lineLimit(2)
                    Text(verbatim: project.host)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                mrrPill
            }
            HStack(spacing: 8) {
                stackBadge
                contractPill
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.22))
                .frame(width: 56, height: 56)
            Text(String(project.name.first ?? "?").uppercased())
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(accent)
        }
    }

    private var accent: Color {
        Color(hex: project.primaryColor) ?? LiquidPalette.iris
    }

    private var mrrPill: some View {
        let label: String
        if project.contractTypeEnum == .retainer {
            label = ProjectMRR.formatEUR(project.monthlyRecurringRevenueEUR)
        } else {
            let format = String(localized: "project.list.oneshot.format")
            label = String(format: format, project.oneShotRevenueEUR)
        }
        return Text(verbatim: label)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background { Capsule().fill(accent.opacity(0.92)) }
    }

    private var stackBadge: some View {
        Text(stackLabel.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background { Capsule().fill(accent.opacity(0.16)) }
    }

    private var contractPill: some View {
        let label: String = project.contractTypeEnum == .retainer
            ? String(localized: "project.contract.retainer")
            : String(localized: "project.contract.oneshot")
        return Text(label.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background { Capsule().fill(.ultraThinMaterial) }
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

    // MARK: - Overview

    private var overviewSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("project.detail.overview")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                overviewRow(
                    icon: "globe",
                    label: String(localized: "project.detail.host"),
                    value: project.host,
                    url: URL(string: "https://\(project.host)")
                )
                if let repo = project.githubRepo {
                    overviewRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        label: "GitHub",
                        value: repo,
                        url: URL(string: "https://github.com/\(repo)")
                    )
                }
                overviewRow(
                    icon: "clock.fill",
                    label: String(localized: "project.detail.lastActivity"),
                    value: project.lastActivityAt.formatted(.relative(presentation: .named)),
                    url: nil
                )
                // v1.0-alpha.8 — Health pulse surface. Hidden when no
                // probe has ever fired (the dot's "unknown" bucket)
                // so the section stays tight on fresh projects, and
                // reveals progressively as the background probe lands
                // real status codes.
                if let pulse = healthPulse, pulse.status != .unknown {
                    healthRow(pulse: pulse)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func healthRow(pulse: HealthPulse) -> some View {
        let tint = healthDotColor(for: pulse.status)
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.18))
                    .frame(width: 28, height: 28)
                Circle().fill(tint)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "project.detail.health"))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(String(localized: String.LocalizationValue(pulse.status.localizationKey)))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)
                    Text(verbatim: HealthPulseHelpers.formatRelativeAge(pulse.checkedAt))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if pulse.responseTimeMs >= 0 {
                Text(verbatim: "\(pulse.responseTimeMs) ms")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background { Capsule().fill(.ultraThinMaterial) }
            }
        }
    }

    // MARK: - Vercel section (v1.0-alpha.8)

    /// Live deployment status + Lighthouse 4-cell grid + "Voir sur
    /// Vercel" link. Renders a soft empty state when the user hasn't
    /// configured a Vercel token yet (tap-to-Settings CTA), and a
    /// distinct one when this Project doesn't carry a
    /// `vercelProjectID` (the most common shape on fresh seeded
    /// projects).
    private var vercelSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "triangle.fill")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                    Text("project.vercel.section.title")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    if let state = latestDeployment?.state {
                        vercelStateChip(rawState: state)
                    } else if vercelLoading {
                        ProgressView().controlSize(.mini)
                    }
                }

                if VercelTokenStore.read() == nil {
                    Text("project.vercel.empty.token")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else if let projectID = project.vercelProjectID, !projectID.isEmpty {
                    if let latest = latestDeployment {
                        vercelDeploymentRow(latest)
                    } else if vercelLoading {
                        skeletonRow()
                    } else if let error = vercelError {
                        Text(verbatim: error)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    lighthouseGrid
                    // v1.1.0 — 30-day Lighthouse trend sparkline grid.
                    // Renders the same four metrics as `lighthouseGrid`
                    // above, but as mini line charts pulled from the
                    // `LighthouseSnapshot` @Query slice. Soft-fails to
                    // an empty-state caption when no snapshot exists
                    // yet — the first audit or pull-to-refresh fills it.
                    LighthouseTrendView(projectID: project.id)
                        .id(SectionAnchor.lighthouseTrend)
                    Link(destination: URL(string: "https://vercel.com/dashboard")!) {
                        HStack(spacing: 4) {
                            Text("project.vercel.openLink")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                    }
                } else {
                    Text("project.vercel.empty.projectID")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func vercelStateChip(rawState: String) -> some View {
        let (label, tint) = vercelStateMetadata(for: rawState)
        Text(label)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background { Capsule().fill(tint) }
    }

    private func vercelStateMetadata(for rawState: String) -> (LocalizedStringKey, Color) {
        switch rawState.uppercased() {
        case "READY":    return ("project.vercel.state.ready", .green)
        case "BUILDING": return ("project.vercel.state.building", .orange)
        case "ERROR":    return ("project.vercel.state.error", .red)
        case "CANCELED": return ("project.vercel.state.canceled", .gray)
        case "QUEUED":   return ("project.vercel.state.queued", LiquidPalette.sky)
        default:         return ("project.vercel.state.unknown", .gray)
        }
    }

    @ViewBuilder
    private func vercelDeploymentRow(_ deployment: VercelDeployment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let sha = deployment.commitSHA, !sha.isEmpty {
                    Text(verbatim: String(sha.prefix(7)))
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                if let message = deployment.commitMessage, !message.isEmpty {
                    Text(verbatim: message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                Text(deployment.createdAt.formatted(.relative(presentation: .named)))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
                if let email = deployment.creatorEmail, !email.isEmpty {
                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)
                    Text(verbatim: email)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var lighthouseGrid: some View {
        let cells: [(LocalizedStringKey, Int?)] = [
            ("project.vercel.lighthouse.perf", lighthouseScore?.performance),
            ("project.vercel.lighthouse.a11y", lighthouseScore?.accessibility),
            ("project.vercel.lighthouse.bp",   lighthouseScore?.bestPractices),
            ("project.vercel.lighthouse.seo",  lighthouseScore?.seo),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(0..<cells.count, id: \.self) { idx in
                let cell = cells[idx]
                lighthouseCell(label: cell.0, value: cell.1)
            }
        }
    }

    @ViewBuilder
    private func lighthouseCell(label: LocalizedStringKey, value: Int?) -> some View {
        VStack(spacing: 4) {
            if let value {
                Text(verbatim: "\(value)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(lighthouseColor(for: value))
            } else if lighthouseLoading {
                ProgressView().controlSize(.mini)
            } else {
                Text(verbatim: "—")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private func lighthouseColor(for score: Int) -> Color {
        if score >= 90 { return .green }
        if score >= 50 { return .orange }
        return .red
    }

    // MARK: - GitHub section (v1.0-alpha.8)

    private var githubSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(LiquidPalette.aqua)
                    Text("project.github.section.title")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    if githubLoading {
                        ProgressView().controlSize(.mini)
                    }
                }

                if GitHubTokenStore.read() == nil {
                    Text("project.github.empty.token")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else if let repo = project.githubRepo, !repo.isEmpty {
                    if let stats = repoStats {
                        githubStatsRow(stats)
                    } else if githubLoading {
                        skeletonRow()
                    } else if let error = githubError {
                        Text(verbatim: error)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if !recentCommits.isEmpty {
                        Divider().background(.white.opacity(0.18))
                        Text("project.github.commits.title")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        VStack(spacing: 6) {
                            ForEach(recentCommits) { commit in
                                githubCommitRow(commit)
                            }
                        }
                    }

                    if let url = URL(string: "https://github.com/\(repo)") {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Text("project.github.openLink")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.aqua)
                        }
                    }
                } else {
                    Text("project.github.empty.repo")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func githubStatsRow(_ stats: GitHubRepoStats) -> some View {
        HStack(spacing: 14) {
            githubStatCell(icon: "star.fill", label: "project.github.stats.stars", value: "\(stats.stars)")
            githubStatCell(icon: "exclamationmark.circle.fill", label: "project.github.stats.issues", value: "\(stats.openIssues)")
            githubStatCell(
                icon: "clock.fill",
                label: "project.github.stats.lastPush",
                value: stats.lastPushedAt.formatted(.relative(presentation: .named))
            )
        }
    }

    @ViewBuilder
    private func githubStatCell(icon: String, label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(label)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Text(verbatim: value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func githubCommitRow(_ commit: GitHubCommit) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: String(commit.sha.prefix(7)))
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: commit.message)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !commit.authorName.isEmpty {
                        Text(verbatim: commit.authorName)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Text(commit.committedAt.formatted(.relative(presentation: .named)))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func skeletonRow() -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial).frame(width: 64, height: 14)
            RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial).frame(maxWidth: .infinity).frame(height: 14)
        }
    }

    // MARK: - Fetch lifecycle

    /// Hydrates the four UI slots from the cache without hitting the
    /// network. Runs synchronously on `.task` appear so the sheet
    /// renders cached data immediately while the background refresh
    /// fires.
    private func hydrateProjectHealth() async {
        let bundle = await ProjectHealthCache.shared.bundle(for: project.id)
        await MainActor.run {
            self.latestDeployment = bundle?.latestDeployment
            self.lighthouseScore = bundle?.lighthouse
            self.recentCommits = bundle?.recentCommits ?? []
            self.repoStats = bundle?.repoStats
        }
        if let bundle {
            await MainActor.run {
                MINDTelemetry.info("projectHealth.cache.hit", data: ["projectID": project.id.uuidString])
            }
            // Skip network fetch if cache is still fresh.
            if Date().timeIntervalSince(bundle.refreshedAt) < ProjectHealthCache.ttl {
                return
            }
        } else {
            await MainActor.run {
                MINDTelemetry.info("projectHealth.cache.miss", data: ["projectID": project.id.uuidString])
            }
        }
    }

    /// Fans out three parallel Tasks — Vercel, GitHub, Lighthouse.
    /// Each lands on its own clock and updates the cache through the
    /// keypath helper so a slow Lighthouse pull doesn't block the
    /// faster Vercel + GitHub rows. Soft-fail per provider.
    private func refreshProjectHealth() async {
        // ----- Vercel
        if let projectID = project.vercelProjectID, !projectID.isEmpty,
           VercelTokenStore.read() != nil {
            await MainActor.run { vercelLoading = true; vercelError = nil }
            do {
                let latest = try await VercelClient.shared.latest(projectID: projectID)
                await MainActor.run {
                    self.latestDeployment = latest
                    self.vercelLoading = false
                    MINDTelemetry.info("vercel.deployment.fetched",
                                       data: ["projectID": project.id.uuidString])
                }
                if let latest {
                    await ProjectHealthCache.shared.update(project.id, keyPath: \.latestDeployment, value: latest)
                }
            } catch {
                await MainActor.run {
                    self.vercelLoading = false
                    self.vercelError = String(describing: error)
                    MINDTelemetry.warning("vercel.deployment.fetch.failed",
                                          data: ["projectID": project.id.uuidString,
                                                 "error": String(describing: error)])
                }
            }
        }

        // ----- GitHub
        if let repo = project.githubRepo, !repo.isEmpty,
           GitHubTokenStore.read() != nil {
            await MainActor.run { githubLoading = true; githubError = nil }
            do {
                let commits = try await GitHubClient.shared.recentCommits(repo: repo, limit: 5)
                let stats = try await GitHubClient.shared.repoStats(repo: repo)
                await MainActor.run {
                    self.recentCommits = commits
                    self.repoStats = stats
                    self.githubLoading = false
                    MINDTelemetry.info("github.commits.fetched",
                                       data: ["projectID": project.id.uuidString,
                                              "count": "\(commits.count)"])
                }
                await ProjectHealthCache.shared.update(project.id, keyPath: \.recentCommits, value: commits)
                await ProjectHealthCache.shared.update(project.id, keyPath: \.repoStats, value: stats)
            } catch {
                await MainActor.run {
                    self.githubLoading = false
                    self.githubError = String(describing: error)
                    MINDTelemetry.warning("github.commits.fetch.failed",
                                          data: ["projectID": project.id.uuidString,
                                                 "error": String(describing: error)])
                }
            }
        }

        // ----- Lighthouse (Project host)
        if !project.host.isEmpty {
            await MainActor.run { lighthouseLoading = true }
            do {
                let score = try await LighthouseProbe.shared.score(for: project.host)
                await MainActor.run {
                    self.lighthouseScore = score
                    self.lighthouseLoading = false
                    MINDTelemetry.info("lighthouse.probe.completed",
                                       data: ["projectID": project.id.uuidString,
                                              "perf": "\(score.performance)"])
                    // v1.1.0 — Persist a `LighthouseSnapshot` row so
                    // the 30-day trend sparkline below this section
                    // has data to render. Soft-failing inside the
                    // store keeps the cockpit alive if SwiftData
                    // momentarily can't save.
                    LighthouseSnapshotStore.persist(
                        score: score,
                        projectID: project.id,
                        host: project.host
                    )
                }
                await ProjectHealthCache.shared.update(project.id, keyPath: \.lighthouse, value: score)
            } catch {
                await MainActor.run {
                    self.lighthouseLoading = false
                    MINDTelemetry.warning("lighthouse.probe.failed",
                                          data: ["projectID": project.id.uuidString,
                                                 "error": String(describing: error)])
                }
            }
        }
    }

    /// Local mirror of the ProjectCard helper so the colour vocabulary
    /// stays consistent across both surfaces without forcing a new
    /// public API in DesignSystem.
    private func healthDotColor(for status: HealthStatus) -> Color {
        switch status {
        case .online:   return .green
        case .degraded: return .orange
        case .error:    return .red
        case .offline:  return .red
        case .unknown:  return .gray
        }
    }

    @ViewBuilder
    private func overviewRow(
        icon: String,
        label: String,
        value: String,
        url: URL?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let url {
                    Link(destination: url) {
                        Text(verbatim: value)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(LiquidPalette.iris)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text(verbatim: value)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    // MARK: - Recent leads

    private var recentLeads: [Lead] {
        let all = project.leads ?? []
        return Array(LeadInboxSorter.sort(all, by: .dateDescending).prefix(5))
    }

    private var recentLeadsSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("project.detail.leads.recent")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    Text("\(project.leads?.count ?? 0)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if recentLeads.isEmpty {
                    Text("project.detail.leads.empty")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(recentLeads) { lead in
                            Button {
                                selectedLead = lead
                            } label: {
                                leadRow(lead)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func leadRow(_ lead: Lead) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: lead.contactName.isEmpty ? lead.contactEmail : lead.contactName)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(verbatim: lead.message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(lead.receivedAt.formatted(.relative(presentation: .named)))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Deliverables

    private var deliverablesSection: some View {
        let deliverables = (project.deliverables ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(6)
        return LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("project.detail.deliverables")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                if deliverables.isEmpty {
                    Text("project.detail.deliverables.empty")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(deliverables)) { deliverable in
                            HStack(spacing: 10) {
                                Image(systemName: Self.icon(for: deliverable.kindEnum))
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: deliverable.title)
                                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(deliverable.createdAt.formatted(.relative(presentation: .named)))
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func icon(for kind: DeliverableKind) -> String {
        switch kind {
        case .page:       return "doc.text.fill"
        case .screenshot: return "photo.fill"
        case .audit:      return "speedometer"
        case .invoice:    return "doc.richtext.fill"
        case .asset:      return "shippingbox.fill"
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(spacing: 12) {
                actionRow(
                    icon: "magnifyingglass",
                    tint: LiquidPalette.iris,
                    title: String(localized: "project.action.audit")
                ) {
                    isAuditing = true
                }
                actionRow(
                    icon: "tornado",
                    tint: LiquidPalette.aqua,
                    title: "Lancer un swarm SEO"
                ) {
                    isSwarming = true
                }

                // v1.0-alpha.10 — Repository-aware audit. Fires the
                // new probe directly against the project's GitHub
                // slug without the 13-probe URL flow. Only mounted
                // when the project has a `githubRepo` configured.
                if let repo = project.githubRepo, !repo.isEmpty {
                    actionRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        tint: LiquidPalette.lavender,
                        title: String(localized: "project.action.auditRepo"),
                        trailing: repoAuditRunning ? .spinner : .chevron,
                        enabled: !repoAuditRunning
                    ) {
                        Task { await runRepoAudit(repo: repo) }
                    }
                }

                // v1.0-alpha.9 — Live actions. Each is guarded so a
                // missing token / missing config soft-empties the row
                // rather than throwing an error sheet.
                if canRedeploy {
                    actionRow(
                        icon: "arrow.up.forward.app.fill",
                        tint: LiquidPalette.iris,
                        title: String(localized: "project.action.redeploy"),
                        trailing: redeployInFlight ? .spinner : .chevron,
                        enabled: !redeployInFlight
                    ) {
                        MINDTelemetry.info(
                            "vercel.redeploy.tapped",
                            data: ["projectID": project.id.uuidString]
                        )
                        showRedeployConfirm = true
                    }
                }

                if !project.host.isEmpty {
                    actionRow(
                        icon: "globe",
                        tint: LiquidPalette.aqua,
                        title: String(localized: "project.action.openSite")
                    ) {
                        if let url = URL(string: "https://\(project.host)") {
                            UIApplication.shared.open(url)
                            MINDTelemetry.info(
                                "project.openSite.tapped",
                                data: ["projectID": project.id.uuidString]
                            )
                        }
                    }
                }

                if let repo = project.githubRepo, !repo.isEmpty {
                    actionRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        tint: LiquidPalette.lavender,
                        title: String(localized: "project.action.openRepo")
                    ) {
                        if let url = URL(string: "https://github.com/\(repo)") {
                            UIApplication.shared.open(url)
                            MINDTelemetry.info(
                                "project.openRepo.tapped",
                                data: ["projectID": project.id.uuidString]
                            )
                        }
                    }
                }

                if let projectID = project.vercelProjectID, !projectID.isEmpty {
                    actionRow(
                        icon: "triangle.fill",
                        tint: LiquidPalette.iris,
                        title: String(localized: "project.action.openVercel")
                    ) {
                        if let url = URL(string: "https://vercel.com/dashboard") {
                            UIApplication.shared.open(url)
                            MINDTelemetry.info(
                                "project.openVercel.tapped",
                                data: ["projectID": project.id.uuidString]
                            )
                        }
                    }
                }

                actionRow(
                    icon: "square.and.arrow.up",
                    tint: LiquidPalette.aqua,
                    title: String(localized: "project.action.sharePortal")
                ) {
                    Task { await sharePortalFolder() }
                }

                actionRow(
                    icon: "tray.full.fill",
                    tint: LiquidPalette.aqua,
                    title: String(localized: "project.action.leads")
                ) {
                    showLeadsListSheet = true
                }
                actionRow(
                    icon: "archivebox.fill",
                    tint: .gray,
                    title: String(localized: "project.action.archive"),
                    enabled: project.lifecycleStageEnum != .archived
                ) {
                    showArchiveConfirm = true
                }
            }
            .padding(16)
        }
    }

    /// v1.0-alpha.9 — Gate for the "Redeploy to production" action.
    /// Requires a stored Vercel token + a project-side
    /// `vercelProjectID` + a `githubRepo` (the redeploy POST needs
    /// the git source). Hidden otherwise so we never present a
    /// button that will throw on tap.
    private var canRedeploy: Bool {
        guard VercelTokenStore.read() != nil else { return false }
        guard let pid = project.vercelProjectID, !pid.isEmpty else { return false }
        guard let repo = project.githubRepo, !repo.isEmpty else { return false }
        return true
    }

    /// Drives the redeploy flow end-to-end. Confirmation already fired
    /// (caller flipped the alert). Marks the row spinning, fires the
    /// POST, hops back to the main actor for haptics + toast + a 3s
    /// delayed re-pull of the latest deployment so the Vercel section
    /// updates to BUILDING without a manual refresh.
    private func runRedeploy() async {
        guard
            let projectID = project.vercelProjectID,
            !projectID.isEmpty,
            let repo = project.githubRepo,
            !repo.isEmpty
        else { return }
        await MainActor.run {
            redeployInFlight = true
            redeployToast = nil
        }
        do {
            let deployment = try await VercelClient.shared.redeploy(
                projectID: projectID,
                projectName: project.slug,
                githubRepo: repo,
                branch: "main"
            )
            await MainActor.run {
                latestDeployment = deployment
                redeployInFlight = false
                LiquidHaptics.success()
                redeployToast = ToastMessage(
                    text: String(localized: "project.action.redeploy.success.toast"),
                    tone: .success
                )
                MINDTelemetry.info(
                    "vercel.redeploy.success",
                    data: ["projectID": project.id.uuidString, "deploymentID": deployment.id]
                )
            }
            await ProjectHealthCache.shared.update(
                project.id,
                keyPath: \.latestDeployment,
                value: deployment
            )
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refreshProjectHealth()
            await MainActor.run {
                // Auto-dismiss the toast after the refresh completes.
                redeployToast = nil
            }
        } catch {
            await MainActor.run {
                redeployInFlight = false
                LiquidHaptics.warning()
                let format = String(localized: "project.action.redeploy.error.toast")
                redeployToast = ToastMessage(
                    text: String(format: format, String(describing: error)),
                    tone: .error
                )
                MINDTelemetry.warning(
                    "vercel.redeploy.failed",
                    data: [
                        "projectID": project.id.uuidString,
                        "error": String(describing: error),
                    ]
                )
            }
        }
    }

    /// v1.0-alpha.10 — Fires the new `RepositoryAuditProbe` directly
    /// for the project's GitHub slug, then presents the result inline
    /// via `RepoAuditDetailSheet`. Doesn't touch the URL audit
    /// pipeline — the consultant just wants the source-code grade.
    private func runRepoAudit(repo: String) async {
        await MainActor.run {
            repoAuditRunning = true
            repoAuditError = nil
        }
        let findings = await RepositoryAuditProbe.shared.run(repo: repo)
        await MainActor.run {
            repoAuditRunning = false
            repoAuditResult = findings
            LiquidHaptics.success()
        }
    }

    /// Finds the most recently written client portal under the
    /// per-project slug + presents the system share sheet. When
    /// nothing exists, falls back to a toast telling Mehdi to
    /// generate one from the audit.
    private func sharePortalFolder() async {
        let folder = ProjectPortalLocator.latestPortalFolder(for: project)
        await MainActor.run {
            if let folder {
                sharePortalURL = folder
                MINDTelemetry.info(
                    "project.sharePortal.opened",
                    data: ["projectID": project.id.uuidString]
                )
            } else {
                redeployToast = ToastMessage(
                    text: String(localized: "project.action.sharePortal.empty"),
                    tone: .info
                )
                MINDTelemetry.info(
                    "project.sharePortal.empty",
                    data: ["projectID": project.id.uuidString]
                )
            }
        }
    }

    /// v1.0-alpha.9 — Trailing accessory variants for `actionRow`. The
    /// stock `.chevron` keeps the v1.0-alpha.8 row chrome; `.spinner`
    /// flips the chevron to a `ProgressView` so an in-flight redeploy
    /// reads "busy" from the same row that triggered it.
    enum ActionRowTrailing {
        case chevron
        case spinner
    }

    @ViewBuilder
    private func actionRow(
        icon: String,
        tint: Color,
        title: String,
        trailing: ActionRowTrailing = .chevron,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            LiquidHaptics.select()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(verbatim: title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                switch trailing {
                case .chevron:
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.tertiary)
                case .spinner:
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .opacity(enabled ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Notes

    private var notesSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("project.detail.notes")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                TextEditor(text: $notesDraft)
                    .font(.system(.body, design: .rounded))
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .onChange(of: notesDraft) { _, newValue in
                        project.notes = newValue
                        try? context.save()
                    }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - ProjectLeadsListSheet

/// v1.0-alpha.3 — Full per-Project lead list (vs. the top-5 preview
/// on the detail sheet). Reuses LeadInboxSorter for consistency.
struct ProjectLeadsListSheet: View {
    let project: Project

    @State private var sortKey: LeadInboxSorter.SortKey = .dateDescending
    @State private var selectedLead: Lead?

    private var sortedLeads: [Lead] {
        LeadInboxSorter.sort(project.leads ?? [], by: sortKey)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("project.detail.leads.recent")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text(verbatim: project.name)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Picker(
                    String(localized: "lead.sort.label"),
                    selection: $sortKey
                ) {
                    Text(String(localized: "lead.sort.recent")).tag(LeadInboxSorter.SortKey.dateDescending)
                    Text(String(localized: "lead.sort.status")).tag(LeadInboxSorter.SortKey.statusPriority)
                }
                .pickerStyle(.segmented)
                if sortedLeads.isEmpty {
                    Text("project.detail.leads.empty")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(sortedLeads) { lead in
                            Button {
                                selectedLead = lead
                            } label: {
                                LiquidCard(cornerRadius: 16) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(verbatim: lead.contactName.isEmpty ? lead.contactEmail : lead.contactName)
                                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(verbatim: lead.message)
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        Text(lead.receivedAt.formatted(.relative(presentation: .named)))
                                            .font(.system(.caption2, design: .rounded))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(12)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .sheet(item: $selectedLead) { lead in
            LeadDetailSheet(lead: lead)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }
}

// MARK: - NewProjectSheet

/// v1.0-alpha.3 — Minimal "Nouveau projet" form. Captures the fields
/// the cockpit list needs immediately; v1.0-alpha.6 will replace
/// this with the full scaffolder wizard.
struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var githubRepo: String = ""
    @State private var vercelProjectID: String = ""
    @State private var stack: ProjectStack = .nextjs
    @State private var contractType: ProjectContractType = .oneshot
    @State private var mrr: String = ""
    @State private var oneShot: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "project.new.section.identity")) {
                    TextField(String(localized: "project.new.name"), text: $name)
                    TextField(String(localized: "project.new.host"), text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(String(localized: "project.new.repo"), text: $githubRepo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    // v1.0-alpha.9 — Optional Vercel Project ID
                    // (`prj_abc123`). Persists on the Project model
                    // so the new Redeploy + Vercel surfaces light up
                    // for fresh projects without a Settings detour.
                    TextField(String(localized: "project.new.vercelProjectID"), text: $vercelProjectID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }
                Section(String(localized: "project.new.section.stack")) {
                    Picker(String(localized: "project.new.stack"), selection: $stack) {
                        ForEach(ProjectStack.allCases, id: \.self) { value in
                            Text(verbatim: value.rawValue.capitalized).tag(value)
                        }
                    }
                }
                Section(String(localized: "project.new.section.revenue")) {
                    Picker(String(localized: "project.new.contract"), selection: $contractType) {
                        Text(String(localized: "project.contract.oneshot")).tag(ProjectContractType.oneshot)
                        Text(String(localized: "project.contract.retainer")).tag(ProjectContractType.retainer)
                    }
                    if contractType == .retainer {
                        TextField(String(localized: "project.new.mrr"), text: $mrr)
                            .keyboardType(.numberPad)
                    } else {
                        TextField(String(localized: "project.new.oneshot"), text: $oneShot)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle(Text("project.new.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "audit.button.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "project.new.save")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let project = Project(
            name: name.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            githubRepo: githubRepo.isEmpty ? nil : githubRepo,
            vercelProjectID: vercelProjectID.isEmpty ? nil : vercelProjectID,
            stack: stack,
            contractType: contractType,
            monthlyRecurringRevenueEUR: contractType == .retainer ? (Int(mrr) ?? 0) : 0,
            oneShotRevenueEUR: contractType == .oneshot ? (Int(oneShot) ?? 0) : 0
        )
        context.insert(project)
        try? context.save()
        MINDTelemetry.info(
            "project.new.created",
            data: [
                "projectID": project.id.uuidString,
                "stack": project.stack,
                "contractType": project.contractType,
            ]
        )
        dismiss()
    }
}

// MARK: - ToastMessage + ToastBanner

/// v1.0-alpha.9 — Tiny value type that drives the bottom-pinned
/// banner overlay used by the redeploy + share-portal flows. The
/// `tone` picks an accent + an SF Symbol so success / warning / info
/// reads consistently without a custom card per call site.
struct ToastMessage: Identifiable, Equatable {
    enum Tone: Equatable { case success, error, info }
    let id: UUID = UUID()
    let text: String
    let tone: Tone
}

/// Bottom-pinned banner. Liquid Glass card + iris tint, max-2 lines,
/// auto-disposed by the parent's `.animation(...)` modifier so we
/// don't need a timer here.
struct ToastBanner: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
            Text(verbatim: message.text)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
    }

    private var icon: String {
        switch message.tone {
        case .success: return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch message.tone {
        case .success: return .green
        case .error:   return .red
        case .info:    return LiquidPalette.iris
        }
    }
}

// MARK: - Portal share helpers

/// `URL.asIdentifiable` lets `.sheet(item:)` bind to an
/// `Optional<URL>` without rolling a custom wrapper at every call
/// site. The wrapper hashes on `absoluteString` so the same folder
/// URL re-presents the sheet idempotently.
struct IdentifiableURL: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }
}

extension Binding where Value == URL? {
    /// Binding adapter that maps `URL?` → `IdentifiableURL?` so
    /// `.sheet(item:)` can drive an activity-view-controller presenter.
    var asIdentifiable: Binding<IdentifiableURL?> {
        Binding<IdentifiableURL?>(
            get: { self.wrappedValue.map(IdentifiableURL.init) },
            set: { newValue in self.wrappedValue = newValue?.url }
        )
    }
}

/// v1.0-alpha.10 — Sheet driver wrapper for `RepositoryAuditFindings?`.
/// The findings type is value-only (no `Identifiable` conformance), so
/// we wrap with the `analyzedAt` timestamp as the stable id.
struct IdentifiableRepoAudit: Identifiable, Hashable {
    let findings: RepositoryAuditFindings
    var id: Date { findings.analyzedAt }

    static func == (lhs: IdentifiableRepoAudit, rhs: IdentifiableRepoAudit) -> Bool {
        lhs.findings.analyzedAt == rhs.findings.analyzedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(findings.analyzedAt)
    }
}

extension Binding where Value == RepositoryAuditFindings? {
    /// Binding adapter that maps `RepositoryAuditFindings?` →
    /// `IdentifiableRepoAudit?` so `.sheet(item:)` can drive the
    /// `RepoAuditDetailSheet` presenter.
    var asRepoAuditItem: Binding<IdentifiableRepoAudit?> {
        Binding<IdentifiableRepoAudit?>(
            get: { self.wrappedValue.map(IdentifiableRepoAudit.init) },
            set: { newValue in self.wrappedValue = newValue?.findings }
        )
    }
}

/// `UIActivityViewController` bridge — same shape as the
/// `PortalActivityView` in `PortalSuccessSheet.swift`, kept private
/// here so the ProjectDetail flow doesn't depend on that file's
/// internals.
struct ProjectPortalShareView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Locates the most recent on-disk client portal for a given Project.
/// `PortalWriter` writes to `Documents/client-portals/<slug>` so we
/// scan that directory for entries whose name starts with the
/// project's slug + sort by modification date desc.
enum ProjectPortalLocator {
    static func latestPortalFolder(for project: Project) -> URL? {
        let root = PortalWriter.defaultDestinationRoot()
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
            )
        else { return nil }
        let needle = project.slug.lowercased()
        // The portal folder slug embeds the project slug + a timestamp
        // suffix (e.g. `az-construction-2026-05-20-1430`). Match on
        // prefix + lowercased to dodge case-mismatch on the Docs root.
        let candidates = entries.filter { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasPrefix(needle)
        }
        let sorted = candidates.sorted { a, b in
            let amod = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let bmod = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return amod > bmod
        }
        return sorted.first
    }
}

