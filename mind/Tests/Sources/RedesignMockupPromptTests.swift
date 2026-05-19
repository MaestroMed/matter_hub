import XCTest
@testable import VisualKit
@testable import AuditKit

/// Locks the pure GPT Image 2 prompt builder shipped in v0.23. The
/// actor's HTTP call cannot be exercised from a hosted unit test (no
/// network, no Keychain in CI), so the contract that gets covered
/// here is everything observable from `RedesignMockupPrompt.build`,
/// `.buildFallback`, `.selectQuickWins`, and
/// `.derivedMockupTitle`. The whole surface is `static` + value-typed
/// so every assertion is a one-liner — no async setup.
final class RedesignMockupPromptTests: XCTestCase {

    // MARK: - Fixtures

    private func sampleWin(
        title: String = "Refondre le hero pour clarifier la promesse",
        detail: String = "Le hero actuel mélange 3 messages — distille-le en une promesse + un CTA."
    ) -> AuditReport.QuickWin {
        AuditReport.QuickWin(
            title: title,
            detail: detail,
            effortDays: 1.0,
            impact: .high
        )
    }

    // MARK: - Anchor: structural

    /// The prompt must surface the client identity so GPT Image 2
    /// generates a visual grounded in the actual prospect, not a
    /// generic "premium SaaS landing".
    func test_build_includesClientNameAndHost() {
        let prompt = RedesignMockupPrompt.build(
            clientName: "Acme Corp",
            host: "acme.com",
            quickWin: sampleWin(),
            persona: .saasB2B
        )
        XCTAssertTrue(prompt.contains("Acme Corp"),
                      "Client name must appear in the prompt body")
        XCTAssertTrue(prompt.contains("acme.com"),
                      "Host must appear in the prompt body")
    }

    /// The quick-win brief (title + detail) is the redesign anchor.
    /// Both must be threaded into the prompt verbatim so the model
    /// knows what to fix.
    func test_build_includesQuickWinTitleAndDetail() {
        let win = sampleWin(
            title: "Ajouter un CTA principal au-dessus de la ligne de flottaison",
            detail: "Aucun CTA visible sans scroll — c'est la priorité conversion."
        )
        let prompt = RedesignMockupPrompt.build(
            clientName: "Acme",
            host: "acme.com",
            quickWin: win,
            persona: .saasB2B
        )
        XCTAssertTrue(prompt.contains("Ajouter un CTA principal au-dessus de la ligne de flottaison"))
        XCTAssertTrue(prompt.contains("Aucun CTA visible sans scroll"))
    }

    /// Locks the MIND iris/aqua brand palette into every prompt so
    /// the generated visuals feel like a continuation of the in-app
    /// Liquid Glass aesthetic. Regression on either hex breaks the
    /// brand-board promise.
    func test_build_includesIrisAndAquaBrandColors() {
        let prompt = RedesignMockupPrompt.build(
            clientName: "Acme",
            host: "acme.com",
            quickWin: sampleWin(),
            persona: .saasB2B
        )
        XCTAssertTrue(prompt.contains(RedesignMockupPrompt.irisHex),
                      "Iris hex \(RedesignMockupPrompt.irisHex) must appear in the brand-palette clause")
        XCTAssertTrue(prompt.contains(RedesignMockupPrompt.aquaHex),
                      "Aqua hex \(RedesignMockupPrompt.aquaHex) must appear in the brand-palette clause")
    }

    /// The persona shapes the copy language hint so a TPE/PME pitch
    /// doesn't ship with SaaS-flavoured CTAs and vice-versa. Every
    /// persona must produce a hint, and the FR-language clause must
    /// always remain (Mehdi's audience is French).
    func test_build_mentionsFrenchCopyLanguageForEveryPersona() {
        for persona in AuditReport.Persona.allCases {
            let prompt = RedesignMockupPrompt.build(
                clientName: "Acme",
                host: "acme.com",
                quickWin: sampleWin(),
                persona: persona
            )
            XCTAssertTrue(prompt.contains("French"),
                          "Persona \(persona) must keep the FR language hint")
        }
    }

    /// The "no logos / no UI chrome" guard prevents GPT Image 2 from
    /// generating a fake browser frame around the hero or copying
    /// the prospect's existing logo into the mockup (legal risk).
    func test_build_includesNoLogosNoUIChromeConstraint() {
        let prompt = RedesignMockupPrompt.build(
            clientName: "Acme",
            host: "acme.com",
            quickWin: sampleWin(),
            persona: .saasB2B
        )
        XCTAssertTrue(prompt.contains("No logos, no UI chrome"),
                      "The no-logos / no-chrome constraint must terminate every prompt")
    }

    // MARK: - Edge cases

    /// Empty quick-wins list → the builder falls back to the
    /// generic premium-hero brief so the carousel always renders 3
    /// coherent tiles. The fallback must still ground the visual
    /// in the prospect.
    func test_buildFallback_groundsVisualInProspect() {
        let prompt = RedesignMockupPrompt.buildFallback(
            clientName: "",
            host: "acme.com",
            persona: .saasB2B,
            variant: 0
        )
        // Empty client name → the builder uses the host as a
        // human-friendly fallback so the prompt never reads "for "
        // with an empty space.
        XCTAssertTrue(prompt.contains("acme.com"),
                      "Empty client name must fall back to the host inside the prompt")
        XCTAssertTrue(prompt.contains(RedesignMockupPrompt.irisHex))
    }

    /// More than 3 quick wins → the selector keeps only the top 3
    /// so a noisy audit doesn't push 8 incoherent mockups into the
    /// carousel.
    func test_selectQuickWins_truncatesToTopThree() {
        let wins = (1...6).map { idx in
            AuditReport.QuickWin(
                title: "Win \(idx)",
                detail: "Detail \(idx)",
                effortDays: 1.0,
                impact: .medium
            )
        }
        let selected = RedesignMockupPrompt.selectQuickWins(wins)
        XCTAssertEqual(selected.count, RedesignMockupPrompt.maxQuickWins,
                       "Selector must hard-cap at \(RedesignMockupPrompt.maxQuickWins) quick wins")
        XCTAssertEqual(selected.first?.title, "Win 1",
                       "Selector must keep the original priority order — top 3 = first 3")
        XCTAssertEqual(selected.last?.title, "Win 3")
    }

    /// Empty input list returns empty — the fallback path is the
    /// caller's responsibility, not the selector's.
    func test_selectQuickWins_emptyInputReturnsEmpty() {
        XCTAssertTrue(RedesignMockupPrompt.selectQuickWins([]).isEmpty)
    }

    // MARK: - Determinism

    /// The prompt builder is pure — identical inputs must produce
    /// the same output, otherwise downstream tests would flake and
    /// the "regenerate this tile" CTA could ship different prompts
    /// on each invocation.
    func test_build_isDeterministicForSameInput() {
        let win = sampleWin()
        let a = RedesignMockupPrompt.build(
            clientName: "Acme",
            host: "acme.com",
            quickWin: win,
            persona: .lifestyleDTC
        )
        let b = RedesignMockupPrompt.build(
            clientName: "Acme",
            host: "acme.com",
            quickWin: win,
            persona: .lifestyleDTC
        )
        XCTAssertEqual(a, b,
                       "Builder must be pure — identical (name, host, win, persona) → identical prompt")
    }

    // MARK: - Title derivation

    func test_derivedMockupTitle_stripsTrailingPunctuation() {
        XCTAssertEqual(
            RedesignMockupPrompt.derivedMockupTitle(quickWinTitle: "Refondre le hero!"),
            "Refondre le hero",
            "Trailing punctuation must be stripped for a clean carousel caption"
        )
    }

    func test_derivedMockupTitle_truncatesOverlongTitlesWithEllipsis() {
        let long = String(repeating: "x", count: 80)
        let derived = RedesignMockupPrompt.derivedMockupTitle(quickWinTitle: long)
        XCTAssertTrue(derived.count <= 48,
                      "Carousel caption must stay within the readable 48-char budget")
        XCTAssertTrue(derived.hasSuffix("…"),
                      "Truncated captions must end on an ellipsis so the user knows there's more")
    }
}
