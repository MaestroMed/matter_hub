import SwiftUI
import SwiftData
import CoreSpotlight
import AuditKit
import CalendarKit
import DesignSystem
import FocusKit
import GraphCore
import HealthInsights
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
    @Environment(\.modelContext) private var context
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
        }
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
