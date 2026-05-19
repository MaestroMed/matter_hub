import Foundation
import AuditKit
import GraphCore

/// v0.22.2 — `AuditLiveBroadcaster` implementation that mirrors
/// controller-side transitions through the embedded WebSocket server
/// (`LiveBroadcastWebSocketServer`) instead of the on-disk JSON
/// snapshot pipeline.
///
/// The adapter keeps its own `LiveBroadcastState` (initialized from
/// the client + initial probe states), mutates it on each protocol
/// callback, and pushes the canonical-encoded JSON through
/// `server.broadcast(_:)`. The server delivers the JSON as a single
/// WebSocket text frame to every connected browser — zero-latency
/// updates with no polling tax.
///
/// **Why a separate adapter** from `LiveBroadcastAdapter`: the
/// polling pipeline writes to disk so it works behind any tunneling
/// solution (cloudflared, Vercel). The WebSocket pipeline only works
/// when the viewer is on the same LAN as the iPhone. Both pipelines
/// can run side by side — Mehdi enables them independently from the
/// AuditSheet.
public final class LiveBroadcastWebSocketAdapter: AuditLiveBroadcaster, @unchecked Sendable {

    public let server: LiveBroadcastWebSocketServer
    public let token: String

    private let stateLock = NSLock()
    private var state: LiveBroadcastState

    public init(
        server: LiveBroadcastWebSocketServer,
        token: String,
        clientName: String,
        host: String,
        now: () -> Date = { Date() }
    ) {
        self.server = server
        self.token = token
        let stamp = now()
        self.state = LiveBroadcastState(
            token: token,
            clientName: clientName,
            host: host,
            startedAt: stamp,
            updatedAt: stamp,
            phase: LiveBroadcastState.Phase.probing.rawValue,
            probes: LiveBroadcastWriter.initialProbes()
        )
    }

    // MARK: - AuditLiveBroadcaster

    public func runStarted(
        client: AuditClient,
        probeStates: [AuditController.ProbeKind: AuditController.ProbeState]
    ) async {
        let probes = LiveBroadcastState.probes(from: probeStates)
        let snapshot = mutate { current in
            LiveBroadcastState(
                token: current.token,
                clientName: current.clientName,
                host: current.host,
                startedAt: current.startedAt,
                updatedAt: Date(),
                phase: LiveBroadcastState.Phase.probing.rawValue,
                probes: probes,
                scoring: current.scoring,
                synthesis: current.synthesis,
                pitch: current.pitch
            )
        }
        await server.broadcast(snapshot)
    }

    public func probeStateChanged(
        kind: AuditController.ProbeKind,
        state controllerState: AuditController.ProbeState,
        durationMs: Int
    ) async {
        let probeSnapshot = LiveBroadcastState.ProbeStatus(
            kind: kind,
            controllerState: controllerState,
            durationMs: durationMs
        )
        let snapshot = mutate { current in
            var probes = current.probes
            if let idx = probes.firstIndex(where: { $0.kind == probeSnapshot.kind }) {
                probes[idx] = probeSnapshot
            } else {
                probes.append(probeSnapshot)
            }
            return LiveBroadcastState(
                token: current.token,
                clientName: current.clientName,
                host: current.host,
                startedAt: current.startedAt,
                updatedAt: Date(),
                phase: current.phase,
                probes: probes,
                scoring: current.scoring,
                synthesis: current.synthesis,
                pitch: current.pitch
            )
        }
        await server.broadcast(snapshot)
    }

    public func auditCompleted(report: AuditReport) async {
        let scoring = LiveBroadcastState.Scoring(report.scoring)
        let snapshot = mutate { current in
            LiveBroadcastState(
                token: current.token,
                clientName: current.clientName,
                host: current.host,
                startedAt: current.startedAt,
                updatedAt: Date(),
                phase: LiveBroadcastState.Phase.completed.rawValue,
                probes: current.probes,
                scoring: scoring,
                synthesis: report.synthesis,
                pitch: report.pitch
            )
        }
        await server.broadcast(snapshot)
    }

    public func auditFailed(message: String) async {
        let snapshot = mutate { current in
            LiveBroadcastState(
                token: current.token,
                clientName: current.clientName,
                host: current.host,
                startedAt: current.startedAt,
                updatedAt: Date(),
                phase: LiveBroadcastState.Phase.failed.rawValue,
                probes: current.probes,
                scoring: current.scoring,
                synthesis: "L'audit a échoué : \(message)",
                pitch: current.pitch
            )
        }
        await server.broadcast(snapshot)
    }

    // MARK: - Helpers

    /// Apply a mutation to the cached state under the lock, return
    /// the new snapshot value. The lock keeps the cached state
    /// consistent across simultaneous protocol callbacks coming from
    /// the controller's MainActor + the server's connection callbacks
    /// on a different queue.
    private func mutate(
        _ block: (LiveBroadcastState) -> LiveBroadcastState
    ) -> LiveBroadcastState {
        stateLock.lock()
        defer { stateLock.unlock() }
        let next = block(state)
        state = next
        return next
    }

    /// Test-only accessor for the cached state. Snapshots the value
    /// under the lock so unit tests can assert state transitions
    /// after each protocol callback.
    public func currentState() -> LiveBroadcastState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }
}
