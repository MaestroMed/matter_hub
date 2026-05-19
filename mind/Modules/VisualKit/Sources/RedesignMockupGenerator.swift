import Foundation
import AuditKit
import GraphCore  // MINDTelemetry

// The value type `RedesignMockup` lives in AuditKit so `AuditReport`
// can hold an array of them without VisualKit needing to depend on
// itself. The HTTP generator + the pure prompt builder stay in
// VisualKit, which already depends on AuditKit.

// MARK: - Pure prompt builder

/// Pure, side-effect-free builder for the GPT Image 2 prompt that
/// turns a single quick win into an "after redesign" mockup. Lives
/// outside the actor so every assertion in `RedesignMockupPromptTests`
/// is a one-liner — no async, no Keychain reads, no URLSession.
///
/// The prompt is calibrated to the GPT Image 2 model (April 2026):
/// it leads with the visual style ("photorealistic mockup of a
/// website redesign"), then the brief, then constraints. The brand
/// palette is hard-coded to the MIND iris/aqua duo (#5E5BD8 /
/// #5EE9D8) so the resulting visuals feel like a continuation of the
/// MIND in-app aesthetic the prospect was just shown.
public enum RedesignMockupPrompt {

    /// Hard cap on how many quick wins the builder will consider.
    /// The brief stays focused on the top 3 so the generated visuals
    /// stay coherent — GPT Image 2 loses fidelity when asked to
    /// blend 5+ orthogonal recommendations into a single hero.
    public static let maxQuickWins: Int = 3

    /// Anchor hex strings for the iris/aqua duo. Locked here so
    /// tests can assert their presence in every generated prompt
    /// without dragging in DesignSystem.
    public static let irisHex = "#5E5BD8"
    public static let aquaHex = "#5EE9D8"

    /// Builds the full GPT Image 2 prompt for a single quick win.
    /// `clientName` + `host` ground the redesign in the actual
    /// prospect; `persona` shapes the copy ("SaaS B2B" prompts the
    /// model to write SaaS-flavoured CTAs, "Lifestyle / DTC" prompts
    /// aspirational hero copy, etc.).
    public static func build(
        clientName: String,
        host: String,
        quickWin: AuditReport.QuickWin,
        persona: AuditReport.Persona
    ) -> String {
        let safeName = clientName.isEmpty ? host : clientName
        let detail = quickWin.detail.isEmpty
            ? "Apply this recommendation visually."
            : quickWin.detail
        return """
        You are an elite senior product designer at Apple Human Interface Group.
        Generate a clean, photorealistic mockup of a website redesign for \(safeName) (\(host)).
        The site has this issue: \(quickWin.title) — \(detail).
        Apply the recommendation. Output: 16:9 web hero, modern Liquid Glass aesthetic,
        subtle gradient background (iris \(irisHex) to aqua \(aquaHex) at 6% opacity),
        SF Pro Display typography, generous whitespace, a single prominent CTA capsule,
        no lorem ipsum (use realistic copy in \(personaCopyLanguage(persona))-appropriate French).
        Mood: confident, premium, Apple-tier. No logos, no UI chrome, just the hero section.
        """
    }

    /// Fallback prompt used when the audit returned zero quick wins
    /// (unusual but possible — e.g. a flawless site). Falls back to a
    /// generic "premium hero redesign" brief so the generator still
    /// produces three coherent visuals tied to the brand.
    public static func buildFallback(
        clientName: String,
        host: String,
        persona: AuditReport.Persona,
        variant: Int
    ) -> String {
        let safeName = clientName.isEmpty ? host : clientName
        let angle = fallbackAngles[variant % fallbackAngles.count]
        return """
        You are an elite senior product designer at Apple Human Interface Group.
        Generate a clean, photorealistic mockup of a website redesign for \(safeName) (\(host)).
        Direction: \(angle).
        Output: 16:9 web hero, modern Liquid Glass aesthetic,
        subtle gradient background (iris \(irisHex) to aqua \(aquaHex) at 6% opacity),
        SF Pro Display typography, generous whitespace, a single prominent CTA capsule,
        no lorem ipsum (use realistic copy in \(personaCopyLanguage(persona))-appropriate French).
        Mood: confident, premium, Apple-tier. No logos, no UI chrome, just the hero section.
        """
    }

    /// Selects + truncates the top quick wins to feed the generator.
    /// The audit synthesizer already ranks `quickWins` by priority,
    /// so we just take the first N. Returns at most `maxQuickWins`.
    public static func selectQuickWins(
        _ wins: [AuditReport.QuickWin]
    ) -> [AuditReport.QuickWin] {
        Array(wins.prefix(maxQuickWins))
    }

    /// Derives a short FR carousel caption from the verbose quick-win
    /// title. Strips trailing punctuation and caps the title at 48
    /// characters so the AuditSheet card overlay stays readable.
    public static func derivedMockupTitle(quickWinTitle: String) -> String {
        let trimmed = quickWinTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".:;!? "))
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(45)) + "…"
    }

    // MARK: - Persona helpers

    private static func personaCopyLanguage(_ persona: AuditReport.Persona) -> String {
        switch persona {
        case .saasB2B:      return "SaaS B2B"
        case .tpePme:       return "TPE / PME"
        case .lifestyleDTC: return "Lifestyle / DTC"
        case .other:        return "general business"
        }
    }

    private static let fallbackAngles: [String] = [
        "Hero with a sharp, confident value proposition and a single CTA",
        "Hero with social proof badges and a quietly elegant secondary CTA",
        "Hero with a product preview tile and a primary capsule CTA",
    ]
}

// MARK: - Generator actor

/// Drives the parallel generation of 3 redesign mockups via GPT Image 2.
/// Soft-fails per mockup so one rate-limited request doesn't sink the
/// whole carousel — the caller receives whatever subset succeeded.
///
/// The HTTP work is delegated to `OpenAIImageClient`; this actor only
/// owns the prompt assembly + the parallel fan-out + the per-failure
/// telemetry. Reusing the existing client means the API key is read
/// from the same Keychain entry the Visual Concept Boards use, and
/// any future rotation of the OpenAI endpoint lands in a single
/// place.
public actor RedesignMockupGenerator {
    public static let shared = RedesignMockupGenerator()

    public enum Error: Swift.Error, LocalizedError, Sendable {
        case missingAPIKey

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Clé OpenAI manquante. Configure-la dans Réglages → OpenAI API Key."
            }
        }
    }

    private let imageClient: OpenAIImageClient

    public init(imageClient: OpenAIImageClient? = nil) {
        self.imageClient = imageClient ?? OpenAIImageClient()
    }

    /// Generates up to 3 mockups, one per quick win. When fewer than
    /// 3 quick wins are available, the missing slots use the generic
    /// fallback prompts so the carousel always displays 3 tiles when
    /// the API key works.
    ///
    /// - Parameters:
    ///   - siteScreenshotPNG: optional current-state screenshot.
    ///     Reserved for v0.23.2 — currently unused, kept in the
    ///     signature so a future patch can wire it into the
    ///     reference-image branch of the OpenAI Images endpoint
    ///     without breaking call sites.
    ///   - clientName: human-friendly client name (e.g. "Stripe").
    ///   - host: site host (e.g. "stripe.com").
    ///   - top3QuickWins: ordered list of quick wins. The generator
    ///     consumes at most 3 — extras are silently truncated.
    ///   - persona: drives the language hint in the prompt.
    ///   - quality: defaults to `.medium` for the first generation —
    ///     a future Settings toggle can promote it to `.high` once
    ///     Mehdi wants every audit to ship the SOTA tier.
    /// - Returns: the successfully-generated mockups, in the order
    ///   their source quick win appeared in the input. Empty when
    ///   every parallel call failed.
    /// - Throws: `Error.missingAPIKey` when no OpenAI key is in the
    ///   Keychain — surfaces immediately so the caller can present
    ///   the "Configure your key" hint instead of waiting on a
    ///   network round-trip.
    public func generate(
        siteScreenshotPNG: Data? = nil,
        clientName: String,
        host: String,
        top3QuickWins: [AuditReport.QuickWin],
        persona: AuditReport.Persona,
        quality: OpenAIImageQuality = .medium
    ) async throws -> [RedesignMockup] {
        guard let key = OpenAIAPIKeyStore.read(), !key.isEmpty else {
            throw Error.missingAPIKey
        }
        _ = key  // silence unused — the client re-reads the keychain itself

        let selected = RedesignMockupPrompt.selectQuickWins(top3QuickWins)
        let briefs = buildBriefs(
            clientName: clientName,
            host: host,
            quickWins: selected,
            persona: persona
        )

        await Self.logInfo(
            "redesignMockup.generation.started",
            data: [
                "host": host,
                "count": String(briefs.count),
                "quality": quality.rawValue,
            ]
        )

        let client = imageClient
        let outcomes: [RedesignMockup?] = await withTaskGroup(
            of: (Int, RedesignMockup?).self
        ) { group in
            for (index, brief) in briefs.enumerated() {
                group.addTask {
                    do {
                        let bytes = try await client.generate(
                            prompt: brief.prompt,
                            size: .landscape,
                            quality: quality
                        )
                        let mockup = RedesignMockup(
                            title: brief.title,
                            quickWinTitle: brief.quickWinTitle,
                            quickWinDetail: brief.quickWinDetail,
                            imageData: bytes,
                            prompt: brief.prompt
                        )
                        return (index, mockup)
                    } catch {
                        await Self.logWarning(
                            "redesignMockup.generation.failed",
                            data: [
                                "host": host,
                                "slot": String(index),
                                "reason": error.localizedDescription,
                            ]
                        )
                        return (index, nil)
                    }
                }
            }
            // Collect by original slot index so the carousel order is
            // stable regardless of which network call returned first.
            var sparse = Array<RedesignMockup?>(repeating: nil, count: briefs.count)
            for await (idx, mockup) in group {
                if idx < sparse.count { sparse[idx] = mockup }
            }
            return sparse
        }

        let mockups = outcomes.compactMap { $0 }
        await Self.logInfo(
            "redesignMockup.generation.completed",
            data: [
                "host": host,
                "count": String(mockups.count),
                "requested": String(briefs.count),
            ]
        )
        return mockups
    }

    /// MINDTelemetry is `@MainActor`-isolated; bouncing through these
    /// async shims keeps the generator + its TaskGroup off the main
    /// actor while still recording the breadcrumb.
    private static func logInfo(_ name: String, data: [String: String]) async {
        await MainActor.run {
            MINDTelemetry.info(name, data: data)
        }
    }

    private static func logWarning(_ name: String, data: [String: String]) async {
        await MainActor.run {
            MINDTelemetry.warning(name, data: data)
        }
    }

    // MARK: - Brief assembly

    private struct Brief: Sendable {
        let title: String
        let quickWinTitle: String
        let quickWinDetail: String
        let prompt: String
    }

    private nonisolated func buildBriefs(
        clientName: String,
        host: String,
        quickWins: [AuditReport.QuickWin],
        persona: AuditReport.Persona
    ) -> [Brief] {
        let total = RedesignMockupPrompt.maxQuickWins
        var briefs: [Brief] = []
        for slot in 0..<total {
            if slot < quickWins.count {
                let win = quickWins[slot]
                briefs.append(Brief(
                    title: RedesignMockupPrompt.derivedMockupTitle(quickWinTitle: win.title),
                    quickWinTitle: win.title,
                    quickWinDetail: win.detail,
                    prompt: RedesignMockupPrompt.build(
                        clientName: clientName,
                        host: host,
                        quickWin: win,
                        persona: persona
                    )
                ))
            } else {
                let fallbackTitle = "Hero refait #\(slot + 1)"
                briefs.append(Brief(
                    title: fallbackTitle,
                    quickWinTitle: fallbackTitle,
                    quickWinDetail: "",
                    prompt: RedesignMockupPrompt.buildFallback(
                        clientName: clientName,
                        host: host,
                        persona: persona,
                        variant: slot
                    )
                ))
            }
        }
        return briefs
    }
}
