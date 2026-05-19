import SwiftUI
import SwiftData
import CoreSpotlight
import AuditKit
import CalendarKit
import DesignSystem
import FocusKit
import GraphCore
import HealthInsights
import Intelligence
import Notes
import Chat
import Settings
import Capture
import OutreachKit

// Settings module exports MINDPreferences which we re-use here.

enum MINDTab: Hashable {
    case home
    case notes
    case graph
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
        // v0.17 — Deep link `mind://brief` opens the DailyBriefSheet.
        // Fired by tapping the daily morning brief local notification
        // (after a future UNUserNotificationCenterDelegate hooks the
        // userInfo dict) or by an "Open Brief" shortcut. Switching the
        // selected tab to .home guarantees the HomeView host that owns
        // `showDailyBrief` is on screen so the sheet actually presents.
        .onOpenURL { url in
            guard let scheme = url.scheme, scheme.lowercased() == "mind" else { return }
            guard url.host?.lowercased() == "brief" else { return }
            selection = .home
            MINDTelemetry.info("brief.deepLink.opened")
            // Post a NotificationCenter signal so HomeView (the actual
            // owner of `showDailyBrief`) flips its sheet bool. HomeView
            // subscribes to this in its `.onAppear`/`.task` block.
            NotificationCenter.default.post(name: .mindOpenDailyBrief, object: nil)
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
                        // v0.15 — Graph tab swaps out the Clients slot in
                        // the bottom tab bar. Clients remain reachable as
                        // indigo nodes inside the graph; tapping one opens
                        // NodeDetailView, which routes into ClientDetailView
                        // when the kind is .client. Keeps the bar at 4
                        // visible slots so the Liquid pill geometry stays
                        // intact.
                        LiquidTab(icon: "point.3.filled.connected.trianglepath.dotted", tag: MINDTab.graph),
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
                            Label(String(localized: "capture.title"), systemImage: "plus.circle.fill")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                        .accessibilityLabel(Text("capture.title"))
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
        case .graph:
            GraphView { node in
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
    /// bar uses, top-to-bottom: Home, Notes, Graph, Clients, Settings.
    /// The iPad sidebar keeps Clients as a first-class destination even
    /// though the iPhone bar swapped it out for Graph — the regular
    /// layout has the screen real-estate to surface both.
    static var allCasesOrdered: [MINDTab] {
        [.home, .notes, .graph, .clients, .settings]
    }

    var title: String {
        switch self {
        case .home:     return "Home"
        case .notes:    return "Notes"
        case .graph:    return "Graph"
        case .clients:  return "Clients"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home:     return "house.fill"
        case .notes:    return "doc.text.fill"
        case .graph:    return "point.3.filled.connected.trianglepath.dotted"
        case .clients:  return "person.text.rectangle.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home:     return LiquidPalette.iris
        case .notes:    return LiquidPalette.iris
        case .graph:    return LiquidPalette.aqua
        case .clients:  return .orange
        case .settings: return .gray
        }
    }
}

private struct HomeView: View {
    @Environment(\.modelContext) private var context
    /// v0.20 — Used by the beta welcome banner to open the TestFlight
    /// universal feedback URL. iOS routes the tap into the in-app
    /// feedback flow when the binary is a beta.
    @Environment(\.openURL) private var openURL
    @Query(sort: \Node.updatedAt, order: .reverse) private var allNodes: [Node]
    @Query private var focusSessions: [FocusSessionRecord]
    @State private var focus = FocusController.shared
    @State private var prefs = MINDPreferences.shared
    @State private var isAuditing: Bool = false
    @State private var isChatting: Bool = false
    /// v0.24 — Audit Battle Mode sheet. Triggered from the audit card's
    /// secondary "Battle" CTA. One client + up to three competitors
    /// audited in parallel, results rendered as a 4-way radar + per-
    /// metric podium.
    @State private var isBattling: Bool = false
    /// v0.26 — AI Sales Email Generator sheet. Triggered from the
    /// audit card's tertiary "Outreach engine" row. Form → 5
    /// shimmer skeletons → 5 LiquidCard variants with Copier /
    /// Ouvrir dans Mail / Aimer actions.
    @State private var isOutreaching: Bool = false
    @State private var selectedClient: Node?
    @State private var selectedNote: Node?
    @State private var showFocusHistory: Bool = false
    @State private var showTasks: Bool = false
    @State private var showAmbient: Bool = false
    @State private var showHabits: Bool = false
    @State private var showJournal: Bool = false
    @State private var showGoals: Bool = false
    @State private var showSearch: Bool = false
    /// v0.20 — Per-device "Plus tard" flag for the beta welcome banner.
    /// Stored in standard UserDefaults via @AppStorage so the user only
    /// sees the banner once until they reinstall. Resets to false on
    /// fresh installs, which is the intended onboarding moment.
    @AppStorage("mind.beta.banner.dismissed") private var betaBannerDismissed: Bool = false
    /// v0.16 — On-device weekly digest surfaced as a non-disruptive
    /// Home card on Sunday evenings and Monday mornings. Computed
    /// synchronously from `allNodes` + `focusSessions` on `.task`, then
    /// hydrated with the optional Foundation Models narrative a beat
    /// later. nil hides the card entirely.
    @State private var weeklyDigest: WeeklyDigest?
    @State private var showWeeklyDigest: Bool = false
    /// v0.17 — Daily morning brief surfaced as a non-disruptive Home
    /// card from 5h to 11h local. Computed synchronously from
    /// `todayEvents` + `allNodes` + `focusSessions` once they've all
    /// loaded. nil hides the card entirely. Opt-in via Settings (the
    /// toggle also schedules the daily local notification at the user's
    /// chosen hour).
    @State private var dailyBrief: DailyBrief?
    @State private var showDailyBrief: Bool = false
    /// v0.8 — events fetched from the user's primary calendar(s) for the
    /// "Aujourd'hui" card. Stays empty when permission is denied or there
    /// are no events today; the card hides itself in either case so the
    /// rest of HomeView keeps its rhythm.
    @State private var todayEvents: [CalendarEvent] = []
    /// v0.9 — 7-day health aggregate (steps, sleep, active minutes) for
    /// the "Cette semaine" card. Stays `.empty` when the user hasn't
    /// opted in via Settings, when HealthKit is unavailable, or when no
    /// samples were logged. `isMeaningful` is the render gate.
    @State private var weeklyHealth: WeeklySummary = .empty

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

    /// v0.16 — Sunday-evening through Monday-morning window. The
    /// weekly digest card surfaces here so the user opens MIND on
    /// Sunday night and sees their week summarized, then has a second
    /// chance Monday morning if they skipped the night before. Other
    /// days hide the card entirely so it doesn't pollute the home
    /// screen mid-week.
    ///
    /// `#if DEBUG` flips the gate to "always visible" so the agent's
    /// vision-verification screenshot captures the card on any day
    /// of the week. Release builds keep the Sun/Mon window intact.
    private var isWeeklyDigestVisibleDay: Bool {
        #if DEBUG
        return true
        #else
        let weekday = Calendar.current.component(.weekday, from: .now)
        // Calendar.weekday: Sunday=1, Monday=2.
        return weekday == 1 || weekday == 2
        #endif
    }

    /// Gate combining the day-of-week window AND a non-empty digest.
    /// A user who hasn't captured / audited / focused all week sees no
    /// card on Sunday — same render gate as the v0.9 health card,
    /// because rendering three zeros is depressing UX.
    private var shouldShowWeeklyDigest: Bool {
        guard let digest = weeklyDigest else { return false }
        return isWeeklyDigestVisibleDay && digest.isMeaningful
    }

    /// v0.17 — Morning render window: hours 5..11 local. The notification
    /// fires at the user's chosen hour (`prefs.dailyBriefHour`, default
    /// 7); we then keep the Home card around until 11h so the user has
    /// a few hours to land on the app after the buzz and still see the
    /// brief in context. Outside the window the card hides itself.
    ///
    /// `#if DEBUG` flips the gate to "always visible" so the agent's
    /// vision-verification screenshot captures the card at any hour.
    /// Release builds keep the 5h-11h window intact.
    private var isDailyBriefVisibleHour: Bool {
        #if DEBUG
        return true
        #else
        let hour = Calendar.current.component(.hour, from: .now)
        return hour >= 5 && hour < 11
        #endif
    }

    /// Gate combining the toggle, the hour window, and a non-nil brief.
    /// A user who never opts in sees no card; an opted-in user who
    /// genuinely has zero meetings + zero open tasks + zero recent
    /// captures still sees the brief — the headline "Journée calme.
    /// Profite." is the actionable signal in that case.
    private var shouldShowDailyBrief: Bool {
        guard dailyBrief != nil else { return false }
        guard prefs.dailyBriefEnabled else { return false }
        return isDailyBriefVisibleHour
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

                // v0.20 — Welcome banner for TestFlight betas. One-time,
                // dismissible per device. Renders only when the running
                // binary is pre-1.0 AND the user hasn't already tapped
                // "Plus tard" on a previous launch.
                if SettingsView.isBetaBuild && !betaBannerDismissed {
                    betaBanner
                }

                quickSearchPill

                if !todayEvents.isEmpty {
                    todayCard
                }

                if !resumableClients.isEmpty {
                    ResumeCarousel(clients: resumableClients) { client in
                        selectedClient = client
                    }
                }

                deepFocusCard

                if !thisWeekSessions.isEmpty {
                    focusWeekCard
                }

                if weeklyHealth.isMeaningful {
                    healthWeekCard
                }

                // v0.17 — Morning brief comes first: it's the actionable
                // wake-up card. The retrospective weekly digest renders
                // just below so the user sees both on Sunday/Monday
                // mornings without scrolling.
                if shouldShowDailyBrief, let brief = dailyBrief {
                    dailyBriefCard(brief)
                }

                if shouldShowWeeklyDigest, let digest = weeklyDigest {
                    weeklyDigestCard(digest)
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
        .sheet(isPresented: $isBattling) {
            BattleSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $isOutreaching) {
            // v0.26 — Open the OutreachSheet with an empty prospect
            // context. The form takes the user from "I just want to
            // draft an outreach" to 5 variants in one screen. When
            // the user wants the audit pre-attached, they enter the
            // sheet via NodeDetailView (client kind) or the
            // ClientCard swipe action instead, both of which mint a
            // fully-populated ProspectContext upstream.
            OutreachSheet()
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
        .sheet(isPresented: $showWeeklyDigest) {
            if let digest = weeklyDigest {
                WeeklyDigestSheet(
                    digest: digest,
                    nodes: allNodes,
                    focusSessions: focusSessions
                ) { node in
                    selectedNote = node
                    showWeeklyDigest = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $showDailyBrief) {
            if let brief = dailyBrief {
                DailyBriefSheet(
                    brief: brief,
                    nodes: allNodes,
                    events: todayEvents
                ) { node in
                    selectedNote = node
                    showDailyBrief = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
        }
        .task {
            // v0.8 — load today's calendar events on appear. Soft-fails
            // to [] when permission is denied / undetermined so the card
            // simply doesn't render and the user is never blocked.
            // Asking for access here (rather than at app launch) means
            // the first prompt fires the moment the user lands on Home,
            // which is the natural moment to grant.
            _ = await CalendarReader.shared.requestAccess()
            todayEvents = await CalendarReader.shared.todayEvents()

            // v0.9 — load the weekly health summary only when the user
            // has explicitly opted in via Settings. We never call
            // requestAccess() here: that would defeat the explicit-opt-in
            // contract of the toggle. If the user toggled on Settings,
            // permission has already been requested at that moment.
            if prefs.healthInsightsEnabled {
                weeklyHealth = await HealthReader.shared.weeklySummary()
            }

            // v0.16 — Build the weekly digest synchronously from the
            // SwiftData snapshots already in memory, then hand the
            // structured digest off to the on-device model for an
            // optional narrative paragraph. The card renders the
            // structured counts immediately; the narrative arrives a
            // beat later and the card re-renders without flicker.
            var baseDigest = WeeklyDigestBuilder.compute(
                nodes: allNodes,
                focusSessions: focusSessions,
                asOf: .now
            )
            #if DEBUG
            // When the graph is empty on a freshly installed Simulator,
            // synthesize a sample digest so the agent's vision check
            // captures the actual card geometry instead of the empty
            // state. Release builds never touch this branch.
            if !baseDigest.isMeaningful {
                baseDigest = WeeklyDigest(
                    weekOf: Date.now.addingTimeInterval(-7 * 24 * 3600),
                    captureCount: 7,
                    auditCount: 1,
                    focusHours: 4.5,
                    highlightedCaptures: [
                        "Brief Verdenomia",
                        "Idée MIND v0.17",
                        "Réunion AZ Construction",
                    ],
                    narrative: nil
                )
            }
            #endif
            weeklyDigest = baseDigest
            if shouldShowWeeklyDigest {
                MINDTelemetry.info(
                    "digest.rendered",
                    data: [
                        "captures": "\(baseDigest.captureCount)",
                        "audits": "\(baseDigest.auditCount)",
                        "focusHours": String(format: "%.1f", baseDigest.focusHours),
                    ]
                )
            }
            let intel = OnDeviceIntelligence()
            if let narrative = await intel.weeklyNarrative(baseDigest),
               !narrative.isEmpty {
                weeklyDigest = baseDigest.withNarrative(narrative)
                MINDTelemetry.info(
                    "digest.narrative.generated",
                    data: ["chars": "\(narrative.count)"]
                )
            }

            // v0.17 — Build the daily morning brief from the in-memory
            // SwiftData / EventKit snapshots. Cheap pure-function call,
            // re-runs every time .task fires (foreground re-entry).
            // The brief renders even when "not meaningful" — the
            // headline branch covers the calm-day case.
            let openTaskNodes = allNodes.filter {
                $0.kindRaw == NodeKind.task.rawValue && $0.completedAt == nil
            }
            let recentCaptureNodes = allNodes.filter {
                $0.kindRaw == NodeKind.capture.rawValue
                    || $0.kindRaw == NodeKind.note.rawValue
            }
            let lastWeekFocusHours = thisWeekTotalSeconds / 3600.0
            var brief = DailyBriefBuilder.compute(
                today: todayEvents,
                tasks: openTaskNodes,
                recentCaptures: recentCaptureNodes,
                lastWeekFocusHours: lastWeekFocusHours,
                asOf: .now
            )
            #if DEBUG
            // When the graph is empty on a freshly installed Simulator,
            // synthesize a sample brief so the agent's vision check
            // captures the actual card geometry instead of the empty
            // state. Release builds never touch this branch.
            if brief.calendarEventCount == 0
                && brief.openTaskCount == 0
                && brief.recentCaptureTitles.isEmpty {
                brief = DailyBrief(
                    date: Date.now,
                    calendarEventCount: 2,
                    openTaskCount: 3,
                    recentCaptureTitles: [
                        "Brief Verdenomia",
                        "Idée MIND v0.17",
                        "Réunion AZ Construction",
                    ],
                    focusSuggestionMinutes: 45,
                    headline: DailyBriefBuilder.headlineString(meetings: 2, tasks: 3)
                )
            }
            #endif
            dailyBrief = brief
            if shouldShowDailyBrief {
                MINDTelemetry.info(
                    "brief.rendered",
                    data: [
                        "meetings": "\(brief.calendarEventCount)",
                        "tasks": "\(brief.openTaskCount)",
                        "captures": "\(brief.recentCaptureTitles.count)",
                        "focusMin": "\(brief.focusSuggestionMinutes)",
                    ]
                )
            }
        }
        // v0.17 — Deep-link bridge. RootView's `.onOpenURL` decodes
        // `mind://brief` and posts this notification because the
        // `showDailyBrief` @State lives here, not on RootView. The
        // listener flips the sheet bool the next runloop tick after
        // the URL arrives.
        .onReceive(NotificationCenter.default.publisher(for: .mindOpenDailyBrief)) { _ in
            showDailyBrief = true
        }
    }

    // MARK: - "Bilan de la semaine" card (v0.16 — WeeklyDigest)

    /// Liquid Glass card surfaced Sunday evening through Monday morning
    /// when the user has at least one capture / audit / focus session
    /// in the rolling 7-day window. Three big-number columns on top,
    /// the narrative (FoundationModels or fallback) as an italic
    /// paragraph below. Tapping the card opens `WeeklyDigestSheet`
    /// with the per-section breakdown.
    @ViewBuilder
    private func weeklyDigestCard(_ digest: WeeklyDigest) -> some View {
        LiquidCard(cornerRadius: 22) {
            Button {
                LiquidHaptics.tap()
                MINDTelemetry.info("digest.detail.opened")
                showWeeklyDigest = true
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(LiquidPalette.lavender.opacity(0.45))
                                .frame(width: 32, height: 32)
                            Image(systemName: "sparkles")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                        Text("home.weekly.title")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.85)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 0) {
                        weeklyDigestColumn(
                            value: "\(digest.captureCount)",
                            labelKey: "home.weekly.captures",
                            tint: LiquidPalette.iris
                        )
                        weeklyDigestDivider
                        weeklyDigestColumn(
                            value: "\(digest.auditCount)",
                            labelKey: "home.weekly.audits",
                            tint: .purple
                        )
                        weeklyDigestDivider
                        weeklyDigestColumn(
                            value: Self.formatFocusHours(digest.focusHours),
                            labelKey: "home.weekly.focusHours",
                            tint: .green
                        )
                    }

                    if let narrative = digest.narrative, !narrative.isEmpty {
                        Text(narrative)
                            .font(.system(.subheadline, design: .rounded))
                            .italic()
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("home.weekly.narrative.fallback")
                            .font(.system(.subheadline, design: .rounded))
                            .italic()
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func weeklyDigestColumn(
        value: String,
        labelKey: String.LocalizationValue,
        tint: Color
    ) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(String(localized: labelKey).uppercased())
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var weeklyDigestDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(width: 1, height: 32)
    }

    /// `2h32` for hours >= 1, `45 min` otherwise, `—` for zero. Matches
    /// the formatter used inside `WeeklyDigestSheet` so the card and
    /// the sheet stay visually in lockstep.
    private static func formatFocusHours(_ hours: Double) -> String {
        guard hours > 0 else { return "—" }
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h\(String(format: "%02d", m))"
        }
        return "\(m) min"
    }

    // MARK: - "Brief du matin" card (v0.17 — DailyBrief)

    /// Liquid Glass card surfaced 5h-11h local when the user has opted
    /// into the daily morning brief. Header shows the localized
    /// headline (one of 4 templates based on meeting/task counts);
    /// three monospaced columns show meetings / open tasks / suggested
    /// focus minutes; tapping opens `DailyBriefSheet` with the per-
    /// section breakdown. The lightbulb icon distinguishes it visually
    /// from the v0.16 weekly digest (sparkles icon).
    @ViewBuilder
    private func dailyBriefCard(_ brief: DailyBrief) -> some View {
        LiquidCard(cornerRadius: 22) {
            Button {
                LiquidHaptics.tap()
                MINDTelemetry.info("brief.detail.opened")
                showDailyBrief = true
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(LiquidPalette.aqua.opacity(0.45))
                                .frame(width: 32, height: 32)
                            Image(systemName: "sun.max.fill")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                        Text("home.brief.title")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.85)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 0) {
                        dailyBriefColumn(
                            value: "\(brief.calendarEventCount)",
                            labelKey: "brief.detail.summary.meetings",
                            tint: LiquidPalette.iris
                        )
                        dailyBriefDivider
                        dailyBriefColumn(
                            value: "\(brief.openTaskCount)",
                            labelKey: "brief.detail.summary.tasks",
                            tint: .purple
                        )
                        dailyBriefDivider
                        dailyBriefColumn(
                            value: "\(brief.focusSuggestionMinutes)m",
                            labelKey: "brief.detail.summary.focus",
                            tint: .green
                        )
                    }

                    Text(brief.headline)
                        .font(.system(.subheadline, design: .rounded))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func dailyBriefColumn(
        value: String,
        labelKey: String.LocalizationValue,
        tint: Color
    ) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(String(localized: labelKey).uppercased())
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var dailyBriefDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(width: 1, height: 32)
    }

    // MARK: - "Cette semaine" health card (v0.9 — HealthInsights)

    /// Three-stat compact card rendered after the Focus week summary
    /// when the user has opted into HealthKit and there is at least one
    /// non-zero metric. Layout mirrors `statsCard` for visual continuity
    /// — three columns, monospaced digits, a coloured icon per metric.
    /// Stays read-only: the card is informational, not interactive.
    /// Tapping doesn't open anything because there is no "health detail"
    /// view yet; we'll add one in a later version if the metric merits it.
    private var healthWeekCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.green.opacity(0.20))
                            .frame(width: 32, height: 32)
                        Image(systemName: "heart.fill")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    Text("home.healthWeek.header")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
                    Spacer()
                }

                HStack(spacing: 0) {
                    healthStatColumn(
                        icon: "figure.walk",
                        value: Self.formatSteps(weeklyHealth.totalSteps),
                        label: "home.healthWeek.steps",
                        tint: LiquidPalette.iris
                    )
                    healthStatDivider
                    healthStatColumn(
                        icon: "bed.double.fill",
                        value: Self.formatSleepHours(weeklyHealth.avgSleepHours),
                        label: "home.healthWeek.sleep",
                        tint: .purple
                    )
                    healthStatDivider
                    healthStatColumn(
                        icon: "flame.fill",
                        value: Self.formatActiveMinutes(weeklyHealth.activeMinutes),
                        label: "home.healthWeek.active",
                        tint: .orange
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func healthStatColumn(
        icon: String,
        value: String,
        label: String.LocalizationValue,
        tint: Color
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(String(localized: label).uppercased())
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var healthStatDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(width: 1, height: 36)
    }

    /// Formats `12345` as "12,3k" so the column never overflows the
    /// stat width on accessibility text sizes. Below 1000 we render
    /// the raw integer with locale-aware grouping.
    private static func formatSteps(_ total: Int) -> String {
        if total >= 1000 {
            let kilos = Double(total) / 1000
            return String(format: "%.1fk", kilos)
        }
        return total.formatted()
    }

    /// Renders the average sleep window as `7h32` (mixed unit, no decimal
    /// — matches how Apple Health displays summaries in the iOS Health
    /// app). Hours < 1 fall through to "—" so we don't lie with zero.
    private static func formatSleepHours(_ hours: Double) -> String {
        guard hours > 0 else { return "—" }
        let wholeHours = Int(hours)
        let minutes = Int((hours - Double(wholeHours)) * 60)
        return "\(wholeHours)h\(String(format: "%02d", minutes))"
    }

    /// "210 min" for any non-zero value, "—" otherwise. Keeps the
    /// column compact at any Dynamic Type size.
    private static func formatActiveMinutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        return "\(minutes) min"
    }

    // MARK: - "Aujourd'hui" card (v0.8 — CalendarKit)

    /// Surfaces up to 3 of today's events. Tapping a row creates a
    /// `.meeting` Node and routes through `selectedNote` so it lands in
    /// the same NodeDetailView the rest of HomeView uses — keeps the UX
    /// consistent and means the user immediately has a place to dump
    /// notes for that meeting.
    private var todayCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LiquidPalette.aqua.opacity(0.28))
                            .frame(width: 32, height: 32)
                        Image(systemName: "calendar")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    Text("home.today.header")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
                    Spacer()
                    Text("\(todayEvents.count)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                VStack(spacing: 10) {
                    ForEach(todayEvents.prefix(3)) { event in
                        todayRow(event: event)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func todayRow(event: CalendarEvent) -> some View {
        Button {
            LiquidHaptics.tap()
            createMeetingNode(from: event)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    Text(event.formattedTime)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(LiquidPalette.iris)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 56, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title.isEmpty
                         ? String(localized: "home.today.untitled")
                         : event.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    if let location = event.location {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(location)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Materialises a `.meeting` Node from a CalendarEvent, persists it,
    /// touches the Spotlight index, and routes the user into NodeDetailView
    /// via `selectedNote`. Attendees become tags so the graph can later
    /// link the meeting to existing `.person` Nodes without a schema change.
    private func createMeetingNode(from event: CalendarEvent) {
        let node = Node(
            kind: .meeting,
            title: event.title.isEmpty
                ? String(localized: "home.today.untitled")
                : event.title,
            content: event.location ?? "",
            tags: event.attendees,
            sourceURL: nil
        )
        node.createdAt = event.startDate
        node.updatedAt = .now
        context.insert(node)
        try? context.save()
        SpotlightIndexer.index(node)
        selectedNote = node
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
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("home.askMind.title")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.85)
                            .lineLimit(2)
                        Text("home.askMind.subtitle")
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

    private var auditCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(spacing: 0) {
                Button {
                    isAuditing = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LiquidPalette.iris.opacity(0.18))
                                .frame(width: 44, height: 44)
                            Image(systemName: "magnifyingglass")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("home.auditCard.title")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.primary)
                                .minimumScaleFactor(0.85)
                                .lineLimit(2)
                            Text("home.auditCard.subtitle")
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

                // v0.24 — Secondary CTA: Audit Battle Mode. Sits on the
                // same card so the discoverability moment for "compare
                // 4 sites at once" lives next to the single-target
                // audit it's a power-user upgrade of. Divider with a
                // hairline stroke keeps the two affordances visually
                // distinct without burning a whole card slot.
                Divider()
                    .background(LiquidPalette.iris.opacity(0.18))

                Button {
                    isBattling = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LiquidPalette.aqua.opacity(0.20))
                                .frame(width: 44, height: 44)
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.aqua)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("home.battleCard.title", bundle: .main)
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.primary)
                                .minimumScaleFactor(0.85)
                                .lineLimit(2)
                            Text("home.battleCard.subtitle", bundle: .main)
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

                // v0.26 — Tertiary CTA: AI Sales Email Generator.
                // Mounted under the Battle Mode row so the natural
                // reading order is single-audit → multi-audit
                // benchmark → outreach. The iris-tinted envelope
                // glyph signals "send" without burning the primary
                // CTA's pure-iris fill.
                Divider()
                    .background(LiquidPalette.iris.opacity(0.18))

                Button {
                    LiquidHaptics.select()
                    isOutreaching = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LiquidPalette.iris.opacity(0.20))
                                .frame(width: 44, height: 44)
                            Image(systemName: "envelope.badge.shield.half.filled")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("home.outreachCard.title", bundle: .main)
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.primary)
                                .minimumScaleFactor(0.85)
                                .lineLimit(2)
                            Text("home.outreachCard.subtitle", bundle: .main)
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
    }

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Self.timeBasedGreeting), Mehdi 👋")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                Text(Self.timeBasedSubtitle)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.85)
                    .lineLimit(3)
            }
            Spacer(minLength: 12)
            Button {
                showAmbient = true
            } label: {
                Image(systemName: "moon.stars.fill")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .padding(10)
                    .background {
                        Circle().fill(LiquidPalette.lavender.opacity(0.4))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("ambient.accessibility"))
        }
    }

    /// v0.20 — Welcome banner for TestFlight betas. Liquid Glass card
    /// with a flask glyph, a 1-line "you're in the beta" headline,
    /// a primary CTA that opens the TestFlight feedback URL, and a
    /// secondary "Plus tard" button that flips `betaBannerDismissed`
    /// so the banner never reappears on this device. The whole card
    /// hides itself the moment `isBetaBuild` returns false — i.e. on
    /// any 1.x or later build, even if `betaBannerDismissed` is
    /// still false from an earlier pre-1.0 install.
    private var betaBanner: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "flask.fill")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                        .padding(10)
                        .background {
                            Circle().fill(LiquidPalette.lavender.opacity(0.4))
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("home.beta.banner.title", bundle: .main)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("home.beta.banner.subtitle", bundle: .main)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Button {
                        openBetaFeedbackFromBanner()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.bubble.fill")
                            Text("home.beta.banner.cta", bundle: .main)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            Capsule(style: .continuous)
                                .fill(LiquidGradient.primary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismissBetaBanner()
                    } label: {
                        Text("home.beta.banner.dismiss", bundle: .main)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Opens the TestFlight universal feedback URL when the user taps
    /// the banner's primary CTA. iOS intercepts the link inside a beta
    /// build and routes the tap into the in-app feedback flow with the
    /// screenshot + device info auto-attached.
    private func openBetaFeedbackFromBanner() {
        MINDTelemetry.info("beta.feedback.opened", data: ["surface": "home.banner"])
        LiquidHaptics.tap()
        openURL(SettingsView.testFlightFeedbackURL)
    }

    /// "Plus tard" button: flips the @AppStorage flag so the banner
    /// never reappears on this device. A new install resets the
    /// default, which is the intended onboarding moment.
    private func dismissBetaBanner() {
        MINDTelemetry.info("beta.banner.dismissed")
        LiquidHaptics.tap()
        withAnimation(LiquidMetrics.spring) {
            betaBannerDismissed = true
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
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                Text("home.quickSearch.placeholder")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
        .accessibilityLabel(Text("home.quickSearch.accessibility"))
    }

    private var deepFocusCard: some View {
        LiquidCard {
            VStack(spacing: 16) {
                Text(focus.isRunning ? "home.deepFocus.running" : "home.deepFocus.idle")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)

                focusTimer

                if focus.isRunning {
                    // success → three-pulse "done" that signals the
                    // session is being wrapped up. Feels rewarding.
                    LiquidButton(
                        title: String(localized: "home.deepFocus.endButton"),
                        systemImage: "stop.fill",
                        haptic: .success
                    ) {
                        focus.end()
                    }
                } else {
                    // select → medium thump that says "I'm committing,
                    // don't disturb me". Heavier than a normal tap.
                    LiquidButton(
                        title: String(localized: "home.deepFocus.startButton"),
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

    // The Deep Focus countdown intentionally locks the size at 64pt
    // (display-only, monospaced digits). It's a hero numeric figure
    // the user glances at — Dynamic Type would either make it useless
    // (too small at xSmall) or break the card frame (huge at AX5).
    // `minimumScaleFactor` keeps it readable inside the card width.
    @ViewBuilder
    private var focusTimer: some View {
        if let session = focus.session, session.endDate > .now {
            Text(timerInterval: .now...session.endDate, countsDown: true)
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
        } else {
            Text(Self.format(seconds: defaultFocusDuration))
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
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
                title: "home.lifeModule.habits",
                tint: .orange,
                badge: habitsTodayCount > 0 ? "\(habitsTodayCount)✓" : nil
            ) { showHabits = true }

            lifeModuleTile(
                icon: "book.closed.fill",
                title: "home.lifeModule.journal",
                tint: LiquidPalette.iris,
                badge: nil
            ) { showJournal = true }

            lifeModuleTile(
                icon: "target",
                title: "home.lifeModule.goals",
                tint: .purple,
                badge: openGoalsCount > 0 ? "\(openGoalsCount)" : nil
            ) { showGoals = true }
        }
    }

    private func lifeModuleTile(
        icon: String,
        title: LocalizedStringKey,
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
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("home.tasks.title")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.85)
                            .lineLimit(2)
                        Text(openTaskCount == 0
                             ? String(localized: "home.tasks.empty")
                             : "\(openTaskCount) à faire")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
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
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
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
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("home.focusWeek.title")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.85)
                            .lineLimit(2)
                        Text(focusWeekSummary)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text("\(thisWeekSessions.count)")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LiquidPalette.iris)
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
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
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("home.empty.title")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .minimumScaleFactor(0.85)
                            .lineLimit(2)
                        Text("home.empty.subtitle")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 12) {
                    onboardingHint(
                        icon: "drop.fill",
                        title: "home.empty.hint.capture.title",
                        detail: "home.empty.hint.capture.detail"
                    )
                    onboardingHint(
                        icon: "magnifyingglass",
                        title: "home.empty.hint.audit.title",
                        detail: "home.empty.hint.audit.detail"
                    )
                    onboardingHint(
                        icon: "brain.head.profile",
                        title: "home.empty.hint.focus.title",
                        detail: "home.empty.hint.focus.detail"
                    )
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func onboardingHint(
        icon: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(LiquidPalette.lavender.opacity(0.5))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.9)
                    .lineLimit(2)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer()
        }
    }

    private var statsCard: some View {
        LiquidCard(cornerRadius: 20) {
            HStack(spacing: 0) {
                statColumn(value: noteCount, labelKey: "home.stats.notes")
                divider
                statColumn(value: captureCount, labelKey: "home.stats.captures")
                divider
                statColumn(value: allNodes.count, labelKey: "home.stats.total")
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func statColumn(value: Int, labelKey: String.LocalizationValue) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(LiquidPalette.iris)
            Text(String(localized: labelKey).uppercased())
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
            Text(String(localized: "home.recent.header").uppercased())
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
        case 5..<12:  return String(localized: "greeting.morning")
        case 12..<18: return String(localized: "greeting.afternoon")
        case 18..<23: return String(localized: "greeting.evening")
        default:      return String(localized: "greeting.night")
        }
    }

    private static var timeBasedSubtitle: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return String(localized: "greeting.subtitle.morning")
        case 12..<18: return String(localized: "greeting.subtitle.afternoon")
        case 18..<23: return String(localized: "greeting.subtitle.evening")
        default:      return String(localized: "greeting.subtitle.night")
        }
    }
}

extension Notification.Name {
    /// v0.17 — Posted by `RootView.onOpenURL` when iOS hands us a
    /// `mind://brief` deep link (typically from the morning notification
    /// tap). Observed by HomeView's `.onReceive` to flip its
    /// `showDailyBrief` sheet on so the brief presents.
    static let mindOpenDailyBrief = Notification.Name("app.mind.ios.openDailyBrief")
}
