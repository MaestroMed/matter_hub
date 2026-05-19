import XCTest
@testable import CalendarKit

/// Locks the pure value-type surface CalendarEvent exposes to the rest
/// of MIND. We intentionally don't touch EKEventStore here — that path
/// is gated by the user's calendar permission, and bringing up a real
/// store inside a test runner is flaky on CI. The actor-level
/// `todayEvents()` is exercised end-to-end on the simulator via the
/// HomeView "Aujourd'hui" card screenshot in vision verification.
final class CalendarReaderTests: XCTestCase {

    // MARK: - Init / accessor contract

    func test_init_preservesAllFields() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(3_600)
        let event = CalendarEvent(
            id: "abc-123",
            title: "Standup VESPER",
            startDate: start,
            endDate: end,
            location: "Visio",
            attendees: ["Mehdi", "Joel"]
        )

        XCTAssertEqual(event.id, "abc-123")
        XCTAssertEqual(event.title, "Standup VESPER")
        XCTAssertEqual(event.startDate, start)
        XCTAssertEqual(event.endDate, end)
        XCTAssertEqual(event.location, "Visio")
        XCTAssertEqual(event.attendees, ["Mehdi", "Joel"])
    }

    func test_init_defaultsLocationAndAttendeesToEmpty() {
        let event = CalendarEvent(
            id: "x",
            title: "Coffee",
            startDate: .now,
            endDate: .now.addingTimeInterval(900)
        )
        XCTAssertNil(event.location)
        XCTAssertTrue(event.attendees.isEmpty,
                      "Default attendees must be empty so HomeView's attendee-strip stays hidden")
    }

    // MARK: - Sorting

    func test_sortedByStart_ordersAscending() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let later = CalendarEvent(id: "b", title: "Later",   startDate: base.addingTimeInterval(7_200), endDate: base.addingTimeInterval(8_000))
        let early = CalendarEvent(id: "a", title: "Early",   startDate: base,                          endDate: base.addingTimeInterval(1_000))
        let mid   = CalendarEvent(id: "c", title: "Mid",     startDate: base.addingTimeInterval(3_600), endDate: base.addingTimeInterval(4_500))

        let sorted = [later, early, mid].sortedByStart()
        XCTAssertEqual(sorted.map(\.id), ["a", "c", "b"])
    }

    func test_sortedByStart_handlesEmptyArray() {
        XCTAssertEqual([CalendarEvent]().sortedByStart(), [])
    }

    // MARK: - Deduplication

    func test_deduplicatedByID_dropsLaterDuplicates() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let first = CalendarEvent(id: "dup", title: "First",  startDate: base, endDate: base.addingTimeInterval(60))
        let dup   = CalendarEvent(id: "dup", title: "Second", startDate: base.addingTimeInterval(120), endDate: base.addingTimeInterval(180))
        let other = CalendarEvent(id: "x",   title: "Other",  startDate: base.addingTimeInterval(240), endDate: base.addingTimeInterval(300))

        let deduped = [first, dup, other].deduplicatedByID()
        XCTAssertEqual(deduped.count, 2)
        XCTAssertEqual(deduped.map(\.id), ["dup", "x"])
        XCTAssertEqual(deduped.first?.title, "First",
                       "First occurrence wins so EventKit's primary copy of a recurring event survives")
    }

    func test_deduplicatedByID_isStableForUniqueIDs() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let events = (0..<5).map { idx in
            CalendarEvent(
                id: "id-\(idx)",
                title: "E\(idx)",
                startDate: base.addingTimeInterval(Double(idx) * 60),
                endDate: base.addingTimeInterval(Double(idx) * 60 + 30)
            )
        }
        XCTAssertEqual(events.deduplicatedByID().map(\.id), events.map(\.id))
    }

    // MARK: - Formatting

    func test_formattedTime_isShortStyleInCurrentLocale() {
        // Build a Date at 09:30 local time so the assertion stays
        // independent of test-machine time zone. Compare against the
        // same formatter we expect the SUT to use.
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 19
        comps.hour = 9
        comps.minute = 30
        let start = Calendar.current.date(from: comps)!
        let event = CalendarEvent(
            id: "fmt",
            title: "Morning sync",
            startDate: start,
            endDate: start.addingTimeInterval(1_800)
        )

        let expected = start.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(event.formattedTime, expected,
                       "Card hour-rendering must follow the user's locale — never hard-code HH:mm")
    }

    // MARK: - Soft-fail contract on CalendarReader

    func test_todayEvents_returnsEmptyWhenPermissionMissing() async {
        // In the test harness EventKit has no granted access, so the
        // actor must short-circuit to [] instead of throwing or crashing.
        // This is the contract HomeView relies on for the card to hide
        // itself silently when permission is denied.
        let reader = CalendarReader(store: .init())
        let events = await reader.todayEvents()
        XCTAssertTrue(events.isEmpty,
                      "todayEvents() must soft-fail to [] when full-access events permission is not granted")
    }
}
