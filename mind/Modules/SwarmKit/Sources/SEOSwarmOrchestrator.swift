import Foundation
import AuditKit      // CloudIntelligenceHandle
import GraphCore     // MINDTelemetry

/// v1.0-alpha.7 — SEO Swarm Orchestrator.
///
/// Drives the `services × zones` matrix through Claude. Three pages in
/// flight at a time keeps us under the per-minute rate limit Anthropic
/// enforces on cloud Sonnet calls (60 RPM on the standard tier — at
/// ~12s per page, 3 in flight ≈ 15 pages/min headroom). Per-page
/// failures are absorbed (the page is dropped from the swarm and the
/// failure counter is bumped); only auth + total-network outages roll
/// up to a `.failed` job status.
///
/// Progress events stream out through an `AsyncStream<ProgressEvent>`
/// so the wizard UI can render "234 / 1140 — 21 min restantes" without
/// polling the job in a timer.
public actor SEOSwarmOrchestrator {

    public static let shared = SEOSwarmOrchestrator()

    /// Number of pages allowed in flight at once. Pinned to 3 to stay
    /// under the standard Anthropic rate limit while keeping the wall
    /// time low. The orchestrator could go higher with a paid-tier
    /// key, but 3 is the safe default for the hand-rolled key flow.
    private let concurrencyLimit: Int

    /// Per-job cancellation flag. Flipped by `cancel(jobID:)` from
    /// outside the actor. The orchestrator checks this flag between
    /// every fan-out batch so the user can abort a 1000-page swarm
    /// mid-flight.
    private var cancelledJobIDs: Set<UUID> = []

    public init(concurrencyLimit: Int = 3) {
        self.concurrencyLimit = max(1, concurrencyLimit)
    }

    // MARK: - Progress streaming

    /// One event in the swarm run-time progress stream.
    public enum ProgressEvent: Sendable, Equatable {
        /// Fired exactly once at the top of `run(_:intelligence:)`
        /// with the total page count. Lets the UI mount the "0 / N"
        /// counter before any page lands.
        case started(totalPages: Int)
        /// Fired after each successful page. Carries the page so the
        /// UI scroll log can render it inline.
        case pageCompleted(page: SwarmPage, successCount: Int, failureCount: Int)
        /// Fired after each page that the parser dropped or whose
        /// network call rethrew. The (service, zone) pair identifies
        /// the slot for the UI's failure list.
        case pageFailed(service: String, zoneSlug: String, reason: String, successCount: Int, failureCount: Int)
        /// Fired exactly once with the final job snapshot.
        case completed(job: SEOSwarmJob)
        /// Fired when `cancel(jobID:)` flipped mid-run.
        case cancelled(partialJob: SEOSwarmJob)
    }

    // MARK: - Public API

    /// Runs `job` end-to-end. Returns the updated `SEOSwarmJob` with
    /// `generatedPages` populated and `status` set to one of
    /// `.completed` / `.partial` / `.failed`. Progress events are
    /// emitted via `progress` AsyncStream — the caller passes in a
    /// continuation. Pass `nil` to skip event streaming (tests).
    public func run(
        _ job: SEOSwarmJob,
        intelligence: CloudIntelligenceHandle = .live,
        progress: AsyncStream<ProgressEvent>.Continuation? = nil
    ) async -> SEOSwarmJob {
        var current = job
        current.status = .running

        let total = current.plannedPageCount
        progress?.yield(.started(totalPages: total))
        await telemetryInfo(
            "swarm.job.started",
            data: [
                "jobID": current.id.uuidString,
                "projectID": current.projectID.uuidString,
                "totalPages": String(total),
                "services": String(current.services.count),
                "zones": String(current.zones.count),
            ]
        )

        // Pre-build the matrix as a flat list of (service, zone) pairs
        // so the TaskGroup fan-out below stays purely indexed.
        var slots: [(service: String, zone: SwarmZone)] = []
        slots.reserveCapacity(total)
        for service in current.services {
            for zone in current.zones {
                slots.append((service, zone))
            }
        }

        var successCount = 0
        var failureCount = 0
        let projectContext = SwarmProjectContext(
            id: current.projectID,
            name: current.projectName,
            host: current.projectHost
        )

        var cursor = 0
        while cursor < slots.count {
            if cancelledJobIDs.contains(current.id) {
                cancelledJobIDs.remove(current.id)
                current.status = current.generatedPages.isEmpty ? .failed : .partial
                progress?.yield(.cancelled(partialJob: current))
                progress?.finish()
                await telemetryInfo(
                    "swarm.job.cancelled",
                    data: [
                        "jobID": current.id.uuidString,
                        "completed": String(successCount),
                        "remaining": String(slots.count - cursor),
                    ]
                )
                return current
            }

            let batchEnd = min(cursor + concurrencyLimit, slots.count)
            let batchSlice = slots[cursor..<batchEnd].map { $0 }
            cursor = batchEnd

            let results = await withTaskGroup(of: SlotOutcome.self) { group -> [SlotOutcome] in
                for slot in batchSlice {
                    group.addTask { [intelligence] in
                        await Self.generatePage(
                            project: projectContext,
                            service: slot.service,
                            zone: slot.zone,
                            intelligence: intelligence
                        )
                    }
                }
                var collected: [SlotOutcome] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            for outcome in results {
                switch outcome {
                case .success(let page):
                    current.generatedPages.append(page)
                    successCount += 1
                    progress?.yield(
                        .pageCompleted(page: page, successCount: successCount, failureCount: failureCount)
                    )
                    await telemetryInfo(
                        "swarm.page.generated",
                        data: [
                            "jobID": current.id.uuidString,
                            "service": page.serviceSlug,
                            "zone": page.zoneSlug,
                            "tokens": String(page.tokensUsed),
                        ]
                    )
                case .failure(let service, let zoneSlug, let reason):
                    failureCount += 1
                    progress?.yield(
                        .pageFailed(
                            service: service,
                            zoneSlug: zoneSlug,
                            reason: reason,
                            successCount: successCount,
                            failureCount: failureCount
                        )
                    )
                    await telemetryWarning(
                        "swarm.page.failed",
                        data: [
                            "jobID": current.id.uuidString,
                            "service": service,
                            "zone": zoneSlug,
                            "reason": reason,
                        ]
                    )
                }
            }
        }

        // Final status reconciliation.
        if successCount == 0 {
            current.status = .failed
            if current.errorMessage == nil {
                current.errorMessage = "Aucune page n'a pu être générée."
            }
        } else if failureCount > 0 {
            current.status = .partial
        } else {
            current.status = .completed
        }
        progress?.yield(.completed(job: current))
        progress?.finish()
        await telemetryInfo(
            "swarm.job.completed",
            data: [
                "jobID": current.id.uuidString,
                "successCount": String(successCount),
                "failureCount": String(failureCount),
                "status": current.status.rawValue,
            ]
        )
        return current
    }

    /// Flip the cancellation flag for `jobID`. The orchestrator
    /// checks this flag between each fan-out batch so cancellation
    /// completes within `concurrencyLimit × ~12s` of the request.
    public func cancel(jobID: UUID) async {
        cancelledJobIDs.insert(jobID)
    }

    // MARK: - Internals

    /// One slot result. Kept private so the TaskGroup hand-back stays
    /// inside this file.
    private enum SlotOutcome: Sendable {
        case success(SwarmPage)
        case failure(service: String, zoneSlug: String, reason: String)
    }

    /// Generate a single page. Static so the TaskGroup closure
    /// doesn't capture the actor (Sendable hygiene).
    private static func generatePage(
        project: SwarmProjectContext,
        service: String,
        zone: SwarmZone,
        intelligence: CloudIntelligenceHandle
    ) async -> SlotOutcome {
        let prompt = SEOSwarmPromptBuilder.pagePrompt(
            project: project,
            service: service,
            zone: zone
        )
        let response: String
        do {
            response = try await intelligence.complete(prompt)
        } catch {
            return .failure(
                service: service,
                zoneSlug: zone.slug,
                reason: error.localizedDescription
            )
        }
        // Approximate token usage: prompt + response. Real billing
        // matches at ~4 chars/token for both English and French
        // (Claude tokenizer). Surface it so the user sees the cost
        // climb in the wizard.
        let tokensUsed = (prompt.count + response.count) / 4
        guard let page = SEOSwarmPromptBuilder.parse(
            response: response,
            service: service,
            zone: zone,
            tokensUsed: tokensUsed
        ) else {
            return .failure(
                service: service,
                zoneSlug: zone.slug,
                reason: "JSON parse failed"
            )
        }
        return .success(page)
    }

    // MARK: - Telemetry MainActor bridges

    /// `MINDTelemetry.info/warning` are MainActor-isolated; the actor
    /// hops through these wrappers so the breadcrumb fires on the
    /// MainActor without polluting call sites with explicit
    /// `await MainActor.run { }` blocks.
    private func telemetryInfo(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.info(name, data: data) }
    }

    private func telemetryWarning(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.warning(name, data: data) }
    }
}
