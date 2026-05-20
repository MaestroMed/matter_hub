import Foundation

/// Pure value type holding the 7-day aggregation HealthReader produces.
///
/// Kept deliberately tiny — three counters that the HomeView "Cette
/// semaine" card renders directly. No HealthKit types leak through the
/// public surface so the rest of MIND can depend on `HealthInsights`
/// without dragging in the HealthKit framework (and without breaking on
/// devices / simulators where HealthKit is unavailable).
///
/// `.empty` is the documented soft-fail value used everywhere the
/// reader can't produce data: permission denied, HealthKit unavailable
/// (iPad without iPhone, Simulator with no seeded data), or the user
/// opted out via Settings. The card hides itself when `isMeaningful`
/// returns false so an empty summary never renders as a row of zeros.
public struct WeeklySummary: Sendable, Equatable {
    /// Sum of steps over the last 7 days. iOS reports steps as a counter
    /// per sample; we aggregate before exposing.
    public let totalSteps: Int

    /// Mean nightly sleep duration in hours over the last 7 nights.
    /// Sleep samples can include multiple stages — we count any "asleep"
    /// state (asleepCore, asleepDeep, asleepREM, asleepUnspecified) and
    /// divide by 7. 0.0 when no nights are recorded.
    public let avgSleepHours: Double

    /// Sum of "active energy" minutes over the last 7 days. We use the
    /// HKQuantityTypeIdentifier.appleExerciseTime metric Apple maintains
    /// internally (sourced from the Ring activity tracker).
    public let activeMinutes: Int

    public init(totalSteps: Int, avgSleepHours: Double, activeMinutes: Int) {
        self.totalSteps = totalSteps
        self.avgSleepHours = avgSleepHours
        self.activeMinutes = activeMinutes
    }

    /// Canonical zero state. Used as the initial @State value on HomeView
    /// and as the soft-fail return for the reader when HealthKit cannot
    /// answer (permission denied, unavailable, etc.).
    public static let empty = WeeklySummary(
        totalSteps: 0,
        avgSleepHours: 0,
        activeMinutes: 0
    )

    /// Whether the summary carries enough data to be worth rendering on
    /// the home card. Three zeroes means we have nothing to show — the
    /// card hides itself instead of displaying a depressing wall of
    /// `0` to a user who's just opted in but hasn't generated any
    /// HealthKit samples yet.
    public var isMeaningful: Bool {
        totalSteps > 0 || avgSleepHours > 0 || activeMinutes > 0
    }
}
