import XCTest
@testable import ClientPortalKit
@testable import AuditKit

/// Locks the pure HTML generator. The pipeline is intentionally
/// Foundation-only so every assertion here walks the in-memory
/// `ClientPortalArchive` — no FileManager, no WebKit, no clock reads.
/// PortalWriter (the IO side) is exercised separately by
/// `PortalWriterTests`; this file owns the rendering contract.
final class ClientPortalBuilderTests: XCTestCase {

    // MARK: - Archive shape

    func test_generateSite_alwaysContainsIndexHTML() {
        let report = TestFixtures.sampleReport()
        let archive = ClientPortalBuilder.generateSite(for: report)

        XCTAssertNotNil(archive.files["index.html"],
                        "ClientPortalArchive contract: index.html is mandatory — the App layer reads only that key")
        XCTAssertGreaterThan(archive.indexHTML.count, 0,
                             "index.html must not be empty otherwise Safari renders a blank tab")
    }

    func test_generateSite_indexHTMLStaysUnderPageWeightCeiling() {
        let report = TestFixtures.sampleReport(
            quickWinsCount: 8,
            strategicBetsCount: 6,
            hiddenRisksCount: 5
        )
        let archive = ClientPortalBuilder.generateSite(for: report)

        XCTAssertLessThan(archive.totalBytes, ClientPortalBuilder.pageWeightCeilingBytes,
                          "Page weight must stay under the locked 200 KB ceiling — adding a heavy section requires a follow-up budget review")
    }

    // MARK: - Slug

    func test_makeSlug_lowercasesAndDashesSpaces() {
        let date = Date(timeIntervalSince1970: 1_747_699_200) // 2025-05-19 (UTC)
        let slug = ClientPortalBuilder.makeSlug(clientName: "Acme Corp", date: date)
        XCTAssertTrue(slug.hasPrefix("acme-corp-"),
                      "Expected 'acme-corp-…' prefix, got '\(slug)'")
        XCTAssertEqual(slug.count, "acme-corp-2025-05-19".count,
                       "Slug must terminate with yyyy-MM-dd of generation date")
    }

    func test_makeSlug_stripsDiacritics() {
        let slug = ClientPortalBuilder.makeSlug(clientName: "Café Münchën", date: .now)
        XCTAssertTrue(slug.contains("cafe-munchen"),
                      "Expected stripped diacritics 'cafe-munchen', got '\(slug)'")
    }

    func test_makeSlug_handlesAllPunctuationAsDashes() {
        let slug = ClientPortalBuilder.makeSlug(clientName: "Foo & Bar / Baz!", date: .now)
        // Collapsed dash runs + no leading/trailing dash.
        XCTAssertTrue(slug.hasPrefix("foo-bar-baz-"),
                      "Punctuation must collapse to single dashes, got '\(slug)'")
        XCTAssertFalse(slug.hasSuffix("-"))
    }

    func test_makeSlug_fallsBackToClientWhenNameIsEmpty() {
        let slug = ClientPortalBuilder.makeSlug(clientName: "", date: .now)
        XCTAssertTrue(slug.hasPrefix("client-"),
                      "Empty client name must fall back to 'client-…' slug")
    }

    // MARK: - Acceptance: full report content surfaces in the HTML

    func test_generateSite_includesClientNameInHero() {
        let report = TestFixtures.sampleReport()
        let html = ClientPortalBuilder.generateSite(for: report).indexHTML

        XCTAssertTrue(html.contains("Stripe"),
                      "Client display name must appear somewhere in the HTML — acceptance criterion")
    }

    func test_generateSite_includesOverallScore() {
        let report = TestFixtures.sampleReport(scoringOverall: 87)
        let html = ClientPortalBuilder.generateSite(for: report).indexHTML

        XCTAssertTrue(html.contains(">87<"),
                      "Overall score must render in the page — acceptance criterion")
    }

    func test_generateSite_includesEveryQuickWin() {
        let report = TestFixtures.sampleReport(quickWinsCount: 3)
        let html = ClientPortalBuilder.generateSite(for: report).indexHTML

        for idx in 1...3 {
            XCTAssertTrue(html.contains("Quick win \(idx)"),
                          "Quick win #\(idx) must appear in the rendered HTML")
        }
    }

    func test_generateSite_includesEveryStrategicBet() {
        let report = TestFixtures.sampleReport(strategicBetsCount: 3)
        let html = ClientPortalBuilder.generateSite(for: report).indexHTML

        for idx in 1...3 {
            XCTAssertTrue(html.contains("Strategic bet \(idx)"),
                          "Strategic bet #\(idx) must appear in the timeline")
        }
    }

    func test_generateSite_includesEveryHiddenRisk() {
        let report = TestFixtures.sampleReport(hiddenRisksCount: 2)
        let html = ClientPortalBuilder.generateSite(for: report).indexHTML

        for idx in 1...2 {
            XCTAssertTrue(html.contains("Hidden risk \(idx)"),
                          "Hidden risk #\(idx) must appear in the risks section")
        }
    }

    func test_generateSite_includesPitchBody() {
        let report = TestFixtures.sampleReport()
        let html = ClientPortalBuilder.generateSite(for: report).indexHTML
        XCTAssertTrue(html.contains("Following my audit of stripe.com"),
                      "Pitch body must appear in the proposition block — acceptance criterion")
    }

    func test_generateSite_omitsHiddenRisksSectionWhenEmpty() {
        let report = TestFixtures.sampleReport(hiddenRisksCount: 0)
        let html = ClientPortalBuilder.generateSite(for: report).indexHTML
        XCTAssertFalse(html.contains("RISQUES CACHÉS"),
                       "Hidden Risks section must be omitted when the audit has none — empty section would feel padded")
    }

    func test_generateSite_brandedConsultantNameAppearsInHeroAndPitch() {
        let report = TestFixtures.sampleReport()
        let brand = BrandSettings(
            consultantName: "Mehdi Nafaa",
            consultantTitle: "Senior Digital Consultant"
        )
        let html = ClientPortalBuilder.generateSite(for: report, brand: brand).indexHTML
        XCTAssertTrue(html.contains("Mehdi Nafaa"))
        XCTAssertTrue(html.contains("Senior Digital Consultant"))
    }

    func test_generateSite_respectsDarkLightSchemePreference() {
        let report = TestFixtures.sampleReport()
        let html = ClientPortalBuilder.generateSite(for: report).indexHTML
        XCTAssertTrue(html.contains("prefers-color-scheme: light"),
                      "Template must honor the user's color-scheme preference — acceptance criterion")
        XCTAssertTrue(html.contains("prefers-reduced-motion"),
                      "Template must honor reduced-motion — accessibility criterion")
    }

    // MARK: - Determinism

    func test_generateSite_isDeterministicForSameInput() {
        let report = TestFixtures.sampleReport()
        let a = ClientPortalBuilder.generateSite(for: report)
        let b = ClientPortalBuilder.generateSite(for: report)
        XCTAssertEqual(a.indexHTML, b.indexHTML,
                       "Generator must be deterministic — two runs on the same (report, brand) pair must emit byte-identical HTML")
        XCTAssertEqual(a.folderSlug, b.folderSlug)
    }

    // MARK: - Security — XSS guard

    func test_generateSite_escapesHTMLInClientName() {
        let report = TestFixtures.sampleReport(scoringOverall: 50)
        // Build a poisoned report with HTML-laced client name.
        let poisonedClient = AuditClient(
            url: URL(string: "https://attacker.example")!,
            name: "<script>alert('xss')</script>"
        )
        let poisoned = AuditReport(
            client: poisonedClient,
            persona: report.persona,
            scoring: report.scoring,
            performance: report.performance,
            findings: report.findings,
            synthesis: report.synthesis,
            quickWins: report.quickWins,
            strategicBets: report.strategicBets,
            hiddenRisks: report.hiddenRisks,
            pitch: report.pitch
        )
        let html = ClientPortalBuilder.generateSite(for: poisoned).indexHTML

        XCTAssertFalse(html.contains("<script>alert('xss')</script>"),
                       "Client name must be HTML-escaped — never inject raw markup")
        XCTAssertTrue(html.contains("&lt;script&gt;"),
                      "Escaped opening tag must be present")
    }

    // MARK: - Markdown light renderer

    func test_renderMarkdownLight_handlesHeadingsAndParagraphs() {
        let source = """
        # Title

        Paragraph one.

        ## Subtitle

        Paragraph two with **bold** text.
        """
        let rendered = HTMLTemplates.renderMarkdownLight(source)
        XCTAssertTrue(rendered.contains("<h2 class=\"synthesis__h2\">Title</h2>"))
        XCTAssertTrue(rendered.contains("<h3 class=\"synthesis__h3\">Subtitle</h3>"))
        XCTAssertTrue(rendered.contains("<strong>bold</strong>"))
        XCTAssertTrue(rendered.contains("<p class=\"synthesis__p\">"))
    }

    func test_renderMarkdownLight_handlesBulletLists() {
        let source = """
        - First item
        - Second item
        - Third item
        """
        let rendered = HTMLTemplates.renderMarkdownLight(source)
        XCTAssertTrue(rendered.contains("<ul class=\"synthesis__list\">"))
        XCTAssertTrue(rendered.contains("<li>First item</li>"))
        XCTAssertTrue(rendered.contains("<li>Second item</li>"))
        XCTAssertTrue(rendered.contains("<li>Third item</li>"))
    }
}
