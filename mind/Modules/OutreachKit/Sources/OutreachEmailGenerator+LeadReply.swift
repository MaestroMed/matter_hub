import Foundation
import AuditKit       // CloudIntelligenceHandle
import GraphCore      // Lead + Project + MINDTelemetry

/// v1.0-alpha.13 — Warm lead reply variants.
///
/// Lives in an extension file rather than inside
/// `OutreachEmailGenerator.swift` so the v0.26 cold-email surface
/// stays untouched while the new warm-reply path co-locates next to
/// it. The two angles (cold prospect vs. warm lead) share the actor
/// + the `CloudIntelligenceHandle` but never share prompts.
///
/// Concurrency contract
/// --------------------
/// `Lead` and `Project` are SwiftData `@Model` classes — neither is
/// `Sendable`. The public composer entry point is a free-standing
/// `@MainActor` function that builds the prompt on MainActor (where
/// the model reads are valid) and **then** hands the plain `String`
/// prompt to the actor for the network call. This keeps the actor's
/// public surface free of non-Sendable parameter types.
extension OutreachEmailGenerator {
    /// Actor-isolated network worker. Public so the MainActor
    /// composer can hand a fully-built prompt to the actor, and so
    /// the test seam can exercise it directly with a stubbed
    /// intelligence handle. Fires the telemetry breadcrumbs for the
    /// reply-composer surface.
    public func completeReplyPrompt(
        _ prompt: String,
        leadID: String,
        projectName: String,
        similarCount: Int,
        voice: String
    ) async throws -> [OutreachReply] {
        await telemetryInfoBridge(
            "lead.reply.generation.started",
            data: [
                "leadID": leadID,
                "projectName": projectName,
                "similarCount": String(similarCount),
                "voice": voice,
            ]
        )
        let response: String
        do {
            response = try await intelligence.complete(prompt)
        } catch {
            await telemetryWarningBridge(
                "lead.reply.generation.failed",
                data: [
                    "leadID": leadID,
                    "stage": "network",
                    "reason": error.localizedDescription,
                ]
            )
            throw error
        }
        let variants = LeadReplyPromptBuilder.parse(response: response)
        if variants.isEmpty {
            await telemetryWarningBridge(
                "lead.reply.generation.failed",
                data: [
                    "leadID": leadID,
                    "stage": "parse",
                ]
            )
        } else {
            await telemetryInfoBridge(
                "lead.reply.generated",
                data: [
                    "leadID": leadID,
                    "variants": String(variants.count),
                    "angles": variants.map { $0.angle.rawValue }.joined(separator: ","),
                ]
            )
        }
        return variants
    }

    /// MainActor telemetry bridge — duplicated here so the extension
    /// file doesn't need to grow the visibility of the private
    /// helpers inside `OutreachEmailGenerator`. Same shape as the
    /// existing bridge.
    private func telemetryInfoBridge(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.info(name, data: data) }
    }

    private func telemetryWarningBridge(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.warning(name, data: data) }
    }
}

/// MainActor entry point for the AI Reply Composer. Free-standing
/// (not an actor method) because it reads SwiftData `@Model` columns
/// (`Lead.message`, `Project.name`, etc.) when building the prompt
/// — those reads are valid only on MainActor, and the prompt builder
/// itself is pure. Once the prompt is a plain `String`, the network
/// call hops to the actor's isolation domain via
/// `completeReplyPrompt(_:leadID:projectName:similarCount:voice:)`.
@MainActor
public func generateLeadReply(
    lead: Lead,
    project: Project?,
    similarProjects: [Project] = [],
    senderProfile: SenderProfile = .default,
    generator: OutreachEmailGenerator = .shared
) async throws -> [OutreachReply] {
    let prompt = LeadReplyPromptBuilder.build(
        lead: lead,
        project: project,
        similarProjects: similarProjects,
        sender: senderProfile
    )
    let leadID = lead.id.uuidString
    let projectName = project?.name ?? ""
    let similarCount = similarProjects.count
    let voice = senderProfile.voice.rawValue
    return try await generator.completeReplyPrompt(
        prompt,
        leadID: leadID,
        projectName: projectName,
        similarCount: similarCount,
        voice: voice
    )
}
