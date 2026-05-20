import Foundation

/// Lightweight, Sendable snapshot of a single iOS Reminder
/// (`EKReminder`).
///
/// We deliberately keep this a pure value type instead of exposing
/// `EKReminder` directly — `EKReminder` is class-bound, non-Sendable, and
/// tied to an `EKEventStore` lifetime. Copying the bits we actually need
/// lets the sync engine diff Reminders against MIND tasks off the main
/// actor, makes unit tests trivial (no EventKit boot), and keeps the
/// public surface of `RemindersKit` stable even if Apple swaps the
/// underlying EventKit machinery in a future iOS release.
///
/// `id` is the `EKReminder.calendarItemIdentifier` — stable per-store,
/// survives the round-trip through CloudKit's reminders sync, and lets us
/// dedupe across overlapping queries.
public struct ReminderSnapshot: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let title: String
    public let notes: String?
    /// Wall-clock due date (no time zone awareness — EventKit stores
    /// `DateComponents` but we coalesce them here for simpler diffs).
    /// `nil` = no due date set.
    public let dueDate: Date?
    public let isCompleted: Bool
    /// Timestamp of the last user-visible mutation (creation, edit,
    /// completion). Drives the sync engine's last-writer-wins
    /// conflict resolution. Defaults to `.distantPast` for snapshots
    /// minted before EventKit started tracking modification dates.
    public let lastModified: Date

    public init(
        id: String,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        lastModified: Date = .distantPast
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.lastModified = lastModified
    }
}

public extension Array where Element == ReminderSnapshot {
    /// Defensive de-duplication keyed on the EKReminder identifier.
    /// EventKit can return duplicates when overlapping calendars hold a
    /// CalDAV copy alongside the local one; the sync engine must never
    /// double-mirror the same reminder into the graph.
    func deduplicatedByID() -> [ReminderSnapshot] {
        var seen = Set<String>()
        var out: [ReminderSnapshot] = []
        out.reserveCapacity(count)
        for snapshot in self where seen.insert(snapshot.id).inserted {
            out.append(snapshot)
        }
        return out
    }

    /// Returns only the open (non-completed) reminders, preserving the
    /// input order. Useful for surfacing pending work in MIND without
    /// the sync engine pulling the entire archive.
    func openOnly() -> [ReminderSnapshot] {
        filter { !$0.isCompleted }
    }
}
