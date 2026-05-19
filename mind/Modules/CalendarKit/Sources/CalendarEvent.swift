import Foundation

/// Lightweight, Sendable snapshot of a single calendar event.
///
/// We deliberately keep this a pure value type instead of exposing EKEvent
/// directly — EKEvent is class-bound, non-Sendable, and tied to an
/// EKEventStore lifetime. Copying the bits we actually render lets the
/// HomeView "Aujourd'hui" card render off the main actor, lets us write
/// unit tests without spinning up EventKit, and keeps the CalendarKit
/// public surface stable even if Apple swaps the underlying EventKit
/// machinery in a future iOS release.
///
/// `id` is the EKEvent's `eventIdentifier` (stable per-calendar-store) —
/// it lets us dedupe across overlapping queries and survives the round-
/// trip to disk if we ever cache today's events.
public struct CalendarEvent: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let location: String?
    /// Attendee display names. Empty when EventKit returns no attendees
    /// (most personal events) or when we lack contacts permission to
    /// resolve names — the card still renders, just without the chips.
    public let attendees: [String]

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        attendees: [String] = []
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.attendees = attendees
    }

    /// `HH:mm` rendering in the user's current locale so the home card
    /// matches the rest of MIND's typography. Kept on the value type so
    /// the card stays a dumb renderer and the formatting is testable.
    public var formattedTime: String {
        startDate.formatted(date: .omitted, time: .shortened)
    }
}

public extension Array where Element == CalendarEvent {
    /// Chronological order is the only sensible reading order for an
    /// "Aujourd'hui" card. EventKit returns events in store order, which
    /// is not guaranteed to be by `startDate`, so the card sorts before
    /// rendering. Done as an Array extension so callers compose it with
    /// `prefix(3)` etc.
    func sortedByStart() -> [CalendarEvent] {
        sorted { $0.startDate < $1.startDate }
    }

    /// Defensive de-duplication keyed on the EKEvent identifier. Recurring
    /// events that span our day-window can be returned twice by EventKit
    /// when their parent series straddles midnight; the card must never
    /// double-render a meeting.
    func deduplicatedByID() -> [CalendarEvent] {
        var seen = Set<String>()
        var out: [CalendarEvent] = []
        out.reserveCapacity(count)
        for event in self where seen.insert(event.id).inserted {
            out.append(event)
        }
        return out
    }
}
