import SwiftUI

public struct LiquidToggle: View {
    @Binding var isOn: Bool

    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }

    public var body: some View {
        Button {
            withAnimation(LiquidMetrics.spring) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(
                        isOn
                            ? AnyShapeStyle(LinearGradient(
                                colors: [LiquidPalette.aqua, LiquidPalette.sky],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            : AnyShapeStyle(.ultraThinMaterial)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                    }
                    .frame(width: 64, height: 36)
                    .shadow(color: isOn ? LiquidPalette.aqua.opacity(0.4) : .clear, radius: 12, y: 6)

                Circle()
                    .fill(.white)
                    .overlay {
                        Circle().stroke(.white.opacity(0.5), lineWidth: 1)
                    }
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .padding(.horizontal, 4)
            }
            .frame(width: 64, height: 36)
        }
        .buttonStyle(.plain)
    }
}
