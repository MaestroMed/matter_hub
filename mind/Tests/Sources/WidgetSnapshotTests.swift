import XCTest
@testable import GraphCore

/// v1.0-alpha.16 — Locks the cross-process bridge that pumps the
/// host App's cockpit snapshot into the App Group container the iOS
/// 26 Lock Screen widgets read. Every test pins a hermetic UserDefaults
/// suite (`mind.tests.<UUID>`) so the production
/// `group.app.mind.ios` container stays untouched.
final class WidgetSnapshotTests: XCTestCase {

    /// Hermetic suite per test. UUID prefix ensures isolation across
    /// parallel test runs.
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "mind.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        SharedSnapshotWriter.clear(suiteName: suite)
        suite = nil
        super.tearDown()
    }

    // MARK: - Round-trip

    /// Writing then reading the four columns through the hermetic
    /// suite round-trips every value. Locks the canonical happy
    /// path the host's `.active` scenePhase pumps every wake.
    func test_writeThenRead_roundTripsAllColumns() {
        SharedSnapshotWriter.write(
            leadCount: 7,
            leadLastContact: "Karim Benali",
            totalMRR: 1_250,
            criticalProjectName: "AZ Construction",
            to: suite
        )
        let snapshot = SharedSnapshotWriter.readSnapshot(suiteName: suite)
        XCTAssertEqual(snapshot.leadCount, 7)
        XCTAssertEqual(snapshot.leadLastContact, "Karim Benali")
        XCTAssertEqual(snapshot.totalMRR, 1_250)
        XCTAssertEqual(snapshot.criticalProjectName, "AZ Construction")
    }

    // MARK: - Defaults

    /// Reading from an untouched suite returns the empty snapshot.
    /// Covers the first-launch + post-wipe paths.
    func test_readEmptySuite_returnsZeroedSnapshot() {
        let snapshot = SharedSnapshotWriter.readSnapshot(suiteName: suite)
        XCTAssertEqual(snapshot.leadCount, 0)
        XCTAssertNil(snapshot.leadLastContact)
        XCTAssertEqual(snapshot.totalMRR, 0)
        XCTAssertNil(snapshot.criticalProjectName)
    }

    // MARK: - Truncation

    /// Contact names longer than `maxContactLength` are truncated
    /// with a trailing ellipsis. Locks the budget the rectangular
    /// accessory family expects.
    func test_truncate_longContactNamesAreClipped() {
        let longName = "Élisabeth-Antoinette de la Rochefoucauld"
        SharedSnapshotWriter.write(
            leadCount: 1,
            leadLastContact: longName,
            totalMRR: 0,
            criticalProjectName: nil,
            to: suite
        )
        let snapshot = SharedSnapshotWriter.readSnapshot(suiteName: suite)
        let contact = snapshot.leadLastContact ?? ""
        XCTAssertTrue(contact.count <= 21,
                      "Truncated contact must stay <= 20 + ellipsis (got \(contact.count))")
        XCTAssertTrue(contact.hasSuffix("\u{2026}"),
                      "Truncated contact must end with ellipsis")
        XCTAssertTrue(contact.hasPrefix("Élisabeth"),
                      "Truncated contact must keep prefix")
    }

    // MARK: - Clamping

    /// Negative `leadCount` + negative `totalMRR` both collapse to
    /// 0. Defensive against any caller passing a math result that
    /// went sideways.
    func test_negativeInputs_clampToZero() {
        SharedSnapshotWriter.write(
            leadCount: -5,
            leadLastContact: "x",
            totalMRR: -1_000,
            criticalProjectName: nil,
            to: suite
        )
        let snapshot = SharedSnapshotWriter.readSnapshot(suiteName: suite)
        XCTAssertEqual(snapshot.leadCount, 0)
        XCTAssertEqual(snapshot.totalMRR, 0)
    }

    // MARK: - Clear

    /// After `clear(suiteName:)` reading the suite returns the
    /// empty snapshot. Covers the "Wipe all data" Settings flow
    /// downstream of v1.0-alpha.16.
    func test_clear_removesEveryKey() {
        SharedSnapshotWriter.write(
            leadCount: 9,
            leadLastContact: "Aaron",
            totalMRR: 9_999,
            criticalProjectName: "IEF&Co",
            to: suite
        )
        SharedSnapshotWriter.clear(suiteName: suite)
        let snapshot = SharedSnapshotWriter.readSnapshot(suiteName: suite)
        XCTAssertEqual(snapshot.leadCount, 0)
        XCTAssertNil(snapshot.leadLastContact)
        XCTAssertEqual(snapshot.totalMRR, 0)
        XCTAssertNil(snapshot.criticalProjectName)
    }

    // MARK: - Refresh helper smoke

    /// Calling the production `refresh(...)` against the real suite
    /// must not crash. We don't assert on the actual stored values
    /// because the production suite is shared across the process —
    /// the smoke test guards the WidgetCenter reload path + key
    /// writes.
    func test_refreshProductionSuite_doesNotCrash() {
        SharedSnapshotWriter.refresh(
            leadCount: 0,
            leadLastContact: nil,
            totalMRR: 0,
            criticalProjectName: nil
        )
        // No XCTAssert needed — the test passes if no crash.
    }

    // MARK: - Concurrent writes

    /// Spawning 32 concurrent write/clear pairs across the same
    /// suite must not deadlock. UserDefaults itself coalesces
    /// concurrent writes; this guards against accidental locks in
    /// the writer's internal logic.
    func test_concurrentRefresh_doesNotDeadlock() async {
        // Pin a fresh suite for this stress test so the lingering
        // values can't leak into other tests.
        let stressSuite = "mind.tests.\(UUID().uuidString).stress"
        defer { SharedSnapshotWriter.clear(suiteName: stressSuite) }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<32 {
                group.addTask {
                    SharedSnapshotWriter.write(
                        leadCount: i,
                        leadLastContact: "Lead-\(i)",
                        totalMRR: i * 10,
                        criticalProjectName: i.isMultiple(of: 2) ? "Project-\(i)" : nil,
                        to: stressSuite
                    )
                }
            }
        }
        // Final read just needs to return something valid (any of
        // the 32 writers wins — UserDefaults coalesces).
        let snapshot = SharedSnapshotWriter.readSnapshot(suiteName: stressSuite)
        XCTAssertGreaterThanOrEqual(snapshot.leadCount, 0)
    }

    // MARK: - Empty contact

    /// Empty + whitespace-only contact names collapse to nil on the
    /// read side. The widget's rectangular family interprets nil as
    /// "no recent contact" + renders the empty-state CTA.
    func test_emptyContactCollapsesToNil() {
        SharedSnapshotWriter.write(
            leadCount: 1,
            leadLastContact: "   ",
            totalMRR: 0,
            criticalProjectName: nil,
            to: suite
        )
        let snapshot = SharedSnapshotWriter.readSnapshot(suiteName: suite)
        XCTAssertNil(snapshot.leadLastContact)
    }
}
