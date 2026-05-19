import Foundation
import UserNotifications
import GraphCore

/// v0.28 — Schedules a single local notification per upcoming
/// prospect/client meeting, fired at 7am the morning of the meeting
/// (default, configurable via the `morningHour` argument). The
/// notification body reads "Demain 14h : brief Stripe prêt" — tap
/// routes through `mind://brief/<eventID>` into RootView, which
/// presents the `MeetingBriefSheet`.
///
/// Idempotent: identifiers are namespaced `mind.meetingBrief.<eventID>`
/// so a re-run replaces the pending request when the event details
/// change (start time pushed, title edited). Stale identifiers for
/// past meetings are also pruned on every call so the pending queue
/// never accumulates.
@MainActor
public enum MeetingBriefScheduler {

    /// Identifier prefix for every meeting-brief notification request.
    /// Public so test helpers + the cancel-on-toggle-off path can
    /// reach it without duplicating the convention. Pure constant —
    /// `nonisolated` so the test suite can reach it without hopping
    /// onto the MainActor.
    public nonisolated static let identifierPrefix: String = "mind.meetingBrief."

    /// Composes the canonical identifier for a given event id.
    public nonisolated static func identifier(for eventID: String) -> String {
        identifierPrefix + eventID
    }

    /// The deep-link URL fired when the user taps a brief notification.
    /// Routed by RootView's `.onOpenURL` to the MeetingBriefSheet.
    public nonisolated static func deepLinkURL(for eventID: String) -> URL? {
        URL(string: "mind://brief/\(eventID)")
    }

    /// Plans the morning-of fire date for the given event start. If
    /// `morningHour` (default 7) on the meeting's calendar day is
    /// still in the future, fire there. Otherwise fall back to
    /// `start - 1h` so the user always gets at least one heads-up
    /// before walking in.
    ///
    /// Pure + testable — `now` defaults to `.now` for production
    /// callers; tests override for determinism.
    public nonisolated static func plannedFireDate(
        for start: Date,
        morningHour: Int = 7,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        var calendar = calendar
        calendar.timeZone = .current

        let startOfMeetingDay = calendar.startOfDay(for: start)
        var morning = DateComponents()
        morning.year = calendar.component(.year, from: startOfMeetingDay)
        morning.month = calendar.component(.month, from: startOfMeetingDay)
        morning.day = calendar.component(.day, from: startOfMeetingDay)
        morning.hour = max(0, min(23, morningHour))
        morning.minute = 0

        guard let morningOfMeeting = calendar.date(from: morning) else {
            return nil
        }

        // If the morning slot is still in the future, use it.
        if morningOfMeeting > now { return morningOfMeeting }

        // Otherwise, fire one hour before the meeting (short-fuse path).
        // This handles the "scheduled mid-day" case where the user just
        // booked a 2pm meeting at 11am — they still need a brief.
        let oneHourBefore = start.addingTimeInterval(-3600)
        return oneHourBefore > now ? oneHourBefore : nil
    }

    /// Schedules briefs for every event in `events` that:
    /// - is happening within the next 7 days (filtered upstream
    ///   by the caller, but defensively re-checked here),
    /// - has at least one attendee email (the heuristic for
    ///   "this is a prospect/client meeting").
    ///
    /// Replaces any previously-scheduled brief for the same event id.
    /// Soft-fails when notification authorization isn't granted —
    /// the next call after the user taps "Autoriser" re-establishes
    /// the queue.
    public static func scheduleBriefs(
        for events: [CalendarEvent],
        morningHour: Int = 7,
        now: Date = .now,
        calendar: Calendar = .current,
        center: UNUserNotificationCenter = .current()
    ) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            MINDTelemetry.info(
                "meetingBrief.schedule.skipped",
                data: ["reason": "notAuthorized"]
            )
            return
        }

        // First: prune identifiers for past events so the pending queue
        // doesn't accumulate. We list every pending request, keep only
        // ours (prefix-matched), and remove the ones whose underlying
        // event id is NOT in the freshly-fetched set OR whose start is
        // already in the past.
        let pending = await center.pendingNotificationRequests()
        let freshIDs = Set(events.map(\.id))
        let stale = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
            .filter {
                let eventID = String($0.dropFirst(identifierPrefix.count))
                return !freshIDs.contains(eventID)
            }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
            MINDTelemetry.info(
                "meetingBrief.pruned",
                data: ["count": "\(stale.count)"]
            )
        }

        var scheduledCount = 0
        for event in events where !event.attendeeEmails.isEmpty && event.startDate > now {
            guard let fireAt = plannedFireDate(
                for: event.startDate,
                morningHour: morningHour,
                now: now,
                calendar: calendar
            ) else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "meetingBrief.notification.title")
            content.body = notificationBody(for: event, calendar: calendar)
            content.sound = .default
            content.userInfo = [
                "mind.meetingBrief.eventID": event.id,
                "mind.meetingBrief.deepLink": deepLinkURL(for: event.id)?.absoluteString ?? "",
            ]

            // Use a calendar trigger so iOS reads the fire date in the
            // user's current time zone (DST is a hard requirement
            // since we may schedule across an October fall-back).
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let request = UNNotificationRequest(
                identifier: identifier(for: event.id),
                content: content,
                trigger: trigger
            )

            // Remove any prior pending request for this event so a
            // start-time change replaces the queued notification
            // instead of leaving two side-by-side.
            center.removePendingNotificationRequests(withIdentifiers: [identifier(for: event.id)])

            do {
                try await center.add(request)
                scheduledCount += 1
            } catch {
                MINDTelemetry.error(
                    "meetingBrief.schedule.failed",
                    data: [
                        "eventID": event.id,
                        "error": String(describing: error),
                    ]
                )
            }
        }

        if scheduledCount > 0 {
            MINDTelemetry.info(
                "meetingBrief.scheduled",
                data: ["count": "\(scheduledCount)"]
            )
        }
    }

    /// Cancels every pending brief notification. Used from the
    /// Settings → Reset privacy / clear data flow.
    public static func cancelAll(
        center: UNUserNotificationCenter = .current()
    ) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        guard !ours.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        MINDTelemetry.info(
            "meetingBrief.cancelled.all",
            data: ["count": "\(ours.count)"]
        )
    }

    // MARK: - Body templating (pure + testable)

    /// Produces the body line — "Demain 14h : brief Stripe prêt" or
    /// "Demain 14h : brief prêt" when the client lookup hasn't fired
    /// yet. Pure helper exposed for the test suite — `nonisolated`
    /// so the test runner can call it without an actor hop.
    public nonisolated static func notificationBody(
        for event: CalendarEvent,
        calendar: Calendar = .current
    ) -> String {
        let timeString = event.startDate.formatted(date: .omitted, time: .shortened)
        let cleanedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = cleanedTitle.isEmpty ? String(localized: "meetingBrief.notification.body.generic") : cleanedTitle
        // String catalog format key: "Demain %1$@ : brief %2$@ prêt"
        let template = String(localized: "meetingBrief.notification.body.format")
        return String(format: template, timeString, label)
    }
}
