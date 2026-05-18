import Foundation
import Observation

/// Orchestrates a digital audit run end-to-end:
///   1. probe every free public source in parallel (PageSpeed + secondary
///      findings),
///   2. hand the typed measurements to Claude for synthesis,
///   3. expose the resulting AuditReport so the SwiftUI layer can render
///      it and the caller can persist it as Nodes in the graph.
///
/// Stays a single @MainActor singleton; the network and LLM work runs
/// inside structured async children so cancellation reaches them.
@MainActor
@Observable
public final class AuditController {
    public static let shared = AuditController()

    public enum Phase: String, Sendable {
        case idle
        case probing
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
        case .probing, .synthesizing:    return true
        }
    }

    /// Friendly progress label for the UI; safe to bind to a Text view.
    public var progressLabel: String {
        switch phase {
        case .idle:         return "Prêt à auditer"
        case .probing:      return "Sondes en parallèle (perf, sécu, DNS, whois, App Store)…"
        case .synthesizing: return "Claude rédige le rapport…"
        case .completed:    return "Audit terminé"
        case .failed:       return "Audit en échec"
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
        phase = .probing

        currentTask = Task { [weak self] in
            await self?.execute(for: client)
        }
    }

    private func execute(for client: AuditClient) async {
        do {
            phase = .probing
            let (performance, findings) = await runProbesInParallel(for: client)
            try Task.checkCancellation()

            phase = .synthesizing
            let synthesized = try await synthesizer.synthesize(
                for: client,
                performance: performance,
                findings: findings
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

    /// Fans out the five probe calls concurrently and folds them into a
    /// PerformanceMetrics + AuditFindings pair. Every probe is allowed to
    /// soft-fail to nil so a single bad upstream never sinks the audit.
    private func runProbesInParallel(
        for client: AuditClient
    ) async -> (AuditReport.PerformanceMetrics?, AuditFindings) {
        let url = client.url
        let host = url.host(percentEncoded: false) ?? ""
        let searchName = client.name?.trimmingCharacters(in: .whitespaces) ?? hostLabel(for: host)

        async let perf      = softFetch { try await PageSpeedProbe.fetch(for: url) }
        async let security  = softFetch { try await SecurityHeadersProbe.fetch(for: url) }
        async let email     = softFetch { try await DNSProbe.fetch(for: host) }
        async let domain    = softFetch { try await WhoisProbe.fetch(for: host) }
        async let mobile    = softFetch { try await AppStoreProbe.search(name: searchName) }

        let findings = AuditFindings(
            security: await security,
            email:    await email,
            domain:   await domain,
            mobile:   await mobile
        )
        return (await perf, findings)
    }

    private func softFetch<T: Sendable>(
        _ body: @Sendable @escaping () async throws -> T
    ) async -> T? {
        do { return try await body() }
        catch { return nil }
    }

    /// Best-effort label when the user didn't provide a name. "stripe.com"
    /// becomes "stripe", "shop.acme.co.uk" becomes "acme".
    private nonisolated func hostLabel(for host: String) -> String {
        let cleaned = host.replacingOccurrences(of: "www.", with: "")
        let parts = cleaned.split(separator: ".")
        guard parts.count >= 2 else { return cleaned }
        // For 3+ parts pick the second-to-last (handles .co.uk / .com.au).
        let candidate = parts.count >= 3
            ? String(parts[parts.count - 2])
            : String(parts[0])
        return candidate
    }
}
