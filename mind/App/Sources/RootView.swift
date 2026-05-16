import SwiftUI
import SwiftData
import DesignSystem
import FocusKit
import GraphCore
import Notes
import Chat
import Settings
import Capture

enum MINDTab: Hashable {
    case home
    case notes
    case chat
    case settings
}

struct RootView: View {
    @State private var selection: MINDTab = .home
    @State private var isCapturing: Bool = false

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
                        LiquidTab(icon: "bubble.left.and.bubble.right.fill", tag: MINDTab.chat),
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
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .home:
            HomeView()
        case .notes:
            NotesView()
        case .chat:
            ChatView()
        case .settings:
            SettingsView()
        }
    }
}

private struct HomeView: View {
    @Query(sort: \Node.updatedAt, order: .reverse) private var allNodes: [Node]
    @State private var focus = FocusController.shared

    private static let defaultFocusDuration: TimeInterval = 25 * 60  // 25 min pomodoro

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                greeting

                deepFocusCard

                statsCard

                if !recentCaptures.isEmpty {
                    recentSection
                }
            }
            .padding(20)
            .padding(.top, 40)
            .padding(.bottom, 120)
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
                            duration: Self.defaultFocusDuration
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
            Text(Self.format(seconds: Self.defaultFocusDuration))
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
        }
    }

    private static func format(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
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
