import SwiftUI
import DesignSystem
import Notes
import Capture

struct RootView: View {
    @State private var selectedTab: Tab = .home
    @State private var showCapture = false

    var body: some View {
        ZStack {
            LiquidBackground()
                .ignoresSafeArea()

            Group {
                switch selectedTab {
                case .home: HomeView()
                case .notes: NotesView()
                case .flow: FlowView()
                case .profile: ProfileView()
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))

            VStack {
                Spacer()
                LiquidTabBar(
                    selection: $selectedTab,
                    leading: [
                        LiquidTab(icon: "house.fill", tag: .home),
                        LiquidTab(icon: "doc.text.fill", tag: .notes),
                    ],
                    trailing: [
                        LiquidTab(icon: "waveform.path", tag: .flow),
                        LiquidTab(icon: "person.fill", tag: .profile),
                    ],
                    onCapture: { showCapture = true }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showCapture) {
            QuickCaptureSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(.thinMaterial)
        }
    }
}

enum Tab: Hashable {
    case home, notes, flow, profile
}

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good morning")
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

struct FlowView: View {
    var body: some View {
        ScrollView {
            Text("Flow")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .padding(20)
                .padding(.top, 40)
        }
    }
}

struct ProfileView: View {
    var body: some View {
        ScrollView {
            Text("Profile")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .padding(20)
                .padding(.top, 40)
        }
    }
}
