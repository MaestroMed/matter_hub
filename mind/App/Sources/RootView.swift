import SwiftUI
import SwiftData
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
    @State private var selection: MINDTab = .home
    @State private var isCapturing: Bool = false
    @State private var selectedNode: Node?

    var body: some View {
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

private struct HomeView: View {
    @Query(sort: \Node.updatedAt, order: .reverse) private var allNodes: [Node]
    @Query private var focusSessions: [FocusSessionRecord]
    @State private var focus = FocusController.shared
    @State private var prefs = MINDPreferences.shared
    @State private var isAuditing: Bool = false
    @State private var isChatting: Bool = false
    @State private var selectedClient: Node?
    @State private var showFocusHistory: Bool = false
    @State private var showTasks: Bool = false

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
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Self.timeBasedGreeting), Mehdi 👋")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text(Self.timeBasedSubtitle)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
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
                    LiquidButton(title: "End focus", systemImage: "stop.fill") {
                        focus.end()
                    }
                } else {
                    LiquidButton(title: "Start Focus", systemImage: "drop.fill") {
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
