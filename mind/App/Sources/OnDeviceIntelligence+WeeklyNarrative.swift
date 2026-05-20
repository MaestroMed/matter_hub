import Foundation
import FoundationModels
import Intelligence

/// v0.16 — Weekly digest narrative generator.
///
/// Lives at the app layer (not inside the Intelligence module) because
/// `WeeklyDigest` is a module-less value type owned by the host App.
/// Putting the extension here keeps the Intelligence module free of an
/// upward dependency on App-level types while still giving callers a
/// single, natural-feeling entry point (`intel.weeklyNarrative(digest)`).
///
/// Returns nil whenever the request can't be honoured: Foundation Models
/// not available on this device, model errors, blank response — every
/// failure mode is soft because the structured digest is the load-bearing
/// data; the narrative is "nice to have" gloss. The HomeView card
/// renders the localized fallback ("Une semaine bien remplie.") when
/// `narrative == nil`, so the user never sees an empty paragraph.
@MainActor
public extension OnDeviceIntelligence {

    func weeklyNarrative(_ digest: WeeklyDigest) async -> String? {
        // Skip the round-trip entirely when there's nothing to summarize.
        // A digest with all-zero counts means the user didn't actually
        // engage this week — no point asking a model to embellish silence.
        guard digest.isMeaningful else { return nil }

        // Soft-fail the moment the on-device model isn't available
        // (older hardware, Apple Intelligence disabled, locale not
        // supported). The card hides the narrative paragraph and shows
        // the localized fallback instead.
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let prompt = Self.buildPrompt(for: digest)

        do {
            let session = LanguageModelSession(
                instructions: Self.narrativeInstructions
            )
            let response = try await session.respond(to: prompt)
            let cleaned = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }

    // MARK: - Prompt construction

    /// FR instructions kept short so the on-device model spends its
    /// token budget on output, not on parsing system context. "ton
    /// chaleureux" matches MIND's voice (warm, personal); two sentences
    /// is the visible limit — the card truncates to ~140 chars if the
    /// model goes long.
    private static let narrativeInstructions: String = """
        Tu résumes la semaine de Mehdi en 2 phrases maximum, ton
        chaleureux et personnel, dans la même langue que la requête.
        Pas de citations, pas de listes, pas de préambule. Termine par
        une phrase qui invite à continuer la semaine prochaine.
        """

    /// Build the human-readable prompt. The structured numbers + the
    /// list of highlights give the model enough texture to write
    /// something specific without leaking the user's actual content
    /// off-device (only titles are shared, never note bodies).
    private static func buildPrompt(for digest: WeeklyDigest) -> String {
        let focus = String(format: "%.1f", digest.focusHours)
        var prompt = """
            Cette semaine : \(digest.captureCount) captures, \
            \(digest.auditCount) audits, \(focus) heures de focus.
            """

        if !digest.highlightedCaptures.isEmpty {
            let bullets = digest.highlightedCaptures
                .prefix(3)
                .map { "- \($0)" }
                .joined(separator: "\n")
            prompt += "\n\nQuelques captures clés :\n\(bullets)"
        }

        return prompt
    }
}
