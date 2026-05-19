import Foundation
import EventKit

/// Thin actor around `EKEventStore` that exposes only what MIND needs
/// for the bidirectional Reminders sync: permission gating, full-list
/// fetch, write-back, and completion toggling.
///
/// Three deliberate design choices mirror `CalendarReader`:
///
///   1. **Actor**, not @MainActor — `EKEventStore` is thread-safe but
///      its reminder fetches block on a background queue. Running them
///      off the main actor keeps the UI responsive when MIND comes
///      back to the foreground.
///
///   2. **Single shared store** — Apple's docs are explicit: keep one
///      `EKEventStore` alive for the lifetime of the process.
///      Recreating it on every call leaks file descriptors and loses
///      change notifications. `RemindersStore.shared` holds the
///      canonical reference; tests can still inject a fresh store via
///      `init(store:)`.
///
///   3. **Soft-fail to `[]` / `nil`** — if the user denied access (or
///      hasn't decided yet), every fetch returns an empty array and
///      every write returns `nil`. The sync engine then has nothing to
///      reconcile and the rest of MIND keeps working without an audible
///      error.
public actor RemindersStore {
    public static let shared = RemindersStore()

    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    // MARK: - Permission

    public func currentAuthorization() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    /// Requests full-access reminders permission using the iOS 17+
    /// API. `requestFullAccessToReminders` replaced the older
    /// `requestAccess(to:)` in iOS 17 and is required on iOS 26 — the
    /// deprecated path is non-functional under the new privacy model.
    ///
    /// Already-granted permissions short-circuit so toggling the sync
    /// setting off and back on doesn't re-prompt the user.
    public func requestAccess() async -> Bool {
        let current = currentAuthorization()
        if current == .fullAccess { return true }
        if current == .denied || current == .restricted { return false }

        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    // MARK: - Read

    /// Returns every reminder in every reminders-capable calendar the
    /// user has surfaced, captured as a pure `ReminderSnapshot`.
    /// Soft-fails to `[]` when permission is denied or the underlying
    /// query throws.
    ///
    /// The result is deduplicated by `calendarItemIdentifier` so
    /// recurring reminders that EventKit re-emits from a parent series
    /// don't double-sync.
    public func fetchAll() async -> [ReminderSnapshot] {
        guard currentAuthorization() == .fullAccess else { return [] }

        let predicate = store.predicateForReminders(in: nil)
        // Map to ReminderSnapshot *inside* the continuation callback —
        // `[EKReminder]` is non-Sendable (class-bound), so Swift 6's
        // strict-concurrency checker rejects resuming with that type
        // across an actor boundary. The pure value-type array is safe.
        let snapshots: [ReminderSnapshot] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { results in
                let mapped = (results ?? []).map { ReminderSnapshot(ekReminder: $0) }
                continuation.resume(returning: mapped)
            }
        }
        return snapshots.deduplicatedByID()
    }

    // MARK: - Write

    /// Creates a new reminder in the default reminders calendar (or
    /// the first reminders-capable calendar EventKit returns).
    /// Returns the newly minted `calendarItemIdentifier` so the caller
    /// can persist the pairing onto `Node.reminderExternalID`.
    public func create(
        title: String,
        notes: String?,
        dueDate: Date?,
        isCompleted: Bool
    ) async -> String? {
        guard currentAuthorization() == .fullAccess else { return nil }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = (notes?.isEmpty == false) ? notes : nil
        reminder.isCompleted = isCompleted
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        guard let calendar = defaultRemindersCalendar() else { return nil }
        reminder.calendar = calendar
        do {
            try store.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    /// Updates an existing reminder. Returns true on success, false on
    /// any failure (not found, save error, permission gone). The
    /// caller can ignore the result when fire-and-forget is fine.
    @discardableResult
    public func update(
        id: String,
        title: String,
        notes: String,
        isCompleted: Bool
    ) async -> Bool {
        guard currentAuthorization() == .fullAccess else { return false }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            return false
        }
        reminder.title = title
        reminder.notes = notes.isEmpty ? nil : notes
        reminder.isCompleted = isCompleted
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    /// Returns the calendar reminders will be created in. Prefers
    /// `defaultCalendarForNewReminders()` (the user's chosen default
    /// list in iOS Reminders), falling back to the first reminders-
    /// capable calendar EventKit returns. Returns nil only when there
    /// is no reminders source at all (extremely rare — would mean the
    /// user has zero accounts configured for reminders).
    private func defaultRemindersCalendar() -> EKCalendar? {
        if let preferred = store.defaultCalendarForNewReminders() {
            return preferred
        }
        return store.calendars(for: .reminder).first
    }
}

// MARK: - EKReminder bridging

extension ReminderSnapshot {
    /// Maps an `EKReminder` into our value type. Defensive on every
    /// field — half-populated reminders (no title, no due date) must
    /// not crash the sync.
    init(ekReminder reminder: EKReminder) {
        self.id = reminder.calendarItemIdentifier
        self.title = reminder.title ?? ""
        self.notes = {
            guard let n = reminder.notes, !n.isEmpty else { return nil }
            return n
        }()
        self.dueDate = reminder.dueDateComponents.flatMap { components in
            Calendar.current.date(from: components)
        }
        self.isCompleted = reminder.isCompleted
        self.lastModified = reminder.lastModifiedDate ?? .distantPast
    }
}
