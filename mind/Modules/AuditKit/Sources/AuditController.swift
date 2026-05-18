import Foundation
import Observation

/// Orchestrates a digital audit run end-to-end:
/// fetch raw probes → ask Claude to synthesize → expose a typed AuditReport
/// to the SwiftUI layer → let the caller persist it as a Node in the graph.
///
/// Stays a single @MainActor singleton so the UI can bind to `phase` and
/// `report` without juggling actor hops. The actual network and LLM work
/// happens inside structured async children so cancellation reaches them.
@MainActor
@Observable
public final class AuditController {
    public static let shared = AuditController()

    public enum Phase: String, Sendable {
        case idle
        case probingPerformance
        case synthesizing
        case completed
        case failed
    }

    public private(set) var phase: Phase = .idle
    public private(set) var report: AuditReport?
    public private(set) var error: String?

    private var currentTask: Task<Void, Never>?

    public init() {}

    public var isRunning: Bool {
        switch phase {
        case .idle, .completed, .failed: return false
        case .probingPerformance, .synthesizing: return true
        }
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        phase = .idle
    }

    /// Kick off an audit. Replaces any in-flight run.
    public func run(for client: AuditClient) {
        cancel()
        report = nil
        error = nil
        phase = .probingPerformance

        currentTask = Task { [weak self] in
            await self?.execute(for: client)
        }
    }

    private func execute(for client: AuditClient) async {
        // Full pipeline lands in the next commit. For now this scaffold
        // resolves to a "no probes available yet" state so the rest of
        // the module can wire up the UI without an external network call.
        phase = .failed
        error = "Audit pipeline not yet implemented (Commit B)."
    }
}
