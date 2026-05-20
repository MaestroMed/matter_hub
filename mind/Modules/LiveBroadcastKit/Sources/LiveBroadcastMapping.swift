import Foundation
import AuditKit

/// Bridges the in-memory `AuditController` state machine to the
/// `LiveBroadcastState` wire format. Lives in `LiveBroadcastKit`
/// rather than `AuditKit` so the AuditController stays unaware of
/// the broadcasting concern when nothing is attached.
public extension LiveBroadcastState.ProbeStatus {

    /// Lift a controller-side probe state into the wire shape.
    /// `durationMs` and `error` are best-effort — when the caller
    /// doesn't have a duration handy (e.g. on initial `.running`
    /// seed), pass `nil`.
    init(
        kind: AuditController.ProbeKind,
        controllerState: AuditController.ProbeState,
        durationMs: Int? = nil
    ) {
        let (state, error): (String, String?) = {
            switch controllerState {
            case .running:
                return (LiveBroadcastState.ProbeLifecycle.running.rawValue, nil)
            case .ok:
                return (LiveBroadcastState.ProbeLifecycle.ok.rawValue, nil)
            case .failed(let reason):
                return (LiveBroadcastState.ProbeLifecycle.failed.rawValue, reason)
            }
        }()
        self.init(
            kind: kind.rawValue,
            state: state,
            durationMs: durationMs,
            error: error
        )
    }
}

public extension LiveBroadcastState {
    /// Mirror a fresh controller-side probe dictionary into the wire
    /// list. Preserves `ProbeKind.allCases` order so the browser-side
    /// grid stays visually stable across snapshots.
    ///
    /// Probes that are not present in `probeStates` fall back to
    /// `pending`, which is the safe default before a run has started
    /// or for a kind that hasn't reported yet.
    static func probes(
        from probeStates: [AuditController.ProbeKind: AuditController.ProbeState]
    ) -> [LiveBroadcastState.ProbeStatus] {
        AuditController.ProbeKind.allCases.map { kind in
            if let st = probeStates[kind] {
                return LiveBroadcastState.ProbeStatus(kind: kind, controllerState: st)
            }
            return LiveBroadcastState.ProbeStatus(
                kind: kind.rawValue,
                state: LiveBroadcastState.ProbeLifecycle.pending.rawValue
            )
        }
    }
}
