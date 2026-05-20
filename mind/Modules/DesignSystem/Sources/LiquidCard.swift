import SwiftUI

public struct LiquidCard<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = LiquidMetrics.cornerLarge, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LiquidGradient.glassFill)
                        .opacity(0.7)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
            }
            .shadow(color: LiquidPalette.iris.opacity(0.25), radius: 30, x: 0, y: 10)
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}
