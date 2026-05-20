import SwiftUI
import SwiftData
import Charts
import CoreSpotlight
import AuditKit
import BootstrapKit
import DesignSystem
import GraphCore
import Intelligence
import ProjectHealthKit
import Settings
import OutreachKit
import SwarmKit

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

    /// v1.0-alpha.15 — `MINDTab` selection persists across window
    /// restores on Mac Catalyst (and iPad multitasking) via
    /// `@SceneStorage`. The raw string lives under the
    /// `MacSceneStorageKey.selectedTab` namespace; `selection`
    /// computes from the raw value with a nonmutating setter that
    /// writes back through the property wrapper. Existing call
    /// sites that read OR write `selection` keep working unchanged.
    @SceneStorage(MacSceneStorageKey.selectedTab) private var rawSelection: String = MINDTab.home.rawValue
    private var selection: MINDTab {
        get { MINDTab(rawValue: rawSelection) ?? .home }
        nonmutating set { rawSelection = newValue.rawValue }
    }
    private var selectionBinding: Binding<MINDTab> {
        Binding(
            get: { MINDTab(rawValue: rawSelection) ?? .home },
            set: { newValue in rawSelection = newValue.rawValue }
        )
    }
    @State private var selectedNode: Node?
    /// v1.0-alpha.11 — Drives the Bulk Import GitHub repos wizard.
    /// Settings's "Importer mes repos" CTA flips this true; the
    /// fullScreenCover renders `BulkImportSheet` over the cockpit.
    @State private var showBulkImport: Bool = false
    /// Sidebar visibility on regular-width layouts. SwiftUI manages it
    /// but binding lets us collapse the sidebar after the user picks
    /// a row on iPad portrait, where the auto behaviour can leave the
    /// sidebar covering half the screen.
    ///
    /// v1.0-alpha.15 — Persisted across window restores via
    /// `@SceneStorage` using the
    /// `MacSceneStorageKey.sidebarVisibility` namespace. The raw
    /// string is decoded back into `NavigationSplitViewVisibility`
    /// inside `columnVisibilityBinding`.
    @SceneStorage(MacSceneStorageKey.sidebarVisibility) private var rawColumnVisibility: String = "all"
    private var columnVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                switch rawColumnVisibility {
                case "doubleColumn": return .doubleColumn
                case "detailOnly":   return .detailOnly
                default:             return .all
                }
            },
            set: { newValue in
                switch newValue {
                case .doubleColumn: rawColumnVisibility = "doubleColumn"
                case .detailOnly:   rawColumnVisibility = "detailOnly"
                default:            rawColumnVisibility = "all"
                }
            }
        )
    }
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
            OnboardingView(
                onPresentBulkImport: { showBulkImport = true },
                onFinish: { onboardingDone = true }
            )
        }
        .sheet(isPresented: $showBulkImport) {
            BulkImportSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
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
            // v1.0-alpha.16 — `mind://leads` deep link fired by the
            // new Cockpit Lock Screen widget's `.accessoryRectangular`
            // + `.accessoryInline` families. Drops the user on Home
            // where the lead inbox card sits at the top of the scroll.
            if url.host?.lowercased() == "leads" {
                selection = .home
                MINDTelemetry.info("leads.deepLink.opened")
                return
            }
            // v1.0-alpha.14 — `mind://lead/<UUID>` deep link fired by
            // the lead-push tap path (NotificationService decorates,
            // MINDPushDelegate routes the tap, the AppDelegate posts
            // `.mindOpenLead`). The deep-link path is the second
            // routing channel so a user who taps a push from a Mail
            // preview lands on the right Lead too.
            if let leadID = PushDeepLink.parse(url) {
                selection = .home
                NotificationCenter.default.post(name: .mindOpenLead, object: leadID)
                MINDTelemetry.info(
                    "push.deepLink.opened",
                    data: ["leadID.prefix": String(leadID.uuidString.prefix(8))]
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
        .onReceive(NotificationCenter.default.publisher(for: .mindCommandAuditToolbar)) { _ in
            // v1.0-alpha.15 — Catalyst toolbar "New Audit" button.
            // Land on Home + fire the same `.mindCommandNewAudit`
            // channel HomeView is already listening on so the
            // existing audit-sheet path triggers without a special
            // toolbar branch.
            MINDTelemetry.info("mac.toolbar.audit.fired")
            selection = .home
            NotificationCenter.default.post(
                name: .mindCommandNewAudit,
                object: nil
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindCommandLeadInbox)) { _ in
            // v1.0-alpha.15 — Catalyst toolbar "Leads" button. Flip
            // back to Home; HomeView already auto-scrolls its lead
            // inbox card into view on `selection = .home`.
            MINDTelemetry.info("mac.toolbar.leads.fired")
            selection = .home
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindCommandBootstrap)) { _ in
            // v1.0-alpha.15 — Catalyst toolbar "Bootstrap" button.
            // Land on Home and surface the same telemetry breadcrumb
            // the menu-bar ⌘B shortcut emits; HomeView's bootstrap
            // card listener handles the actual sheet present.
            MINDTelemetry.info("mac.toolbar.bootstrap.fired")
            selection = .home
        }
        .onReceive(NotificationCenter.default.publisher(for: .mindCommandRefresh)) { _ in
            // v1.0-alpha.15 — Catalyst toolbar refresh button. Emits
            // a refresh breadcrumb; HomeView already runs the same
            // portfolio fan-out on its own pull-to-refresh, so the
            // toolbar surface piggybacks on that path via the
            // notification channel.
            MINDTelemetry.info("mac.toolbar.refresh.fired")
        }
        #if targetEnvironment(macCatalyst)
        // v1.0-alpha.15 — Mac Catalyst window toolbar. Four buttons
        // wired to the `MacToolbarAction` table: Lead inbox / New
        // audit / Bootstrap / Refresh. Each button posts on its
        // matching `Notification.Name.mindCommand*` channel, the
        // same channels the Stage Manager menu-bar entries already
        // post on, so the downstream listeners (HomeView,
        // RootView) react identically whether the user clicks the
        // toolbar or hits ⌘L / ⌘N / ⌘B / ⌘R.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ForEach(MacToolbarAction.allCases, id: \.self) { action in
                    Button {
                        LiquidHaptics.tap()
                        MINDTelemetry.info(
                            "mac.toolbar.tapped",
                            data: ["action": action.rawValue]
                        )
                        NotificationCenter.default.post(
                            name: action.notificationName,
                            object: nil
                        )
                    } label: {
                        Label(
                            String(localized: String.LocalizationValue(action.localizedKey)),
                            systemImage: action.systemImage
                        )
                    }
                    .help(Text(String(localized: String.LocalizationValue(action.localizedKey))))
                }
            }
        }
        #endif
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
                    selection: selectionBinding,
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
        NavigationSplitView(columnVisibility: columnVisibilityBinding) {
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
            SettingsView(onPresentBulkImport: { showBulkImport = true })
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
    @State private var isBootstrapping: Bool = false
    @State private var isSwarming: Bool = false
    @State private var selectedLead: Lead?
    @State private var selectedProject: Project?

    // v1.0-alpha.9 — Portfolio health rollup that drives the new KPI
    // bar in the greeting subtitle + the tap-through sheet. `nil`
    // until the first snapshot lands. Refreshes on `.task` + on
    // pull-to-refresh.
    @State private var portfolioHealth: PortfolioHealth?
    @State private var showPortfolioSheet: Bool = false

    // v1.0-alpha.13 — Velocity dashboard surface. Tapping the card
    // flips this true; the sheet renders `SalesVelocitySheet` with
    // the per-month MRR + cumulative leads + funnel distribution.
    @State private var showVelocitySheet: Bool = false

    // v1.0-alpha.13 — Dormant-project heuristic results. Populated
    // on `.task` so the dormant card only appears when at least one
    // active project has been quiet > 90 days. Mutating the
    // lifecycleStage from the row archives the project; "Garder
    // actif" touches lastActivityAt + drops it from the array.
    @State private var dormantProjects: [Project] = []

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
                portfolioKPIBar
                leadInboxCard
                velocityCard
                projectsCarouselCard
                if !dormantProjects.isEmpty {
                    dormantProjectsCard
                }
                pipelineSummaryCard
                bootstrapCard
                auditCardStack
            }
            .padding(20)
            .padding(.top, 40)
            .padding(.bottom, 120)
        }
        .refreshable {
            await refreshAllHealth(origin: "home.pulldown.refresh")
        }
        .task {
            // v1.0-alpha.9 — Pull the portfolio rollup from the cache
            // on first appear so the KPI bar lights up immediately
            // with whatever the per-Project sheets have already
            // persisted. Subsequent refreshes happen via the
            // pull-to-refresh gesture on the parent ScrollView.
            await loadPortfolioSnapshot()
            // v1.0-alpha.13 — Surface dormant projects so the
            // archive-suggestion card knows whether to render. The
            // heuristic itself is pure GraphCore math; the only
            // SwiftData touch happens here (reading `allProjects`).
            refreshDormantProjects()
        }
        .sheet(isPresented: $showPortfolioSheet) {
            PortfolioHealthSheet(
                projects: activeProjects,
                portfolioHealth: portfolioHealth
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showVelocitySheet) {
            SalesVelocitySheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
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
        .sheet(isPresented: $isBootstrapping) {
            BootstrapWizardSheet(onProjectCreated: { _ in
                // Route to the Projects tab where the new row lives.
                onOpenProjects()
            })
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
        // v1.0-alpha.14 — `MINDPushDelegate` (lead push tap) and
        // `RootView.onOpenURL` (`mind://lead/<UUID>` deep link) both
        // post `.mindOpenLead` with the Lead UUID as the object. We
        // resolve the UUID against the `allLeadsForFunnel` slice (which
        // already pulls every Lead regardless of status) so the sheet
        // can present even for leads outside the inbox's `.new` filter.
        .onReceive(
            NotificationCenter.default.publisher(for: .mindOpenLead)
        ) { notif in
            guard let leadID = notif.object as? UUID else {
                MINDTelemetry.warning(
                    "push.openLead.malformed",
                    data: ["object": String(describing: notif.object)]
                )
                return
            }
            if let match = allLeadsForFunnel.first(where: { $0.id == leadID }) {
                selectedLead = match
                MINDTelemetry.info(
                    "push.openLead.matched",
                    data: ["leadID.prefix": String(leadID.uuidString.prefix(8))]
                )
            } else {
                MINDTelemetry.warning(
                    "push.openLead.notFound",
                    data: ["leadID.prefix": String(leadID.uuidString.prefix(8))]
                )
            }
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

    // MARK: - Portfolio KPI bar (v1.0-alpha.9)

    /// Single-row strip of four cells: leads, active projects, builds
    /// in flight, errors in the last 24h. Tap → opens the per-project
    /// `PortfolioHealthSheet`.
    private var portfolioKPIBar: some View {
        Button {
            LiquidHaptics.select()
            showPortfolioSheet = true
            MINDTelemetry.info("portfolio.sheet.opened",
                               data: [
                                "builds": "\(portfolioHealth?.buildsInProgress ?? 0)",
                                "errors24h": "\(portfolioHealth?.buildErrors24h ?? 0)",
                               ])
        } label: {
            HStack(spacing: 10) {
                kpiCell(icon: "tray.fill",
                        tint: LiquidPalette.iris,
                        value: "\(newLeads.count)",
                        label: "leads")
                kpiCell(icon: "shippingbox.fill",
                        tint: LiquidPalette.aqua,
                        value: "\(ProjectMRR.activeCount(in: allProjects))",
                        label: "actifs")
                kpiCell(icon: "hammer.fill",
                        tint: .orange,
                        value: "\(portfolioHealth?.buildsInProgress ?? 0)",
                        label: "builds",
                        accessibilityKey: "home.kpi.builds.inProgress")
                kpiCell(icon: "exclamationmark.triangle.fill",
                        tint: .red,
                        value: "\(portfolioHealth?.buildErrors24h ?? 0)",
                        label: "erreurs",
                        accessibilityKey: "home.kpi.builds.errors24h")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                            .opacity(0.5)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("portfolio.sheet.title"))
    }

    @ViewBuilder
    private func kpiCell(
        icon: String,
        tint: Color,
        value: String,
        label: String,
        accessibilityKey: String? = nil
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(tint)
                Text(verbatim: value)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            Text(verbatim: label)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    // MARK: - Velocity card (v1.0-alpha.13)

    /// Compact horizontal strip with three sparkline-style mini-
    /// charts (MRR / Leads / Conversion). Tap → opens the full-
    /// screen `SalesVelocitySheet`. Sits between the lead inbox and
    /// the projects carousel so it earns the second-row real-estate
    /// the cockpit "what's hot?" mental model expects.
    private var velocityCard: some View {
        let mrr = SalesVelocityCalculator.monthlyMRRHistory(
            projects: allProjects,
            months: 12
        )
        let leads = SalesVelocityCalculator.weeklyLeads(
            leads: newLeads + allLeadsForFunnel,
            weeks: 12
        )
        let conversion = SalesVelocityCalculator.conversionRate(
            leads: allLeadsForFunnel,
            lastWeeks: 4
        )

        return LiquidCard(cornerRadius: 22) {
            Button {
                LiquidHaptics.select()
                showVelocitySheet = true
                MINDTelemetry.info(
                    "velocity.opened",
                    data: [
                        "mrrPoints": String(mrr.count),
                        "leadPoints": String(leads.count),
                        "conversion": String(format: "%.2f", conversion),
                    ]
                )
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(LiquidPalette.aqua.opacity(0.18))
                                .frame(width: 32, height: 32)
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.aqua)
                        }
                        Text("home.velocity.title")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 12) {
                        miniMRRChart(points: mrr)
                        miniLeadsChart(points: leads)
                        miniConversionGauge(value: conversion)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Pull every Lead (regardless of status) so the velocity card's
    /// weeklyLeads bucket lands the entire history, not just the
    /// `.new` slice the inbox card consumes. The funnel + conversion
    /// readouts need every status to be accurate.
    @Query private var allLeadsForFunnel: [Lead]

    @ViewBuilder
    private func miniMRRChart(points: [MRRPoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("home.velocity.chart.mrr")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Chart(points) { point in
                LineMark(
                    x: .value("Month", point.monthStart),
                    y: .value("MRR", point.mrrEUR)
                )
                .foregroundStyle(LiquidPalette.iris)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 36)
            Text(verbatim: "€\(points.last?.mrrEUR ?? 0)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(LiquidPalette.iris)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func miniLeadsChart(points: [WeeklyLeadPoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("home.velocity.chart.leads")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Chart(points) { point in
                BarMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Leads", point.count)
                )
                .foregroundStyle(LiquidPalette.aqua)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 36)
            Text(verbatim: "\(points.reduce(0) { $0 + $1.count })")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(LiquidPalette.aqua)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func miniConversionGauge(value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("home.velocity.chart.conversion")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ZStack {
                Circle()
                    .stroke(LiquidPalette.lavender.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0, min(1, value)))
                    .stroke(
                        LiquidPalette.lavender,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 36, height: 36)
            Text(verbatim: "\(Int((max(0, min(1, value))) * 100))%")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(LiquidPalette.lavender)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dormant projects card (v1.0-alpha.13)

    /// Non-intrusive archive-suggestion card. Renders only when at
    /// least one active project has been quiet for > 90 days. Each
    /// row exposes two CTAs: "Archiver" flips lifecycleStage to
    /// `.archived` + emits `project.archived.auto`; "Garder actif"
    /// touches `lastActivityAt` to now + emits
    /// `project.archive.dismissed`.
    private var dormantProjectsCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    let format = String(localized: "home.dormant.title.format")
                    Text(verbatim: String(format: format, dormantProjects.count))
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                Text("home.dormant.subtitle")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    ForEach(dormantProjects) { project in
                        dormantRow(project)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func dormantRow(_ project: Project) -> some View {
        let accent = Color(hex: project.primaryColor) ?? LiquidPalette.iris
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(verbatim: project.name)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            Text(verbatim: ProjectLifecycleHeuristic.reason(
                for: project,
                lastPush: nil,
                asOf: .now
            ))
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            HStack(spacing: 8) {
                Button {
                    LiquidHaptics.tap()
                    archiveProject(project)
                } label: {
                    Text("home.dormant.action.archive")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.92))
                        }
                }
                .buttonStyle(.plain)
                Button {
                    LiquidHaptics.tap()
                    keepActive(project)
                } label: {
                    Text("home.dormant.action.keepActive")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(LiquidPalette.iris.opacity(0.2), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.05))
        }
    }

    /// Refreshes the dormant-projects snapshot from the live
    /// `allProjects` array. Called on `.task` once + after every
    /// row CTA so the card visibility stays consistent.
    private func refreshDormantProjects() {
        let candidates = ProjectLifecycleHeuristic.dormantProjects(
            allProjects,
            thresholdDays: ProjectLifecycleHeuristic.defaultThresholdDays
        )
        dormantProjects = candidates
        if !candidates.isEmpty {
            MINDTelemetry.info(
                "project.archive.suggested",
                data: [
                    "count": String(candidates.count),
                ]
            )
        }
    }

    private func archiveProject(_ project: Project) {
        project.lifecycleStageEnum = .archived
        project.touchActivity()
        try? context.save()
        MINDTelemetry.info(
            "project.archived.auto",
            data: [
                "projectID": project.id.uuidString,
                "projectName": project.name,
            ]
        )
        refreshDormantProjects()
    }

    private func keepActive(_ project: Project) {
        project.touchActivity()
        try? context.save()
        MINDTelemetry.info(
            "project.archive.dismissed",
            data: [
                "projectID": project.id.uuidString,
                "projectName": project.name,
            ]
        )
        refreshDormantProjects()
    }

    // MARK: - Refresh fan-out (v1.0-alpha.9)

    /// Loads the current `ProjectHealthCache`-backed snapshot. No
    /// network calls — `refreshAllHealth(origin:)` does that.
    private func loadPortfolioSnapshot() async {
        let identities = makeIdentities()
        let snapshot = await PortfolioHealthAggregator.shared.snapshot(for: identities)
        await MainActor.run {
            portfolioHealth = snapshot
            MINDTelemetry.info("portfolio.health.snapshot",
                               data: [
                                "projects": "\(snapshot.totalActiveProjects)",
                                "builds": "\(snapshot.buildsInProgress)",
                                "errors24h": "\(snapshot.buildErrors24h)",
                               ])
        }
    }

    /// Pull-to-refresh handler. Heart-beat haptic on start + success
    /// haptic on finish. Emits a `home.pulldown.refresh` breadcrumb
    /// so we can see how often Mehdi pulls vs. just waiting.
    private func refreshAllHealth(origin: String) async {
        await MainActor.run {
            LiquidHaptics.tap()
            MINDTelemetry.info(origin)
        }
        let identities = makeIdentities()
        let snapshot = await PortfolioHealthAggregator.shared.refreshAndSnapshot(for: identities)
        await MainActor.run {
            portfolioHealth = snapshot
            LiquidHaptics.success()
        }
    }

    /// Build the Sendable identities array the aggregator consumes.
    /// Runs on the MainActor because `Project` is @Model-bound.
    private func makeIdentities() -> [ProjectIdentity] {
        activeProjects.map { project in
            ProjectIdentity(
                id: project.id,
                vercelProjectID: project.vercelProjectID,
                githubRepo: project.githubRepo,
                host: project.host
            )
        }
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

    // MARK: - Bootstrap card (v1.0-alpha.6)

    /// Rocket-iconned card that opens the `BootstrapWizardSheet`.
    /// Sits between the pipeline summary and the audit card stack
    /// because it's a "start a new project" action that mirrors the
    /// "+" CTA on ProjectsView but lives one tap closer than that
    /// tab switch.
    private var bootstrapCard: some View {
        LiquidCard(cornerRadius: 22) {
            Button {
                LiquidHaptics.select()
                isBootstrapping = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.iris.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("home.bootstrap.title")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("home.bootstrap.subtitle")
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
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

    // MARK: - SEO Swarm card (v1.0-alpha.7)

    /// v1.0-alpha.7 — Single-tap entry to the SEO Swarm Orchestrator.
    /// Sits below the audit card stack because the swarm is the
    /// heavier operation (batch of N pages) — placing it last avoids
    /// pushing the more-common Audit / Battle / Reply actions
    /// off-screen on iPhone portrait.
    private var swarmCard: some View {
        LiquidCard(cornerRadius: 22) {
            Button {
                LiquidHaptics.select()
                isSwarming = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.aqua.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: "tornado")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.aqua)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("home.swarm.title")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("home.swarm.subtitle")
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted when `mind://comparison` is opened. HomeView listens
    /// for it to flip its comparison sheet bool.
    static let mindOpenComparison = Notification.Name("mind.openComparison")

    /// v1.0-alpha.14 — Posted when a lead push is tapped OR when the
    /// `mind://lead/<UUID>` deep link is opened. HomeView listens for
    /// it, looks the matching `Lead` up via its `@Query` slice, and
    /// presents `LeadDetailSheet`.
    static let mindOpenLead = Notification.Name("mind.openLead")
}

// MARK: - Push deep-link parser (v1.0-alpha.14)

/// Pure URL → UUID parser for the `mind://lead/<UUID>` deep link
/// spawned by the APNs push tap routing. Lives at file scope so
/// `PushDeepLinkTests` can exercise every branch without standing up
/// SwiftUI / SwiftData.
enum PushDeepLink {
    /// Returns the lead UUID encoded in `url`, or nil if the URL
    /// doesn't match the `mind://lead/<UUID>` shape. Tolerates a
    /// trailing slash + uppercase host (`mind://LEAD/<id>/`) so
    /// share-sheet copies don't silently swallow the tap.
    static func parse(_ url: URL) -> UUID? {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "mind",
            url.host?.lowercased() == "lead"
        else { return nil }
        // pathComponents includes a leading "/" entry; drop it so the
        // last segment is the UUID candidate.
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let last = segments.last else { return nil }
        return UUID(uuidString: last)
    }
}

// MARK: - PortfolioHealthSheet (v1.0-alpha.9)

/// Per-project status table reached from the HomeView KPI bar tap.
/// Pure presentation — reads `PortfolioHealth` from the parent and
/// fetches the per-project bundle lazily from `ProjectHealthCache` so
/// we don't burn extra API calls on open.
struct PortfolioHealthSheet: View {
    let projects: [Project]
    let portfolioHealth: PortfolioHealth?

    @State private var rows: [ProjectHealthRow] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if rows.isEmpty {
                    LiquidCard(cornerRadius: 18) {
                        Text("portfolio.sheet.empty")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(rows) { row in
                            healthRow(row)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .task {
            await hydrate()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("portfolio.sheet.title")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            if let health = portfolioHealth {
                Text(verbatim: subtitle(for: health))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(for h: PortfolioHealth) -> String {
        let builds = h.buildsInProgress
        let errors = h.buildErrors24h
        let total = h.totalActiveProjects
        return "\(total) projets · \(builds) builds en cours · \(errors) erreurs (24h)"
    }

    @ViewBuilder
    private func healthRow(_ row: ProjectHealthRow) -> some View {
        LiquidCard(cornerRadius: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(row.tint)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.name)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(verbatim: row.host)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(verbatim: row.stateLabel.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background { Capsule().fill(row.tint.opacity(0.95)) }
            }
            .padding(12)
        }
    }

    private func hydrate() async {
        let cache = ProjectHealthCache.shared
        var built: [ProjectHealthRow] = []
        for project in projects {
            let bundle = await cache.bundle(for: project.id)
            let state = bundle?.latestDeployment?.state.uppercased() ?? "UNKNOWN"
            built.append(ProjectHealthRow(
                id: project.id,
                name: project.name,
                host: project.host,
                stateLabel: ProjectHealthRow.shortLabel(for: state),
                tint: ProjectHealthRow.tint(for: state)
            ))
        }
        await MainActor.run {
            self.rows = built
        }
    }
}

/// Sendable view-model row used by `PortfolioHealthSheet`. Co-located
/// here because it's a private surface — promoting it to GraphCore
/// would inflate the public API for one sheet's worth of plumbing.
struct ProjectHealthRow: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let host: String
    let stateLabel: String
    let tint: Color

    static func shortLabel(for state: String) -> String {
        switch state {
        case "READY":    return "Ready"
        case "BUILDING": return "Build"
        case "QUEUED":   return "Queue"
        case "ERROR":    return "Error"
        case "CANCELED": return "Cancel"
        default:         return "—"
        }
    }

    static func tint(for state: String) -> Color {
        switch state {
        case "READY":    return .green
        case "BUILDING", "QUEUED": return .orange
        case "ERROR":    return .red
        case "CANCELED": return .gray
        default:         return .gray
        }
    }
}
