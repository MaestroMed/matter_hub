import SwiftUI
import DesignSystem

struct RootView: View {
    var body: some View {
        ZStack {
            LiquidBackground()
                .ignoresSafeArea()

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
                .padding(.bottom, 40)
            }
        }
    }
}
