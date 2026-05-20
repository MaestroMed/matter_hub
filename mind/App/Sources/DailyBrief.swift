import Foundation
import GraphCore
import CalendarKit

/// v0.17 — Daily morning brief value type. Pushed via local
/// `UNCalendarNotificationTrigger` at the user-configured wake-up hour
/// (default 7am), then surfaced as a Home card the rest of the morning
/// and a sheet on tap. The struct is pure data: every field is computed
/// by `DailyBriefBuilder.compute` from the live SwiftData + EventKit
/// snapshots, so the same code path serves the notification body, the
/// HomeView card, and the detail sheet without re-running anything.
///
/// Concept
/// -------
/// The brief is the antithesis of the v0.16 weekly digest. The digest
/// is a celebratory retrospective; the brief is a focused 30-second
/// read at wake-up: "here's what's on today, here's what's open, here
/// are the captures you might want to revisit, and here's how long
/// you should aim to focus today." Everything actionable.
///
/// The `headline` field is the single-sentence summary that fits in a
/// push notification body. It encodes the brief in one localized line
/// so the user reads it without unlocking.
public struct DailyBrief: Sendable, Equatable {

    /// The day this brief covers (the start of the morning the
    /// notification was scheduled for). Used as the sheet title anchor
    /// and as the dedup key when re-computing the brief mid-morning.
    public let date: Date

    /// Number of calendar events scheduled for today. Same source as
    /// the v0.8 "Aujourd'hui" card. Zero is meaningful — a calm day
    /// flips the headline copy.
    public let calendarEventCount: Int

    /// Number of `.task` Nodes whose `completedAt == nil`. The brief
    /// only highlights the count; the detail sheet lists them and lets
    /// the user toggle done in place.
    public let openTaskCount: Int

    /// Last 3 capture / note titles, sorted by `updatedAt` descending.
    /// Capped at 3 by the builder so the sheet section stays compact.
    /// Empty titles are filtered out before sorting, mirroring the
    /// `WeeklyDigestBuilder` contract.
    public let recentCaptureTitles: [String]

    /// Suggested focus duration in minutes for today. Derived from the
    /// last 7 days of `FocusSessionRecord.actualDurationSeconds` —
    /// "average daily focus" rounded and clamped into the
    /// `[15, 90]` window so the suggestion is always a believable
    /// pomodoro-sized chunk. Defaults to 25 (pomodoro classic) when
    /// the user has no focus history at all.
    public let focusSuggestionMinutes: Int

    /// One-sentence FR/EN localized headline used as the notification
    /// body and the card subtitle. The builder picks the key based on
    /// which of `(calendarEventCount, openTaskCount)` are non-zero.
    /// The four-branch table is locked by tests.
    public let headline: String

    public init(
        date: Date,
        calendarEventCount: Int,
        openTaskCount: Int,
        recentCaptureTitles: [String],
        focusSuggestionMinutes: Int,
        headline: String
    ) {
        self.date = date
        self.calendarEventCount = calendarEventCount
        self.openTaskCount = openTaskCount
        self.recentCaptureTitles = recentCaptureTitles
        self.focusSuggestionMinutes = focusSuggestionMinutes
        self.headline = headline
    }
}

/// Pure-function builder that aggregates today's calendar events, the
/// user's open tasks, the recent captures, and the last-week focus
/// average into a `DailyBrief`. No I/O — callers fetch the inputs
/// (`CalendarReader.todayEvents()`, a SwiftData @Query snapshot, etc.)
/// and pass plain arrays in. That makes the headline / suggestion
/// math trivially unit-testable without spinning up EventKit, the
/// SwiftData container, or HealthKit.
public enum DailyBriefBuilder {

    /// Cap on `recentCaptureTitles`. Matches the ULTRAPLAN spec
    /// ("last 3 captures") and keeps the card section compact at any
    /// Dynamic Type size.
    private static let recentCaptureLimit: Int = 3

    /// Minimum / maximum focus suggestion in minutes. 15 keeps the
    /// suggestion meaningful (anything shorter is a context-switch,
    /// not a focus session); 90 caps it at one ultradian cycle so the
    /// brief never recommends a 4-hour grind even after a heavy week.
    private static let focusMinMinutes: Int = 15
    private static let focusMaxMinutes: Int = 90

    /// Pomodoro classic. Returned when the user has zero recorded
    /// focus history, so the very first brief still ships a concrete
    /// number instead of a placeholder dash.
    private static let pomodoroDefaultMinutes: Int = 25

    /// Build a brief. Pass `Date.now` as `reference` in production;
    /// tests can pin any date and observe the headline branch + focus
    /// clamp behave deterministically.
    ///
    /// - Parameters:
    ///   - today: today's calendar events (already filtered by the
    ///     caller to the day-window — typically
    ///     `CalendarReader.todayEvents()`).
    ///   - tasks: every `.task` Node that's still open
    ///     (`completedAt == nil`). The caller filters with
    ///     `node.kindRaw == "task" && node.completedAt == nil`.
    ///   - recentCaptures: every `.capture` / `.note` Node, sorted or
    ///     unsorted — the builder re-sorts by `updatedAt` descending
    ///     internally and caps at 3, so callers don't have to.
    ///   - lastWeekFocusHours: total focus hours over the last 7 days.
    ///     Pass 0 when the user has no history; the builder falls back
    ///     to the pomodoro default.
    ///   - reference: the "now" anchor for the date stamp. Production
    ///     passes `.now`; tests pin it for deterministic asserts.
    public static func compute(
        today calendarEvents: [CalendarEvent],
        tasks openTasks: [Node],
        recentCaptures: [Node],
        lastWeekFocusHours: Double,
        asOf reference: Date
    ) -> DailyBrief {
        let meetingCount = calendarEvents.count
        // openTasks is already filtered by the caller, but defensively
        // re-check the predicate so a stale Node array doesn't leak a
        // completed task into the brief headline.
        let taskCount = openTasks.filter {
            $0.kindRaw == NodeKind.task.rawValue && $0.completedAt == nil
        }.count

        // Top 3 recent captures/notes by updatedAt desc. Skip blank
        // titles for the same reason WeeklyDigestBuilder does — empty
        // bullets read as broken UI on the sheet.
        let recentTitles = recentCaptures
            .filter {
                ($0.kindRaw == NodeKind.capture.rawValue
                    || $0.kindRaw == NodeKind.note.rawValue)
                    && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(recentCaptureLimit)
            .map { $0.title }

        let focusMinutes = focusSuggestionMinutes(lastWeekHours: lastWeekFocusHours)
        let headline = headlineString(
            meetings: meetingCount,
            tasks: taskCount
        )

        return DailyBrief(
            date: reference,
            calendarEventCount: meetingCount,
            openTaskCount: taskCount,
            recentCaptureTitles: Array(recentTitles),
            focusSuggestionMinutes: focusMinutes,
            headline: headline
        )
    }

    /// Internal helper exposed for tests via `@testable import` —
    /// keeps the clamp / pomodoro-default contract pinned in isolation.
    /// Production code goes through `compute(...)`.
    public static func focusSuggestionMinutes(lastWeekHours: Double) -> Int {
        guard lastWeekHours > 0 else { return pomodoroDefaultMinutes }
        // last 7 days → average daily minutes
        let avgDailyMinutes = (lastWeekHours * 60.0) / 7.0
        let rounded = Int(avgDailyMinutes.rounded())
        return max(focusMinMinutes, min(focusMaxMinutes, rounded))
    }

    /// Builds the localized headline string. Resolved against the main
    /// app bundle (Localizable.xcstrings) so the FR build always reads
    /// FR copy. `String(format:)` handles the `%d` substitutions in
    /// both the FR and EN templates.
    ///
    /// Branches:
    /// - 0 meetings + 0 tasks → "Journée calme. Profite."
    /// - N meetings + 0 tasks → "N rendez-vous aujourd'hui."
    /// - 0 meetings + N tasks → "N tâches à clôturer."
    /// - N meetings + M tasks → "N tâches, M rendez-vous."
    public static func headlineString(meetings: Int, tasks: Int) -> String {
        switch (meetings, tasks) {
        case (0, 0):
            return String(localized: "brief.headline.calmDay")
        case let (m, 0) where m > 0:
            let template = String(localized: "brief.headline.meetings")
            return String(format: template, m)
        case let (0, t) where t > 0:
            let template = String(localized: "brief.headline.tasks")
            return String(format: template, t)
        case let (m, t):
            let template = String(localized: "brief.headline.both")
            return String(format: template, t, m)
        }
    }
}
