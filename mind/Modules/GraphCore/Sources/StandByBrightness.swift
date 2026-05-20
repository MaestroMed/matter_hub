import Foundation

/// v1.2.0 (carried in from the v0.28.1 cron iteration that landed
/// the SettingsView preview surface but not the substrate).
///
/// Pure value types + namespace describing the time-of-day phase the
/// StandByDashboardWidget uses to dim its gradient overnight. Lives
/// in GraphCore so both Settings (which surfaces a preview row) and
/// Widgets (the actual consumer) can import without circular linkage.
public enum StandByPhase: String, Sendable, Codable, CaseIterable, Equatable {
    case day
    case dusk
    case night
    case deepNight
}

/// Pure namespace — no state, every call deterministic in the hour
/// component of its `Date` argument. Locked by
/// `StandByBrightnessAdapterTests` (carried in from the cron's
/// uncommitted work-in-progress; this stub provides the minimal
/// public API the Settings preview row + the widget gradient need).
public enum StandByBrightnessAdapter {

    /// Resolves the phase from a wall-clock hour:
    ///   - day (07..18)
    ///   - dusk (19..20 and 06)
    ///   - night (21..23 and 05)
    ///   - deepNight (00..04)
    public static func phase(for date: Date) -> StandByPhase {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 7...18:           return .day
        case 6, 19, 20:        return .dusk
        case 5, 21, 22, 23:    return .night
        default:               return .deepNight
        }
    }

    /// Returns the multiplier the widget applies to its container
    /// gradient. When `nightDimEnabled` is false the multiplier
    /// stays at 1.0 (full daytime brightness) regardless of phase.
    public static func dimOpacity(
        for phase: StandByPhase,
        nightDimEnabled: Bool
    ) -> Double {
        guard nightDimEnabled else { return 1.0 }
        switch phase {
        case .day:       return 1.0
        case .dusk:      return 0.7
        case .night:     return 0.45
        case .deepNight: return 0.25
        }
    }

    /// FR-localised label for the Settings preview row. Inlined
    /// rather than routed through `Localizable.xcstrings` so the
    /// substrate stays self-contained (the cron's strings batch
    /// for v0.28.1 didn't ship; FR-only matches the rest of the
    /// in-progress preview row that surfaces here).
    public static func displayLabel(for phase: StandByPhase) -> String {
        switch phase {
        case .day:       return "Jour"
        case .dusk:      return "Crépuscule"
        case .night:     return "Nuit"
        case .deepNight: return "Nuit profonde"
        }
    }
}
