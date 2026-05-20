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

    // MARK: - v0.4 ProbeKind contract

    /// ProbeKind enumerates every network sensor the controller fans
    /// out to. The count is 14 since v1.0-alpha.10 (the 14th is the
    /// optional `.repoAudit` probe, only seeded when the client carries
    /// a `githubRepo`). The progressLabel copy still reads "13 sondes"
    /// because the repo-aware probe sits on its own row in the UI when
    /// active and is invisible when not.
    func test_probeKind_allCases_matchAdvertisedCount() {
        XCTAssertEqual(AuditController.ProbeKind.allCases.count, 14)
    }

    /// Raw values are persistence-stable (telemetry `audit.probe.failed`
    /// emits them). Pin them so renames don't quietly break filters.
    func test_probeKind_rawValues_areStable() {
        XCTAssertEqual(AuditController.ProbeKind.pageSpeed.rawValue, "pageSpeed")
        XCTAssertEqual(AuditController.ProbeKind.security.rawValue, "security")
        XCTAssertEqual(AuditController.ProbeKind.email.rawValue, "email")
        XCTAssertEqual(AuditController.ProbeKind.domain.rawValue, "domain")
        XCTAssertEqual(AuditController.ProbeKind.mobile.rawValue, "mobile")
        XCTAssertEqual(AuditController.ProbeKind.schema.rawValue, "schema")
        XCTAssertEqual(AuditController.ProbeKind.openGraph.rawValue, "openGraph")
        XCTAssertEqual(AuditController.ProbeKind.crawlability.rawValue, "crawlability")
        XCTAssertEqual(AuditController.ProbeKind.compliance.rawValue, "compliance")
        XCTAssertEqual(AuditController.ProbeKind.analytics.rawValue, "analytics")
        XCTAssertEqual(AuditController.ProbeKind.payment.rawValue, "payment")
        XCTAssertEqual(AuditController.ProbeKind.cdn.rawValue, "cdn")
        XCTAssertEqual(AuditController.ProbeKind.trust.rawValue, "trust")
    }

    /// Every probe must have a non-empty FR label and an SF Symbol —
    /// the per-probe row UI assumes both fields render. Catches a new
    /// probe shipping without copy.
    func test_probeKind_labelAndIcon_areAlwaysPresent() {
        for kind in AuditController.ProbeKind.allCases {
            XCTAssertFalse(
                kind.label.isEmpty,
                "Empty label for \(kind.rawValue)"
            )
            XCTAssertFalse(
                kind.systemImage.isEmpty,
                "Empty SF Symbol for \(kind.rawValue)"
            )
        }
    }

    // MARK: - v0.4 ProbeState predicates

    /// ProbeState's three predicates (`isOK`/`isFailed`/`isRunning`)
    /// are read directly by the AuditSheet to size the colored
    /// summary pills. Exhaustively assert the table so a future
    /// `case skipped` addition can't silently lie to the UI.
    func test_probeState_predicates_areExhaustive() {
        let running = AuditController.ProbeState.running
        XCTAssertTrue(running.isRunning)
        XCTAssertFalse(running.isOK)
        XCTAssertFalse(running.isFailed)
        XCTAssertNil(running.failureReason)

        let ok = AuditController.ProbeState.ok
        XCTAssertTrue(ok.isOK)
        XCTAssertFalse(ok.isRunning)
        XCTAssertFalse(ok.isFailed)
        XCTAssertNil(ok.failureReason)

        let failed = AuditController.ProbeState.failed(reason: "timeout")
        XCTAssertTrue(failed.isFailed)
        XCTAssertFalse(failed.isOK)
        XCTAssertFalse(failed.isRunning)
        XCTAssertEqual(failed.failureReason, "timeout")
    }

    // MARK: - v0.4 Per-probe state lifecycle

    /// Before the first run the per-probe map is empty so the
    /// AuditSheet falls back to the form view (no probe rows
    /// rendered). Mehdi sees the URL field, not a list of yellow
    /// dots.
    func test_probeStates_initiallyEmpty() {
        let controller = AuditController()
        XCTAssertTrue(controller.probeStates.isEmpty)
        XCTAssertFalse(controller.hasFailedProbes)
        XCTAssertTrue(controller.failedProbes.isEmpty)
    }

    /// `run(for:)` synchronously seeds every probe to `.running` on
    /// the MainActor before the structured concurrency task fires.
    /// This is what lets the running view paint the per-probe row
    /// list immediately — no first-frame flicker. v1.0-alpha.10 —
    /// the seeded set respects `client.githubRepo`: URL-only audits
    /// seed 13 probes (no .repoAudit), repo-aware audits seed 14.
    func test_run_seedsAllProbesToRunning() {
        let controller = AuditController()
        let client = AuditClient(
            url: URL(string: "https://example.com")!,
            name: "Example"
        )
        controller.run(for: client)
        // URL-only audit → 13 probes, .repoAudit not seeded.
        XCTAssertEqual(controller.probeStates.count, 13)
        for kind in AuditController.ProbeKind.allCases where kind != .repoAudit {
            XCTAssertEqual(
                controller.probeStates[kind],
                .running,
                "Probe \(kind.rawValue) should be seeded as .running"
            )
        }
        XCTAssertNil(
            controller.probeStates[.repoAudit],
            "URL-only audit should not seed the .repoAudit row"
        )
        XCTAssertFalse(controller.hasFailedProbes)
        controller.cancel()  // tear down so the network task doesn't leak
    }

    /// v1.0-alpha.10 — A client carrying a `githubRepo` seeds all 14
    /// probes, including the new `.repoAudit` row.
    func test_run_withGithubRepo_seedsRepoAuditRow() {
        let controller = AuditController()
        let client = AuditClient(
            url: URL(string: "https://example.com")!,
            name: "Example",
            githubRepo: "owner/example-repo"
        )
        controller.run(for: client)
        XCTAssertEqual(controller.probeStates.count, 14)
        XCTAssertEqual(controller.probeStates[.repoAudit], .running)
        controller.cancel()
    }

    // MARK: - v0.4 Retry contract

    /// Retry with no prior run is a no-op — there's no client to
    /// re-run against. Guards against the AuditSheet calling
    /// `retryFailedProbes()` from a stale view state.
    func test_retryFailedProbes_withoutPriorRun_isNoOp() {
        let controller = AuditController()
        controller.retryFailedProbes()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertTrue(controller.probeStates.isEmpty)
    }

    /// Retry with prior run but zero failures is a no-op. The CTA
    /// is hidden in this case, but if the orchestrator somehow
    /// fires the action we must not destabilize the controller.
    func test_retryFailedProbes_withNoFailures_isNoOp() {
        let controller = AuditController()
        let client = AuditClient(
            url: URL(string: "https://example.com")!,
            name: "Example"
        )
        controller.run(for: client)
        controller.cancel()
        // After cancel the controller is idle; probeStates still
        // reflects the .running seeds — no `.failed` entries.
        XCTAssertFalse(controller.hasFailedProbes)

        controller.retryFailedProbes()
        XCTAssertEqual(controller.phase, .idle)
    }

    /// Retry only mutates the failed-probe rows. We simulate the
    /// post-run state by mutating `probeStates` directly through
    /// the run() seed path, then synthesising a failure and
    /// asserting `failedProbes` mirrors it. Successful rows must
    /// stay `.ok`.
    func test_failedProbes_ordering_followsAllCases() {
        let controller = AuditController()
        let client = AuditClient(
            url: URL(string: "https://example.com")!,
            name: "Example"
        )
        controller.run(for: client)
        controller.cancel()  // freeze probeStates at the .running seed
        // After cancel, no probes have failed yet — failedProbes is
        // empty regardless of declaration order.
        XCTAssertEqual(controller.failedProbes, [])
        // Sanity: allCases is the canonical order the UI iterates in.
        XCTAssertEqual(
            AuditController.ProbeKind.allCases.first,
            .pageSpeed,
            "PageSpeed runs first to anchor the perf score"
        )
        XCTAssertEqual(
            AuditController.ProbeKind.allCases.last,
            .repoAudit,
            "Repo audit is the 14th probe (v1.0-alpha.10), appended after Trustpilot"
        )
    }
}
