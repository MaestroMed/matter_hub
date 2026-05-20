import XCTest
@testable import AuditKit

final class ClaudeCodeBriefBuilderTests: XCTestCase {

    func test_brief_mentionsClientAndPersona() {
        let report = TestFixtures.sampleReport()
        let brief = ClaudeCodeBriefBuilder.build(from: report)
        XCTAssertTrue(brief.contains("Stripe"))
        XCTAssertTrue(brief.contains("SaaS B2B"), "Persona label should appear in Context")
    }

    func test_brief_listsQuickWinsTitles() {
        let report = TestFixtures.sampleReport(quickWinsCount: 5)
        let brief = ClaudeCodeBriefBuilder.build(from: report)
        XCTAssertTrue(brief.contains("Quick win 1"))
        XCTAssertTrue(brief.contains("Quick win 5"))
    }

    func test_brief_includesConstraintsSection() {
        let report = TestFixtures.sampleReport()
        let brief = ClaudeCodeBriefBuilder.build(from: report)
        XCTAssertTrue(brief.contains("## Constraints"))
        XCTAssertTrue(brief.contains("LCP < 2.5s"), "Performance budget should always be stated")
    }

    func test_brief_skipsHiddenRisksSectionWhenEmpty() {
        let report = TestFixtures.sampleReport(hiddenRisksCount: 0)
        let brief = ClaudeCodeBriefBuilder.build(from: report)
        XCTAssertFalse(brief.contains("## Risques cachés"))
    }

    func test_brief_adaptsStackToPersona_tpePme() {
        let report = AuditReport(
            client: TestFixtures.sampleClient(name: "Pizza Locale"),
            persona: .tpePme,
            scoring: AuditReport.Scoring(overall: 50, performance: 60, seo: 40, security: 70, brand: 50, mobile: 30),
            performance: nil,
            findings: nil,
            synthesis: "",
            quickWins: [],
            strategicBets: [],
            pitch: ""
        )
        let brief = ClaudeCodeBriefBuilder.build(from: report)
        XCTAssertTrue(brief.contains("Astro"), "TPE/PME stack should propose Astro for static-first sites")
    }
}
