import XCTest
@testable import AuditKit

final class ClaudeSynthesizerTests: XCTestCase {

    // MARK: - Happy path

    func test_parseResponse_decodesValidJSON() throws {
        let json = Self.validJSON()
        let report = try ClaudeSynthesizer.parseResponse(json, client: TestFixtures.sampleClient())

        XCTAssertEqual(report.persona, .saasB2B)
        XCTAssertEqual(report.scoring.overall, 87)
        XCTAssertEqual(report.scoring.performance, 92)
        XCTAssertEqual(report.synthesis, "Stripe est solide.")
        XCTAssertEqual(report.quickWins.count, 2)
        XCTAssertEqual(report.quickWins.first?.title, "Compresser images home")
        XCTAssertEqual(report.quickWins.first?.impact, .high)
        XCTAssertEqual(report.strategicBets.count, 1)
        XCTAssertEqual(report.strategicBets.first?.budgetMinEUR, 25_000)
        XCTAssertEqual(report.hiddenRisks.count, 1)
        XCTAssertEqual(report.hiddenRisks.first?.severity, .high)
        XCTAssertTrue(report.pitch.contains("Mehdi"))
    }

    // MARK: - Code fences

    func test_parseResponse_stripsTripleBacktickJsonFences() throws {
        let wrapped = "```json\n" + Self.validJSON() + "\n```"
        let report = try ClaudeSynthesizer.parseResponse(wrapped, client: TestFixtures.sampleClient())
        XCTAssertEqual(report.scoring.overall, 87)
    }

    func test_parseResponse_stripsBareBacktickFences() throws {
        let wrapped = "```\n" + Self.validJSON() + "\n```"
        let report = try ClaudeSynthesizer.parseResponse(wrapped, client: TestFixtures.sampleClient())
        XCTAssertEqual(report.scoring.overall, 87)
    }

    // MARK: - Error paths

    func test_parseResponse_throwsOnMalformedJSON() {
        XCTAssertThrowsError(
            try ClaudeSynthesizer.parseResponse("{not json", client: TestFixtures.sampleClient())
        ) { error in
            guard case ClaudeSynthesizerError.decodingFailed = error else {
                return XCTFail("Expected decodingFailed, got \(error)")
            }
        }
    }

    func test_parseResponse_throwsOnMissingRequiredField() {
        // Missing "synthesis" — required by the JSON schema.
        let incomplete = """
        {
          "persona": "saasB2B",
          "scoring": {
            "overall": 50, "performance": 50, "seo": 50,
            "security": 50, "brand": 50, "mobile": 50
          },
          "quickWins": [],
          "strategicBets": [],
          "pitch": "x"
        }
        """
        XCTAssertThrowsError(
            try ClaudeSynthesizer.parseResponse(incomplete, client: TestFixtures.sampleClient())
        )
    }

    // MARK: - Persona mapping

    func test_parseResponse_unknownPersonaFallsBackToOther() throws {
        let weird = Self.validJSON(persona: "unknown-cat")
        let report = try ClaudeSynthesizer.parseResponse(weird, client: TestFixtures.sampleClient())
        XCTAssertEqual(report.persona, .other)
    }

    // MARK: - Optional fields

    func test_parseResponse_hiddenRisksAbsentDoesntFail() throws {
        let json = """
        {
          "persona": "saasB2B",
          "scoring": {
            "overall": 80, "performance": 80, "seo": 80,
            "security": 80, "brand": 80, "mobile": 80
          },
          "synthesis": "x",
          "quickWins": [],
          "strategicBets": [],
          "pitch": "x"
        }
        """
        let report = try ClaudeSynthesizer.parseResponse(json, client: TestFixtures.sampleClient())
        XCTAssertEqual(report.hiddenRisks.count, 0, "Missing hiddenRisks field should be tolerated")
    }

    // MARK: - Helpers

    private static func validJSON(persona: String = "saasB2B") -> String {
        """
        {
          "persona": "\(persona)",
          "scoring": {
            "overall": 87,
            "performance": 92,
            "seo": 88,
            "security": 95,
            "brand": 80,
            "mobile": 70
          },
          "synthesis": "Stripe est solide.",
          "quickWins": [
            {
              "title": "Compresser images home",
              "detail": "Passer en WebP économise 400KB.",
              "effortDays": 0.5,
              "impact": "high"
            },
            {
              "title": "Activer HSTS",
              "detail": "Header manquant, ajout 5 min.",
              "effortDays": 0.25,
              "impact": "medium"
            }
          ],
          "strategicBets": [
            {
              "title": "Refonte design system",
              "detail": "Unifier marketing + produit.",
              "durationMonths": 4,
              "budgetMinEUR": 25000,
              "budgetMaxEUR": 45000
            }
          ],
          "hiddenRisks": [
            {
              "title": "Dépendance Stripe non backupée",
              "detail": "Aucune stratégie de failover.",
              "severity": "high"
            }
          ],
          "pitch": "Bonjour, j'ai audité stripe.com. Je propose 3 chantiers. — Mehdi"
        }
        """
    }
}
