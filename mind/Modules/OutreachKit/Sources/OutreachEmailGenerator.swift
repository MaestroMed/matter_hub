import Foundation
import AuditKit       // CloudIntelligenceHandle + AuditReport
import GraphCore      // MINDTelemetry

/// v0.26 — AI Sales Email Generator.
///
/// Mehdi taps "Générer outreach" on any client/prospect Node. The
/// generator builds a single prompt covering the prospect's audit
/// findings + recent trigger + industry + sender voice, asks the
/// cloud LLM for 5 distinct email variants tagged by angle (ROI /
/// Quick win / Concurrent / Funding / Question), parses the JSON
/// response, and hands a `[OutreachEmail]` back to the UI.
///
/// Architecture
/// ------------
/// - `OutreachPromptBuilder` (pure namespace) — turns a
///   `(ProspectContext, SenderProfile, variantCount)` triple into the
///   prompt string + parses the JSON response into `OutreachEmail`
///   values. Tested in isolation without network access.
/// - `OutreachEmailGenerator` (actor) — wraps the
///   `CloudIntelligenceHandle` so the network call hops off the
///   MainActor. Soft-fails to `[]` only when the LLM string parse
///   fails; network errors are rethrown so the UI can surface a
///   precise "no Anthropic key" / "network down" message.
/// - `ProspectContext` (Sendable value) — name + host + optional
///   audit + recent trigger + industry + contact info. Audit nil is
///   the "no audit yet, generic angle" path.
/// - `SenderProfile` (Sendable value) — Mehdi's identity + voice
///   tone. Defaults to "Mehdi Nafaa / Senior Digital Consultant /
///   friendly".
/// - `OutreachEmail` (Sendable value) — one variant: subject + body +
///   angle + estimated read time. `Identifiable` so SwiftUI's `ForEach`
///   can mount the 5 cards without juggling indices.
///
/// Why an actor: the round trip is 8-20s (5 variants generated in
/// one shot). Pinning that to the MainActor would freeze the sheet's
/// shimmer skeletons. Actor isolation gives us serial generator
/// access without dragging the request onto the MainActor queue.
public actor OutreachEmailGenerator {
    /// Shared singleton — the app reaches the generator from the
    /// `OutreachSheet` "Générer 5 variants" CTA. Tests inject their
    /// own instance with a stubbed `CloudIntelligenceHandle`.
    public static let shared = OutreachEmailGenerator()

    /// Pluggable LLM facade so tests can swap `CloudIntelligence`
    /// for a deterministic stub. Reuses the same `.live` handle
    /// shipped by `ROIEstimator` (v0.25) — a single bridge fix
    /// repairs both flows.
    public let intelligence: CloudIntelligenceHandle

    public init(intelligence: CloudIntelligenceHandle = .live) {
        self.intelligence = intelligence
    }

    /// Generate `variantCount` email variants for the given prospect.
    /// Clamps `variantCount` to 1...10 so a noisy caller can't blow
    /// the token budget. Throws on network or empty-response errors
    /// so the UI can surface a precise error. Returns `[]` only when
    /// the parser drops every variant (Claude returned malformed
    /// JSON every time) — the UI shows an "essaie à nouveau" CTA in
    /// that case rather than a confusing success state.
    public func generate(
        prospect: ProspectContext,
        senderProfile: SenderProfile = .default,
        variantCount: Int = 5
    ) async throws -> [OutreachEmail] {
        let clamped = max(1, min(10, variantCount))
        let prompt = OutreachPromptBuilder.build(
            prospect: prospect,
            sender: senderProfile,
            variantCount: clamped
        )
        await telemetryInfo(
            "outreach.generation.started",
            data: [
                "host": prospect.host,
                "variantCount": String(clamped),
                "voice": senderProfile.voice.rawValue,
                "hasAudit": prospect.auditReport == nil ? "false" : "true",
            ]
        )
        let response: String
        do {
            response = try await intelligence.complete(prompt)
        } catch {
            await telemetryWarning(
                "outreach.generation.failed",
                data: [
                    "host": prospect.host,
                    "stage": "network",
                    "reason": error.localizedDescription,
                ]
            )
            throw error
        }
        let variants = OutreachPromptBuilder.parse(response: response)
        if variants.isEmpty {
            await telemetryWarning(
                "outreach.generation.failed",
                data: [
                    "host": prospect.host,
                    "stage": "parse",
                ]
            )
        } else {
            await telemetryInfo(
                "outreach.generation.completed",
                data: [
                    "host": prospect.host,
                    "variants": String(variants.count),
                ]
            )
        }
        return variants
    }

    // MARK: - Telemetry MainActor bridges

    private func telemetryInfo(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.info(name, data: data) }
    }

    private func telemetryWarning(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.warning(name, data: data) }
    }
}

// MARK: - Prospect context

/// Everything the generator needs to ground the email in the
/// prospect's reality. Every field except `clientName` + `host` is
/// optional so the same generator works whether Mehdi has just
/// captured a URL or has a full audit + funding signal in hand.
public struct ProspectContext: Sendable, Equatable {
    public let clientName: String
    public let host: String
    public let auditReport: AuditReport?
    public let recentTrigger: String?
    public let industry: String?
    public let primaryContactName: String?
    public let primaryContactRole: String?

    public init(
        clientName: String,
        host: String,
        auditReport: AuditReport? = nil,
        recentTrigger: String? = nil,
        industry: String? = nil,
        primaryContactName: String? = nil,
        primaryContactRole: String? = nil
    ) {
        self.clientName = clientName
        self.host = host
        self.auditReport = auditReport
        self.recentTrigger = recentTrigger
        self.industry = industry
        self.primaryContactName = primaryContactName
        self.primaryContactRole = primaryContactRole
    }
}

// MARK: - Sender profile

/// Mehdi's identity + voice tone, threaded into the prompt so the
/// generated emails read in his voice rather than a generic SaaS
/// pitch. `default` is "Mehdi Nafaa / Senior Digital Consultant /
/// friendly".
public struct SenderProfile: Sendable, Equatable {
    public let name: String
    public let title: String
    public let signature: String
    public let voice: VoiceTone

    public init(
        name: String,
        title: String,
        signature: String,
        voice: VoiceTone
    ) {
        self.name = name
        self.title = title
        self.signature = signature
        self.voice = voice
    }

    public static var `default`: SenderProfile {
        SenderProfile(
            name: "Mehdi Nafaa",
            title: "Senior Digital Consultant",
            signature: "— Mehdi",
            voice: .friendly
        )
    }

    public enum VoiceTone: String, Sendable, Codable, CaseIterable, Equatable {
        case friendly
        case direct
        case formal
    }
}

// MARK: - Outreach email value

/// One generated email variant. `Identifiable` so SwiftUI's
/// `ForEach` can stack the 5 cards without re-keying on tap.
public struct OutreachEmail: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let subject: String
    public let body: String
    public let angle: Angle
    public let estimatedReadTimeSeconds: Int

    public init(
        id: UUID = UUID(),
        subject: String,
        body: String,
        angle: Angle,
        estimatedReadTimeSeconds: Int
    ) {
        self.id = id
        self.subject = subject
        self.body = body
        self.angle = angle
        self.estimatedReadTimeSeconds = estimatedReadTimeSeconds
    }

    /// Distinct angles Claude is asked to cover across the 5 variants.
    /// The angle drives the per-card pill colour in `OutreachSheet`
    /// and the localized label in the variant header.
    public enum Angle: String, Sendable, Codable, CaseIterable, Equatable {
        case roi
        case quickWin
        case competitor
        case funding
        case question
    }
}
