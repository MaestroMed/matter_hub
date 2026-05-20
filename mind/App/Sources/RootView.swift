import SwiftUI
import SwiftData
import CoreSpotlight
import AuditKit
import DesignSystem
import GraphCore
import Intelligence
import Settings
import OutreachKit

/// v1.0-alpha.1 — Cockpit Studio pivot. Stripped down to the four
/// tabs the freelance studio cockpit ships against today: Home (Top
/// leads + Pipeline summary + Audit), Clients (client list), Pipeline
/// (kanban), Settings (API keys, sync, invoice identity). Everything
/// from the pre-pivot "second brain" era (Notes, Graph, Capture,
/// Focus, Health, Reminders, Calendar, Chat, Daily/Weekly digests,
/// Ambient, Goals, Habits, Journal) has been removed alongside the
/// modules that produced it.
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
            // iPad (and iPhone Plus landscape) get a proper two-column
            // NavigationSplitView so the sidebar is always visible and
            // the central pane has more breathing room. iPhone portrait
            // keeps the Liquid Glass tab bar that defines the brand.
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
        // First-launch onboarding. `isPresented` is bound to !onboardingDone
        // so the cover opens automatically the very first time RootView
        // renders, and dismisses the moment the user hits "Start".
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
            // Backfill the Spotlight index every launch. CSSearchableIndex
            // dedupes by uniqueIdentifier, so re-indexing existing rows is
            // a no-op overwrite — cheap, and keeps us correct even after
            // the user adds nodes from App Intents while the app wasn't
            // running.
            SpotlightIndexer.indexAll(allNodes)
        }
        // Spotlight deep link. When the user taps a MIND row in iOS
        // Spotlight, the system hands us a userActivity carrying the
        // Node's UUID under CSSearchableItemActivityIdentifier.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard
                let idString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                let nodeID = UUID(uuidString: idString),
                let match = allNodes.first(where: { $0.id == nodeID })
            else { return }
            selectedNode = match
        }
        // v1.0-alpha.1 — Cockpit deep-link surface narrowed to two
        // routes: `mind://pipeline` lands on the kanban, and
        // `mind://comparison` lands on Home + posts the comparison-
        // sheet notification HomeView listens for.
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
        // v0.24.1 — Stage Manager / Mac Catalyst keyboard shortcuts.
        // `StageManagerCommands` (mounted on `WindowGroup` in
        // `MINDApp`) posts on these names whenever the user picks the
        // matching menu item or hits the key equivalent. RootView is
        // the natural owner of `selection`, so the tab-switch
        // listener lives here. The ⌘N "New Audit" listener flips the
        // selection to .home AND lets HomeView's own `.onReceive`
        // observer flip its `isAuditing` sheet bool, so the audit
        // form actually presents.
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
            // Land the user on Home (where the audit sheet is hosted)
            // before HomeView flips its own bool — otherwise the user
            // could be on Pipeline / Settings when ⌘N fires and the
            // sheet would present-then-vanish as soon as selection
            // moved.
            MINDTelemetry.info("command.newAudit.fired")
            selection = .home
        }
    }

    // MARK: - Compact (iPhone portrait, the brand-defining layout)

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

    /// Liquid Glass sidebar — 4 destinations + a section header that
    /// doubles as the app's wordmark + a footer with live counts so
    /// the user has a cockpit-health view at a glance.
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
    /// Read straight from the @Query so the numbers update the moment
    /// the user finishes an audit or adds a client.
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

    /// Bridges the optional-Tab selection NavigationSplitView wants
    /// (nil = nothing selected on cold start) with our non-optional
    /// `@State selection`. We default back to `.home` if the user
    /// somehow lands on nil.
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
            HomeView(onOpenPipeline: { selection = .pipeline })
        case .clients:
            ClientsView()
        case .pipeline:
            PipelineView()
        case .settings:
            SettingsView()
        }
    }
}

extension MINDTab {
    /// Stable ordering used by the regular-width sidebar.
    static var allCasesOrdered: [MINDTab] {
        [.home, .clients, .pipeline, .settings]
    }

    var title: String {
        switch self {
        case .home:     return "Home"
        case .clients:  return "Clients"
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

/// Cockpit Numelite home: greeting + audit card stack + pipeline
/// summary + top leads.
private struct HomeView: View {
    /// Closure forwarded from `RootView` so the pipeline summary card
    /// on Home can route the user straight into the Pipeline Kanban
    /// tab.
    let onOpenPipeline: () -> Void

    init(onOpenPipeline: @escaping () -> Void = {}) {
        self.onOpenPipeline = onOpenPipeline
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Node.updatedAt, order: .reverse) private var allNodes: [Node]

    @State private var isAuditing: Bool = false
    @State private var isBattling: Bool = false
    @State private var isOutreaching: Bool = false
    @State private var isComparing: Bool = false
    @State private var selectedClient: Node?

    private var clients: [Node] {
        allNodes.filter { $0.kindRaw == "client" }
    }

    private var topLeads: [(node: Node, score: LeadScore)] {
        return clients
            .map { ($0, LeadScorer.heuristic(node: $0)) }
            .sorted { $0.1.total > $1.1.total }
            .prefix(3)
            .map { ($0.0, $0.1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greeting

                if clients.isEmpty {
                    emptyStateCard
                } else {
                    topLeadsCard
                }

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
        .sheet(item: $selectedClient) { client in
            NodeDetailView(node: client)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .mindOpenComparison)
        ) { _ in
            isComparing = true
        }
        // v0.24.1 — Bridges the ⌘N keyboard shortcut posted by
        // `StageManagerCommands` into the audit-sheet bool. RootView
        // already flipped `selection` to `.home` so this card is on
        // screen by the time the sheet presents.
        .onReceive(
            NotificationCenter.default.publisher(for: .mindCommandNewAudit)
        ) { _ in
            isAuditing = true
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(Self.timeBasedGreeting), Mehdi 👋")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text(verbatim: Self.timeBasedSubtitle)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.85)
                .lineLimit(3)
        }
    }

    private static var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Bonjour"
        case 12..<18: return "Bel après-midi"
        case 18..<23: return "Bonsoir"
        default:      return "Salut"
        }
    }

    private static var timeBasedSubtitle: String {
        "Pilote tes sites, tes leads et tes factures depuis un seul endroit."
    }

    // MARK: - Empty state

    private var emptyStateCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.iris.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "sparkles")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Bienvenue dans ton cockpit Numelite")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(verbatim: "Lance un premier audit sur un de tes sites clients pour amorcer le cockpit.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Top leads card

    private var topLeadsCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.iris.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Text(verbatim: "🔥")
                            .font(.system(.subheadline, design: .rounded))
                    }
                    Text(verbatim: "Top leads")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(topLeads.count)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if topLeads.isEmpty {
                    Text(verbatim: "Aucun lead pour le moment.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(topLeads, id: \.node.id) { entry in
                            topLeadRow(entry.node, score: entry.score)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func topLeadRow(_ client: Node, score: LeadScore) -> some View {
        Button {
            selectedClient = client
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if let host = Self.topLeadHost(of: client) {
                        Text(host)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(score.total)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LiquidPalette.iris)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(LiquidPalette.iris.opacity(0.16))
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private static func topLeadHost(of node: Node) -> String? {
        guard let url = URL(string: node.content),
              let host = url.host(percentEncoded: false) else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - Pipeline summary card

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

    /// Pure helper aggregating client-Node pipeline stages into a flat
    /// per-stage count tuple. Nil pipelineStage rolls into Prospect.
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

    // MARK: - Audit card stack

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
