import SwiftUI

public struct LiquidSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    public init(value: Binding<Double>, in range: ClosedRange<Double> = 0...1) {
        self._value = value
        self.range = range
    }

    public var body: some View {
        GeometryReader { geo in
            let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let width = geo.size.width
            let thumb: CGFloat = 28

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                    }
                    .frame(height: 14)

                Capsule(style: .continuous)
                    .fill(LiquidGradient.primary)
                    .frame(width: max(thumb, progress * width), height: 14)
                    .shadow(color: LiquidPalette.iris.opacity(0.5), radius: 8, y: 3)

                Circle()
                    .fill(.white)
                    .overlay { Circle().stroke(.white.opacity(0.5), lineWidth: 1) }
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    .offset(x: max(0, min(width - thumb, progress * width - thumb / 2)))
            }
            .frame(height: thumb)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let ratio = max(0, min(1, drag.location.x / width))
                        let next = range.lowerBound + Double(ratio) * (range.upperBound - range.lowerBound)
                        value = next
                    }
            )
        }
        .frame(height: 28)
    }
}
