import Foundation

/// v1.0-alpha.19 — Pure value type computing the half-circle floating
/// positions for the `SpatialAuditTheater` immersive surface.
///
/// The Audit Theater renders an audit's synthesis on a central panel
/// and floats every quick win in a half-arc around the viewer. This
/// type owns the math — given the number of quick wins, return the
/// angular position (radians) and the depth/height offset (metres) for
/// every card. The `SpatialAuditTheaterImmersive` SwiftUI surface
/// reads those positions to place `RealityKit` entities at runtime.
///
/// Why a pure value type
/// --------------------
/// - Deterministic: every input N → identical output, lets the future
///   visionOS surface diff between layout updates without re-rendering.
/// - Testable: no `RealityView`, no `SwiftUI`, no `XRDevice` reach
///   means the tests run on the iOS host's test bundle without the
///   visionOS simulator runtime.
/// - Clamped: the arc tops out at `maxPlacements = 8`. Eight is the
///   most cards a viewer can scan in a single head sweep without
///   losing peripheral acuity; past that, callers truncate or page.
///
/// Coordinate convention mirrors `SpatialAnchor`: `(0, 0, 0)` is the
/// viewer's head pose at theater open, `+x` = right, `+y` = up,
/// `-z` = forward. Units are radians for angles and metres for
/// position. The arc lives at radius `arcRadiusMeters` in front of
/// the viewer, spans `arcHalfAngle` to either side, and centres on
/// `-z` (i.e. straight ahead).
public enum TheaterPlacement {

    /// One quick-win card's position on the half-arc. The SwiftUI /
    /// RealityKit surface mints an entity at `(x, y, z)` rotated to
    /// face the origin via `SpatialAnchor.facing(.origin)`.
    public struct Placement: Sendable, Hashable {
        /// Zero-based index of this placement in the arc, walking
        /// left → right. Useful for matching the placement back to
        /// the input `QuickWin.id` by index in the caller.
        public let index: Int
        /// Horizontal offset in metres.
        public let x: Double
        /// Vertical offset in metres (cards slope up subtly so the
        /// outer cards on the periphery sit slightly higher than the
        /// inner ones — keeps the arc readable for a standing viewer).
        public let y: Double
        /// Depth offset in metres. Constant across the arc — every
        /// card sits at exactly `-arcRadiusMeters` to preserve the
        /// circular silhouette.
        public let z: Double
        /// Angle in radians. `0` = directly in front of the viewer,
        /// `+` = right, `-` = left. Wrapped into `[-π, π]`.
        public let angle: Double
    }

    /// Maximum number of quick-win cards the arc accommodates. Beyond
    /// this the viewer cannot scan the full arc in one head sweep —
    /// callers must page or truncate. Tuned to 8 by symmetry of the
    /// 120° spread (four cards per side) and validated by the test
    /// suite.
    public static let maxPlacements: Int = 8

    /// Distance in metres from the viewer's head pose to the arc.
    /// 1.6 m places the cards just past arm's reach — close enough to
    /// read 18 pt body copy, far enough to read the full arc without
    /// the eyes saccading wildly.
    public static let arcRadiusMeters: Double = 1.6

    /// Half-angle of the arc in radians. 60° → 120° total spread
    /// matches Apple's TV "immersive cinema" surface and the
    /// `SpatialLayoutBuilder.cinemaArcHalfAngle` constant the existing
    /// substrate already locks for the `cinema` preset.
    public static let arcHalfAngle: Double = .pi / 3.0

    /// Vertical sweep of the arc in metres. The outermost card on
    /// either side sits this much above the innermost card — keeps
    /// the periphery readable for a standing viewer without forcing
    /// them to tilt their head up.
    public static let verticalRiseMeters: Double = 0.18

    // MARK: - Public

    /// Returns the placements for `count` quick-win cards on the
    /// half-arc. Empty input → empty output. Counts above
    /// `maxPlacements` are clamped (the caller is responsible for
    /// paging / truncating the input list before calling).
    public static func placements(count: Int) -> [Placement] {
        guard count > 0 else { return [] }
        let clampedCount = Swift.min(count, maxPlacements)

        if clampedCount == 1 {
            // Single card sits dead centre at the arc radius.
            return [
                Placement(
                    index: 0,
                    x: 0,
                    y: 0,
                    z: -arcRadiusMeters,
                    angle: 0
                ),
            ]
        }

        // Distribute the cards evenly across the full 120° spread.
        // For N cards the step between adjacent cards is the full
        // spread divided by `N - 1`, with the first card at
        // `-arcHalfAngle` and the last at `+arcHalfAngle`.
        let totalSpread = 2 * arcHalfAngle
        let step = totalSpread / Double(clampedCount - 1)

        return (0..<clampedCount).map { index in
            let angle = -arcHalfAngle + step * Double(index)
            // The vertical rise grows with the distance from centre
            // so the outer cards sit higher than the inner ones.
            // Magnitude is clamped to `verticalRiseMeters` at the
            // extremes; cards near centre stay at eye level.
            let normalized = abs(angle) / arcHalfAngle
            let y = verticalRiseMeters * normalized
            let x = arcRadiusMeters * sin(angle)
            let z = -arcRadiusMeters * cos(angle)
            return Placement(
                index: index,
                x: x,
                y: y,
                z: z,
                angle: angle
            )
        }
    }

    /// Returns the central synthesis-panel placement. Always sits at
    /// `(0, 0, -arcRadiusMeters)` facing the viewer, slightly larger
    /// than the quick-win cards so the synthesis text reads as the
    /// hero of the theater.
    public static var synthesisPanel: Placement {
        Placement(
            index: -1,
            x: 0,
            y: 0,
            z: -arcRadiusMeters,
            angle: 0
        )
    }
}
