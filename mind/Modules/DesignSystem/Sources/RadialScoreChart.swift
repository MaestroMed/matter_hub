import SwiftUI

/// 5-axis spider/radar chart for displaying the audit scoring matrix
/// (Perf / SEO / Security / Brand / Mobile) as a single visual block.
/// Pure Canvas SwiftUI — zero external dep, scales gracefully from a
/// 120pt detail card to a 320pt hero on iPad.
public struct RadialScoreChart: View {
    private let scores: [Score]

    public struct Score: Identifiable {
        public let id: String
        public let label: String
        public let value: Int    // 0-100

        public init(label: String, value: Int) {
            self.id = label
            self.label = label
            self.value = max(0, min(100, value))
        }
    }

    public init(scores: [Score]) {
        self.scores = scores
    }

    public init(
        performance: Int,
        seo: Int,
        security: Int,
        brand: Int,
        mobile: Int
    ) {
        self.scores = [
            Score(label: "Perf",   value: performance),
            Score(label: "SEO",    value: seo),
            Score(label: "Sécu",   value: security),
            Score(label: "Brand",  value: brand),
            Score(label: "Mobile", value: mobile),
        ]
    }

    public var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let chartRadius = size / 2 * 0.66
            let labelRadius = size / 2 * 0.92

            ZStack {
                Canvas { ctx, _ in
                    drawRings(ctx, center: center, radius: chartRadius)
                    drawAxes(ctx, center: center, radius: chartRadius)
                    drawScorePolygon(ctx, center: center, radius: chartRadius)
                    drawScoreDots(ctx, center: center, radius: chartRadius)
                }

                ForEach(Array(scores.enumerated()), id: \.element.id) { index, score in
                    let angle = angle(at: index)
                    let x = center.x + labelRadius * cos(angle)
                    let y = center.y + labelRadius * sin(angle)
                    AxisLabel(label: score.label, value: score.value)
                        .position(x: x, y: y)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Drawing

    private func angle(at index: Int) -> CGFloat {
        let step = 2 * .pi / CGFloat(max(scores.count, 1))
        // -π/2 puts the first axis straight up.
        return -.pi / 2 + CGFloat(index) * step
    }

    private func drawRings(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for fraction in [0.25, 0.5, 0.75, 1.0] {
            let r = radius * fraction
            var path = Path()
            for i in 0..<scores.count {
                let a = angle(at: i)
                let p = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            ctx.stroke(
                path,
                with: .color(.white.opacity(fraction == 1.0 ? 0.35 : 0.18)),
                lineWidth: 0.8
            )
        }
    }

    private func drawAxes(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for i in 0..<scores.count {
            let a = angle(at: i)
            let end = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            var path = Path()
            path.move(to: center)
            path.addLine(to: end)
            ctx.stroke(path, with: .color(.white.opacity(0.14)), lineWidth: 0.6)
        }
    }

    private func drawScorePolygon(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        var path = Path()
        for (i, score) in scores.enumerated() {
            let a = angle(at: i)
            let r = radius * CGFloat(score.value) / 100
            let p = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()

        let gradient = Gradient(colors: [
            LiquidPalette.iris.opacity(0.55),
            LiquidPalette.aqua.opacity(0.35),
        ])
        let start = CGPoint(x: center.x - radius, y: center.y - radius)
        let end = CGPoint(x: center.x + radius, y: center.y + radius)
        ctx.fill(path, with: .linearGradient(gradient, startPoint: start, endPoint: end))
        ctx.stroke(path, with: .color(LiquidPalette.iris), lineWidth: 1.8)
    }

    private func drawScoreDots(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for (i, score) in scores.enumerated() {
            let a = angle(at: i)
            let r = radius * CGFloat(score.value) / 100
            let p = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            let dot = Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            ctx.fill(dot, with: .color(.white))
            ctx.stroke(dot, with: .color(LiquidPalette.iris), lineWidth: 1.5)
        }
    }
}

// MARK: - Axis label

private struct AxisLabel: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text("\(value)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color(for: value))
        }
    }

    private func color(for value: Int) -> Color {
        switch value {
        case 80...:   return .green
        case 50..<80: return .orange
        default:      return .red
        }
    }
}
