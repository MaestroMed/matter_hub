import SwiftUI
import SwiftData
import DesignSystem
import GraphCore
// Disambiguate `Edge` (GraphCore's SwiftData @Model) from SwiftUI's
// `Edge` alignment enum. Importing the concrete class symbol means the
// unqualified `Edge` resolves to the model in this file without
// affecting any other file in the App target.
import class GraphCore.Edge

/// v0.15 — Interactive knowledge graph visualization.
///
/// Renders every Node in the SwiftData store as a coloured disc connected
/// by light grey edges in a force-directed layout. Spring attraction
/// keeps connected nodes close, Coulomb repulsion keeps unrelated nodes
/// apart, damping prevents the simulation from oscillating forever.
///
/// Implementation notes
/// --------------------
/// - The physics integration runs in a `TimelineView(.animation)` so it
///   stays in sync with the display refresh rate (60 Hz on most iPhones,
///   120 Hz on ProMotion). Each frame we step the simulation forward by
///   `0.016s` (one 60 Hz tick) regardless of the actual frame interval —
///   this keeps the visual motion stable across refresh rates without
///   introducing per-frame jitter from variable `dt`.
/// - Position state lives in `@State` as a `[UUID: NodePosition]` dict so
///   we never lose layout when SwiftData refetches the @Query result.
/// - Rendering is one `Canvas` pass per frame: edges first (so they sit
///   behind the nodes), then nodes on top. Far cheaper than instantiating
///   one SwiftUI view per node — a graph with 200 nodes would otherwise
///   stutter on hit-testing alone.
/// - Tap detection walks the position dictionary linearly looking for the
///   nearest node within 20pt of the tap. O(n) per tap, trivially fast
///   at our 200-node cap.
/// - Zoom (0.5x…3.0x) and pan are tracked separately and composed into
///   the Canvas transform so the user can explore dense clusters without
///   losing context.
///
/// Performance contract
/// --------------------
/// 200-node cap, 60 fps on iPhone 12 baseline. Above 200 nodes we show a
/// "Show more" CTA but don't auto-load them — the user opts into the
/// extra work explicitly.
struct GraphView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Node.createdAt, order: .reverse) private var allNodes: [Node]
    // GraphCore's `Edge` SwiftData @Model would collide with SwiftUI's
    // `Edge` (the .top/.bottom/.leading/.trailing alignment enum) when
    // referenced unqualified inside an `@Query` declaration — and the
    // `GraphCore.Edge` form fails too because the GraphCore module also
    // exports a `public enum GraphCore` namespace that shadows the
    // module path. So we fetch edges manually in `.onAppear` via the
    // FetchDescriptor API instead. Cheap at our 200-node cap and avoids
    // the macro/import disambiguation pain entirely.
    @State private var allEdges: [Edge] = []

    let onSelectNode: (Node) -> Void

    /// Hard cap to keep the layout snappy. The user can opt into rendering
    /// more by tapping the "Afficher plus" CTA in the empty state.
    @State private var nodeCap: Int = 200

    /// One position per visible node, keyed by Node.id. Survives Canvas
    /// redraws and SwiftData refetches alike.
    @State private var positions: [UUID: GraphPhysics.NodePosition] = [:]

    /// Whether we've laid out the initial seed positions for the current
    /// node set. Flipped after the first `.onAppear` and the @Query first
    /// delivers data. Reseeded whenever the visible node count changes.
    @State private var seededForCount: Int = -1

    /// Zoom factor applied to the Canvas coordinate system. Clamped 0.5…3.0
    /// to keep the gesture usable.
    @State private var scale: CGFloat = 1.0
    /// Pending scale delta during an active MagnificationGesture — added to
    /// `scale` on gesture end so the user gets a smooth pinch + commit.
    @State private var pendingScale: CGFloat = 1.0

    /// Pan translation applied to the Canvas coordinate system.
    @State private var offset: CGSize = .zero
    /// Pending translation delta during an active DragGesture — committed
    /// on `.onEnded`.
    @State private var pendingOffset: CGSize = .zero

    /// Stored last tap location so we can detect which node was tapped
    /// outside of the gesture closure (the SwiftUI tap gesture API doesn't
    /// give us the location directly on hit-test).
    @State private var lastTapLocation: CGPoint?

    init(onSelectNode: @escaping (Node) -> Void) {
        self.onSelectNode = onSelectNode
    }

    // MARK: - Derived data

    /// Visible nodes, capped at `nodeCap`. Sorted by createdAt desc via the
    /// @Query so the first N are the most recent — the slice that's most
    /// likely to interest the user when the graph is too large to fit.
    private var visibleNodes: [Node] {
        Array(allNodes.prefix(nodeCap))
    }

    /// Visible edges, filtered to those whose both endpoints made the cut.
    /// Reduces stray edges leading to clipped neighbours.
    private var visibleEdges: [Edge] {
        let visibleIDs = Set(visibleNodes.map(\.id))
        return allEdges.filter { edge in
            guard let fromID = edge.from?.id, let toID = edge.to?.id else { return false }
            return visibleIDs.contains(fromID) && visibleIDs.contains(toID)
        }
    }

    /// Pure tuples of (from.id, to.id) used by the physics step. Built
    /// once per frame and passed in so the simulation never depends on
    /// SwiftData model identities.
    private var visibleEdgePairs: [(UUID, UUID)] {
        visibleEdges.compactMap { edge in
            guard let fromID = edge.from?.id, let toID = edge.to?.id else { return nil }
            return (fromID, toID)
        }
    }

    private var effectiveScale: CGFloat {
        max(0.5, min(3.0, scale * pendingScale))
    }

    private var effectiveOffset: CGSize {
        CGSize(width: offset.width + pendingOffset.width,
               height: offset.height + pendingOffset.height)
    }

    var body: some View {
        ZStack {
            if visibleNodes.isEmpty {
                emptyState
            } else {
                canvasLayer
            }

            // Header overlay sits at the very top, above the Canvas, so
            // the user can always tell which view they're in even mid-pan.
            VStack {
                header
                Spacer()
                if allNodes.count > nodeCap {
                    showMoreFooter
                }
            }
            .padding(20)
            .padding(.top, 40)
            .padding(.bottom, 120)
        }
        .onAppear {
            refetchEdges()
            MINDTelemetry.info("graph.tab.opened", data: [
                "nodes": "\(allNodes.count)",
                "edges": "\(allEdges.count)",
            ])
            seedIfNeeded()
        }
        .onChange(of: visibleNodes.count) { _, _ in
            // Node set changed (the user just captured something / an
            // audit completed) — refresh edges so the new neighbours
            // also render. Cheap; at our 200-node cap a refetch is a
            // single SQLite query.
            refetchEdges()
            seedIfNeeded()
        }
    }

    // MARK: - Canvas + physics tick

    /// The interactive layer. TimelineView drives one physics tick per
    /// frame, the Canvas closure paints edges + nodes, the gestures
    /// update the transform, and `.onTapGesture(coordinateSpace: .local)`
    /// records the last tap so we can find the closest node.
    private var canvasLayer: some View {
        GeometryReader { proxy in
            let size = proxy.size
            TimelineView(.animation) { _ in
                // One pure physics step per frame. Pulling the data from
                // `positions` (a @State dict) means SwiftUI invalidates
                // when we write back, redrawing the Canvas in step.
                let _ = stepPhysics(canvas: size)
                Canvas { ctx, _ in
                    drawEdges(in: ctx)
                    drawNodes(in: ctx)
                }
                .frame(width: size.width, height: size.height)
                .scaleEffect(effectiveScale, anchor: .center)
                .offset(effectiveOffset)
            }
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            pendingScale = value
                        }
                        .onEnded { value in
                            scale = max(0.5, min(3.0, scale * value))
                            pendingScale = 1.0
                        },
                    DragGesture()
                        .onChanged { value in
                            pendingOffset = value.translation
                        }
                        .onEnded { value in
                            offset.width  += value.translation.width
                            offset.height += value.translation.height
                            pendingOffset = .zero
                        }
                )
            )
            .onTapGesture(coordinateSpace: .local) { location in
                handleTap(at: location, canvas: size)
            }
        }
    }

    /// Steps the physics simulation once. Called every frame from inside
    /// the TimelineView closure. Returns Void; mutates `positions` in
    /// place. We use `Task { @MainActor in }` so the write happens on the
    /// run loop boundary, not inside the rendering pass — SwiftUI rejects
    /// state writes mid-evaluation otherwise.
    @MainActor
    private func stepPhysics(canvas size: CGSize) -> Void {
        guard !positions.isEmpty, size.width > 0, size.height > 0 else { return }
        let snapshot = Array(positions.values)
        let stepped = GraphPhysics.physicsStep(
            positions: snapshot,
            edges: visibleEdgePairs,
            bounds: size
        )
        Task { @MainActor in
            for pos in stepped {
                positions[pos.id] = pos
            }
        }
    }

    /// Pulls every Edge from the shared graph into `allEdges`. We avoid
    /// `@Query` here because the macro expansion would force the
    /// unqualified `Edge` symbol, which collides with SwiftUI's
    /// alignment enum inside a file that imports both modules.
    @MainActor
    private func refetchEdges() {
        let descriptor = FetchDescriptor<Edge>()
        if let fetched = try? context.fetch(descriptor) {
            allEdges = fetched
        }
    }

    /// Lays out one position per visible node, only when the cardinality
    /// changes. Initial seed places nodes on a circle of radius
    /// min(width,height)/3 so the simulation has somewhere meaningful to
    /// converge from. Adds new nodes near the centre if the set grows.
    @MainActor
    private func seedIfNeeded() {
        let count = visibleNodes.count
        guard count != seededForCount else { return }
        seededForCount = count
        guard count > 0 else {
            positions.removeAll()
            return
        }

        let canvasSize = UIScreen.main.bounds.size
        let radius = min(canvasSize.width, canvasSize.height) / 3
        let centerX = canvasSize.width / 2
        let centerY = canvasSize.height / 2

        var next: [UUID: GraphPhysics.NodePosition] = [:]
        for (index, node) in visibleNodes.enumerated() {
            if let existing = positions[node.id] {
                next[node.id] = existing
                continue
            }
            let angle = (Double(index) / Double(max(count, 1))) * .pi * 2
            next[node.id] = GraphPhysics.NodePosition(
                id: node.id,
                x: centerX + cos(angle) * radius,
                y: centerY + sin(angle) * radius
            )
        }
        positions = next
    }

    // MARK: - Drawing

    private func drawEdges(in ctx: GraphicsContext) {
        for edge in visibleEdges {
            guard
                let fromID = edge.from?.id,
                let toID   = edge.to?.id,
                let from   = positions[fromID],
                let to     = positions[toID]
            else { continue }
            var path = Path()
            path.move(to: CGPoint(x: from.x, y: from.y))
            path.addLine(to: CGPoint(x: to.x, y: to.y))
            ctx.stroke(
                path,
                with: .color(.white.opacity(0.3)),
                lineWidth: 1
            )
        }
    }

    private func drawNodes(in ctx: GraphicsContext) {
        for node in visibleNodes {
            guard let pos = positions[node.id] else { continue }
            let radius: CGFloat = 14
            let rect = CGRect(
                x: pos.x - radius,
                y: pos.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let tint = GraphView.kindColor(for: node.kind)
            ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.85)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.6)), lineWidth: 1.5)
        }
    }

    // MARK: - Tap routing

    /// Maps a tap from the on-screen coordinate space (post-transform)
    /// back into the simulation's coordinate space, then routes to the
    /// nearest node within 20pt. The transform is `T(p) = (p - center) *
    /// scale + center + offset`, so the inverse is
    /// `T⁻¹(p) = (p - center - offset) / scale + center`.
    @MainActor
    private func handleTap(at screenPoint: CGPoint, canvas size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let invX = (screenPoint.x - center.x - effectiveOffset.width) / effectiveScale + center.x
        let invY = (screenPoint.y - center.y - effectiveOffset.height) / effectiveScale + center.y
        let target = CGPoint(x: invX, y: invY)

        var bestNode: Node?
        var bestDistanceSquared = CGFloat(20 * 20)
        for node in visibleNodes {
            guard let pos = positions[node.id] else { continue }
            let dx = pos.x - target.x
            let dy = pos.y - target.y
            let d2 = dx * dx + dy * dy
            if d2 < bestDistanceSquared {
                bestDistanceSquared = d2
                bestNode = node
            }
        }
        if let bestNode {
            LiquidHaptics.tap()
            onSelectNode(bestNode)
        }
    }

    // MARK: - Header / empty state / overflow CTA

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LiquidPalette.aqua.opacity(0.30))
                    .frame(width: 36, height: 36)
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("graph.header.title")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("\(visibleNodes.count) / \(allNodes.count) • \(visibleEdges.count) liens")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            // Reset CTA — restores zoom/pan to the initial transform so
            // the user can recover from getting lost in the cluster.
            if scale != 1.0 || offset != .zero {
                Button {
                    LiquidHaptics.tap()
                    withAnimation(LiquidMetrics.spring) {
                        scale = 1.0
                        offset = .zero
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("graph.reset.accessibility"))
            }
        }
        .padding(14)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
    }

    private var emptyState: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LiquidPalette.lavender.opacity(0.5))
                        .frame(width: 60, height: 60)
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                }
                Text("graph.empty.title")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                Text("graph.empty.detail")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private var showMoreFooter: some View {
        Button {
            LiquidHaptics.tap()
            withAnimation(LiquidMetrics.spring) {
                nodeCap = min(nodeCap + 200, allNodes.count)
            }
        } label: {
            Text("graph.showMore")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background {
                    Capsule(style: .continuous)
                        .fill(LiquidGradient.primary)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kind → Color

    /// Mirror of the NodeKindBadge palette in Notes. Duplicated here so
    /// the Canvas pass doesn't have to round-trip through a SwiftUI view
    /// to extract a colour. Kept in sync by inspection.
    static func kindColor(for kind: NodeKind) -> Color {
        switch kind {
        case .note:    return LiquidPalette.iris
        case .capture: return LiquidPalette.iris
        case .audit:   return .orange
        case .client:  return .indigo
        case .task:    return .green
        case .event:   return .blue
        case .person:  return .pink
        case .place:   return .red
        case .file:    return .gray
        case .idea:    return .yellow
        case .habit:   return .teal
        case .goal:    return .purple
        case .journal: return .brown
        case .meeting: return LiquidPalette.iris
        case .mail:    return LiquidPalette.aqua
        }
    }
}

// MARK: - GraphPhysics (pure)

/// Pure, deterministic force-directed layout step. Lives in this file so
/// the GraphView Canvas pass can call it directly, and so the Tests
/// target can exercise the same code path without spinning up a UI.
///
/// All functions are `static` and free of UIKit / SwiftUI dependencies —
/// they take `CGFloat` / `CGSize`, return new value types, mutate nothing
/// outside their return value. That's what makes the simulation testable.
///
/// Constants
/// ---------
/// - Spring constant `k = 0.05`, target rest length `100pt`.
/// - Coulomb constant `2000 / d²` with a floor at `d = 4pt` so a pair of
///   colocated nodes can't shoot to infinity.
/// - Damping `0.85` per step.
/// - Integration step `0.016s` (60 Hz tick).
/// - Velocity clamp `200 pt/s` magnitude to keep the simulation visually
///   stable when the user adds many nodes at once.
enum GraphPhysics {

    /// Per-node position + velocity. `Identifiable` so SwiftUI iteration
    /// (and our `[UUID: NodePosition]` dict) can key on it directly.
    struct NodePosition: Identifiable, Equatable, Sendable {
        let id: UUID
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat = 0
        var vy: CGFloat = 0

        init(id: UUID, x: CGFloat, y: CGFloat, vx: CGFloat = 0, vy: CGFloat = 0) {
            self.id = id
            self.x = x
            self.y = y
            self.vx = vx
            self.vy = vy
        }
    }

    // Tunables — exposed `static let` so tests can assert on them and
    // future-tuning can happen in one place.
    static let springK: CGFloat = 0.05
    static let restLength: CGFloat = 100
    static let coulombK: CGFloat = 2000
    static let minDistance: CGFloat = 4
    static let damping: CGFloat = 0.85
    static let dt: CGFloat = 0.016
    static let maxVelocity: CGFloat = 200
    static let padding: CGFloat = 30

    /// One simulation step. Returns the new positions; never mutates the
    /// input. Empty `positions` returns empty. Bounds < (1,1) returns the
    /// input unchanged (Canvas hasn't sized yet).
    static func physicsStep(
        positions: [NodePosition],
        edges: [(UUID, UUID)],
        bounds: CGSize
    ) -> [NodePosition] {
        guard !positions.isEmpty else { return [] }
        guard bounds.width > 1, bounds.height > 1 else { return positions }

        // Index positions by id for O(1) lookup by edge endpoints. We
        // mutate `result` directly and copy out at the end.
        var indexByID: [UUID: Int] = [:]
        indexByID.reserveCapacity(positions.count)
        for (i, p) in positions.enumerated() {
            indexByID[p.id] = i
        }
        var result = positions

        // Accumulate forces per node. Indexed parallel to `result`.
        var forces = Array(repeating: CGPoint.zero, count: result.count)

        // Coulomb repulsion: every pair of nodes pushes each other apart
        // with force ~ k / d². O(n²); fine at our 200-node cap.
        if result.count >= 2 {
            for i in 0..<result.count {
                for j in (i + 1)..<result.count {
                    let dx = result[j].x - result[i].x
                    let dy = result[j].y - result[i].y
                    var d  = (dx * dx + dy * dy).squareRoot()
                    if d < minDistance { d = minDistance }
                    let magnitude = coulombK / (d * d)
                    let fx = (dx / d) * magnitude
                    let fy = (dy / d) * magnitude
                    forces[i].x -= fx
                    forces[i].y -= fy
                    forces[j].x += fx
                    forces[j].y += fy
                }
            }
        }

        // Spring attraction along every edge: force ~ k * (d - restLength)
        // pulling the two endpoints together (or pushing apart if too close).
        for (fromID, toID) in edges {
            guard
                let i = indexByID[fromID],
                let j = indexByID[toID]
            else { continue }
            let dx = result[j].x - result[i].x
            let dy = result[j].y - result[i].y
            var d  = (dx * dx + dy * dy).squareRoot()
            if d < minDistance { d = minDistance }
            let displacement = d - restLength
            let magnitude = springK * displacement
            let fx = (dx / d) * magnitude
            let fy = (dy / d) * magnitude
            forces[i].x += fx
            forces[i].y += fy
            forces[j].x -= fx
            forces[j].y -= fy
        }

        // Integrate: v += f * dt, then damp, then x += v * dt. Clamp
        // velocity magnitude so the simulation never explodes.
        for i in 0..<result.count {
            var vx = result[i].vx + forces[i].x * dt
            var vy = result[i].vy + forces[i].y * dt
            vx *= damping
            vy *= damping
            let speed = (vx * vx + vy * vy).squareRoot()
            if speed > maxVelocity {
                let scaleDown = maxVelocity / speed
                vx *= scaleDown
                vy *= scaleDown
            }
            result[i].vx = vx
            result[i].vy = vy
            result[i].x  += vx * dt
            result[i].y  += vy * dt
        }

        // Bounds clamp so nodes can't drift offscreen. We keep them
        // `padding` inside the edge of the canvas. When a node hits a
        // wall we also zero its perpendicular velocity component so it
        // doesn't keep grinding against the edge.
        for i in 0..<result.count {
            if result[i].x < padding {
                result[i].x = padding
                if result[i].vx < 0 { result[i].vx = 0 }
            }
            if result[i].x > bounds.width - padding {
                result[i].x = bounds.width - padding
                if result[i].vx > 0 { result[i].vx = 0 }
            }
            if result[i].y < padding {
                result[i].y = padding
                if result[i].vy < 0 { result[i].vy = 0 }
            }
            if result[i].y > bounds.height - padding {
                result[i].y = bounds.height - padding
                if result[i].vy > 0 { result[i].vy = 0 }
            }
        }

        return result
    }
}
