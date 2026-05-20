import XCTest
@testable import VisionSpatialKit

/// v1.0-alpha.19 — Locks the public surface area of the spatial
/// telemetry bridge + the placement substrate the visionOS surface
/// reads. Every test here is a pure-Swift smoke test that compiles +
/// runs on the iOS host simulator without the visionOS runtime, so
/// the bridge contract is enforced by CI regardless of whether Mehdi
/// has installed `visionOS Simulator 26.5`.
///
/// The visionOS-only SwiftUI surfaces themselves (`SpatialRootView`,
/// `SpatialLeadsView`, …) live behind `#if os(visionOS)` and so
/// cannot be exercised here. Their compilation is validated by the
/// visionOS build slice once the runtime lands (see
/// `MIND_BLOCKER_visionos_runtime.md`).
final class SpatialTokenAvailabilityTests: XCTestCase {

    // MARK: - Bridge wiring

    func test_telemetryBridge_singletonHandsBackSameInstance() {
        let a = SpatialTelemetryBridge.shared
        let b = SpatialTelemetryBridge.shared
        XCTAssertTrue(a === b)
    }

    func test_telemetryBridge_sinkNil_appLaunchedIsSilentNoOp() {
        // Default sink is nil; calling appLaunched() must not crash.
        let bridge = SpatialTelemetryBridge.shared
        bridge.sink = nil
        bridge.appLaunched()
        // No XCTFail — the absence of a crash is the contract.
    }

    func test_telemetryBridge_sinkConfigured_appLaunchedFiresExpectedName() {
        let bridge = SpatialTelemetryBridge.shared
        var captured: [SpatialTelemetryBridge.Event] = []
        bridge.sink = { event in
            captured.append(event)
        }
        defer { bridge.sink = nil }

        bridge.appLaunched()

        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured.first?.name, "spatial.app.launched")
    }

    func test_telemetryBridge_theaterEvents_carryTruncatedID() {
        let bridge = SpatialTelemetryBridge.shared
        var captured: [SpatialTelemetryBridge.Event] = []
        bridge.sink = { captured.append($0) }
        defer { bridge.sink = nil }

        let auditID = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
        bridge.theaterOpened(auditID: auditID)
        bridge.theaterExited()

        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[0].name, "spatial.audit.theater.opened")
        // ID is truncated to first 8 chars so Sentry never logs a
        // full UUID (no PII leak).
        XCTAssertEqual(captured[0].data["auditID.prefix"], "12345678")
        XCTAssertEqual(captured[1].name, "spatial.audit.theater.exited")
    }
}
