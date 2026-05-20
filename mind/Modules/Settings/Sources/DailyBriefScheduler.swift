import Foundation
import UserNotifications
import GraphCore

/// v0.17 — Local-notification scheduler for the daily morning brief.
///
/// Wraps `UNUserNotificationCenter` behind a small surface so the rest
/// of the app never imports UserNotifications directly. Four entry
/// points:
///
///   - `scheduleIfEnabled()` — reads `MINDPreferences.dailyBriefEnabled`
///     + `dailyBriefHour` and registers / replaces a single repeating
///     `UNCalendarNotificationTrigger`. Called from `MINDApp.init` and
///     on every `.active` scenePhase so hour changes apply without a
///     relaunch. Soft-fails when notifications are not authorized.
///   - `requestAuthorization()` — call on toggle-on from Settings.
///     Returns `true` when the user grants permission, `false` on
///     denial / restriction / error.
///   - `schedule(hour:minute:)` — explicit-hour variant called by the
///     Settings hour picker. Cancels any previously-scheduled brief
///     so a hour-change doesn't leave duplicates queued.
///   - `cancel()` — removes the pending notification. Called on
///     toggle-off in Settings.
///
/// The notification payload is a localized "Brief du matin" stub —
/// the brief itself is rendered when the user taps and lands on
/// HomeView (the card is already there, and the `mind://brief` URL
/// pops the detail sheet). Keeping the notification payload generic
/// avoids us trying to render personal data inside the system tray.
@MainActor
public enum DailyBriefScheduler {

    /// Stable identifier for the repeating notification request so we
    /// can replace it idempotently. Namespaced under the app bundle id
    /// to play nicely with any future notification categories.
    public static let notificationIdentifier: String = "app.mind.ios.dailyBrief"

    /// Reads `MINDPreferences.dailyBriefEnabled` + `dailyBriefHour`,
    /// then registers (or cancels) the repeating notification. Safe
    /// to call from `MINDApp.init()` and from the `.active` scene
    /// phase handler — it's idempotent and never prompts the user
    /// for permission (the Settings toggle does that explicitly).
    public static func scheduleIfEnabled() {
        let enabled = MINDPreferences.currentDailyBriefEnabled()
        guard enabled else {
            cancel()
            return
        }
        let hour = MINDPreferences.currentDailyBriefHour()
        Task { await schedule(hour: hour) }
    }

    /// Asks the user for notification permission (alert + sound).
    /// Idempotent — the system returns the cached status instantly
    /// when the user has already responded once.
    ///
    /// Returns `true` only when authorization is `.authorized`. The
    /// `.provisional` and `.ephemeral` levels still allow scheduling,
    /// but the morning-brief use case wants the full alert + sound
    /// experience, so we surface them as "not granted" to nudge the
    /// user toward flipping the proper toggle in iOS Settings.
    @discardableResult
    public static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            MINDTelemetry.info(
                "brief.auth.requested",
                data: ["granted": granted ? "1" : "0"]
            )
            return granted
        } catch {
            MINDTelemetry.warning(
                "brief.auth.failed",
                data: ["error": String(describing: error)]
            )
            return false
        }
    }

    /// Schedules (or replaces) the daily morning-brief notification at
    /// the given hour:minute in the user's local time zone. Repeats
    /// every day forever via `UNCalendarNotificationTrigger`. Calling
    /// twice with different times leaves only the most recent schedule
    /// active.
    ///
    /// Soft-fails when authorization isn't granted — the caller will
    /// see the toggle stay on, but no notification fires until they
    /// grant permission. The next call after permission flips on
    /// re-establishes the schedule.
    public static func schedule(hour: Int, minute: Int = 0) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            MINDTelemetry.info(
                "brief.schedule.skipped",
                data: ["reason": "notAuthorized"]
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "brief.notification.title")
        content.body = String(localized: "brief.notification.body")
        content.sound = .default
        // Hint iOS that tapping should open the in-app brief sheet via
        // the `mind://brief` deep link handled by RootView.onOpenURL.
        // The userInfo dict survives the tray round-trip; iOS doesn't
        // auto-route it (apps have to inspect the response in
        // UNUserNotificationCenterDelegate). We surface the URL here
        // for completeness even though the current build relies on
        // the user opening the app and seeing the card — a future PR
        // can wire a delegate and auto-present the sheet.
        content.userInfo = ["mind.briefDeepLink": "mind://brief"]

        // Hour-only trigger repeats every day at the same wall-clock
        // time. Pinning to the user's current calendar means a DST
        // change still fires at the right local hour without our help.
        var dateComponents = DateComponents()
        dateComponents.hour = max(0, min(23, hour))
        dateComponents.minute = max(0, min(59, minute))

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )

        // Remove the previous one first — UNUserNotificationCenter
        // de-duplicates by identifier, but being explicit makes the
        // breadcrumb trail easier to read and shields us from a future
        // Apple change to the dedup contract.
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        do {
            try await center.add(request)
            MINDTelemetry.info(
                "brief.scheduled",
                data: [
                    "hour": "\(dateComponents.hour ?? -1)",
                    "minute": "\(dateComponents.minute ?? -1)",
                ]
            )
        } catch {
            MINDTelemetry.error(
                "brief.schedule.failed",
                data: ["error": String(describing: error)]
            )
        }
    }

    /// Cancels the pending daily morning brief notification. Idempotent —
    /// safe to call from a fresh install where no notification was
    /// scheduled yet.
    public static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        MINDTelemetry.info("brief.schedule.cancelled")
    }
}
