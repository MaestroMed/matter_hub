import Foundation
import Observation

/// Orchestrates a digital audit run end-to-end:
/// fetch raw probes → ask Claude to synthesize → expose a typed AuditReport
/// to the SwiftUI layer → let the caller persist it as a Node in the graph.
///
/// Stays a single @MainActor singleton so the UI can bind to `phase` and
/// `report` without juggling actor hops. The actual network and LLM work
/// happens inside a structured async child so cancellation reaches them.
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
    private let synthesizer: ClaudeSynthesizer

    public init(synthesizer: ClaudeSynthesizer? = nil) {
        self.synthesizer = synthesizer ?? ClaudeSynthesizer()
    }

    public var isRunning: Bool {
        switch phase {
        case .idle, .completed, .failed: return false
        case .probingPerformance, .synthesizing: return true
        }
    }

    /// Friendly progress label for the UI; safe to bind to a Text view.
    public var progressLabel: String {
        switch phase {
        case .idle:                return "Prêt à auditer"
        case .probingPerformance:  return "Mesure Lighthouse en cours…"
        case .synthesizing:        return "Claude rédige le rapport…"
        case .completed:           return "Audit terminé"
        case .failed:              return "Audit en échec"
        }
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        phase = .idle
    }

    /// Kick off a new audit run. Replaces any in-flight one.
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
        do {
            phase = .probingPerformance
            let performance = await fetchPerformanceSoftFail(for: client.url)
            try Task.checkCancellation()

            phase = .synthesizing
            let synthesized = try await synthesizer.synthesize(
                for: client,
                performance: performance
            )
            try Task.checkCancellation()

            self.report = synthesized
            self.phase = .completed
        } catch is CancellationError {
            self.phase = .idle
        } catch {
            self.error = error.localizedDescription
            self.phase = .failed
        }
    }

    /// PageSpeed Insights is best-effort: rate limits, transient 5xx, and
    /// edge cases (sites blocking Google's crawler) all mean we want to
    /// keep going and let Claude reason without metrics rather than fail
    /// the whole audit.
    private func fetchPerformanceSoftFail(
        for url: URL
    ) async -> AuditReport.PerformanceMetrics? {
        do {
            return try await PageSpeedProbe.fetch(for: url)
        } catch {
            return nil
        }
    }
}
