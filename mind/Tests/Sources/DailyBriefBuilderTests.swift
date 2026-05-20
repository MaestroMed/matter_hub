import XCTest
import Foundation
@testable import MIND
@testable import GraphCore
@testable import CalendarKit

/// v0.17 — Locks the pure `DailyBriefBuilder.compute` contract that
/// powers the new HomeView "Brief du matin" card + the local
/// notification body. Every visible string + number on the brief comes
/// out of this function, so a regression here either ships the wrong
/// headline at 7am or trips the focus-suggestion clamp.
///
/// Strategy
/// --------
/// Build small in-memory arrays of `Node` + `CalendarEvent`, pin the
/// reference date so any sliding window stays deterministic, run
/// `compute` once, then assert on every field of the returned brief.
/// No SwiftData container is needed because `compute` takes plain
/// arrays — exactly what makes it cheap to lock.
final class DailyBriefBuilderTests: XCTestCase {

    /// Fixed anchor used by every test. ~2026-05-19 07:00 UTC.
    private let reference = Date(timeIntervalSince1970: 1_779_339_600)

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
        id: String = UUID().uuidString,
        title: String = "Meeting",
        offsetHours: Double = 1
    ) -> CalendarEvent {
        let start = reference.addingTimeInterval(offsetHours * 3600)
        return CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3600)
        )
    }

    // MARK: - Headline branch: 0 + 0

    /// 0 meetings + 0 tasks → "Journée calme. Profite." headline.
    /// The brief still ships — the calm-day branch IS the actionable
    /// signal on a quiet day.
    func test_emptyDay_yieldsCalmHeadline() {
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
        XCTAssertEqual(
            brief.headline,
            DailyBriefBuilder.headlineString(meetings: 0, tasks: 0),
            "Empty day must resolve the calm-day headline branch"
        )
    }

    // MARK: - Headline branch: meetings only

    /// 1+ meetings + 0 tasks → meetings headline. Locks the
    /// `%d rendez-vous` template substitution.
    func test_meetingsOnly_yieldsMeetingsHeadline() {
        let brief = DailyBriefBuilder.compute(
            today: [makeEvent(title: "Standup"), makeEvent(title: "1:1")],
            tasks: [],
            recentCaptures: [],
            lastWeekFocusHours: 0,
            asOf: reference
        )

        XCTAssertEqual(brief.calendarEventCount, 2)
        XCTAssertEqual(brief.openTaskCount, 0)
        XCTAssertEqual(
            brief.headline,
            DailyBriefBuilder.headlineString(meetings: 2, tasks: 0)
        )
    }

    // MARK: - Headline branch: tasks only

    /// 0 meetings + 3 tasks → tasks headline. Locks the
    /// `%d tâches à clôturer` template substitution.
    func test_tasksOnly_yieldsTasksHeadline() {
        let tasks: [Node] = [
            makeNode(kind: .task, title: "Pay invoice",   createdAt: reference.addingTimeInterval(-3 * 3600)),
            makeNode(kind: .task, title: "Call Verdenomia", createdAt: reference.addingTimeInterval(-2 * 3600)),
            makeNode(kind: .task, title: "Review PR",     createdAt: reference.addingTimeInterval(-1 * 3600)),
        ]

        let brief = DailyBriefBuilder.compute(
            today: [],
            tasks: tasks,
            recentCaptures: [],
            lastWeekFocusHours: 0,
            asOf: reference
        )

        XCTAssertEqual(brief.calendarEventCount, 0)
        XCTAssertEqual(brief.openTaskCount, 3)
        XCTAssertEqual(
            brief.headline,
            DailyBriefBuilder.headlineString(meetings: 0, tasks: 3)
        )
    }

    // MARK: - Headline branch: both

    /// Both meetings + tasks → "X tâches, Y rendez-vous." headline.
    /// Asserts the order of template args ((tasks, meetings)).
    func test_bothMeetingsAndTasks_yieldsBothHeadline() {
        let tasks: [Node] = (0..<4).map { i in
            makeNode(kind: .task, title: "Task \(i)", createdAt: reference.addingTimeInterval(Double(-i) * 600))
        }
        let events: [CalendarEvent] = (0..<2).map { i in
            makeEvent(id: "evt-\(i)", title: "Meeting \(i)", offsetHours: Double(i + 1))
        }

        let brief = DailyBriefBuilder.compute(
            today: events,
            tasks: tasks,
            recentCaptures: [],
            lastWeekFocusHours: 0,
            asOf: reference
        )

        XCTAssertEqual(brief.calendarEventCount, 2)
        XCTAssertEqual(brief.openTaskCount, 4)
        XCTAssertEqual(
            brief.headline,
            DailyBriefBuilder.headlineString(meetings: 2, tasks: 4),
            "Both branch must pass (tasks, meetings) in that order to the template"
        )
    }

    // MARK: - Recent captures cap

    /// `recentCaptureTitles` must be capped at 3, sorted by
    /// `updatedAt` descending, even when 7 candidates are passed.
    /// Locks the slice contract of the builder.
    func test_recentCaptures_cappedAtThree() {
        var captures: [Node] = []
        for i in 0..<7 {
            captures.append(
                makeNode(
                    kind: .capture,
                    title: "Capture #\(i)",
                    createdAt: reference.addingTimeInterval(Double(-i) * 600),
                    updatedAt: reference.addingTimeInterval(Double(i) * 60)
                )
            )
        }

        let brief = DailyBriefBuilder.compute(
            today: [],
            tasks: [],
            recentCaptures: captures,
            lastWeekFocusHours: 0,
            asOf: reference
        )

        XCTAssertEqual(brief.recentCaptureTitles.count, 3,
                       "Recent captures must be hard-capped at 3")
        XCTAssertEqual(
            brief.recentCaptureTitles,
            ["Capture #6", "Capture #5", "Capture #4"],
            "Recent captures must be sorted by updatedAt descending"
        )
    }

    // MARK: - Focus suggestion: clamp + average

    /// Average daily focus minutes from `lastWeekFocusHours` must be
    /// rounded and clamped into [15, 90]. 28h over 7 days = 240 min/day
    /// → clamped down to 90.
    func test_focusSuggestion_clampedUpperBound() {
        let brief = DailyBriefBuilder.compute(
            today: [],
            tasks: [],
            recentCaptures: [],
            lastWeekFocusHours: 28.0,  // average 240 min / day
            asOf: reference
        )
        XCTAssertEqual(brief.focusSuggestionMinutes, 90,
                       "240 min/day average must clamp down to 90 min")
    }

    /// 0.5h over 7 days = ~4 min/day → clamped up to 15. The lower
    /// bound guarantees the suggestion is always a meaningful chunk.
    func test_focusSuggestion_clampedLowerBound() {
        let brief = DailyBriefBuilder.compute(
            today: [],
            tasks: [],
            recentCaptures: [],
            lastWeekFocusHours: 0.5,  // average ~4 min / day
            asOf: reference
        )
        XCTAssertEqual(brief.focusSuggestionMinutes, 15,
                       "4 min/day average must clamp up to 15 min")
    }

    /// 4.5h over 7 days = ~38 min/day → stays at 38. Locks the
    /// rounding contract for the average-case path.
    func test_focusSuggestion_roundsAverageHours() {
        let brief = DailyBriefBuilder.compute(
            today: [],
            tasks: [],
            recentCaptures: [],
            lastWeekFocusHours: 4.5,  // average ~38.57 min / day
            asOf: reference
        )
        XCTAssertEqual(brief.focusSuggestionMinutes, 39,
                       "4.5h/week averaged across 7 days rounds to 39 min")
    }

    // MARK: - Focus suggestion: no history fallback

    /// 0 hours of focus history → the pomodoro default of 25 min so
    /// the very first morning brief on a fresh install still ships a
    /// concrete number instead of a placeholder dash.
    func test_focusSuggestion_noHistory_returns25() {
        let brief = DailyBriefBuilder.compute(
            today: [],
            tasks: [],
            recentCaptures: [],
            lastWeekFocusHours: 0,
            asOf: reference
        )
        XCTAssertEqual(brief.focusSuggestionMinutes, 25,
                       "No focus history must fall back to the pomodoro default of 25 min")
    }

    // MARK: - Defensive: completed tasks excluded

    /// Even when the caller hands in a stale `[Node]` snapshot that
    /// includes a now-completed task, the builder must not count it.
    /// Locks the defensive re-filter in `compute`.
    func test_openTaskCount_excludesCompleted() {
        let tasks: [Node] = [
            makeNode(kind: .task, title: "Open", createdAt: reference),
            makeNode(
                kind: .task,
                title: "Done",
                createdAt: reference,
                completedAt: reference
            ),
        ]
        let brief = DailyBriefBuilder.compute(
            today: [],
            tasks: tasks,
            recentCaptures: [],
            lastWeekFocusHours: 0,
            asOf: reference
        )
        XCTAssertEqual(brief.openTaskCount, 1,
                       "A completed task in the input array must not count toward the brief")
    }

    // MARK: - Localizable contract

    /// Each headline branch must resolve to a non-empty string from
    /// the bundle (i.e., not the literal key). If a translation
    /// regresses, this test catches the missing entry before it ships
    /// into the FR build.
    func test_headlineKeys_resolveToNonEmptyStrings() {
        for (m, t) in [(0, 0), (3, 0), (0, 5), (4, 2)] {
            let value = DailyBriefBuilder.headlineString(meetings: m, tasks: t)
            XCTAssertFalse(value.isEmpty,
                           "headlineString(meetings: \(m), tasks: \(t)) must resolve")
            // %d placeholders must have been substituted — no stray "%d" left.
            XCTAssertFalse(value.contains("%d"),
                           "headlineString must format the %d placeholders for (\(m), \(t))")
        }
    }
}
