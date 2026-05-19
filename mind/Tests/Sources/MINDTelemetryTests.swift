import XCTest
@testable import GraphCore

/// MINDTelemetry is the dependency-free instrumentation facade. These
/// tests lock the contract that every module relies on:
///   - calls are silent no-ops when no sink is installed
///   - the sink receives every breadcrumb with the right name,
///     category, level, and data
///   - sink replacement works (so MINDApp.bootstrapSentry can be
///     re-run if Mehdi swaps DSNs at runtime)
@MainActor
final class MINDTelemetryTests: XCTestCase {

    /// Captures every event the sink receives so tests can assert
    /// on what arrived.
    private var received: [MINDTelemetry.Event] = []

    override func setUp() {
        super.setUp()
        received = []
        MINDTelemetry.sink = nil  // start every test with a clean slate
    }

    override func tearDown() {
        MINDTelemetry.sink = nil
        super.tearDown()
    }

    // MARK: - No-op when sink is nil

    func test_breadcrumb_isSilent_whenSinkIsNil() {
        XCTAssertNil(MINDTelemetry.sink)
        MINDTelemetry.breadcrumb("anything", category: "test")
        // No assertion needed — the test passes as long as the call
        // didn't crash. Documenting the contract explicitly.
        XCTAssertTrue(received.isEmpty)
    }

    func test_info_warning_error_areAllSilent_whenSinkIsNil() {
        MINDTelemetry.info("a")
        MINDTelemetry.warning("b")
        MINDTelemetry.error("c")
        XCTAssertTrue(received.isEmpty)
    }

    // MARK: - Sink installation

    func test_sink_receivesBreadcrumb_whenInstalled() {
        MINDTelemetry.sink = { event in
            self.received.append(event)
        }

        MINDTelemetry.breadcrumb(
            "user.tapped.run",
            category: "ui",
            level: .info,
            data: ["screen": "AuditSheet"]
        )

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].name, "user.tapped.run")
        XCTAssertEqual(received[0].category, "ui")
        XCTAssertEqual(received[0].level, .info)
        XCTAssertEqual(received[0].data["screen"], "AuditSheet")
    }

    func test_info_setsLevelToInfo() {
        MINDTelemetry.sink = { self.received.append($0) }
        MINDTelemetry.info("ok")
        XCTAssertEqual(received.first?.level, .info)
    }

    func test_warning_setsLevelToWarning() {
        MINDTelemetry.sink = { self.received.append($0) }
        MINDTelemetry.warning("watch out")
        XCTAssertEqual(received.first?.level, .warning)
    }

    func test_error_setsLevelToError() {
        MINDTelemetry.sink = { self.received.append($0) }
        MINDTelemetry.error("boom")
        XCTAssertEqual(received.first?.level, .error)
    }

    // MARK: - Defaults

    func test_breadcrumb_defaultsToAppCategory() {
        MINDTelemetry.sink = { self.received.append($0) }
        MINDTelemetry.breadcrumb("default")
        XCTAssertEqual(received.first?.category, "app")
    }

    func test_breadcrumb_defaultsToInfoLevel() {
        MINDTelemetry.sink = { self.received.append($0) }
        MINDTelemetry.breadcrumb("default")
        XCTAssertEqual(received.first?.level, .info)
    }

    func test_breadcrumb_defaultsToEmptyData() {
        MINDTelemetry.sink = { self.received.append($0) }
        MINDTelemetry.breadcrumb("no-data")
        XCTAssertTrue(received.first?.data.isEmpty ?? false)
    }

    // MARK: - Sink replacement

    func test_sinkReplacement_routesToNewSink() {
        var firstSinkReceived: [String] = []
        var secondSinkReceived: [String] = []

        MINDTelemetry.sink = { firstSinkReceived.append($0.name) }
        MINDTelemetry.info("event_1")
        XCTAssertEqual(firstSinkReceived, ["event_1"])

        MINDTelemetry.sink = { secondSinkReceived.append($0.name) }
        MINDTelemetry.info("event_2")
        XCTAssertEqual(firstSinkReceived, ["event_1"],
                       "first sink must not receive after replacement")
        XCTAssertEqual(secondSinkReceived, ["event_2"])
    }

    func test_settingSinkToNil_silencesEverything() {
        MINDTelemetry.sink = { self.received.append($0) }
        MINDTelemetry.info("recorded")
        XCTAssertEqual(received.count, 1)

        MINDTelemetry.sink = nil
        MINDTelemetry.info("silenced")
        XCTAssertEqual(received.count, 1, "nil sink must accept no more events")
    }

    // MARK: - Multi-call ordering

    func test_multipleBreadcrumbs_preserveOrder() {
        MINDTelemetry.sink = { self.received.append($0) }
        MINDTelemetry.info("first")
        MINDTelemetry.warning("second")
        MINDTelemetry.error("third")
        XCTAssertEqual(received.map(\.name), ["first", "second", "third"])
        XCTAssertEqual(received.map(\.level), [.info, .warning, .error])
    }

    // MARK: - Timestamp

    func test_event_carriesNonZeroTimestamp() {
        MINDTelemetry.sink = { self.received.append($0) }
        let before = Date.now
        MINDTelemetry.info("timed")
        let after = Date.now
        let timestamp = received.first?.timestamp ?? .distantPast
        XCTAssertGreaterThanOrEqual(timestamp, before)
        XCTAssertLessThanOrEqual(timestamp, after.addingTimeInterval(0.01))
    }
}
