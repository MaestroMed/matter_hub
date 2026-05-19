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
    // All non-optional properties carry a default value so the
    // CloudKit-backed persistent store loads cleanly. Note: retired the
    // attempt to also drop `@Attribute(.unique)` for CloudKit — removing
    // the unique constraint caused the SwiftData test runner to crash
    // at boot (Early unexpected exit). Tracking the underlying CloudKit
    // sync issue separately; for now uniqueness via the SQLite index is
    // safer than not booting at all.
    @Attribute(.unique) public var id: UUID = UUID()
    public var intention: String = ""
    public var startDate: Date = Date.now
    public var completedAt: Date = Date.now
    /// Planned duration in seconds (what the user committed to at start).
    public var plannedDurationSeconds: Double = 0
    /// Effective duration in seconds (might be shorter if user ended early).
    public var actualDurationSeconds: Double = 0
    /// `true` if the user reached the end of the planned timer, `false`
    /// if they tapped End focus early. Used to compute completion rate.
    public var completedNormally: Bool = false

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
