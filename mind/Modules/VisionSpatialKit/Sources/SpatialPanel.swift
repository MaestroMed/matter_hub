import Foundation

/// v0.25.1 — Pure descriptor of a single floating panel in the future
/// visionOS spatial layout. Lives outside the visionOS target so the
/// layout math + the persistence shape lock now, ahead of the
/// `RealityView` surface that will render them.
///
/// Every panel carries:
/// - a stable `id` (UUID) so the visionOS surface can diff panels
///   between layout updates without remounting RealityKit entities;
/// - a `kind` driving the panel's content (focus timer becomes a
///   glowing sphere; audit reports float as readable panels; notes
///   render as legible 8.5 × 11 cards);
/// - a `SpatialAnchor` for position + orientation;
/// - a `size` in metres so the SwiftUI surface can mint a
///   `RealityView` with `.frame(width:depth:height:)` directly.
public struct SpatialPanel: Codable, Sendable, Hashable, Identifiable {

    /// Content classification driving the visionOS surface's render
    /// branch. Raw values are stable strings so on-disk JSON
    /// migrates cleanly between releases.
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        /// Deep Focus countdown — visionOS renders this as a
        /// glowing sphere with the timer text floating above.
        case focusTimer

        /// `AuditReport` — visionOS renders the full report as a
        /// 1.6 × 1.0 m readable panel, scrollable with eye + pinch.
        case auditReport

        /// Note / capture body — visionOS renders this as a
        /// 0.5 × 0.7 m floating card.
        case noteCard

        /// Project / Lead inbox row — visionOS renders this as a
        /// small 0.4 × 0.3 m chip.
        case projectChip

        /// Catch-all for surfaces that don't yet have a dedicated
        /// kind. Renders as a plain Liquid Glass panel of the
        /// supplied size.
        case generic
    }

    /// Stable identity for diffing panels between layout updates.
    public let id: UUID

    /// Content classification.
    public let kind: Kind

    /// Position + orientation in 3D space.
    public let anchor: SpatialAnchor

    /// Panel width in metres. Clamped to `[0.05, 4.0]` so a
    /// programmer error never spawns a 100-metre panel.
    public let widthMeters: Double

    /// Panel height in metres. Clamped to `[0.05, 4.0]`.
    public let heightMeters: Double

    /// Optional human-readable title surfaced on the panel's chrome.
    /// Trimmed to 80 characters at construction so a runaway
    /// transcript can't blow the panel's title bar.
    public let title: String

    /// Optional ID of the underlying domain object the panel is
    /// rendering (Node UUID for notes, AuditReport UUID for
    /// audits, etc.). Lets the SwiftUI surface route taps back
    /// into the host app's navigation without a secondary lookup.
    public let payloadID: UUID?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        anchor: SpatialAnchor,
        widthMeters: Double,
        heightMeters: Double,
        title: String = "",
        payloadID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.anchor = anchor
        self.widthMeters = Self.clamp(widthMeters)
        self.heightMeters = Self.clamp(heightMeters)
        self.title = String(title.prefix(80))
        self.payloadID = payloadID
    }

    /// Returns a copy of this panel with a new anchor. Used by the
    /// layout builder to walk a base anchor across a grid.
    public func anchored(at newAnchor: SpatialAnchor) -> SpatialPanel {
        SpatialPanel(
            id: id,
            kind: kind,
            anchor: newAnchor,
            widthMeters: widthMeters,
            heightMeters: heightMeters,
            title: title,
            payloadID: payloadID
        )
    }

    /// Returns the diagonal of the panel in metres. Used by the
    /// layout builder to compute a safe radial spacing so two
    /// panels never visually collide.
    public var diagonalMeters: Double {
        sqrt(widthMeters * widthMeters + heightMeters * heightMeters)
    }

    // MARK: - Private

    private static func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, 0.05), 4.0)
    }
}
