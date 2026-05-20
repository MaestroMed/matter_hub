import Foundation
import GraphCore

/// v0.28 — Optional async enricher that the host App can call after
/// `MeetingBriefBuilder.assemble` returns a heuristic-only brief.
/// Designed to fail soft: any error inside the enrichment closures
/// simply leaves the original brief's bullets in place. Network /
/// LLM access lives behind the `enrichClosure` to keep the actor
/// free of dependencies on AuditKit / Intelligence (CalendarKit
/// stays a leaf module).
///
/// The host App supplies the closure (typically wrapping a
/// `CloudIntelligenceHandle` call) on construction, so unit tests
/// can inject a deterministic stub.
public actor MeetingBriefEnricher {

    /// Pure-function shape of the enrichment hook. Receives the
    /// current brief, returns a copy with `recentNews` /
    /// `auditHighlights` / `attendeeIntel` augmented. The hook is
    /// expected to be idempotent — calling it twice with the same
    /// input must return the same output.
    public typealias Enrich = @Sendable (MeetingBrief) async throws -> MeetingBrief

    private let enrich: Enrich

    public init(enrich: @escaping Enrich) {
        self.enrich = enrich
    }

    /// Runs the injected closure, soft-failing back to the input
    /// brief on any error and bouncing the breadcrumb onto the
    /// MainActor so MINDTelemetry stays consistent.
    public func enrich(_ brief: MeetingBrief) async -> MeetingBrief {
        do {
            let enriched = try await enrich(brief)
            await emit("meetingBrief.enriched", data: [
                "eventID": brief.event.id,
                "newsBullets": "\(enriched.recentNews.count)",
                "auditBullets": "\(enriched.auditHighlights.count)",
                "attendees": "\(enriched.attendeeIntel.count)",
            ])
            return enriched
        } catch {
            await emit("meetingBrief.enrich.failed", data: [
                "eventID": brief.event.id,
                "error": String(describing: error),
            ])
            return brief
        }
    }

    @MainActor
    private func emit(_ name: String, data: [String: String]) {
        MINDTelemetry.info(name, data: data)
    }
}
