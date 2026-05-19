import SwiftUI
import SwiftData
import CoreSpotlight
import AuditKit
import DesignSystem
import FocusKit
import GraphCore
import Notes
import Chat
import Settings
import Capture

// Settings module exports MINDPreferences which we re-use here.

enum MINDTab: Hashable {
    case home
    case notes
    case clients
    case settings
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Query private var allNodes: [Node]

    @State private var selection: MINDTab = .home
    @State private var isCapturing: Bool = false
    @State private var selectedNode: Node?
    /// Sidebar visibility on regular-width layouts. SwiftUI manages it
    /// but binding lets us collapse the sidebar after the user picks
    /// a row on iPad portrait, where the auto behaviour can leave the
    /// sidebar covering half the screen.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Flipped to `true` by OnboardingView's final "Start" button on
    /// first launch. Persisted in standard UserDefaults (not the app
    /// group) because the widget doesn't need to know; only this view
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
        .sheet(isPresented: $isCapturing) {
            QuickCaptureSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
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
            // the user adds nodes from the widget or App Intents while the
            // app wasn't running.
            SpotlightIndexer.indexAll(allNodes)
        }
        // Spotlight deep link. When the user taps a MIND row in iOS
        // Spotlight, the system hands us a userActivity carrying the
        // Node's UUID under CSSearchableItemActivityIdentifier. We look
        // it up in SwiftData and open the same sheet as a tap from
        // NotesView would.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard
                let idString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                let nodeID = UUID(uuidString: idString),
                let match = allNodes.first(where: { $0.id == nodeID })
            else { return }
            selectedNode = match
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
                        LiquidTab(icon: "doc.text.fill", tag: MINDTab.notes),
                    ],
                    trailing: [
                        LiquidTab(icon: "person.text.rectangle.fill", tag: MINDTab.clients),
                        LiquidTab(icon: "gearshape.fill", tag: MINDTab.settings),
                    ],
                    onCapture: { isCapturing = true }
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
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            LiquidHaptics.select()
                            isCapturing = true
                        } label: {
                            Label("Quick capture", systemImage: "plus.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                        .accessibilityLabel("Quick capture")
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// Liquid Glass sidebar — 4 destinations + a section header that
    /// doubles as the app's wordmark + a footer with live graph stats
    /// so the user has a knowledge-health view at a glance.
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
                                        .font(.system(size: 14, weight: .semibold))
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
                                .font(.system(size: 13, weight: .semibold))
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
    /// the user captures a new node or finishes an audit.
    private var sidebarFooter: some View {
        let noteCount  = allNodes.filter { $0.kindRaw == "note" || $0.kindRaw == "capture" }.count
        let clientCount = allNodes.filter { $0.kindRaw == "client" }.count
        let auditCount = allNodes.filter { $0.kindRaw == "audit" }.count

        return HStack(spacing: 14) {
            sidebarStatPill(value: noteCount, label: "Notes", tint: LiquidPalette.iris)
            sidebarStatPill(value: clientCount, label: "Clients", tint: .orange)
            sidebarStatPill(value: auditCount, label: "Audits", tint: .purple)
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
            HomeView()
        case .notes:
            NotesView { node in
                selectedNode = node
            }
        case .clients:
            ClientsView()
        case .settings:
            SettingsView()
        }
    }
}

extension MINDTab {
    /// Stable ordering used by the regular-width sidebar so the
    /// destinations always appear in the same sequence the iPhone tab
    /// bar uses, top-to-bottom: Home, Notes, Clients, Settings.
    static var allCasesOrdered: [MINDTab] {
        [.home, .notes, .clients, .settings]
    }

    var title: String {
        switch self {
        case .home:     return "Home"
        case .notes:    return "Notes"
        case .clients:  return "Clients"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home:     return "house.fill"
        case .notes:    return "doc.text.fill"
        case .clients:  return "person.text.rectangle.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home:     return LiquidPalette.iris
        case .notes:    return LiquidPalette.iris
        case .clients:  return .orange
        case .settings: return .gray
        }
    }
}

private struct HomeView: View {
    @Query(sort: \Node.updatedAt, order: .reverse) private var allNodes: [Node]
    @Query private var focusSessions: [FocusSessionRecord]
    @State private var focus = FocusController.shared
    @State private var prefs = MINDPreferences.shared
    @State private var isAuditing: Bool = false
    @State private var isChatting: Bool = false
    @State private var selectedClient: Node?
    @State private var selectedNote: Node?
    @State private var showFocusHistory: Bool = false
    @State private var showTasks: Bool = false
    @State private var showAmbient: Bool = false
    @State private var showHabits: Bool = false
    @State private var showJournal: Bool = false
    @State private var showGoals: Bool = false
    @State private var showSearch: Bool = false

    private var habitsTodayCount: Int {
        HabitsView.checkedTodayCount(in: allNodes)
    }

    private var openGoalsCount: Int {
        allNodes.filter { $0.kindRaw == "goal" && GoalsView.progress(of: $0) < 100 }.count
    }

    private var openTaskCount: Int {
        allNodes.filter { $0.kindRaw == "task" && $0.completedAt == nil }.count
    }

    private var defaultFocusDuration: TimeInterval {
        TimeInterval(prefs.focusDurationMinutes) * 60
    }

    /// Focus sessions completed within the last 7 days, used by the
    /// "Focus cette semaine" card under the Deep Focus timer.
    private var thisWeekSessions: [FocusSessionRecord] {
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 3600)
        return focusSessions.filter { $0.completedAt >= cutoff }
    }

    private var thisWeekTotalSeconds: Double {
        thisWeekSessions.reduce(0) { $0 + $1.actualDurationSeconds }
    }

    private var noteCount: Int {
        allNodes.filter { $0.kindRaw == "note" }.count
    }

    private var captureCount: Int {
        allNodes.filter { $0.kindRaw == "capture" }.count
    }

    private var recentCaptures: [Node] {
        allNodes
            .filter { $0.kindRaw == "capture" || $0.kindRaw == "note" }
            .prefix(3)
            .map { $0 }
    }

    /// Top 5 clients to surface in the "Reprendre" carousel, ranked by
    /// most-recently-opened, falling back to creation date when the user
    /// hasn't opened a client yet.
    private var resumableClients: [Node] {
        allNodes
            .filter { $0.kindRaw == "client" }
            .sorted { lhs, rhs in
                let l = lhs.lastAccessedAt ?? lhs.createdAt
                let r = rhs.lastAccessedAt ?? rhs.createdAt
                return l > r
            }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                greeting

                quickSearchPill

                if !resumableClients.isEmpty {
                    ResumeCarousel(clients: resumableClients) { client in
                        selectedClient = client
                    }
                }

                deepFocusCard

                if !thisWeekSessions.isEmpty {
                    focusWeekCard
                }

                tasksCard

                lifeModulesRow

                auditCard

                askMindCard

                if allNodes.isEmpty {
                    welcomeEmptyState
                } else {
                    statsCard

                    if !recentCaptures.isEmpty {
                        recentSection
                    }
                }
            }
            .padding(20)
            .padding(.top, 40)
            .padding(.bottom, 120)
        }
        .sheet(item: $selectedClient) { client in
            NodeDetailView(node: client)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showFocusHistory) {
            FocusHistoryView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showTasks) {
            TasksView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $showAmbient) {
            AmbientView()
        }
        .sheet(isPresented: $showHabits) {
            HabitsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showJournal) {
            JournalView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showGoals) {
            GoalsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $isAuditing) {
            AuditSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $isChatting) {
            ChatView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSearch) {
            // Reuse the full-featured NotesView. Its search field auto-
            // focuses on appearance when reached via this entry point,
            // so the user can start typing immediately. Tapping a result
            // routes through `selectedNote`, then opens NodeDetailView
            // — same flow as the Notes tab.
            NotesView { node in
                selectedNote = node
                showSearch = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $selectedNote) { node in
            NodeDetailView(node: node)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var askMindCard: some View {
        LiquidCard(cornerRadius: 22) {
            Button {
                isChatting = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.aqua.opacity(0.30))
                            .frame(width: 44, height: 44)
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask MIND")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Pose une question à ton graphe.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var auditCard: some View {
        LiquidCard(cornerRadius: 22) {
            Button {
                isAuditing = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.iris.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audit client")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Du domaine au pitch en quelques minutes.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Self.timeBasedGreeting), Mehdi 👋")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                Text(Self.timeBasedSubtitle)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showAmbient = true
            } label: {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .padding(10)
                    .background {
                        Circle().fill(LiquidPalette.lavender.opacity(0.4))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ambient mode")
        }
    }

    /// One-tap entry into the semantic search sheet from anywhere on
    /// Home. Faster than tab-switching to Notes and tapping the search
    /// field there. Shows a hint count ("82 nodes searchable") so the
    /// user sees the corpus they're searching against.
    private var quickSearchPill: some View {
        Button {
            LiquidHaptics.tap()
            showSearch = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                Text("Cherche dans ton graphe…")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if !allNodes.isEmpty {
                    Text("\(allNodes.count)")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            Capsule().fill(.white.opacity(0.4))
                        }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search the graph")
    }

    private var deepFocusCard: some View {
        LiquidCard {
            VStack(spacing: 16) {
                Text(focus.isRunning ? "In focus" : "Deep Focus")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)

                focusTimer

                if focus.isRunning {
                    // success → three-pulse "done" that signals the
                    // session is being wrapped up. Feels rewarding.
                    LiquidButton(
                        title: "End focus",
                        systemImage: "stop.fill",
                        haptic: .success
                    ) {
                        focus.end()
                    }
                } else {
                    // select → medium thump that says "I'm committing,
                    // don't disturb me". Heavier than a normal tap.
                    LiquidButton(
                        title: "Start Focus",
                        systemImage: "drop.fill",
                        haptic: .select
                    ) {
                        focus.start(
                            intention: "Deep Focus",
                            duration: defaultFocusDuration
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .animation(LiquidMetrics.spring, value: focus.isRunning)
        }
    }

    @ViewBuilder
    private var focusTimer: some View {
        if let session = focus.session, session.endDate > .now {
            Text(timerInterval: .now...session.endDate, countsDown: true)
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
        } else {
            Text(Self.format(seconds: defaultFocusDuration))
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private static func format(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var lifeModulesRow: some View {
        HStack(spacing: 10) {
            lifeModuleTile(
                icon: "repeat.circle.fill",
                title: "Habits",
                tint: .orange,
                badge: habitsTodayCount > 0 ? "\(habitsTodayCount)✓" : nil
            ) { showHabits = true }

            lifeModuleTile(
                icon: "book.closed.fill",
                title: "Journal",
                tint: LiquidPalette.iris,
                badge: nil
            ) { showJournal = true }

            lifeModuleTile(
                icon: "target",
                title: "Goals",
                tint: .purple,
                badge: openGoalsCount > 0 ? "\(openGoalsCount)" : nil
            ) { showGoals = true }
        }
    }

    private func lifeModuleTile(
        icon: String,
        title: String,
        tint: Color,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        LiquidCard(cornerRadius: 18) {
            Button(action: action) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let badge {
                        Text(badge)
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                    } else {
                        Text(" ")
                            .font(.system(.caption2, design: .rounded))
                    }
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var tasksCard: some View {
        LiquidCard(cornerRadius: 22) {
            Button {
                showTasks = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(.green.opacity(0.20))
                            .frame(width: 44, height: 44)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tasks")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(openTaskCount == 0
                             ? "Capture ce qui reste à faire."
                             : "\(openTaskCount) à faire")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if openTaskCount > 0 {
                        Text("\(openTaskCount)")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                            .contentTransition(.numericText())
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var focusWeekCard: some View {
        LiquidCard(cornerRadius: 18) {
            Button {
                showFocusHistory = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.iris.opacity(0.22))
                            .frame(width: 40, height: 40)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Focus cette semaine")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(focusWeekSummary)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(thisWeekSessions.count)")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LiquidPalette.iris)
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var focusWeekSummary: String {
        let totalMinutes = Int((thisWeekTotalSeconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", minutes)) sur 7 jours"
        }
        return "\(minutes) min sur 7 jours"
    }

    private var welcomeEmptyState: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LiquidGradient.primary)
                            .frame(width: 40, height: 40)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Bienvenue dans MIND")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Text("Ton second cerveau démarre vide.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 12) {
                    onboardingHint(
                        icon: "drop.fill",
                        title: "Capture",
                        detail: "Tap le bouton + en bas pour saisir ta première pensée."
                    )
                    onboardingHint(
                        icon: "magnifyingglass",
                        title: "Audit client",
                        detail: "Du domaine au pitch en 2 minutes — pour qualifier un prospect."
                    )
                    onboardingHint(
                        icon: "brain.head.profile",
                        title: "Deep Focus",
                        detail: "Démarre une session focus, suis-la en Live Activity."
                    )
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func onboardingHint(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(LiquidPalette.lavender.opacity(0.5))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statsCard: some View {
        LiquidCard(cornerRadius: 20) {
            HStack(spacing: 0) {
                statColumn(value: noteCount, label: "Notes")
                divider
                statColumn(value: captureCount, label: "Captures")
                divider
                statColumn(value: allNodes.count, label: "Total")
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func statColumn(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(LiquidPalette.iris)
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(width: 1, height: 28)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent thoughts".uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 4)

            ForEach(recentCaptures) { node in
                LiquidCard(cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(node.title)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .lineLimit(2)
                        if !node.content.isEmpty {
                            Text(node.content)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(node.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private static var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        case 18..<23: return "Good evening"
        default:      return "Still up"
        }
    }

    private static var timeBasedSubtitle: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Stay soft. Stay focused."
        case 12..<18: return "Keep moving. One thought at a time."
        case 18..<23: return "Wind down. Capture what mattered."
        default:      return "Your brain stays on, but you should rest soon."
        }
    }
}
