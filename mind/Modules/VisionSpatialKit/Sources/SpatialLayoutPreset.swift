import Foundation

/// v0.25.1 — Pure enumeration of the named layouts the visionOS
/// surface will offer. Three presets ship now (Bento / Cinema /
/// Atelier) so the SwiftUI surface lands with a curated set rather
/// than a free-form arrangement, and so the layout builder has
/// concrete acceptance criteria to test against.
public enum SpatialLayoutPreset: String, Codable, Sendable, Hashable, CaseIterable {

    /// "Bento" — 3-column grid 1.2 m in front of the user, panels
    /// arranged left-to-right, top-to-bottom. Mirrors the existing
    /// iPad Stage Manager layout (v0.24.1) so the user's mental
    /// model carries over.
    case bento

    /// "Cinema" — a single panel front-and-centre at 2.0 m, with
    /// every other panel curved into a 120° arc to the user's left
    /// and right. Inspired by the visionOS "immersive cinema"
    /// pattern Apple uses for the AppleTV app.
    case cinema

    /// "Atelier" — focus-friendly: the focus timer floats centrally
    /// at 1.0 m as a glowing sphere, every other panel pushed
    /// behind the user's peripheral vision (off to one side at
    /// ±1.0 m horizontal). Used during Deep Focus sessions.
    case atelier

    /// FR-locale display name (the cockpit is FR-first).
    public var displayNameFR: String {
        switch self {
        case .bento: return "Bento"
        case .cinema: return "Cinéma"
        case .atelier: return "Atelier"
        }
    }

    /// EN display name for the public TestFlight.
    public var displayNameEN: String {
        switch self {
        case .bento: return "Bento"
        case .cinema: return "Cinema"
        case .atelier: return "Atelier"
        }
    }

    /// One-line description of the layout, FR-first.
    public var subtitleFR: String {
        switch self {
        case .bento: return "Grille 3 colonnes devant toi"
        case .cinema: return "Arc cinéma à 120°"
        case .atelier: return "Sphère focus centrale, panneaux en périphérie"
        }
    }
}
