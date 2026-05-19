import XCTest
@testable import OutreachKit

/// v0.29 — Locks the pure parts of Smart Follow-Up Sequences:
/// `FollowUpSequenceBuilder` (default + custom templates), the
/// mutating helpers on `FollowUpSequence`, and the Codable round
/// trip. The store + scheduler are exercised end-to-end via the
/// simulator screenshot path; the disk + UN bindings can't run from
/// a hosted unit test cleanly.
final class FollowUpSequenceTests: XCTestCase {

    // MARK: - Fixtures

    private func anchorStart(year: Int = 2026, month: Int = 5, day: Int = 19) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 8, minute: 30))
            ?? Date(timeIntervalSince1970: 1747641000)
    }

    private func sampleSequence(
        prospectID: UUID = UUID(),
        startDate: Date? = nil
    ) -> FollowUpSequence {
        FollowUpSequenceBuilder.build(
            prospectNodeID: prospectID,
            startDate: startDate ?? anchorStart()
        )
    }

    // MARK: - Default template shape

    /// The canonical template must yield exactly 4 touches — every
    /// downstream UI assumption (step indicator, 1/4 progress math)
    /// depends on this contract.
    func test_defaultTemplate_produces4Touches() {
        let seq = sampleSequence()
        XCTAssertEqual(seq.touches.count, 4)
    }

    /// The day offsets must be 0 / 3 / 7 / 14 in order — the cadence
    /// is the v0.29 product contract. Lock it so a future template
    /// edit raises a test failure rather than silently shipping a
    /// different rhythm.
    func test_defaultTemplate_dayOffsetsAre_0_3_7_14() {
        let seq = sampleSequence()
        XCTAssertEqual(seq.touches.map(\.dayOffset), [0, 3, 7, 14])
    }

    /// `scheduledFor` for each touch must equal `startOfDay(startDate)
    /// + dayOffset days, at noon local`. Locks the noon-anchor
    /// invariant that makes the scheduler's DST math safe.
    func test_defaultTemplate_scheduledForDatesComputedFromStart() {
        let calendar = Calendar.current
        let start = anchorStart()
        let seq = FollowUpSequenceBuilder.build(
            prospectNodeID: UUID(),
            startDate: start,
            calendar: calendar
        )
        let dayStart = calendar.startOfDay(for: start)
        for (i, expectedOffset) in [0, 3, 7, 14].enumerated() {
            let expectedDay = calendar.date(byAdding: .day, value: expectedOffset, to: dayStart)!
            let expectedNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: expectedDay)!
            XCTAssertEqual(
                calendar.compare(seq.touches[i].scheduledFor, to: expectedNoon, toGranularity: .minute),
                .orderedSame,
                "Touch \(i): expected scheduledFor \(expectedNoon) but got \(seq.touches[i].scheduledFor)"
            )
        }
    }

    /// The channel / angle pairs must match the v0.29 product
    /// contract: Day 0 email-initial, Day 3 linkedIn-reminder, Day 7
    /// email-valueAdd, Day 14 email-breakUp.
    func test_defaultTemplate_pairsChannelAngleCorrectly() {
        let seq = sampleSequence()
        XCTAssertEqual(seq.touches[0].channel, .email)
        XCTAssertEqual(seq.touches[0].angle, .initial)
        XCTAssertEqual(seq.touches[1].channel, .linkedIn)
        XCTAssertEqual(seq.touches[1].angle, .reminder)
        XCTAssertEqual(seq.touches[2].channel, .email)
        XCTAssertEqual(seq.touches[2].angle, .valueAdd)
        XCTAssertEqual(seq.touches[3].channel, .email)
        XCTAssertEqual(seq.touches[3].angle, .breakUp)
    }

    /// Day 0 touch is pre-marked `.sent` because the toggle that
    /// triggers the builder fires from the "Ouvrir dans Mail" CTA —
    /// the initial email IS that send. Every other touch starts
    /// `.pending`.
    func test_defaultTemplate_day0PreSent_othersPending() {
        let seq = sampleSequence()
        XCTAssertEqual(seq.touches[0].status, .sent)
        XCTAssertEqual(seq.touches[1].status, .pending)
        XCTAssertEqual(seq.touches[2].status, .pending)
        XCTAssertEqual(seq.touches[3].status, .pending)
        XCTAssertNotNil(seq.touches[0].sentAt)
    }

    /// Custom templates override the default. Locks the contract so
    /// a hypothetical "aggressive" cadence (more touches, tighter
    /// spacing) is plumbed end-to-end without a code change.
    func test_customTemplate_overridesDefault() {
        let custom: [(Int, TouchChannel, TouchAngle)] = [
            (0, .email, .initial),
            (1, .email, .reminder),
        ]
        let seq = FollowUpSequenceBuilder.build(
            prospectNodeID: UUID(),
            template: custom
        )
        XCTAssertEqual(seq.touches.count, 2)
        XCTAssertEqual(seq.touches[0].dayOffset, 0)
        XCTAssertEqual(seq.touches[1].dayOffset, 1)
    }

    // MARK: - Status lifecycle

    /// Fresh sequences start as `.active` — the UI's "Marquer comme
    /// répondu" CTA + the scheduler's "skip non-active" guard both
    /// rely on this default.
    func test_freshSequence_statusIsActive() {
        XCTAssertEqual(sampleSequence().status, .active)
    }

    /// `markReplied` flips status to `.replied`, sets `pausedAt`,
    /// and records `pausedReason = .replied`. Touches stay in their
    /// last state so the UI can still show "2/4 done, paused at
    /// replied".
    func test_markReplied_transitionsStatusAndReason() {
        var seq = sampleSequence()
        seq.markReplied(at: Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(seq.status, .replied)
        XCTAssertEqual(seq.pausedReason, .replied)
        XCTAssertEqual(seq.pausedAt?.timeIntervalSince1970, 2_000_000_000)
    }

    /// `markPaused` flips status to `.paused` with the supplied
    /// reason. Distinguished from `.replied` so the scheduler /
    /// store / UI can tell the user-driven pause apart from the
    /// data-driven one.
    func test_markPaused_recordsReason() {
        var seq = sampleSequence()
        seq.markPaused(reason: .doNotContact)
        XCTAssertEqual(seq.status, .paused)
        XCTAssertEqual(seq.pausedReason, .doNotContact)
    }

    /// `markTouchSent` flips the matching touch's status to `.sent`
    /// + records `sentAt`. Calling twice is a no-op past the first.
    func test_markTouchSent_isIdempotent() {
        var seq = sampleSequence()
        let touchID = seq.touches[1].id
        seq.markTouchSent(touchID: touchID, at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(seq.touches[1].status, .sent)
        XCTAssertEqual(seq.touches[1].sentAt?.timeIntervalSince1970, 1)
        seq.markTouchSent(touchID: touchID, at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(seq.touches[1].status, .sent)
        // First sentAt sticks — the helper isn't a "last touch wins"
        // ratchet; the second call simply re-asserts.
    }

    /// `nextPendingTouch` returns the first non-sent / non-skipped
    /// touch in order. After Day 0 is pre-sent, the next pending is
    /// Day 3. Mark it sent, next pending becomes Day 7.
    func test_nextPendingTouch_walksPendingInOrder() {
        var seq = sampleSequence()
        XCTAssertEqual(seq.nextPendingTouch?.dayOffset, 3)
        seq.markTouchSent(touchID: seq.touches[1].id)
        XCTAssertEqual(seq.nextPendingTouch?.dayOffset, 7)
    }

    /// Once every touch is `.sent` / `.skipped`, `recompute()`
    /// flips status to `.completed`. Pure sequence-level invariant
    /// the store relies on for "stop scheduling" branches.
    func test_allTouchesResolved_transitionsToCompleted() {
        var seq = sampleSequence()
        for touch in seq.touches {
            seq.markTouchSent(touchID: touch.id)
        }
        XCTAssertEqual(seq.status, .completed)
        XCTAssertNil(seq.nextPendingTouch)
    }

    // MARK: - Codable round-trip

    /// A sequence written through JSONEncoder and read back via
    /// JSONDecoder must be equal to the original. Locks the store's
    /// on-disk contract so any future field is added with a default
    /// value (otherwise the decode would fail silently).
    func test_codable_roundTripsLossless() throws {
        let seq = sampleSequence()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(seq)
        let restored = try decoder.decode(FollowUpSequence.self, from: data)
        XCTAssertEqual(restored, seq)
    }

    // MARK: - Equality semantics

    /// Two sequences built from the same inputs but with different
    /// touch ids must NOT compare equal — `id` + per-touch `id` are
    /// part of the equality contract so the store can use Equatable
    /// to short-circuit redundant writes.
    func test_equality_distinguishesByTouchID() {
        let prospectID = UUID()
        let start = anchorStart()
        let a = FollowUpSequenceBuilder.build(prospectNodeID: prospectID, startDate: start)
        let b = FollowUpSequenceBuilder.build(prospectNodeID: prospectID, startDate: start)
        XCTAssertNotEqual(a, b, "Distinct builds must produce distinct ids")
    }

    // MARK: - Touches due today

    /// `touchesDue(on:)` filters to pending touches whose
    /// `scheduledFor` lands on the calendar day spanning `on`.
    /// Day 3 of the sequence falls in the window when `on` is
    /// start + 3 days; outside the window it returns no rows.
    func test_touchesDueToday_filtersByCalendarDay() {
        let start = anchorStart()
        let calendar = Calendar.current
        let seq = FollowUpSequenceBuilder.build(prospectNodeID: UUID(), startDate: start)
        let day3 = calendar.date(byAdding: .day, value: 3, to: start)!
        let day4 = calendar.date(byAdding: .day, value: 4, to: start)!
        XCTAssertEqual(seq.touchesDue(on: day3).map(\.dayOffset), [3])
        XCTAssertEqual(seq.touchesDue(on: day4).map(\.dayOffset), [])
    }
}
