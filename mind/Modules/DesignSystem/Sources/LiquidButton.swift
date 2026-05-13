import SwiftUI

public struct LiquidButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    @State private var pressed = false

    public init(title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.headline, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background {
                Capsule(style: .continuous)
                    .fill(LiquidGradient.primary)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(LiquidGradient.glassFill)
                            .blendMode(.overlay)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.4), lineWidth: 1)
                    }
            }
            .shadow(color: LiquidPalette.iris.opacity(0.45), radius: pressed ? 8 : 18, y: pressed ? 4 : 10)
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(LiquidMetrics.bounce, value: pressed)
        }
        .buttonStyle(PressTracker(pressed: $pressed))
    }
}

private struct PressTracker: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                pressed = newValue
            }
    }
}
