import XCTest
@testable import GraphCore

/// v1.0-alpha.3 — Locks the pure `LeadInboxSorter.sort(_:by:)`
/// projection that backs HomeView's "Aujourd'hui" inbox + the per-
/// Project leads list. Eight tests cover the documented contract:
/// date sort desc, status priority order, status tie-break by date,
/// empty input, single-lead short-circuit, deterministic re-sort,
/// and the priority table itself.
@MainActor
final class LeadInboxSortingTests: XCTestCase {

    // Reference dates anchored at a fixed instant so the tests don't
    // depend on `Date.now` drift. `t0` is the newest, `t3` the oldest.
    private let t0 = Date(timeIntervalSince1970: 1_000_300)
    private let t1 = Date(timeIntervalSince1970: 1_000_200)
    private let t2 = Date(timeIntervalSince1970: 1_000_100)
    private let t3 = Date(timeIntervalSince1970: 1_000_000)

    private func lead(_ status: LeadStatus, at date: Date, email: String = "x@y.fr") -> Lead {
        Lead(
            receivedAt: date,
            contactEmail: email,
            status: status,
            statusUpdatedAt: date
        )
    }

    /// `.dateDescending` sorts newest first. The classic "Aujourd'hui
    /// inbox" projection — most recent webhook lands at the top of
    /// the HomeView card.
    func test_dateDescending_sortsNewestFirst() {
        let input = [
            lead(.new, at: t3),
            lead(.new, at: t0),
            lead(.new, at: t2),
            lead(.new, at: t1),
        ]
        let sorted = LeadInboxSorter.sort(input, by: .dateDescending)
        XCTAssertEqual(sorted.map(\.receivedAt), [t0, t1, t2, t3])
    }

    /// `.statusPriority` ordering: `.new` → `.qualified` → `.contacted`
    /// → `.won` → `.lost` → `.spam`. Drives the triage view where
    /// unanswered leads must surface before terminal ones.
    func test_statusPriority_followsDocumentedOrder() {
        let input = [
            lead(.spam, at: t0),
            lead(.lost, at: t0),
            lead(.won, at: t0),
            lead(.contacted, at: t0),
            lead(.qualified, at: t0),
            lead(.new, at: t0),
        ]
        let sorted = LeadInboxSorter.sort(input, by: .statusPriority)
        XCTAssertEqual(
            sorted.map(\.statusEnum),
            [.new, .qualified, .contacted, .won, .lost, .spam]
        )
    }

    /// Inside a status bucket, the secondary key is `receivedAt` desc.
    /// Two `.new` leads from the same minute → newest renders first.
    func test_statusPriority_tieBreaksByDateDescending() {
        let input = [
            lead(.new, at: t2, email: "a@x.fr"),
            lead(.new, at: t0, email: "b@x.fr"),
            lead(.new, at: t1, email: "c@x.fr"),
        ]
        let sorted = LeadInboxSorter.sort(input, by: .statusPriority)
        XCTAssertEqual(sorted.map(\.contactEmail), ["b@x.fr", "c@x.fr", "a@x.fr"])
    }

    /// `.statusPriority` keeps the documented order across mixed
    /// statuses + mixed dates — verifies the predicate composes
    /// correctly (priority first, then date).
    func test_statusPriority_mixedStatusesAndDates() {
        let input = [
            lead(.qualified, at: t3, email: "q-old@x.fr"),
            lead(.new, at: t2, email: "n-mid@x.fr"),
            lead(.new, at: t0, email: "n-new@x.fr"),
            lead(.contacted, at: t1, email: "c-mid@x.fr"),
        ]
        let sorted = LeadInboxSorter.sort(input, by: .statusPriority)
        XCTAssertEqual(
            sorted.map(\.contactEmail),
            ["n-new@x.fr", "n-mid@x.fr", "q-old@x.fr", "c-mid@x.fr"]
        )
    }

    /// Empty input returns empty output without crashing the
    /// allocator (short-circuit path).
    func test_emptyInput_returnsEmpty() {
        let sorted = LeadInboxSorter.sort([], by: .dateDescending)
        XCTAssertEqual(sorted.count, 0)
    }

    /// Single-lead input round-trips unchanged regardless of key —
    /// the short-circuit must not corrupt the lone row.
    func test_singleLead_isPreserved() {
        let solo = lead(.qualified, at: t1)
        XCTAssertEqual(LeadInboxSorter.sort([solo], by: .dateDescending).count, 1)
        XCTAssertEqual(LeadInboxSorter.sort([solo], by: .statusPriority).count, 1)
        XCTAssertIdentical(
            LeadInboxSorter.sort([solo], by: .dateDescending).first,
            solo
        )
    }

    /// Running the sort twice on the same input yields the same
    /// order — locks determinism so SwiftUI's diff doesn't flicker
    /// rows across renders.
    func test_isDeterministic_acrossRepeatCalls() {
        let input = [
            lead(.new, at: t2, email: "a@x.fr"),
            lead(.contacted, at: t1, email: "b@x.fr"),
            lead(.new, at: t0, email: "c@x.fr"),
            lead(.qualified, at: t3, email: "d@x.fr"),
        ]
        let first = LeadInboxSorter.sort(input, by: .statusPriority)
        let second = LeadInboxSorter.sort(input, by: .statusPriority)
        XCTAssertEqual(first.map(\.contactEmail), second.map(\.contactEmail))
    }

    /// The priority table itself: every `LeadStatus` value returns a
    /// unique non-negative priority and the documented order holds.
    func test_priorityTable_isUniqueAndOrdered() {
        let priorities = LeadStatus.allCases.map { LeadInboxSorter.priority(of: $0) }
        XCTAssertEqual(Set(priorities).count, LeadStatus.allCases.count,
                       "Every LeadStatus must map to a unique priority.")
        XCTAssertLessThan(
            LeadInboxSorter.priority(of: .new),
            LeadInboxSorter.priority(of: .qualified)
        )
        XCTAssertLessThan(
            LeadInboxSorter.priority(of: .qualified),
            LeadInboxSorter.priority(of: .contacted)
        )
        XCTAssertLessThan(
            LeadInboxSorter.priority(of: .contacted),
            LeadInboxSorter.priority(of: .won)
        )
        XCTAssertLessThan(
            LeadInboxSorter.priority(of: .won),
            LeadInboxSorter.priority(of: .lost)
        )
        XCTAssertLessThan(
            LeadInboxSorter.priority(of: .lost),
            LeadInboxSorter.priority(of: .spam)
        )
    }
}
