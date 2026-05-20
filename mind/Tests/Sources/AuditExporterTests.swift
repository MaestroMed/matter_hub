import XCTest
@testable import AuditKit

final class AuditExporterTests: XCTestCase {

    // MARK: - Markdown

    func test_markdown_containsClientName() {
        let report = TestFixtures.sampleReport()
        let md = AuditExporter.markdown(from: report)
        XCTAssertTrue(md.contains("Stripe"), "Markdown should mention client display name")
    }

    func test_markdown_containsScoringTable() {
        let report = TestFixtures.sampleReport(scoringOverall: 87)
        let md = AuditExporter.markdown(from: report)
        XCTAssertTrue(md.contains("Performance"), "Markdown should include Performance row")
        XCTAssertTrue(md.contains("87"), "Markdown should include overall score")
    }

    func test_markdown_listsQuickWinsAndBets() {
        let report = TestFixtures.sampleReport(quickWinsCount: 3, strategicBetsCount: 2)
        let md = AuditExporter.markdown(from: report)
        XCTAssertTrue(md.contains("Quick win 1"))
        XCTAssertTrue(md.contains("Quick win 3"))
        XCTAssertTrue(md.contains("Strategic bet 1"))
        XCTAssertTrue(md.contains("Strategic bet 2"))
    }

    func test_markdown_skipsHiddenRisksSectionWhenEmpty() {
        let report = TestFixtures.sampleReport(hiddenRisksCount: 0)
        let md = AuditExporter.markdown(from: report)
        XCTAssertFalse(md.contains("## Risques cachés"), "Section should be omitted when there are no risks")
    }

    func test_markdown_includesPitch() {
        let report = TestFixtures.sampleReport()
        let md = AuditExporter.markdown(from: report)
        XCTAssertTrue(md.contains("Pitch"))
        XCTAssertTrue(md.contains("Mehdi"), "Pitch should keep the signature")
    }

    // MARK: - JSON

    func test_json_isValidPrettyPrinted() throws {
        let report = TestFixtures.sampleReport()
        let data = try XCTUnwrap(AuditExporter.json(from: report))
        let parsed = try JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(parsed)
        let asString = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(asString.contains("\n"), "JSON should be pretty printed")
    }

    func test_json_keysSortedAlphabetically() throws {
        let report = TestFixtures.sampleReport()
        let data = try XCTUnwrap(AuditExporter.json(from: report))
        let asString = String(data: data, encoding: .utf8) ?? ""
        let synthesisIdx = asString.range(of: "\"synthesis\"")?.lowerBound
        let pitchIdx = asString.range(of: "\"pitch\"")?.lowerBound
        if let s = synthesisIdx, let p = pitchIdx {
            // sorted alphabetically → "pitch" before "synthesis"
            XCTAssertLessThan(p, s, "JSON encoding should sort keys alphabetically")
        }
    }

    // MARK: - HTML email

    func test_html_isWellFormed() {
        let report = TestFixtures.sampleReport()
        let html = AuditExporter.htmlEmail(from: report)
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("</html>"))
        XCTAssertTrue(html.contains(report.client.displayName))
    }

    func test_html_escapesAmpersand() {
        var client = TestFixtures.sampleClient(name: "A&B Co")
        let report = AuditReport(
            client: client,
            persona: .other,
            scoring: AuditReport.Scoring(overall: 50, performance: 50, seo: 50, security: 50, brand: 50, mobile: 50),
            performance: nil,
            findings: nil,
            synthesis: "",
            quickWins: [],
            strategicBets: [],
            pitch: "M & M test"
        )
        let html = AuditExporter.htmlEmail(from: report)
        XCTAssertTrue(html.contains("A&amp;B Co"), "Ampersand in client name should be HTML-escaped")
    }
}
