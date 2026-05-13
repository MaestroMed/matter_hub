import SwiftUI

public struct LiquidBackground: View {
    @State private var phase: CGFloat = 0

    public init() {}

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1/60)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                LiquidPalette.pearl

                blob(
                    color: LiquidPalette.lavender.opacity(0.55),
                    center: CGPoint(x: 0.25 + 0.08 * sin(t * 0.3), y: 0.25 + 0.06 * cos(t * 0.4)),
                    radius: 0.55
                )
                blob(
                    color: LiquidPalette.aqua.opacity(0.45),
                    center: CGPoint(x: 0.75 + 0.07 * cos(t * 0.25), y: 0.35 + 0.08 * sin(t * 0.35)),
                    radius: 0.50
                )
                blob(
                    color: LiquidPalette.blush.opacity(0.40),
                    center: CGPoint(x: 0.5 + 0.10 * sin(t * 0.20), y: 0.85 + 0.05 * cos(t * 0.30)),
                    radius: 0.60
                )
            }
            .blur(radius: 60)
            .saturation(1.15)
        }
    }

    @ViewBuilder
    private func blob(color: Color, center: CGPoint, radius: CGFloat) -> some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height) * radius
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .position(
                    x: geo.size.width * center.x,
                    y: geo.size.height * center.y
                )
        }
    }
}

#Preview {
    LiquidBackground()
}
