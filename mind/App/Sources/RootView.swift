import SwiftUI
import SwiftData
import DesignSystem
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good morning, Mehdi 👋")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text("Stay soft. Stay focused.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                LiquidCard {
                    VStack(spacing: 16) {
                        Text("Deep Focus")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("24:36")
                            .font(.system(size: 64, weight: .light, design: .rounded))
                            .monospacedDigit()
                        LiquidButton(title: "Start Focus", systemImage: "drop.fill") {}
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .padding(.top, 40)
            .padding(.bottom, 120)
        }
    }
}
