import Foundation
import SwiftData

/// SwiftData persistence for a completed Deep Focus session. Lives in
/// GraphCore (not FocusKit) so it can be declared in `GraphCore.schema`
/// without creating a dependency cycle — GraphCore is the data backbone
/// every other module already depends on.
///
/// One record per finished session: written by FocusController.end()
/// when the user completes (or manually ends) a focus run, never
/// overwritten thereafter. Read by HomeView to surface weekly stats and
/// by future "Focus history" detail views.
@Model
public final class FocusSessionRecord {
    @Attribute(.unique) public var id: UUID
    public var intention: String
    public var startDate: Date
    public var completedAt: Date
    /// Planned duration in seconds (what the user committed to at start).
    public var plannedDurationSeconds: Double
    /// Effective duration in seconds (might be shorter if user ended early).
    public var actualDurationSeconds: Double
    /// `true` if the user reached the end of the planned timer, `false`
    /// if they tapped End focus early. Used to compute completion rate.
    public var completedNormally: Bool

    public init(
        id: UUID = UUID(),
        intention: String,
        startDate: Date,
        completedAt: Date = .now,
        plannedDurationSeconds: Double,
        actualDurationSeconds: Double,
        completedNormally: Bool
    ) {
        self.id = id
        self.intention = intention
        self.startDate = startDate
        self.completedAt = completedAt
        self.plannedDurationSeconds = plannedDurationSeconds
        self.actualDurationSeconds = actualDurationSeconds
        self.completedNormally = completedNormally
    }
}
