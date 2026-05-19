import XCTest
import Foundation
@testable import MIND
@testable import GraphCore

/// v0.16 — Locks the pure `WeeklyDigestBuilder.compute` contract that
/// powers the new HomeView "Bilan de la semaine" card. Every visible
/// number on the card comes from this function, so if any of these
/// fail the user sees wrong counts on the most-trafficked screen of
/// the app.
///
/// Strategy
/// --------
/// Build small in-memory arrays of `Node` + `FocusSessionRecord`,
/// pin the reference date so the 7-day window is deterministic, run
/// `compute` once, then assert on every field of the returned digest.
/// No SwiftData container is needed because `compute` takes plain
/// arrays — exactly what makes it cheap to lock.
final class WeeklyDigestTests: XCTestCase {

    /// Fixed anchor used by every test. ~2026-05-19 12:00 UTC. The
    /// 7-day window is then [2026-05-12 12:00, 2026-05-19 12:00].
    private let reference = Date(timeIntervalSince1970: 1_779_355_200)

    // MARK: - Builders

    private func makeNode(
        kind: NodeKind,
        title: String,
        createdAt: Date,
        updatedAt: Date? = nil
    ) -> Node {
        let node = Node(kind: kind, title: title)
        node.createdAt = createdAt
        node.updatedAt = updatedAt ?? createdAt
        return node
    }

    private func makeSession(
        completedAt: Date,
        actualSeconds: Double
    ) -> FocusSessionRecord {
        FocusSessionRecord(
            intention: "Test",
            startDate: completedAt.addingTimeInterval(-actualSeconds),
            completedAt: completedAt,
            plannedDurationSeconds: actualSeconds,
            actualDurationSeconds: actualSeconds,
            completedNormally: true
        )
    }

    private func dayAgo(_ days: Double) -> Date {
        reference.addingTimeInterval(-days * 24 * 3600)
    }

    // MARK: - Empty input

    /// Empty arrays → every counter is zero and the digest is
    /// non-meaningful. The render gate on HomeView depends on this
    /// case to hide the card on a freshly installed app.
    func test_emptyInputs_yieldZeroDigest() {
        let digest = WeeklyDigestBuilder.compute(
            nodes: [],
            focusSessions: [],
            asOf: reference
        )

        XCTAssertEqual(digest.captureCount, 0)
        XCTAssertEqual(digest.auditCount, 0)
        XCTAssertEqual(digest.focusHours, 0, accuracy: 0.001)
        XCTAssertTrue(digest.highlightedCaptures.isEmpty)
        XCTAssertNil(digest.narrative)
        XCTAssertFalse(digest.isMeaningful)
    }

    // MARK: - Window filter

    /// 3 captures within the 7-day window + 2 outside → `captureCount`
    /// must be exactly 3. Anchors the cutoff math against
    /// off-by-one-day mistakes.
    func test_captureCount_filtersOutsideWindow() {
        let nodes: [Node] = [
            makeNode(kind: .capture, title: "Inside 1", createdAt: dayAgo(1)),
            makeNode(kind: .capture, title: "Inside 2", createdAt: dayAgo(3)),
            makeNode(kind: .note,    title: "Inside 3", createdAt: dayAgo(6)),
            makeNode(kind: .capture, title: "Outside 1", createdAt: dayAgo(8)),
            makeNode(kind: .note,    title: "Outside 2", createdAt: dayAgo(30)),
        ]

        let digest = WeeklyDigestBuilder.compute(
            nodes: nodes,
            focusSessions: [],
            asOf: reference
        )

        XCTAssertEqual(digest.captureCount, 3,
                       "Both .capture and .note kinds inside the window must count")
        XCTAssertTrue(digest.isMeaningful,
                      "Any non-zero counter must flip isMeaningful")
    }

    // MARK: - Focus aggregation

    /// `focusHours` must sum the in-window sessions' actual durations
    /// and divide by 3600. Two sessions outside the window must be
    /// ignored even though their durations are large.
    func test_focusHours_sumsOnlyInWindowSessions() {
        let sessions: [FocusSessionRecord] = [
            // 25 minutes + 35 minutes = 60 minutes = 1 hour
            makeSession(completedAt: dayAgo(0.5), actualSeconds: 25 * 60),
            makeSession(completedAt: dayAgo(2),   actualSeconds: 35 * 60),
            // Outside the window — must NOT be summed
            makeSession(completedAt: dayAgo(8),   actualSeconds: 90 * 60),
            makeSession(completedAt: dayAgo(20),  actualSeconds: 600 * 60),
        ]

        let digest = WeeklyDigestBuilder.compute(
            nodes: [],
            focusSessions: sessions,
            asOf: reference
        )

        XCTAssertEqual(digest.focusHours, 1.0, accuracy: 0.001,
                       "Two 25+35 minute in-window sessions → 1 focus hour")
    }

    // MARK: - Highlights ordering + cap

    /// `highlightedCaptures` must be ordered by `updatedAt` descending
    /// AND capped at 5. We seed 7 in-window captures with monotonically
    /// increasing updatedAt; the digest must surface the 5 most recently
    /// edited, in the right order.
    func test_highlights_sortedAndCappedAtFive() {
        var nodes: [Node] = []
        for i in 0..<7 {
            // createdAt all inside window; updatedAt increases with i
            nodes.append(makeNode(
                kind: .capture,
                title: "Capture #\(i)",
                createdAt: dayAgo(1),
                updatedAt: dayAgo(0.1).addingTimeInterval(Double(i) * 60)
            ))
        }

        let digest = WeeklyDigestBuilder.compute(
            nodes: nodes,
            focusSessions: [],
            asOf: reference
        )

        XCTAssertEqual(digest.highlightedCaptures.count, 5,
                       "Highlights are hard-capped at 5")
        XCTAssertEqual(
            digest.highlightedCaptures,
            ["Capture #6", "Capture #5", "Capture #4", "Capture #3", "Capture #2"],
            "Highlights must be ordered by updatedAt descending"
        )
    }

    // MARK: - Audits

    /// 1 audit inside the window + irrelevant kinds outside → audit
    /// count of 1 and capture count of zero. The two counters live on
    /// different render columns of the card and must never bleed.
    func test_auditCount_separatesFromCaptureCount() {
        let nodes: [Node] = [
            makeNode(kind: .audit,   title: "Q1 brand audit", createdAt: dayAgo(2)),
            makeNode(kind: .capture, title: "Outside",        createdAt: dayAgo(40)),
        ]

        let digest = WeeklyDigestBuilder.compute(
            nodes: nodes,
            focusSessions: [],
            asOf: reference
        )

        XCTAssertEqual(digest.auditCount, 1)
        XCTAssertEqual(digest.captureCount, 0)
        XCTAssertTrue(digest.isMeaningful,
                      "An audit alone is enough to surface the card")
    }

    // MARK: - Reference cutoff

    /// Sliding the reference date forward by N days must slide the
    /// cutoff forward too — i.e. captures that were "inside the
    /// window" relative to last Tuesday are "outside" relative to
    /// today. Locks the cutoff math.
    func test_referenceDate_slidesCutoffWindow() {
        let nodes: [Node] = [
            // ~5 days before original reference → inside window for `reference`
            // but outside the window if we move the reference 10 days forward.
            makeNode(kind: .capture, title: "Slides out", createdAt: dayAgo(5)),
        ]

        let nowDigest = WeeklyDigestBuilder.compute(
            nodes: nodes,
            focusSessions: [],
            asOf: reference
        )
        XCTAssertEqual(nowDigest.captureCount, 1,
                       "5-day-old capture is inside the window relative to reference")

        let futureReference = reference.addingTimeInterval(10 * 24 * 3600)
        let laterDigest = WeeklyDigestBuilder.compute(
            nodes: nodes,
            focusSessions: [],
            asOf: futureReference
        )
        XCTAssertEqual(laterDigest.captureCount, 0,
                       "Moving the reference 10 days forward must slide the same capture OUT of the window")
    }

    // MARK: - Empty-title filter

    /// Highlights must never contain blank titles — those would render
    /// as empty bullets on the card. Locks the trim+filter step the
    /// builder applies before sorting.
    func test_highlights_skipBlankTitles() {
        let nodes: [Node] = [
            makeNode(kind: .capture, title: "Visible",   createdAt: dayAgo(1)),
            makeNode(kind: .capture, title: "   ",        createdAt: dayAgo(2)),
            makeNode(kind: .note,    title: "",           createdAt: dayAgo(3)),
            makeNode(kind: .note,    title: "Second one", createdAt: dayAgo(4)),
        ]

        let digest = WeeklyDigestBuilder.compute(
            nodes: nodes,
            focusSessions: [],
            asOf: reference
        )

        XCTAssertEqual(digest.captureCount, 4,
                       "Counter is permissive — counts even blank-title nodes")
        XCTAssertEqual(digest.highlightedCaptures, ["Visible", "Second one"],
                       "Highlights must drop empty-title captures")
    }

    // MARK: - withNarrative

    /// `withNarrative` returns a new digest with every other field
    /// preserved. The HomeView async path depends on this to swap
    /// the narrative in after the on-device model resolves.
    func test_withNarrative_preservesOtherFields() {
        let original = WeeklyDigest(
            weekOf: reference,
            captureCount: 4,
            auditCount: 1,
            focusHours: 2.5,
            highlightedCaptures: ["A", "B"],
            narrative: nil
        )

        let hydrated = original.withNarrative("Bonne semaine.")

        XCTAssertEqual(hydrated.captureCount, 4)
        XCTAssertEqual(hydrated.auditCount, 1)
        XCTAssertEqual(hydrated.focusHours, 2.5, accuracy: 0.001)
        XCTAssertEqual(hydrated.highlightedCaptures, ["A", "B"])
        XCTAssertEqual(hydrated.narrative, "Bonne semaine.")
        XCTAssertEqual(hydrated.weekOf, original.weekOf)
    }
}
