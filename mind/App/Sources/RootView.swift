import SwiftUI
import SwiftData
import CoreSpotlight
import AuditKit
import DesignSystem
import GraphCore
import Intelligence
import Settings
import OutreachKit

/// v1.0-alpha.3 — Cockpit Studio. Four tabs:
/// Home (Aujourd'hui lead inbox + Projets actifs + Pipeline +
/// Audit), Clients (now Projects), Pipeline (kanban), Settings.
enum MINDTab: String, Hashable {
    case home
    case clients
    case pipeline
    case settings
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Query private var allNodes: [Node]

    @State private var selection: MINDTab = .home
    @State private var selectedNode: Node?
    /// Sidebar visibility on regular-width layouts. SwiftUI manages it
    /// but binding lets us collapse the sidebar after the user picks
    /// a row on iPad portrait, where the auto behaviour can leave the
    /// sidebar covering half the screen.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Flipped to `true` by OnboardingView's final "Start" button on
    /// first launch. Persisted in standard UserDefaults (not the app
    /// group) because no extension needs to know; only this view
    /// reads it. Once true, the cover never re-appears.
    @AppStorage("mind.onboarding.completed") private var onboardingDone: Bool = false

    var body: some View {
        Group {
            if hSizeClass == .regular {
                regularBody
            } else {
                compactBody
            }
        }
        .sheet(item: $selectedNode) { node in
            NodeDetailView(node: node)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingDone },
            set: { newValue in
                if !newValue { onboardingDone = true }
            }
        )) {
            OnboardingView {
                onboardingDone = true
            }
        }
        .onAppear {
            SpotlightIndexer.indexAll(allNodes)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard
                let idString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                let nodeID = UUID(uuidString: idString),
                let match = allNodes.first(where: { $0.id == nodeID })
            else { return }
            selectedNode = match
        }
        .onOpenURL { url in
            guard let scheme = url.scheme, scheme.lowercased() == "mind" else { return }
            if url.host?.lowercased() == "pipeline" {
                selection = .pipeline
                MINDTelemetry.info("pipeline.deepLink.opened")
                return
            }
            if url.host?.lowercased() == "comparison" {
                selection = .home
                MINDTelemetry.info("comparison.deepLink.opened")
                NotificationCenter.default.post(
                    name: .mindOpenComparison,
                    object: nil
                )
                return
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindCommandSelectTab)) { notif in
            guard let raw = notif.userInfo?["tab"] as? String,
                  let tab = MINDTab(rawValue: raw) else {
                MINDTelemetry.warning(
                    "command.selectTab.malformed",
                    data: ["raw": notif.userInfo?["tab"] as? String ?? "nil"]
                )
                return
            }
            MINDTelemetry.info("command.selectTab.fired", data: ["tab": raw])
            selection = tab
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindCommandNewAudit)) { _ in
            MINDTelemetry.info("command.newAudit.fired")
            selection = .home
        }
    }

    // MARK: - Compact (iPhone portrait)

    private var compactBody: some View {
        ZStack {
            LiquidBackground()
                .ignoresSafeArea()

            content
                .transition(.opacity)
                .animation(LiquidMetrics.spring, value: selection)

            VStack {
                Spacer()
                LiquidTabBar(
                    selection: $selection,
                    leading: [
                        LiquidTab(icon: "house.fill", tag: MINDTab.home),
                        LiquidTab(icon: "person.text.rectangle.fill", tag: MINDTab.clients),
                    ],
                    trailing: [
                        LiquidTab(icon: "square.stack.3d.up.fill", tag: MINDTab.pipeline),
                        LiquidTab(icon: "gearshape.fill", tag: MINDTab.settings),
                    ],
                    onCapture: { selection = .home }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Regular (iPad / iPhone Plus landscape)

    private var regularBody: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
                .background {
                    LiquidBackground()
                        .ignoresSafeArea()
                }
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        } detail: {
            NavigationStack {
                ZStack {
                    LiquidBackground()
                        .ignoresSafeArea()
                    content
                        .transition(.opacity)
                        .animation(LiquidMetrics.spring, value: selection)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: sidebarBinding) {
                Section {
                    ForEach(MINDTab.allCasesOrdered, id: \.self) { tab in
                        NavigationLink(value: tab) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(tab.tint.opacity(0.18))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: tab.icon)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(tab.tint)
                                }
                                Text(tab.title)
                                    .font(.system(.body, design: .rounded, weight: .medium))
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(LiquidGradient.primary)
                                .frame(width: 28, height: 28)
                            Image(systemName: "brain.head.profile")
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("MIND")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .textCase(nil)
                    .padding(.vertical, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.sidebar)
            .navigationTitle("MIND")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)

            sidebarFooter
        }
    }

    /// Footer pinned at the bottom of the iPad sidebar with live counts.
    private var sidebarFooter: some View {
        let clientCount = allNodes.filter { $0.kindRaw == "client" }.count
        let auditCount  = allNodes.filter { $0.kindRaw == "audit"  }.count

        return HStack(spacing: 14) {
            sidebarStatPill(value: clientCount, label: "Clients", tint: .orange)
            sidebarStatPill(value: auditCount,  label: "Audits",  tint: .purple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Rectangle()
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                        .opacity(0.4)
                }
        }
    }

    @ViewBuilder
    private func sidebarStatPill(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var sidebarBinding: Binding<MINDTab?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    LiquidHaptics.tap()
                    selection = newValue
                }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .home:
            HomeView(
                onOpenPipeline: { selection = .pipeline },
                onOpenProjects: { selection = .clients }
            )
        case .clients:
            // v1.0-alpha.3 — Tab routes to ProjectsView (project-
            // backed). Legacy ClientsView (Node-backed) stays
            // compiled for the daemon-resurrection edge case but
            // no longer owns the tab.
            ProjectsView()
        case .pipeline:
            PipelineView()
        case .settings:
            SettingsView()
        }
    }
}

extension MINDTab {
    static var allCasesOrdered: [MINDTab] {
        [.home, .clients, .pipeline, .settings]
    }

    var title: String {
        switch self {
        case .home:     return "Home"
        case .clients:  return "Projets"
        case .pipeline: return "Pipeline"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home:     return "house.fill"
        case .clients:  return "person.text.rectangle.fill"
        case .pipeline: return "square.stack.3d.up.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home:     return LiquidPalette.iris
        case .clients:  return .orange
        case .pipeline: return .orange
        case .settings: return .gray
        }
    }
}

// MARK: - HomeView

/// v1.0-alpha.3 — Aujourd'hui-first cockpit home. From top:
/// 1. Greeting (FR, time-based) + subtitle with lead/project/MRR
///    counts.
/// 2. "Boîte leads" — `@Query var newLeads: [Lead]` filtered by
///    `status == "new"`, sorted desc, capped at 10.
/// 3. "Projets actifs" — horizontal carousel of active projects.
/// 4. Pipeline summary card (legacy, kept).
/// 5. Audit card stack (legacy, kept).
private struct HomeView: View {
    let onOpenPipeline: () -> Void
    let onOpenProjects: () -> Void

    init(
        onOpenPipeline: @escaping () -> Void = {},
        onOpenProjects: @escaping () -> Void = {}
    ) {
        self.onOpenPipeline = onOpenPipeline
        self.onOpenProjects = onOpenProjects
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Node.updatedAt, order: .reverse) private var allNodes: [Node]
    // v1.0-alpha.3 — Pull every Lead with status == "new" so the new
    // HomeView "Aujourd'hui" inbox lands populated. We sort the slice
    // through `LeadInboxSorter` rather than via the @Query sort
    // descriptor so the same projection used in tests + the per-
    // project sheet drives the iPhone card.
    @Query(filter: #Predicate<Lead> { $0.status == "new" })
    private var newLeads: [Lead]
    @Query private var allProjects: [Project]

    @State private var isAuditing: Bool = false
    @State private var isBattling: Bool = false
    @State private var isOutreaching: Bool = false
    @State private var isComparing: Bool = false
    @State private var selectedLead: Lead?
    @State private var selectedProject: Project?

    private var sortedNewLeads: [Lead] {
        Array(LeadInboxSorter.sort(newLeads, by: .dateDescending).prefix(10))
    }

    private var activeProjects: [Project] {
        ProjectSorter.sort(
            allProjects.filter {
                $0.lifecycleStageEnum == .active ||
                $0.lifecycleStageEnum == .maintenance
            },
            by: .activityDescending
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greeting
                leadInboxCard
                projectsCarouselCard
                pipelineSummaryCard
                auditCardStack
            }
            .padding(20)
            .padding(.top, 40)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $isAuditing) {
            AuditSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isBattling) {
            BattleSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isOutreaching) {
            OutreachSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isComparing) {
            ComparisonSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLead) { lead in
            LeadDetailSheet(lead: lead)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailSheet(project: project)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .onAppear {
            MINDTelemetry.info(
                "home.leads.opened",
                data: ["count": String(sortedNewLeads.count)]
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .mindOpenComparison)
        ) { _ in
            isComparing = true
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .mindCommandNewAudit)
        ) { _ in
            isAuditing = true
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Bonjour Mehdi 👋")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text(verbatim: subtitle)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.85)
                .lineLimit(3)
        }
    }

    private var subtitle: String {
        let leadCount = newLeads.count
        let projectCount = ProjectMRR.activeCount(in: allProjects)
        let mrr = ProjectMRR.total(of: allProjects)
        let format = String(localized: "home.greeting.subtitle.format")
        return String(format: format, leadCount, projectCount, mrr)
    }

    // MARK: - Lead inbox card

    private var leadInboxCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.iris.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "tray.full.fill")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    Text("home.aujourdhui.title")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if !sortedNewLeads.isEmpty {
                        Text("\(sortedNewLeads.count)")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background {
                                Capsule().fill(LiquidPalette.iris.opacity(0.92))
                            }
                    }
                }
                if sortedNewLeads.isEmpty {
                    leadInboxEmptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(sortedNewLeads) { lead in
                            leadRow(lead)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var leadInboxEmptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.open.fill")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(LiquidPalette.iris.opacity(0.6))
                .symbolEffect(.pulse.byLayer, options: .repeating)
            VStack(alignment: .leading, spacing: 2) {
                Text("home.leads.empty.title")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("home.leads.empty.detail")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func leadRow(_ lead: Lead) -> some View {
        Button {
            selectedLead = lead
        } label: {
            HStack(spacing: 10) {
                avatarCircle(for: lead)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: lead.contactName.isEmpty ? lead.contactEmail : lead.contactName)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let projectName = lead.project?.name {
                            Circle()
                                .fill(projectAccent(for: lead))
                                .frame(width: 6, height: 6)
                            Text(verbatim: projectName)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text(verbatim: lead.message)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Text(lead.receivedAt.formatted(.relative(presentation: .named)))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button {
                LiquidHaptics.select()
                selectedLead = lead
            } label: {
                Label(
                    String(localized: "lead.action.respond"),
                    systemImage: "arrowshape.turn.up.left.fill"
                )
            }
            .tint(LiquidPalette.iris)
        }
        .contextMenu {
            Button {
                applyStatus(.qualified, on: lead)
            } label: {
                Label(String(localized: "lead.action.qualified"), systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                applyStatus(.spam, on: lead)
            } label: {
                Label(String(localized: "lead.action.spam"), systemImage: "trash.slash")
            }
        }
    }

    private func avatarCircle(for lead: Lead) -> some View {
        ZStack {
            Circle()
                .fill(projectAccent(for: lead).opacity(0.20))
                .frame(width: 32, height: 32)
            Text(LeadDetailSheet.initials(of: lead.contactName.isEmpty ? lead.contactEmail : lead.contactName))
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(projectAccent(for: lead))
        }
    }

    private func projectAccent(for lead: Lead) -> Color {
        if let hex = lead.project?.primaryColor, let color = Color(hex: hex) {
            return color
        }
        return LiquidPalette.iris
    }

    private func applyStatus(_ status: LeadStatus, on lead: Lead) {
        let from = lead.status
        lead.statusEnum = status
        lead.project?.touchActivity()
        try? context.save()
        MINDTelemetry.info(
            "lead.status.changed",
            data: [
                "leadID": lead.id.uuidString,
                "from": from,
                "to": status.rawValue,
            ]
        )
    }

    // MARK: - Projects carousel

    private var projectsCarouselCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.aqua.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "shippingbox.fill")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.aqua)
                    }
                    Text("home.projects.title")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        onOpenProjects()
                    } label: {
                        HStack(spacing: 2) {
                            Text("\(activeProjects.count)")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if activeProjects.isEmpty {
                    Text("home.projects.empty")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(activeProjects) { project in
                                Button {
                                    LiquidHaptics.select()
                                    selectedProject = project
                                } label: {
                                    miniProjectCard(project)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func miniProjectCard(_ project: Project) -> some View {
        let accent = Color(hex: project.primaryColor) ?? LiquidPalette.iris
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(verbatim: project.name)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Text(verbatim: project.host)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            HStack {
                Text(verbatim: mrrLabel(for: project))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background { Capsule().fill(accent.opacity(0.92)) }
                Spacer()
                Text(verbatim: stackShort(for: project))
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background { Capsule().fill(accent.opacity(0.14)) }
            }
        }
        .padding(12)
        .frame(width: 200, height: 130, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(accent.opacity(0.20), lineWidth: 1)
                }
        }
    }

    private func mrrLabel(for project: Project) -> String {
        if project.contractTypeEnum == .retainer {
            return ProjectMRR.formatEUR(project.monthlyRecurringRevenueEUR)
        }
        let format = String(localized: "project.list.oneshot.format")
        return String(format: format, project.oneShotRevenueEUR)
    }

    private func stackShort(for project: Project) -> String {
        switch project.stackEnum {
        case .nextjs:     return "Next"
        case .wordpress:  return "WP"
        case .shopify:    return "Shop"
        case .staticSite: return "Static"
        case .other:      return "Custom"
        }
    }

    // MARK: - Pipeline summary card (kept from v1.0-alpha.1)

    private var clients: [Node] { allNodes.filter { $0.kindRaw == "client" } }

    private var pipelineSummaryCard: some View {
        let buckets = HomeView.pipelineCounts(in: clients)
        let totalNonTerminal = buckets.prospect + buckets.contacted + buckets.qualified + buckets.audit + buckets.pitch

        return LiquidCard(cornerRadius: 22) {
            Button {
                LiquidHaptics.select()
                onOpenPipeline()
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(verbatim: "Pipeline")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    if clients.isEmpty {
                        Text(verbatim: "Aucun client placé sur le kanban.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                pipelinePill(count: buckets.prospect,  label: "Prospect",  tint: LiquidPalette.sky)
                                pipelinePill(count: buckets.contacted, label: "Contacted", tint: LiquidPalette.aqua)
                                pipelinePill(count: buckets.qualified, label: "Qualified", tint: LiquidPalette.lavender)
                                pipelinePill(count: buckets.audit,     label: "Audit",     tint: .purple)
                                pipelinePill(count: buckets.pitch,     label: "Pitch",     tint: .orange)
                                pipelinePill(count: buckets.won,       label: "Won",       tint: LiquidPalette.iris)
                            }
                        }
                        Text(verbatim: "\(totalNonTerminal) in flight · \(buckets.won) won")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func pipelinePill(count: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(verbatim: label)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                }
        }
    }

    /// Pure helper aggregating client-Node pipeline stages.
    static func pipelineCounts(in clients: [Node]) -> PipelineBuckets {
        var buckets = PipelineBuckets()
        for client in clients {
            switch client.pipelineStage {
            case .none, .some(.prospect): buckets.prospect += 1
            case .some(.contacted):       buckets.contacted += 1
            case .some(.qualified):       buckets.qualified += 1
            case .some(.audit):           buckets.audit += 1
            case .some(.pitch):           buckets.pitch += 1
            case .some(.won):             buckets.won += 1
            case .some(.lost):            buckets.lost += 1
            }
        }
        return buckets
    }

    struct PipelineBuckets: Equatable {
        var prospect: Int = 0
        var contacted: Int = 0
        var qualified: Int = 0
        var audit: Int = 0
        var pitch: Int = 0
        var won: Int = 0
        var lost: Int = 0
    }

    // MARK: - Audit card stack (kept)

    private var auditCardStack: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(spacing: 0) {
                auditRow(
                    icon: "magnifyingglass",
                    iconTint: LiquidPalette.iris,
                    title: "Lance un audit",
                    subtitle: "Probes Performance, SEO, Sécurité, UX, Stack — synthèse IA, ROI, Quick Wins.",
                    action: { isAuditing = true }
                )
                Divider().background(LiquidPalette.iris.opacity(0.18))
                auditRow(
                    icon: "bolt.horizontal.fill",
                    iconTint: LiquidPalette.aqua,
                    title: "Battle Mode",
                    subtitle: "Compare un client face à 3 concurrents en parallèle.",
                    action: { isBattling = true }
                )
                Divider().background(LiquidPalette.iris.opacity(0.18))
                auditRow(
                    icon: "envelope.badge.shield.half.filled",
                    iconTint: LiquidPalette.iris,
                    title: "Reply assistant",
                    subtitle: "Génère 5 variantes de réponse personnalisées à partir du contexte audit.",
                    action: { isOutreaching = true }
                )
                Divider().background(LiquidPalette.iris.opacity(0.18))
                auditRow(
                    icon: "square.split.2x1",
                    iconTint: LiquidPalette.iris,
                    title: "Comparer mes audits",
                    subtitle: "Multi-target — compare deux audits côte-à-côte depuis l'archive.",
                    action: { isComparing = true }
                )
            }
        }
    }

    @ViewBuilder
    private func auditRow(
        icon: String,
        iconTint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconTint.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(iconTint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.85)
                        .lineLimit(2)
                    Text(verbatim: subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted when `mind://comparison` is opened. HomeView listens
    /// for it to flip its comparison sheet bool.
    static let mindOpenComparison = Notification.Name("mind.openComparison")
}
