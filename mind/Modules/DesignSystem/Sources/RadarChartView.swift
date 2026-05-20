import SwiftUI

/// v0.24 — Pure SwiftUI Canvas-based radar (spider) chart.
///
/// Renders any number of `RadarSeries` (one per "team" — for the
/// Audit Battle Mode that's one polygon per competitor) over a
/// shared axis set. Axes are evenly spaced around a circle starting
/// at -90° (12 o'clock). The polygon for each series is filled with
/// 22% alpha and stroked with full-alpha at 2 px so 2-4 overlapping
/// polygons remain legible without a legend.
///
/// Values are clamped to 0-100 — feeding -10 or 250 won't blow the
/// chart up, it just snaps to the boundary. Empty `axes` returns a
/// silent empty canvas (defensive against the "nothing to draw"
/// case while a battle is still resolving).
///
/// Reusable: any future feature (focus-mode scoring, weekly health
/// snapshot, etc.) can drop the same view in by handing it a
/// labelled axis set + colored series. The radar formula lives in
/// `Self.polygonPoints(values:axes:size:)` so tests can lock it
/// directly without spinning up a render pass.
public struct RadarChartView: View {

    /// One coloured polygon. `id` is propagated by SwiftUI for the
    /// animated transition between snapshots — keep it stable
    /// across re-renders so the polygon morphs rather than fades.
    public struct Series: Identifiable, Equatable {
        public let id: UUID
        public let label: String
        public let values: [Int]
        public let color: Color

        public init(
            id: UUID = UUID(),
            label: String,
            values: [Int],
            color: Color
        ) {
            self.id = id
            self.label = label
            self.values = values
            self.color = color
        }
    }

    public let series: [Series]
    public let axes: [String]

    public init(series: [Series], axes: [String]) {
        self.series = series
        self.axes = axes
    }

    public var body: some View {
        Canvas { context, size in
            guard !axes.isEmpty else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 32

            // Concentric rings (25/50/75/100) — light Liquid Glass
            // stroke so the polygons read against the backdrop.
            for fraction in [0.25, 0.5, 0.75, 1.0] {
                let r = radius * fraction
                var path = Path()
                for (i, _) in axes.enumerated() {
                    let pt = Self.point(
                        center: center,
                        radius: r,
                        index: i,
                        total: axes.count
                    )
                    if i == 0 {
                        path.move(to: pt)
                    } else {
                        path.addLine(to: pt)
                    }
                }
                path.closeSubpath()
                context.stroke(
                    path,
                    with: .color(.primary.opacity(0.10)),
                    lineWidth: 1
                )
            }

            // Axis rays
            for i in axes.indices {
                let pt = Self.point(
                    center: center,
                    radius: radius,
                    index: i,
                    total: axes.count
                )
                var path = Path()
                path.move(to: center)
                path.addLine(to: pt)
                context.stroke(
                    path,
                    with: .color(.primary.opacity(0.08)),
                    lineWidth: 1
                )
            }

            // Axis labels — placed slightly outside the polygon.
            for (i, label) in axes.enumerated() {
                let pt = Self.point(
                    center: center,
                    radius: radius + 16,
                    index: i,
                    total: axes.count
                )
                let resolved = context.resolve(
                    Text(label)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
                let textSize = resolved.measure(in: CGSize(width: 80, height: 24))
                context.draw(
                    resolved,
                    at: CGPoint(
                        x: pt.x - textSize.width / 2,
                        y: pt.y - textSize.height / 2
                    )
                )
            }

            // Each series polygon — fill then stroke so the line
            // sits on top of its own translucent body.
            for s in series {
                let pts = Self.polygonPoints(
                    values: s.values,
                    axes: axes,
                    center: center,
                    radius: radius
                )
                guard pts.count >= 3 else { continue }
                var path = Path()
                path.move(to: pts[0])
                for p in pts.dropFirst() {
                    path.addLine(to: p)
                }
                path.closeSubpath()
                context.fill(path, with: .color(s.color.opacity(0.22)))
                context.stroke(path, with: .color(s.color), lineWidth: 2)

                // Vertex dots for the same legibility win.
                for p in pts {
                    let dot = Path(ellipseIn: CGRect(
                        x: p.x - 3, y: p.y - 3, width: 6, height: 6
                    ))
                    context.fill(dot, with: .color(s.color))
                }
            }
        }
        .animation(.smooth(duration: 0.6), value: snapshotKey)
        .accessibilityLabel(accessibilityText)
    }

    /// Identity-ish key derived from the visible data so SwiftUI
    /// animates value changes (one polygon morphing into another)
    /// rather than the whole canvas flickering.
    private var snapshotKey: String {
        series.map { s in
            "\(s.id.uuidString):\(s.values.map(String.init).joined(separator: ","))"
        }.joined(separator: "|")
    }

    private var accessibilityText: Text {
        let parts = series.map { s -> String in
            let label = s.label
            let values = zip(axes, s.values.map { Self.clamp($0) })
                .map { "\($0): \($1)" }
                .joined(separator: ", ")
            return "\(label) — \(values)"
        }.joined(separator: ". ")
        return Text(parts)
    }

    // MARK: - Pure helpers (testable)

    /// Compute the (x, y) for axis `index` at distance `radius`
    /// from `center`. Angle starts at -π/2 (12 o'clock) and walks
    /// clockwise — same convention as iOS pie/donut chart code so
    /// the radar reads the same direction the eye expects.
    public static func point(
        center: CGPoint,
        radius: CGFloat,
        index: Int,
        total: Int
    ) -> CGPoint {
        guard total > 0 else { return center }
        let angle = -CGFloat.pi / 2 + (CGFloat(index) / CGFloat(total)) * 2 * .pi
        return CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }

    /// Build the polygon points for one series. Each value is
    /// clamped to 0-100 and projected onto its axis at
    /// `radius * value / 100`. Returns one point per axis; if the
    /// values array is shorter than the axes array the missing
    /// values are treated as zero so the polygon still closes.
    public static func polygonPoints(
        values: [Int],
        axes: [String],
        center: CGPoint,
        radius: CGFloat
    ) -> [CGPoint] {
        guard !axes.isEmpty else { return [] }
        var points: [CGPoint] = []
        points.reserveCapacity(axes.count)
        for i in axes.indices {
            let raw = i < values.count ? values[i] : 0
            let v = Self.clamp(raw)
            let r = radius * CGFloat(v) / 100.0
            points.append(point(
                center: center,
                radius: r,
                index: i,
                total: axes.count
            ))
        }
        return points
    }

    /// Clamp a single radar value to the 0-100 range. Negative ⇒ 0,
    /// over-100 ⇒ 100. Public so the host (BattleSheet, Portal HTML)
    /// can apply the exact same rule before rendering.
    public static func clamp(_ value: Int) -> Int {
        max(0, min(100, value))
    }
}
