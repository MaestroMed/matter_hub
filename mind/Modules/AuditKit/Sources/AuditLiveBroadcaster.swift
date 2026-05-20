import Foundation

/// Inversion point between the AuditController (here in AuditKit) and
/// the LiveBroadcastKit module that owns the on-disk JSON writer.
///
/// Defined here — not in LiveBroadcastKit — so the AuditController
/// can take a strongly-typed dependency without AuditKit having to
/// import LiveBroadcastKit (which would create a circular module
/// graph). LiveBroadcastKit ships an extension that conforms its
/// session wrapper to this protocol.
///
/// When `liveBroadcaster` is nil on the controller (the common case
/// today, and the only case in unit tests), every method call is
/// skipped — zero overhead. When non-nil, the controller calls
/// `probeStateChanged` on every probe transition and
/// `auditCompleted` / `auditFailed` once the run is terminal.
///
/// Errors are absorbed by the conforming implementation — a broken
/// broadcast must never sink an audit run. The controller logs the
/// breadcrumb but does not propagate the failure up.
public protocol AuditLiveBroadcaster: Sendable {
    /// Initial snapshot — called once right after `AuditController.run`
    /// transitions into `.probing`. Lets the broadcaster lay down a
    /// snapshot showing every probe as `pending` so the polling
    /// browser sees a populated grid on first paint.
    func runStarted(
        client: AuditClient,
        probeStates: [AuditController.ProbeKind: AuditController.ProbeState]
    ) async

    /// Per-probe transition. Called by `AuditController.runProbe` on
    /// every `.running → .ok` or `.running → .failed` edge.
    func probeStateChanged(
        kind: AuditController.ProbeKind,
        state: AuditController.ProbeState,
        durationMs: Int
    ) async

    /// Terminal success path. Lets the broadcaster mirror the final
    /// scoring + synthesis + pitch into the JSON snapshot so the
    /// browser-side CTA renders.
    func auditCompleted(report: AuditReport) async

    /// Terminal failure path. Lets the broadcaster flip the JSON
    /// `phase` to `"failed"` so the browser stops the pulse animation
    /// and surfaces a polite error banner.
    func auditFailed(message: String) async
}
