import XCTest
import CoreGraphics
@testable import MIND

/// v0.15 — Locks the pure force-directed layout step that drives the
/// new GraphView Canvas. The step is the heart of the simulation —
/// every visible motion goes through it. If any of these break the
/// graph either explodes (nodes shoot offscreen) or freezes (forces
/// cancel out incorrectly).
///
/// Strategy
/// --------
/// Build a tiny `[NodePosition]` by hand, run one or N steps, then
/// assert on the resulting geometry. We never touch SwiftUI here: the
/// physics is a pure function over value types, which is exactly what
/// makes it testable without simulator boot or @MainActor hops.
final class GraphPhysicsTests: XCTestCase {

    // MARK: - Helpers

    private let canvas = CGSize(width: 400, height: 800)

    private func node(_ id: UUID, x: CGFloat, y: CGFloat, vx: CGFloat = 0, vy: CGFloat = 0) -> GraphPhysics.NodePosition {
        GraphPhysics.NodePosition(id: id, x: x, y: y, vx: vx, vy: vy)
    }

    private func distance(_ a: GraphPhysics.NodePosition, _ b: GraphPhysics.NodePosition) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Run `n` consecutive physics steps. Used by tests that need a
    /// few ticks of integration before the geometry changes
    /// meaningfully (a single 16ms tick at low force barely moves a
    /// node visually).
    private func step(_ positions: [GraphPhysics.NodePosition], edges: [(UUID, UUID)], times n: Int) -> [GraphPhysics.NodePosition] {
        var current = positions
        for _ in 0..<n {
            current = GraphPhysics.physicsStep(positions: current, edges: edges, bounds: canvas)
        }
        return current
    }

    // MARK: - Empty / degenerate inputs

    func test_emptyPositions_returnEmpty() {
        let result = GraphPhysics.physicsStep(positions: [], edges: [], bounds: canvas)
        XCTAssertTrue(result.isEmpty, "Empty input must return empty output")
    }

    func test_zeroBounds_returnsInputUnchanged() {
        let a = UUID()
        let positions = [node(a, x: 100, y: 100)]
        let result = GraphPhysics.physicsStep(
            positions: positions,
            edges: [],
            bounds: CGSize(width: 0, height: 0)
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.x, 100, "Bounds < 1 = Canvas not sized yet, no integration")
        XCTAssertEqual(result.first?.y, 100)
    }

    // MARK: - Attraction along edges

    func test_twoConnectedNodesAtRestLength_areAttractedTowardEachOther() {
        // restLength = 100 — when the distance is much larger (300),
        // the spring should pull both nodes closer. We assert on the
        // distance shrinking after a handful of steps.
        let a = UUID()
        let b = UUID()
        let initial = [
            node(a, x: 100, y: 400),
            node(b, x: 400, y: 400),
        ]
        let initialDistance = distance(initial[0], initial[1])
        XCTAssertGreaterThan(initialDistance, GraphPhysics.restLength, "Setup precondition")

        let result = step(initial, edges: [(a, b)], times: 20)
        let finalDistance = distance(result[0], result[1])
        XCTAssertLessThan(finalDistance, initialDistance,
                          "Spring attraction must reduce distance when nodes start far from restLength")
    }

    // MARK: - Repulsion between unconnected nodes

    func test_twoClosebyDisconnectedNodes_arePushedApartByRepulsion() {
        // No edge, very close — Coulomb repulsion should dominate and
        // push them apart on the first step.
        let a = UUID()
        let b = UUID()
        let initial = [
            node(a, x: 200, y: 400),
            node(b, x: 205, y: 400),
        ]
        let initialDistance = distance(initial[0], initial[1])

        let result = step(initial, edges: [], times: 5)
        let finalDistance = distance(result[0], result[1])
        XCTAssertGreaterThan(finalDistance, initialDistance,
                             "Coulomb repulsion must increase distance for unconnected close nodes")
    }

    // MARK: - Damping

    func test_dampingReducesVelocityMagnitude() {
        // A single isolated node with a non-zero velocity and no
        // forces acting on it should slow down each step (damping = 0.85).
        let a = UUID()
        let initial = [node(a, x: 200, y: 400, vx: 100, vy: 0)]
        let result = GraphPhysics.physicsStep(positions: initial, edges: [], bounds: canvas)
        let initialSpeed = (initial[0].vx * initial[0].vx + initial[0].vy * initial[0].vy).squareRoot()
        let finalSpeed   = (result[0].vx * result[0].vx + result[0].vy * result[0].vy).squareRoot()
        XCTAssertLessThan(finalSpeed, initialSpeed,
                          "Damping (0.85) must shrink |v| each step when no force balances it")
    }

    // MARK: - Bounds clamp

    func test_boundsClamp_keepsNodesInsideCanvas_afterOutwardVelocity() {
        // Node at the right edge with a strong outward velocity. After
        // one step the bounds clamp must hold it inside the canvas
        // and zero out the offending vx component.
        let a = UUID()
        let initial = [node(a, x: 399, y: 400, vx: 500, vy: 0)]
        let result = GraphPhysics.physicsStep(positions: initial, edges: [], bounds: canvas)
        XCTAssertLessThanOrEqual(result[0].x, canvas.width - GraphPhysics.padding,
                                 "Bounds clamp must keep nodes inside the canvas right edge")
        XCTAssertGreaterThanOrEqual(result[0].x, GraphPhysics.padding,
                                    "Bounds clamp must respect padding on the left edge too")
    }

    func test_boundsClamp_zeroesOutwardVelocity() {
        // After being clamped against the right wall, vx must be <= 0
        // — otherwise the node would just grind against the edge for
        // the rest of the simulation.
        let a = UUID()
        let initial = [node(a, x: 399, y: 400, vx: 500, vy: 0)]
        let result = GraphPhysics.physicsStep(positions: initial, edges: [], bounds: canvas)
        XCTAssertLessThanOrEqual(result[0].vx, 0,
                                 "Outward velocity must be zeroed when the node hits the wall")
    }

    // MARK: - Disconnected components

    func test_disconnectedComponents_stayApartUnderRepulsion() {
        // Three nodes — two connected on the left, one well-separated
        // on the right. The lone node sits beyond the spring's rest
        // length (100pt) so the system is in repulsion territory. The
        // pair's centre-of-mass should not drift towards the lone
        // node, AND the lone node should not collapse onto the pair.
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let initial = [
            node(a, x: 100, y: 400),
            node(b, x: 200, y: 400),
            node(c, x: 350, y: 400),
        ]

        let result = step(initial, edges: [(a, b)], times: 30)
        guard let resultC = result.first(where: { $0.id == c }),
              let resultA = result.first(where: { $0.id == a }),
              let resultB = result.first(where: { $0.id == b })
        else {
            XCTFail("Lost a node during physicsStep")
            return
        }
        // The lone node and the pair's centre-of-mass should remain
        // visibly separated — at least 80pt apart. Stronger than just
        // "didn't move" because we want to catch the case where the
        // simulation converges to a single cluster.
        let pairCentreX = (resultA.x + resultB.x) / 2
        let pairCentreY = (resultA.y + resultB.y) / 2
        let dx = resultC.x - pairCentreX
        let dy = resultC.y - pairCentreY
        let separation = (dx * dx + dy * dy).squareRoot()
        XCTAssertGreaterThan(separation, 80,
                             "Disconnected components must remain visibly separated under repulsion")
    }

    // MARK: - Determinism

    func test_physicsStep_isPureAndDeterministic() {
        // Same inputs → same outputs. Calling the function twice on
        // the same positions array yields identical results.
        let a = UUID()
        let b = UUID()
        let initial = [
            node(a, x: 100, y: 200),
            node(b, x: 300, y: 200),
        ]
        let first = GraphPhysics.physicsStep(
            positions: initial,
            edges: [(a, b)],
            bounds: canvas
        )
        let second = GraphPhysics.physicsStep(
            positions: initial,
            edges: [(a, b)],
            bounds: canvas
        )
        XCTAssertEqual(first, second,
                       "physicsStep must be a pure function — identical inputs yield identical outputs")
    }
}
