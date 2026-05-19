import SwiftUI

public struct LiquidButton: View {
    /// Semantic haptic flavour fired on press. Default `.tap` matches
    /// the standard CTA feel; callers can pass `.select` (medium) when
    /// the button commits a choice (Save key, Start focus), `.success`
    /// when it finalises something that was in flight (End focus), or
    /// `.none` to opt out entirely (toggles, repeated taps).
    public enum HapticStyle {
        case none
        case tap
        case select
        case success
        case warning
    }

    let title: String
    let systemImage: String?
    let haptic: HapticStyle
    let action: () -> Void
    @State private var pressed = false

    public init(
        title: String,
        systemImage: String? = nil,
        haptic: HapticStyle = .tap,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.haptic = haptic
        self.action = action
    }

    public var body: some View {
        Button {
            // Fire the haptic before the action so the tactile response
            // beats any UI work (sheet present, async start) that the
            // closure kicks off. Single source of truth — keeps every
            // call site free of UIImpactFeedbackGenerator boilerplate.
            switch haptic {
            case .none:    break
            case .tap:     LiquidHaptics.tap()
            case .select:  LiquidHaptics.select()
            case .success: LiquidHaptics.success()
            case .warning: LiquidHaptics.warning()
            }
            action()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
