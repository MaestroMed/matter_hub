import SwiftUI

/// 2×2 strategy matrix plotting items by effort (X) against impact (Y).
/// Quadrants follow the classic prioritization framing:
///   - Top-left  → **Quick wins** (low effort × high impact) — do first
///   - Top-right → **Big bets**   (high effort × high impact) — plan
///   - Bot-left  → **Fill-ins**   (low effort × low impact)  — backlog
///   - Bot-right → **Thankless**  (high effort × low impact) — drop
///
/// Used by AuditSheet to surface the audit's quick wins visually rather
/// than as a flat list, so Mehdi can spot the high-leverage ones at a
/// glance.
public struct ImpactEffortMatrix: View {
    private let items: [Item]
    private let effortCap: Double

    public struct Item: Identifiable, Hashable {
        public let id: UUID
        public let label: String
        /// Effort in days. Capped at `effortCap` (default 10) for display.
        public let effortDays: Double
        public let impact: Impact

        public enum Impact: String, CaseIterable, Hashable {
            case low
            case medium
            case high
        }

        public init(
            id: UUID = UUID(),
            label: String,
            effortDays: Double,
            impact: Impact
        ) {
            self.id = id
            self.label = label
            self.effortDays = effortDays
            self.impact = impact
        }
    }

    public init(items: [Item], effortCap: Double = 10) {
        self.items = items
        self.effortCap = max(1, effortCap)
    }

    public var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 16
            let plot = CGRect(
                x: inset,
                y: inset,
                width: max(0, geo.size.width - 2 * inset),
                height: max(0, geo.size.height - 2 * inset)
            )

            ZStack {
                Canvas { ctx, _ in
                    drawQuadrants(ctx, in: plot)
                    drawAxes(ctx, in: plot)
                    drawDots(ctx, in: plot)
                }

                quadrantLabels(in: plot)
                axisLabels(in: plot, size: geo.size)
            }
        }
        .aspectRatio(1.4, contentMode: .fit)
    }

    // MARK: - Layout helpers

    private func point(for item: Item, in plot: CGRect) -> CGPoint {
        let xNorm = min(1, max(0, item.effortDays / effortCap))
        let yNorm: Double = {
            switch item.impact {
            case .low:    return 0.18
            case .medium: return 0.5
            case .high:   return 0.82
            }
        }()
        return CGPoint(
            x: plot.minX + plot.width * xNorm,
            y: plot.minY + plot.height * (1 - yNorm)  // SwiftUI Y points down
        )
    }

    // MARK: - Drawing

    private func drawQuadrants(_ ctx: GraphicsContext, in plot: CGRect) {
        let midX = plot.midX
        let midY = plot.midY

        let topLeft = CGRect(x: plot.minX, y: plot.minY, width: midX - plot.minX, height: midY - plot.minY)
        let topRight = CGRect(x: midX, y: plot.minY, width: plot.maxX - midX, height: midY - plot.minY)
        let botLeft = CGRect(x: plot.minX, y: midY, width: midX - plot.minX, height: plot.maxY - midY)
        let botRight = CGRect(x: midX, y: midY, width: plot.maxX - midX, height: plot.maxY - midY)

        // Soft tints — quick wins quadrant is the iris hero.
        ctx.fill(Path(roundedRect: topLeft.insetBy(dx: 2, dy: 2), cornerRadius: 14),
                 with: .color(LiquidPalette.iris.opacity(0.25)))
        ctx.fill(Path(roundedRect: topRight.insetBy(dx: 2, dy: 2), cornerRadius: 14),
                 with: .color(LiquidPalette.aqua.opacity(0.20)))
        ctx.fill(Path(roundedRect: botLeft.insetBy(dx: 2, dy: 2), cornerRadius: 14),
                 with: .color(LiquidPalette.lavender.opacity(0.20)))
        ctx.fill(Path(roundedRect: botRight.insetBy(dx: 2, dy: 2), cornerRadius: 14),
                 with: .color(LiquidPalette.blush.opacity(0.18)))
    }

    private func drawAxes(_ ctx: GraphicsContext, in plot: CGRect) {
        // Mid lines
        var horizontal = Path()
        horizontal.move(to: CGPoint(x: plot.minX, y: plot.midY))
        horizontal.addLine(to: CGPoint(x: plot.maxX, y: plot.midY))
        ctx.stroke(horizontal, with: .color(.white.opacity(0.45)), lineWidth: 0.8)

        var vertical = Path()
        vertical.move(to: CGPoint(x: plot.midX, y: plot.minY))
        vertical.addLine(to: CGPoint(x: plot.midX, y: plot.maxY))
        ctx.stroke(vertical, with: .color(.white.opacity(0.45)), lineWidth: 0.8)
    }

    private func drawDots(_ ctx: GraphicsContext, in plot: CGRect) {
        for item in items {
            let p = point(for: item, in: plot)
            let r: CGFloat = 6
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(dotTint(for: item)))
            ctx.stroke(dot, with: .color(.white), lineWidth: 1.5)
        }
    }

    private func dotTint(for item: Item) -> Color {
        switch item.impact {
        case .high:   return LiquidPalette.iris
        case .medium: return .orange
        case .low:    return .gray
        }
    }

    @ViewBuilder
    private func quadrantLabels(in plot: CGRect) -> some View {
        Group {
            Text("Quick wins")
                .modifier(QuadrantTitle())
                .position(x: plot.minX + plot.width * 0.25, y: plot.minY + 14)
            Text("Big bets")
                .modifier(QuadrantTitle())
                .position(x: plot.minX + plot.width * 0.75, y: plot.minY + 14)
            Text("Fill-ins")
                .modifier(QuadrantTitle())
                .position(x: plot.minX + plot.width * 0.25, y: plot.maxY - 12)
            Text("Drop")
                .modifier(QuadrantTitle())
                .position(x: plot.minX + plot.width * 0.75, y: plot.maxY - 12)
        }
    }

    private func axisLabels(in plot: CGRect, size: CGSize) -> some View {
        ZStack {
            Text("Impact ↑")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
                .rotationEffect(.degrees(-90))
                .position(x: 8, y: plot.midY)
            Text("Effort →")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
                .position(x: plot.maxX - 24, y: plot.maxY + 4)
        }
    }
}

// MARK: - Modifiers

private struct QuadrantTitle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}
