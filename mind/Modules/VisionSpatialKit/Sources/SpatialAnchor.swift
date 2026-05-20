import Foundation

/// v0.25.1 — Pure substrate behind the deferred Vision Pro spatial
/// layout. Same model as v0.22.1 / v0.31.1 / v1.0-alpha.8: lock the
/// value types + the layout math + the persistence shape ahead of the
/// visionOS App target itself, so the future visionOS surface plugs
/// in without re-rolling the data model.
///
/// `SpatialAnchor` is a frozen 3D point + orientation that any
/// SwiftUI `Model3D` / `RealityView` in the future visionOS target
/// reads to render a floating panel at a stable location in the
/// user's room. Units are metres (Apple's RealityKit convention);
/// yaw / pitch / roll are radians.
///
/// Design intent
/// -------------
/// - **Pure SIMD-free**: no `simd_float3`, no `RealityKit` import.
///   Lets the substrate ship now on iOS-only target builds and
///   round-trip through `Codable` for on-disk persistence.
/// - **Codable + Sendable + Hashable**: every anchor crosses
///   threads (the layout builder runs on a background task) and
///   persists to disk (one JSON file per layout preset under
///   `Documents/spatial-layouts/`).
/// - **Origin convention**: `(0, 0, 0)` is the user's head at app
///   launch; `+x` = right, `+y` = up, `-z` = forward (away from
///   the user). Matches RealityKit's right-handed coordinate
///   system so the visionOS surface can read these values verbatim.
public struct SpatialAnchor: Codable, Sendable, Hashable {

    /// Horizontal offset in metres. `-x` = left of head pose,
    /// `+x` = right. Clamped to ±10 metres at construction so a
    /// programmer error (e.g. mistaking centimetres for metres)
    /// never spawns a panel outside the user's room.
    public let x: Double

    /// Vertical offset in metres. `+y` = above eye line.
    /// Clamped to ±10 m.
    public let y: Double

    /// Depth offset in metres. `-z` = in front of the user
    /// (away from head pose). Clamped to ±10 m.
    public let z: Double

    /// Rotation around the Y axis in radians (how the panel
    /// faces the user). `0` = facing the user directly.
    /// Wrapped into `[-π, π]` at construction.
    public let yaw: Double

    /// Rotation around the X axis in radians (pitch — looking up
    /// or down at the panel). `0` = panel is vertical.
    /// Wrapped into `[-π, π]`.
    public let pitch: Double

    /// Rotation around the Z axis in radians (roll — tilting
    /// the panel left or right). `0` = panel is upright.
    /// Wrapped into `[-π, π]`.
    public let roll: Double

    public init(
        x: Double,
        y: Double,
        z: Double,
        yaw: Double = 0,
        pitch: Double = 0,
        roll: Double = 0
    ) {
        self.x = Self.clamp(x, min: -10, max: 10)
        self.y = Self.clamp(y, min: -10, max: 10)
        self.z = Self.clamp(z, min: -10, max: 10)
        self.yaw = Self.wrapAngle(yaw)
        self.pitch = Self.wrapAngle(pitch)
        self.roll = Self.wrapAngle(roll)
    }

    /// Anchor at the origin (head pose at launch). Useful default
    /// when a layout preset opens before the user has aimed.
    public static let origin = SpatialAnchor(x: 0, y: 0, z: 0)

    /// Returns a new anchor translated by the supplied vector.
    /// Useful for "next-to" layouts where the builder takes a base
    /// anchor and walks outward in column / row order.
    public func translated(byX dx: Double, y dy: Double, z dz: Double) -> SpatialAnchor {
        SpatialAnchor(
            x: x + dx,
            y: y + dy,
            z: z + dz,
            yaw: yaw,
            pitch: pitch,
            roll: roll
        )
    }

    /// Returns a new anchor rotated to face the supplied target
    /// position (recomputes yaw via `atan2`, pitch via the
    /// vertical opposite/hypotenuse ratio). Used by the
    /// "cinema-arc" preset so every panel curves to face the
    /// viewer's head pose at the origin.
    public func facing(_ target: SpatialAnchor) -> SpatialAnchor {
        let dx = target.x - x
        let dy = target.y - y
        let dz = target.z - z

        let newYaw = atan2(dx, -dz) // -z = forward
        let horizontalDistance = sqrt(dx * dx + dz * dz)
        let newPitch = horizontalDistance > 0 ? atan2(dy, horizontalDistance) : 0

        return SpatialAnchor(
            x: x,
            y: y,
            z: z,
            yaw: newYaw,
            pitch: newPitch,
            roll: roll
        )
    }

    // MARK: - Private

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }

    private static func wrapAngle(_ radians: Double) -> Double {
        var wrapped = radians.truncatingRemainder(dividingBy: 2 * .pi)
        if wrapped > .pi {
            wrapped -= 2 * .pi
        } else if wrapped < -.pi {
            wrapped += 2 * .pi
        }
        return wrapped
    }
}
