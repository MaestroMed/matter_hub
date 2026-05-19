import XCTest
import Foundation
@testable import MIND
@testable import GraphCore
@testable import CalendarKit

/// v0.17 — Locks the pure `DailyBriefBuilder.compute` contract that
/// powers the new HomeView "Brief du matin" card and the daily local
/// notification. Every number shown on the card and every headline
/// branch in the notification body flows through this builder, so any
/// regression here lands on the most-trafficked screen of the app at
/// the most-trafficked moment (wake-up).
///
/// Strategy
/// --------
/// Build small in-memory arrays of `CalendarEvent` + `Node` + a focus
/// hours total, pin the reference date, run `compute` once, then assert
/// every field of the returned brief. No SwiftData container is needed
/// because the builder takes plain arrays — exactly what makes it
/// cheap to lock.
final class DailyBriefTests: XCTestCase {

    /// Fixed anchor used by every test. ~2026-05-19 08:00 UTC — inside
    /// the typical morning window.
    private let reference = Date(timeIntervalSince1970: 1_779_336_000)

    // MARK: - Builders

    private func makeNode(
        kind: NodeKind,
        title: String,
        createdAt: Date,
        updatedAt: Date? = nil,
        completedAt: Date? = nil
    ) -> Node {
        let node = Node(kind: kind, title: title)
        node.createdAt = createdAt
        node.updatedAt = updatedAt ?? createdAt
        node.completedAt = completedAt
        return node
    }

    private func makeEvent(
        title: String,
        startOffsetHours: Double,
        location: String? = nil
    ) -> CalendarEvent {
        let start = reference.addingTimeInterval(startOffsetHours * 3600)
        return CalendarEvent(
            id: UUID().uuidString,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            location: location,
            attendees: []
        )
    }

    // MARK: - Empty input

    /// Empty arrays → every counter is zero, the headline is the
    /// calm-day branch, and the focus suggestion falls back to the
    /// pomodoro default (25). Drives the first-launch UX.
    func test_emptyInputs_yieldCalmDayBrief() {
        let brief = DailyBriefBuilder.compute(
            today: [],
            tasks: [],
            recentCaptures: [],
            lastWeekFocusHours: 0,
            asOf: reference
        )

        XCTAssertEqual(brief.calendarEventCount, 0)
        XCTAssertEqual(brief.openTaskCount, 0)
        XCTAssertTrue(brief.recentCaptureTitles.isEmpty)
        XCTAssertEqual(brief.focusSuggestionMinutes, 25,
                       "Zero focus history must fall back to the 25-minute pomodoro default")
        XCTAssertEqual(brief.headline, DailyBriefBuilder.headlineString(meetings: 0, tasks: 0),
                       "Empty brief renders the calm-day headline")
    }

    // MARK: - Counter wiring

    /// Calendar event count is the array length, period — no filtering
    /// happens at the builder level (the caller already passes today's
    /// events). Same for open task count; the builder defensively
    /// filters on `completedAt == nil` so a stale array doesn't leak
    /// completed rows.
    func test_counts_passThroughInputArrays() {
        let events = [
            makeEvent(title: "Standup", startOffsetHours: 1),
            makeEvent(title: "Client call", startOffsetHours: 3),
            makeEvent(title: "Pair session", startOffsetHours: 5),
        ]
        let tasks = [
            makeNode(kind: .task, title: "Open A", createdAt: reference),
            makeNode(kind: .task, title: "Open B", createdAt: reference),
            // Already-completed task — must NOT increment the count
            makeNode(kind: .task, title: "Done",   createdAt: reference,
                     completedAt: reference.addingTimeInterval(-3600)),
        ]

        let brief = DailyBriefBuilder.compute(
            today: events,
            tasks: tasks,
            recentCaptures: [],
            lastWeekFocusHours: 0,
            asOf: reference
        )

        XCTAssertEqual(brief.calendarEventCount, 3)
        XCTAssertEqual(brief.openTaskCount, 2,
                       "Completed task must be filtered out by the builder")
    }

    // MARK: - Recent captures ordering + cap

    /// `recentCaptureTitles` must be ordered by `updatedAt` descending
    /// AND capped at 3. We seed 5 captures with monotonically increasing
    /// updatedAt; the brief surfaces the 3 most-recent.
    func test_recentCaptures_sortedAndCappedAtThree() {
        var captures: [Node] = []
        for i in 0..<5 {
            captures.append(makeNode(
                kind: .capture,
                title: "Capture #\(i)",
                createdAt: reference,
                updatedAt: reference.addingTimeInterval(Double(i) * 60)
            ))
        }

        let brief = DailyBriefBuilder.compute(
            today: [],
            tasks: [],
            recentCaptures: captures,
            lastWeekFocusHours: 0,
            asOf: reference
        )

        XCTAssertEqual(brief.recentCaptureTitles.count, 3,
                       "Recent-captures list is hard-capped at 3")
        XCTAssertEqual(
            brief.recentCaptureTitles,
            ["Capture #4", "Capture #3", "Capture #2"],
            "Recent captures must be ordered by updatedAt descending"
        )
    }

    // MARK: - Recent captures kind filter + blank skip

    /// The builder only accepts `.capture` and `.note` kinds for the
    /// recent list — task / audit / client nodes must not bleed into
    /// the captures section. Blank titles are dropped (mirrors the
    /// v0.16 contract).
    func test_recentCaptures_filtersNonCaptureKindsAndBlankTitles() {
        let nodes: [Node] = [
            makeNode(kind: .capture, title: "Visible",   createdAt: reference,
                     updatedAt: reference.addingTimeInterval(-10)),
            makeNode(kind: .audit,   title: "Audit row", createdAt: reference,
                     updatedAt: reference.addingTimeInterval(-20)),
            makeNode(kind: .capture, title: "   ",        createdAt: reference,
                     updatedAt: reference.addingTimeInterval(-30)),
            makeNode(kind: .note,    title: "Note row",  createdAt: reference,
                     updatedAt: reference.addingTimeInterval(-40)),
            makeNode(kind: .client,  title: "Stripe",    createdAt: reference,
                     updatedAt: reference.addingTimeInterval(-50)),
        ]

        let brief = DailyBriefBuilder.compute(
            today: [],
            tasks: [],
            recentCaptures: nodes,
            lastWeekFocusHours: 0,
            asOf: reference
        )

        XCTAssertEqual(brief.recentCaptureTitles, ["Visible", "Note row"],
                       "Builder must drop audit / client / blank-title rows")
    }

    // MARK: - Focus suggestion math

    /// Zero focus history → 25-minute pomodoro default. The very first
    /// brief a user sees still ships a concrete number.
    func test_focusSuggestion_zeroHistoryDefaultsToPomodoro() {
        let minutes = DailyBriefBuilder.focusSuggestionMinutes(lastWeekHours: 0)
        XCTAssertEqual(minutes, 25)
    }

    /// 7 hours / 7 days = 1h/day = 60 min. Inside the [15, 90] clamp,
    /// so the suggestion is exactly 60.
    func test_focusSuggestion_returnsAverageInsideClamp() {
        let minutes = DailyBriefBuilder.focusSuggestionMinutes(lastWeekHours: 7.0)
        XCTAssertEqual(minutes, 60)
    }

    /// 70 hours / 7 days = 10h/day = 600 min. Way above the 90-minute
    /// cap, so the suggestion clamps to 90. Prevents a heavy
    /// crunch-week from spawning "do a 4-hour focus today" copy.
    func test_focusSuggestion_clampsToNinetyOnHeavyWeek() {
        let minutes = DailyBriefBuilder.focusSuggestionMinutes(lastWeekHours: 70.0)
        XCTAssertEqual(minutes, 90)
    }

    /// 0.5 hours / 7 days ≈ 4.3 min, below the 15-minute floor. The
    /// suggestion clamps up to 15 so the brief never tells the user
    /// "do 4 minutes today" — that reads as a typo.
    func test_focusSuggestion_clampsToFifteenOnLightWeek() {
        let minutes = DailyBriefBuilder.focusSuggestionMinutes(lastWeekHours: 0.5)
        XCTAssertEqual(minutes, 15)
    }

    // MARK: - Headline branch table

    /// 0 + 0 → calm-day. 2 + 0 → meetings-only. 0 + 3 → tasks-only.
    /// 1 + 4 → both. Each branch resolves through Localizable.xcstrings
    /// so we assert non-empty strings + that the four branches are
    /// distinct (the calm-day string can't equal the meetings string,
    /// etc.).
    func test_headline_fourBranchesAreDistinctAndNonEmpty() {
        let calm     = DailyBriefBuilder.headlineString(meetings: 0, tasks: 0)
        let meetings = DailyBriefBuilder.headlineString(meetings: 2, tasks: 0)
        let tasks    = DailyBriefBuilder.headlineString(meetings: 0, tasks: 3)
        let both     = DailyBriefBuilder.headlineString(meetings: 1, tasks: 4)

        for s in [calm, meetings, tasks, both] {
            XCTAssertFalse(s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "Every headline branch must resolve to a non-empty string")
        }
        XCTAssertNotEqual(calm, meetings)
        XCTAssertNotEqual(calm, tasks)
        XCTAssertNotEqual(meetings, tasks)
        XCTAssertNotEqual(meetings, both)
        XCTAssertNotEqual(tasks, both)
    }

    /// The meeting-only headline must carry the actual number (a "%d"
    /// substitution). We assert "2" appears in the rendered string —
    /// regardless of the locale-specific wording around it.
    func test_headline_meetingsBranchSubstitutesCount() {
        let s = DailyBriefBuilder.headlineString(meetings: 2, tasks: 0)
        XCTAssertTrue(s.contains("2"),
                      "Meetings-only headline must substitute the meeting count")
    }

    // MARK: - Date stamp

    /// `brief.date` must equal the reference passed by the caller —
    /// no off-by-one timezone shenanigans. The detail sheet's
    /// "Mardi 19 mai" formatter depends on this for the right day name.
    func test_briefDate_matchesReference() {
        let brief = DailyBriefBuilder.compute(
            today: [],
            tasks: [],
            recentCaptures: [],
            lastWeekFocusHours: 0,
            asOf: reference
        )
        XCTAssertEqual(brief.date, reference)
    }
}
