import Foundation

/// v0.25.1 — Pure deterministic builder that turns an ordered list of
/// `SpatialPanel`s + a `SpatialLayoutPreset` into the same panels
/// re-anchored in 3D space. The visionOS surface (future) feeds the
/// builder its current scene and writes the result back as the
/// `RealityView` content; on iOS today the math runs in tests only.
///
/// Why a pure builder
/// ------------------
/// The math is the only thing that needs to be deterministic +
/// testable. Spawning RealityKit entities, hover effects, and the
/// `WindowGroup(immersionStyle:)` plumbing all live in the future
/// visionOS App target. Splitting the math out means:
/// - Every preset is locked by a test (panel count → expected
///   arc, grid columns, sphere position).
/// - The layout can be persisted via `SpatialLayoutStore` without
///   touching RealityKit.
/// - A future "user dragged this panel" event can be folded back
///   into the layout via `withCustomAnchor(_:for:)` and survive
///   across launches.
public enum SpatialLayoutBuilder {

    // MARK: - Public knobs

    /// Distance in metres the Bento grid sits in front of the user
    /// (`-z` direction). Tuned to 1.2 m — close enough to read,
    /// far enough to fit a 3-column grid in the user's FoV.
    public static let bentoDepth: Double = -1.2

    /// Distance in metres the Cinema arc's hero panel sits in
    /// front of the user. Apple's TV app uses ~2.0 m for the
    /// immersive view; matching that distance keeps the
    /// recognition curve consistent.
    public static let cinemaDepth: Double = -2.0

    /// Atelier preset — distance of the central focus sphere from
    /// the user. Tighter than Bento so the sphere reads as a
    /// "deep focus token" the user is meant to gaze at directly.
    public static let atelierDepth: Double = -1.0

    /// Cinema preset arc half-angle in radians (60° → 120° total).
    public static let cinemaArcHalfAngle: Double = .pi / 3.0

    /// Bento preset — number of columns in the grid. Tuned for
    /// visionOS's FoV: 3 columns × N rows reads cleanly without
    /// the user needing to turn their head.
    public static let bentoColumns: Int = 3

    /// Bento preset — horizontal step between adjacent columns,
    /// in metres. Tuned so a 0.55 m wide panel never visually
    /// collides with its neighbour.
    public static let bentoColumnStep: Double = 0.7

    /// Bento preset — vertical step between adjacent rows, in
    /// metres. Tuned so a 0.4 m tall panel never collides.
    public static let bentoRowStep: Double = 0.55

    // MARK: - Build

    /// Returns the supplied panels re-anchored per the preset.
    /// The panel ordering is preserved (the SwiftUI surface
    /// renders them in input order); only the `.anchor` field
    /// changes. Empty input returns empty output.
    public static func layout(
        panels: [SpatialPanel],
        preset: SpatialLayoutPreset
    ) -> [SpatialPanel] {
        guard !panels.isEmpty else { return [] }
        switch preset {
        case .bento: return layoutBento(panels: panels)
        case .cinema: return layoutCinema(panels: panels)
        case .atelier: return layoutAtelier(panels: panels)
        }
    }

    // MARK: - Bento

    private static func layoutBento(panels: [SpatialPanel]) -> [SpatialPanel] {
        // Centre the grid horizontally — for `bentoColumns = 3`, the
        // middle column sits at x = 0, the left column at x = -step,
        // the right column at x = +step.
        let columnOffset = Double(bentoColumns - 1) / 2.0

        return panels.enumerated().map { index, panel in
            let column = index % bentoColumns
            let row = index / bentoColumns
            let xOffset = (Double(column) - columnOffset) * bentoColumnStep
            // Top row above eye line, walk down with each row.
            let yOffset = -Double(row) * bentoRowStep + bentoRowStep
            let anchor = SpatialAnchor(
                x: xOffset,
                y: yOffset,
                z: bentoDepth
            )
            return panel.anchored(at: anchor)
        }
    }

    // MARK: - Cinema

    private static func layoutCinema(panels: [SpatialPanel]) -> [SpatialPanel] {
        // Hero (index 0) sits dead centre. Every other panel splays
        // out into a 120° arc — odd indices to the left, even to the
        // right, walking outward in `cinemaArcHalfAngle / N` steps
        // where N is the number of side panels.
        let sideCount = panels.count - 1
        let stepAngle: Double
        if sideCount > 0 {
            // Distribute the side panels across the half-arc so the
            // first side panel sits at ±(stepAngle), not ±(arcHalfAngle).
            stepAngle = cinemaArcHalfAngle / Double((sideCount + 1) / 2 + 1)
        } else {
            stepAngle = 0
        }

        return panels.enumerated().map { index, panel in
            if index == 0 {
                let anchor = SpatialAnchor(x: 0, y: 0, z: cinemaDepth)
                return panel.anchored(at: anchor)
            }
            // Side panels: odd → left, even → right.
            let side = (index % 2 == 1) ? -1.0 : 1.0
            let depth = abs(cinemaDepth)
            let angleIndex = Double((index + 1) / 2)
            let angle = side * stepAngle * angleIndex
            let anchor = SpatialAnchor(
                x: depth * sin(angle),
                y: 0,
                z: -depth * cos(angle)
            )
            return panel.anchored(at: anchor).facingOrigin()
        }
    }

    // MARK: - Atelier

    private static func layoutAtelier(panels: [SpatialPanel]) -> [SpatialPanel] {
        // The focus timer (first `.focusTimer` panel found, or
        // index 0 if none) sits centrally. Every other panel pushes
        // off to ±1.0 m horizontal, alternating sides.
        let focusIndex = panels.firstIndex(where: { $0.kind == .focusTimer }) ?? 0

        var sideToggle = 0
        return panels.enumerated().map { index, panel in
            if index == focusIndex {
                let anchor = SpatialAnchor(x: 0, y: 0, z: atelierDepth)
                return panel.anchored(at: anchor)
            }
            sideToggle += 1
            let side = (sideToggle % 2 == 1) ? -1.0 : 1.0
            let anchor = SpatialAnchor(
                x: side * 1.0,
                y: 0,
                z: atelierDepth
            )
            return panel.anchored(at: anchor).facingOrigin()
        }
    }
}

private extension SpatialPanel {
    func facingOrigin() -> SpatialPanel {
        let rotated = anchor.facing(.origin)
        return self.anchored(at: rotated)
    }
}
