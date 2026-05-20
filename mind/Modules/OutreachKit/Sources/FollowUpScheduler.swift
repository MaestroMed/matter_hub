import Foundation
import UserNotifications
import GraphCore  // MINDTelemetry

/// v0.29 — Local-notification scheduler for follow-up touches.
///
/// Pairs with `FollowUpSequence` + `FollowUpStore`. When the user
/// flips the "Programmer la suite (4 touches)" toggle in
/// `OutreachSheet` and taps "Ouvrir dans Mail", the host:
///   1. builds a `FollowUpSequence` via
///      `FollowUpSequenceBuilder.build(prospectNodeID:)`,
///   2. persists it via `FollowUpStore.shared.save(_:)`,
///   3. registers all pending touches via
///      `FollowUpScheduler.scheduleNotifications(for:)`.
///
/// Each pending touch fires once via a `UNCalendarNotificationTrigger`
/// at 9am local time on the touch's calendar day. The notification
/// payload deep-links to `mind://followUp/<seqID>/<touchID>` which
/// `RootView.onOpenURL` routes back into the prospect's
/// `NodeDetailView`.
///
/// Identifier convention: `mind.followUp.<seqID>.<touchID>` so the
/// scheduler can cancel + replace per touch without disturbing
/// unrelated pending requests. The shared prefix `mind.followUp.`
/// lets `cancelAll()` reap every pending follow-up notification in
/// one swept call.
@MainActor
public enum FollowUpScheduler {

    /// Shared prefix for every follow-up notification identifier.
    /// `nonisolated` so the test suite can reach it without an actor
    /// hop and the prefix can be reused by `cancelAll` without
    /// duplicating the convention.
    public nonisolated static let identifierPrefix: String = "mind.followUp."

    /// Default hour-of-day the touches fire (9am local). Surfaced as
    /// a parameter on `scheduleNotifications(for:morningHour:)` so
    /// tests can pin a deterministic time and a future "preferred
    /// hour" Settings toggle can override the default without
    /// touching this enum.
    public nonisolated static let defaultMorningHour: Int = 9

    /// Builds the per-touch notification identifier. Pure helper
    /// callable from the cancel + reschedule paths.
    public nonisolated static func identifier(
        sequenceID: UUID,
        touchID: UUID
    ) -> String {
        "\(identifierPrefix)\(sequenceID.uuidString).\(touchID.uuidString)"
    }

    /// Builds the deep-link URL fired when the user taps a follow-up
    /// notification. `RootView.onOpenURL` parses the two-segment path
    /// (`<sequenceID>/<touchID>`) and routes back into the prospect's
    /// detail sheet.
    public nonisolated static func deepLinkURL(
        sequenceID: UUID,
        touchID: UUID
    ) -> URL? {
        URL(string: "mind://followUp/\(sequenceID.uuidString)/\(touchID.uuidString)")
    }

    /// Registers (or replaces) one `UNCalendarNotificationTrigger`
    /// per pending touch in `sequence`. Soft-fails when authorization
    /// isn't granted yet — the caller (OutreachSheet) requests
    /// permission separately. Idempotent: re-running the same
    /// sequence simply rewrites every per-touch identifier.
    public static func scheduleNotifications(
        for sequence: FollowUpSequence,
        morningHour: Int = defaultMorningHour,
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = .current
    ) async {
        // Don't queue notifications for paused / replied / completed
        // sequences. The caller usually filters first but the guard
        // here keeps the contract honest.
        guard sequence.status == .active else {
            await cancelNotifications(for: sequence.id, center: center)
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            MINDTelemetry.info(
                "followUp.schedule.skipped",
                data: ["reason": "notAuthorized"]
            )
            return
        }

        var scheduled = 0
        for touch in sequence.touches where touch.status == .pending {
            guard let fireDate = plannedFireDate(
                for: touch.scheduledFor,
                morningHour: morningHour,
                calendar: calendar
            ) else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "followUp.notification.title")
            content.body = notificationBody(
                touchIndex: index(of: touch, in: sequence) + 1,
                totalTouches: sequence.touches.count
            )
            content.sound = .default
            let id = identifier(sequenceID: sequence.id, touchID: touch.id)
            content.userInfo = [
                "mind.followUp.sequenceID": sequence.id.uuidString,
                "mind.followUp.touchID": touch.id.uuidString,
                "mind.followUp.channel": touch.channel.rawValue,
                "mind.followUp.angle": touch.angle.rawValue,
                "mind.followUp.deepLink":
                    deepLinkURL(sequenceID: sequence.id, touchID: touch.id)?
                    .absoluteString ?? "",
            ]

            let comps = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: comps,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: trigger
            )

            // Replace any prior pending request for this touch so a
            // rescheduled sequence (start date shifted) doesn't leave
            // duplicate notifications queued.
            center.removePendingNotificationRequests(withIdentifiers: [id])
            do {
                try await center.add(request)
                scheduled += 1
                MINDTelemetry.info(
                    "followUp.touch.scheduled",
                    data: [
                        "sequenceID": sequence.id.uuidString,
                        "touchID": touch.id.uuidString,
                        "channel": touch.channel.rawValue,
                        "angle": touch.angle.rawValue,
                    ]
                )
            } catch {
                MINDTelemetry.error(
                    "followUp.schedule.failed",
                    data: [
                        "sequenceID": sequence.id.uuidString,
                        "touchID": touch.id.uuidString,
                        "error": String(describing: error),
                    ]
                )
            }
        }

        if scheduled > 0 {
            MINDTelemetry.info(
                "followUp.sequence.created",
                data: [
                    "sequenceID": sequence.id.uuidString,
                    "touches": "\(scheduled)",
                ]
            )
        }
    }

    /// Removes every pending notification request whose identifier
    /// begins with `mind.followUp.<sequenceID>.`. Used when the user
    /// flips a sequence to `.replied` / `.paused` / `.completed` so
    /// no stale touches fire.
    public static func cancelNotifications(
        for sequenceID: UUID,
        center: UNUserNotificationCenter = .current()
    ) async {
        let pending = await center.pendingNotificationRequests()
        let prefix = "\(identifierPrefix)\(sequenceID.uuidString)."
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !ours.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        MINDTelemetry.info(
            "followUp.sequence.paused",
            data: [
                "sequenceID": sequenceID.uuidString,
                "cancelled": "\(ours.count)",
            ]
        )
    }

    /// Removes every pending follow-up notification across every
    /// sequence. Used by Settings → Danger zone (future) and on a
    /// hard reset of the follow-up store.
    public static func cancelAll(
        center: UNUserNotificationCenter = .current()
    ) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        guard !ours.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    /// Drains the `FollowUpStore` shared singleton and re-queues
    /// every pending touch of every active sequence. Called from
    /// `MINDApp.init` + every `.active` scenePhase so a missed
    /// permission grant or a device clock change rebuilds the queue
    /// without requiring the user to revisit each prospect.
    public static func rescheduleAll(
        store: FollowUpStore = .shared,
        morningHour: Int = defaultMorningHour,
        center: UNUserNotificationCenter = .current()
    ) async {
        let active = await store.allActive()
        for seq in active {
            await scheduleNotifications(
                for: seq,
                morningHour: morningHour,
                center: center
            )
        }
    }

    // MARK: - Pure helpers

    /// Computes the fire date for a touch's `scheduledFor` value.
    /// Returns the noon-anchored date shifted to `morningHour` (9am
    /// by default) on the same calendar day. Returns nil only when
    /// the resulting date is already in the past — past touches
    /// shouldn't queue a "fire now" notification.
    public nonisolated static func plannedFireDate(
        for scheduledFor: Date,
        morningHour: Int = defaultMorningHour,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        let dayStart = calendar.startOfDay(for: scheduledFor)
        guard let fire = calendar.date(
            bySettingHour: max(0, min(23, morningHour)),
            minute: 0,
            second: 0,
            of: dayStart
        ) else { return nil }
        return fire > now ? fire : nil
    }

    /// Pure body templating. Surfaced for the test suite.
    public nonisolated static func notificationBody(
        touchIndex: Int,
        totalTouches: Int
    ) -> String {
        let template = String(localized: "followUp.notification.body.format")
        return String(format: template, touchIndex, totalTouches)
    }

    /// Locates the index of `touch` inside `sequence.touches`. Pure
    /// helper used by the notification body templating to render
    /// "touche 2/4" rather than the raw UUID.
    public nonisolated static func index(
        of touch: FollowUpTouch,
        in sequence: FollowUpSequence
    ) -> Int {
        sequence.touches.firstIndex(where: { $0.id == touch.id }) ?? 0
    }
}
