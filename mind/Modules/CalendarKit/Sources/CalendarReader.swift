import Foundation
import EventKit

/// Thin actor around `EKEventStore` that exposes only what MIND needs:
/// permission gating and "give me today's events".
///
/// Three deliberate design choices:
///
///   1. **Actor**, not @MainActor — EKEventStore is thread-safe but its
///      calls block. Doing them off the main actor keeps the HomeView
///      scroll latency clean.
///
///   2. **Single shared store** — Apple's docs are explicit: keep one
///      EKEventStore alive for the lifetime of the process. Recreating
///      it on every call leaks file descriptors and (worse) loses change
///      notifications. `CalendarReader.shared` holds the canonical
///      reference; the test suite still works because the actor isolates
///      it correctly.
///
///   3. **Soft-fail to `[]`** — if the user denied access (or hasn't
///      decided yet), `todayEvents()` returns an empty array instead of
///      throwing. The card simply doesn't render, the rest of HomeView
///      stays intact, and we never block startup on a calendar prompt.
///      Callers that want to surface the deny-state explicitly should
///      check `currentAuthorization()` separately.
public actor CalendarReader {
    public static let shared = CalendarReader()

    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    // MARK: - Permission

    /// Current EventKit authorization status. Cheap, sync — no system call
    /// crosses an XPC boundary.
    public func currentAuthorization() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Requests full-access events permission using the iOS 17+ API.
    ///
    /// `requestFullAccessToEvents` replaced the older
    /// `requestAccess(to:)` in iOS 17 and is required on iOS 26 — the
    /// deprecated path is non-functional once the user is asked under the
    /// new privacy model. We treat any failure (denied, restricted,
    /// system error) as `false` so the caller's contract stays simple.
    public func requestAccess() async -> Bool {
        // Already granted from a previous launch? Short-circuit so we
        // never re-prompt the user once they've decided.
        let current = currentAuthorization()
        if current == .fullAccess { return true }
        if current == .denied || current == .restricted { return false }

        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    // MARK: - Today's events

    /// Returns the events overlapping today's local window — `startOfDay`
    /// up to (but not including) tomorrow's `startOfDay`.
    ///
    /// Soft-fails to `[]` when:
    /// - the user hasn't granted full-access events permission
    /// - EventKit returns nothing (the simulator does, by default)
    /// - any underlying call throws
    ///
    /// Output is sorted by `startDate` and de-duplicated by event ID so
    /// the HomeView card can render it directly without further massaging.
    public func todayEvents(
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> [CalendarEvent] {
        guard currentAuthorization() == .fullAccess else { return [] }

        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: startOfDay
        ) else {
            return []
        }

        let predicate = store.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: nil  // nil = every calendar the user has surfaced
        )

        let raw = store.events(matching: predicate)
        return raw
            .map { CalendarEvent(ekEvent: $0) }
            .deduplicatedByID()
            .sortedByStart()
    }
}

// MARK: - EKEvent bridging

extension CalendarEvent {
    /// Maps an EKEvent into our value type. Defensive on every field so a
    /// half-populated event (no title, no end-date) doesn't crash the
    /// card. `eventIdentifier` can be nil for events that haven't been
    /// committed to a store yet — we fall back to a synthesized UUID so
    /// dedupe still works.
    init(ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier ?? UUID().uuidString
        self.title = ekEvent.title ?? ""
        self.startDate = ekEvent.startDate ?? .now
        self.endDate = ekEvent.endDate ?? ekEvent.startDate ?? .now
        self.location = {
            guard let loc = ekEvent.location, !loc.isEmpty else { return nil }
            return loc
        }()
        self.attendees = (ekEvent.attendees ?? []).compactMap { participant in
            // Apple's docs warn that `name` is often nil on personal
            // calendars (CalDAV without contacts mapping). Skip those so
            // the attendee strip stays clean instead of showing blanks.
            let name = participant.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { return nil }
            return name
        }
    }
}
