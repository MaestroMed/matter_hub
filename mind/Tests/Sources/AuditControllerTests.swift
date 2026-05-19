import XCTest
@testable import AuditKit

/// Covers the AuditController state machine — every Phase value, the
/// derived helpers (`isRunning`, `progressLabel`), the cancellation
/// contract, and the persistence-safe enum raw values. These are
/// pure-logic tests so they stay deterministic without hitting the
/// network or Anthropic API.
@MainActor
final class AuditControllerTests: XCTestCase {

    // MARK: - Initial state

    /// A freshly-built controller must start clean: idle phase, no
    /// report, no error. AuditSheet relies on this contract to render
    /// the "Prêt à auditer" empty state on first launch.
    func test_initialState_isIdleWithNoReportOrError() {
        let controller = AuditController()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.report)
        XCTAssertNil(controller.error)
        XCTAssertFalse(controller.isRunning)
    }

    // MARK: - Phase enum contract

    /// Raw values are persistence-stable identifiers (logged via
    /// MINDTelemetry, surfaced in tests, and would land in CloudKit
    /// if we ever decide to mirror the live phase). Pinning them down
    /// means a typo on rename triggers a test failure instead of a
    /// silent telemetry drift.
    func test_phaseRawValues_areStable() {
        XCTAssertEqual(AuditController.Phase.idle.rawValue, "idle")
        XCTAssertEqual(AuditController.Phase.probing.rawValue, "probing")
        XCTAssertEqual(AuditController.Phase.synthesizing.rawValue, "synthesizing")
        XCTAssertEqual(AuditController.Phase.completed.rawValue, "completed")
        XCTAssertEqual(AuditController.Phase.failed.rawValue, "failed")
    }

    // MARK: - isRunning state machine

    /// Exhaustive check: probing + synthesizing are "running" (UI
    /// shows the spinner); idle, completed, failed are "done" (UI
    /// shows the result or the CTA). This is the single source of
    /// truth AuditSheet uses to gate the cancel button.
    func test_isRunning_isTrueOnlyForActivePhases() {
        XCTAssertFalse(AuditController.isRunning(for: .idle))
        XCTAssertTrue(AuditController.isRunning(for: .probing))
        XCTAssertTrue(AuditController.isRunning(for: .synthesizing))
        XCTAssertFalse(AuditController.isRunning(for: .completed))
        XCTAssertFalse(AuditController.isRunning(for: .failed))
    }

    // MARK: - progressLabel state machine

    /// Every phase has a French, non-empty user-facing label. Catches
    /// regressions where a new phase ships without copy, which would
    /// surface as an empty Text view in AuditSheet.
    func test_progressLabel_isLocalizedFRForEveryPhase() {
        let cases: [(AuditController.Phase, String)] = [
            (.idle, "Prêt à auditer"),
            (.probing, "13 sondes en parallèle (perf, sécu, SEO, brand, infra, trust)…"),
            (.synthesizing, "Claude rédige le rapport complet…"),
            (.completed, "Audit terminé"),
            (.failed, "Audit en échec"),
        ]
        for (phase, expected) in cases {
            let actual = AuditController.progressLabel(for: phase)
            XCTAssertEqual(actual, expected, "Mismatch for \(phase.rawValue)")
            XCTAssertFalse(actual.isEmpty, "Empty label for \(phase.rawValue)")
        }
    }

    // MARK: - Cancellation contract

    /// `cancel()` called on an idle controller is a no-op — phase
    /// stays idle, report/error remain nil. Mehdi taps the "Annuler"
    /// button on a fresh sheet by mistake all the time; this must not
    /// stutter the state machine into a weird intermediate state.
    func test_cancel_fromIdle_isIdempotent() {
        let controller = AuditController()
        controller.cancel()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.report)
        XCTAssertNil(controller.error)
        controller.cancel()  // twice — must still be a no-op
        XCTAssertEqual(controller.phase, .idle)
    }

    /// Starting a run then immediately cancelling resets phase to
    /// idle. The contract is documented in AuditController.cancel():
    /// cancellation transitions to `.idle`, not to a dedicated
    /// `.cancelled` case. We assert phase synchronously after
    /// `cancel()` because the call is `@MainActor` and the
    /// cancellation branch reassigns phase synchronously inside the
    /// `cancel()` body before any awaited work resumes.
    func test_cancel_fromRunning_resetsPhaseToIdle() {
        let controller = AuditController()
        let client = AuditClient(
            url: URL(string: "https://example.com")!,
            name: "Example"
        )
        controller.run(for: client)
        // run() flips to .probing synchronously before the async task
        // fires, so this assertion is deterministic.
        XCTAssertEqual(controller.phase, .probing)
        XCTAssertTrue(controller.isRunning)

        controller.cancel()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertFalse(controller.isRunning)
    }
}
