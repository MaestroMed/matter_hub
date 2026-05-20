import Foundation

/// A single Deep Focus session intent. Lives in-memory while it runs;
/// persistence (history, weekly stats) is deferred until Phase 9 — at
/// that point this becomes a SwiftData `@Model` and joins the graph.
public struct FocusSession: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public let intention: String
    public let totalDuration: TimeInterval
    public let startDate: Date

    public init(
        id: UUID = UUID(),
        intention: String,
        totalDuration: TimeInterval,
        startDate: Date = .now
    ) {
        self.id = id
        self.intention = intention
        self.totalDuration = totalDuration
        self.startDate = startDate
    }

    public var endDate: Date {
        startDate.addingTimeInterval(totalDuration)
    }
}
