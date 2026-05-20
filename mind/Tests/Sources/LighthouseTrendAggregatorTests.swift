import XCTest
@testable import GraphCore

/// v1.1.0 — Locks the day-bucketing behaviour of
/// `LighthouseTrendAggregator.last30Days(...)` so a regression that
/// fills missing days with zeros (vs. nil) or quietly drops snapshots
/// from the window shows up as a test failure, not a silent UI bug.
final class LighthouseTrendAggregatorTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func snapshot(
        capturedAt: Date,
        performance: Int = 50,
        projectID: UUID = UUID()
    ) -> LighthouseSnapshot {
        LighthouseSnapshot(
            id: UUID(),
            capturedAt: capturedAt,
            projectID: projectID,
            host: "example.com",
            strategy: "mobile",
            performance: performance,
            accessibility: performance,
            bestPractices: performance,
            seo: performance,
            lcpSeconds: 0,
            inpMs: 0,
            cls: 0
        )
    }

    func test_emptyInput_emitsEmptyOutputForCustomWindow() {
        let now = Date(timeIntervalSince1970: 1_716_000_000)
        let points = LighthouseTrendAggregator.last30Days(
            [],
            now: now,
            calendar: calendar,
            window: 7
        )
        XCTAssertEqual(points.count, 7)
        XCTAssertTrue(points.allSatisfy { $0.value == nil })
    }

    func test_outputLengthMatchesWindow() {
        let now = Date(timeIntervalSince1970: 1_716_000_000)
        let points = LighthouseTrendAggregator.last30Days(
            [],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(points.count, 30)
    }

    func test_missingDaysCollapseToNilNotZero() {
        let now = Date(timeIntervalSince1970: 1_716_000_000)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        let pts = LighthouseTrendAggregator.last30Days(
            [snapshot(capturedAt: twoDaysAgo, performance: 80)],
            now: now,
            calendar: calendar,
            window: 5
        )
        XCTAssertEqual(pts.count, 5)
        // Index 2 (counting from 0 oldest → newest with offset
        // 4,3,2,1,0) is the day -2 from today: 5-1-2 = 2.
        XCTAssertEqual(pts[2].value, 80)
        XCTAssertNil(pts[0].value)
        XCTAssertNil(pts[1].value)
        XCTAssertNil(pts[3].value)
        XCTAssertNil(pts[4].value)
    }

    func test_multipleSnapshotsSameDay_latestWins() {
        let now = Date(timeIntervalSince1970: 1_716_000_000)
        let dayStart = calendar.startOfDay(for: now)
        let morning = dayStart.addingTimeInterval(3 * 3600)   // 03:00
        let evening = dayStart.addingTimeInterval(20 * 3600)  // 20:00
        let pts = LighthouseTrendAggregator.last30Days(
            [
                snapshot(capturedAt: morning, performance: 30),
                snapshot(capturedAt: evening, performance: 90),
            ],
            now: now,
            calendar: calendar,
            window: 1
        )
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(pts.first?.value, 90)
    }

    func test_snapshotsOlderThanWindow_areDropped() {
        let now = Date(timeIntervalSince1970: 1_716_000_000)
        let ancient = calendar.date(byAdding: .day, value: -45, to: now)!
        let recent = calendar.date(byAdding: .day, value: -3, to: now)!
        let pts = LighthouseTrendAggregator.last30Days(
            [
                snapshot(capturedAt: ancient, performance: 10),
                snapshot(capturedAt: recent, performance: 70),
            ],
            now: now,
            calendar: calendar,
            window: 30
        )
        XCTAssertEqual(pts.count, 30)
        let values = pts.compactMap { $0.value }
        XCTAssertEqual(values, [70])
        XCTAssertFalse(values.contains(10))
    }

    func test_snapshotCount_inWindow_matchesExpectations() {
        let now = Date(timeIntervalSince1970: 1_716_000_000)
        let d1 = calendar.date(byAdding: .day, value: -1, to: now)!
        let d2 = calendar.date(byAdding: .day, value: -3, to: now)!
        let d3 = calendar.date(byAdding: .day, value: -40, to: now)!
        let count = LighthouseTrendAggregator.snapshotCount(
            [
                snapshot(capturedAt: d1, performance: 80),
                snapshot(capturedAt: d2, performance: 60),
                snapshot(capturedAt: d3, performance: 20),
            ],
            now: now,
            calendar: calendar,
            window: 30
        )
        XCTAssertEqual(count, 2)
    }
}
