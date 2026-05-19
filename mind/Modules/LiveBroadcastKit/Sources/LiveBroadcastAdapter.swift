import Foundation
import AuditKit
import GraphCore

/// Concrete `AuditLiveBroadcaster` implementation that mirrors every
/// controller-side transition into the on-disk JSON snapshot.
///
/// Constructed with a freshly-minted `LiveBroadcastSession` and a
/// shared `LiveBroadcastWriter`. The host App layer hands the result
/// to `AuditController.liveBroadcaster` right before calling
/// `run(for:)`.
///
/// All four protocol methods catch their own errors — a broken
/// broadcast must never sink an audit. Failures land as a single
/// `liveBroadcast.failed` telemetry breadcrumb so they're visible
/// in Sentry without spamming the user.
public final class LiveBroadcastAdapter: AuditLiveBroadcaster, @unchecked Sendable {

    public let session: LiveBroadcastSession
    public let writer: LiveBroadcastWriter
    public let rootURL: URL

    public init(
        session: LiveBroadcastSession,
        writer: LiveBroadcastWriter,
        rootURL: URL = LiveBroadcastWriter.defaultRoot()
    ) {
        self.session = session
        self.writer = writer
        self.rootURL = rootURL
    }

    public func runStarted(
        client: AuditClient,
        probeStates: [AuditController.ProbeKind: AuditController.ProbeState]
    ) async {
        let token = session.token
        let root = rootURL
        let probes = LiveBroadcastState.probes(from: probeStates)
        do {
            try await writer.update(token: token, under: root) { state in
                state = LiveBroadcastState(
                    token: state.token,
                    clientName: state.clientName,
                    host: state.host,
                    startedAt: state.startedAt,
                    updatedAt: state.updatedAt,
                    phase: LiveBroadcastState.Phase.probing.rawValue,
                    probes: probes,
                    scoring: state.scoring,
                    synthesis: state.synthesis,
                    pitch: state.pitch
                )
            }
        } catch {
            await postFailure(name: "runStarted", error: error)
        }
    }

    public func probeStateChanged(
        kind: AuditController.ProbeKind,
        state controllerState: AuditController.ProbeState,
        durationMs: Int
    ) async {
        let token = session.token
        let root = rootURL
        let snapshot = LiveBroadcastState.ProbeStatus(
            kind: kind,
            controllerState: controllerState,
            durationMs: durationMs
        )
        do {
            try await writer.update(token: token, under: root) { state in
                var probes = state.probes
                if let idx = probes.firstIndex(where: { $0.kind == snapshot.kind }) {
                    probes[idx] = snapshot
                } else {
                    probes.append(snapshot)
                }
                state = LiveBroadcastState(
                    token: state.token,
                    clientName: state.clientName,
                    host: state.host,
                    startedAt: state.startedAt,
                    updatedAt: state.updatedAt,
                    phase: state.phase,
                    probes: probes,
                    scoring: state.scoring,
                    synthesis: state.synthesis,
                    pitch: state.pitch
                )
            }
        } catch {
            await postFailure(name: "probeStateChanged", error: error)
        }
    }

    public func auditCompleted(report: AuditReport) async {
        let token = session.token
        let root = rootURL
        let scoring = LiveBroadcastState.Scoring(report.scoring)
        let synthesis = report.synthesis
        let pitch = report.pitch
        do {
            try await writer.update(token: token, under: root) { state in
                state = LiveBroadcastState(
                    token: state.token,
                    clientName: state.clientName,
                    host: state.host,
                    startedAt: state.startedAt,
                    updatedAt: state.updatedAt,
                    phase: LiveBroadcastState.Phase.synthesizing.rawValue,
                    probes: state.probes,
                    scoring: scoring,
                    synthesis: synthesis,
                    pitch: pitch
                )
            }
            try await writer.close(token: token, success: true, under: root)
        } catch {
            await postFailure(name: "auditCompleted", error: error)
        }
    }

    public func auditFailed(message: String) async {
        let token = session.token
        let root = rootURL
        do {
            try await writer.close(token: token, success: false, under: root)
        } catch {
            await postFailure(name: "auditFailed", error: error)
        }
        // Surface the failure message into the synthesis field so the
        // browser-side viewer can show the user what went wrong without
        // needing a separate widget.
        do {
            try await writer.update(token: token, under: root) { state in
                state = LiveBroadcastState(
                    token: state.token,
                    clientName: state.clientName,
                    host: state.host,
                    startedAt: state.startedAt,
                    updatedAt: state.updatedAt,
                    phase: LiveBroadcastState.Phase.failed.rawValue,
                    probes: state.probes,
                    scoring: state.scoring,
                    synthesis: "L'audit a échoué : \(message)",
                    pitch: state.pitch
                )
            }
        } catch {
            await postFailure(name: "auditFailed.update", error: error)
        }
    }

    private nonisolated func postFailure(name: String, error: Error) async {
        let token = session.token
        await MainActor.run {
            MINDTelemetry.warning("liveBroadcast.failed", data: [
                "phase": name,
                "token_prefix": String(token.prefix(8)),
                "error": String(describing: error),
            ])
        }
    }
}
