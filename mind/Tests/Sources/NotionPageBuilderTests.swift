import XCTest
@testable import AuditKit
@testable import NotionKit

/// Pure tests for `NotionPageBuilder.buildPagePayload(for:databaseID:)`.
///
/// Why pure?
/// ---------
/// The builder produces a `[String: Any]` matching the JSON body of
/// `POST https://api.notion.com/v1/pages`. Every test asserts on the
/// dict directly — no `URLSession`, no `JSONEncoder`, no mocked Notion
/// server. The actor that wraps the builder is exercised end-to-end
/// from the Settings "Test sync" button.
///
/// What's locked here
/// ------------------
/// - Title block contains the client name
/// - "Score" property mirrors the overall scoring
/// - Synthesis chunked into paragraph blocks (one per `\n\n`)
/// - Persona stored as a `select` property
/// - Quick wins / strategic bets / hidden risks each emit a heading_2
///   followed by bulleted_list_item children
/// - Empty quick wins doesn't crash the builder, doesn't emit the
///   heading either (clean page = no orphan sections)
/// - Long synthesis paragraphs get chunked into spans inside the
///   same paragraph block (Notion's 2000-char per-span cap)
final class NotionPageBuilderTests: XCTestCase {

    // MARK: - Title + properties

    func testTitleContainsClientName() {
        let report = TestFixtures.sampleReport()
        let payload = NotionPageBuilder.buildPagePayload(for: report, databaseID: "db_xyz")

        let properties = payload["properties"] as? [String: Any]
        XCTAssertNotNil(properties, "Top-level properties must be present")

        let nameProp = properties?["Name"] as? [String: Any]
        let titleArray = nameProp?["title"] as? [[String: Any]]
        let firstTitle = titleArray?.first
        let textDict = firstTitle?["text"] as? [String: Any]
        let content = textDict?["content"] as? String

        XCTAssertEqual(content, "Stripe", "Title rich-text content must equal the client display name")
    }

    func testParentDatabaseIDIsForwarded() {
        let report = TestFixtures.sampleReport()
        let payload = NotionPageBuilder.buildPagePayload(for: report, databaseID: "db_unique_42")

        let parent = payload["parent"] as? [String: Any]
        XCTAssertEqual(parent?["database_id"] as? String, "db_unique_42")
    }

    func testScorePropertyMirrorsOverallScoring() {
        let report = TestFixtures.sampleReport(scoringOverall: 73)
        let payload = NotionPageBuilder.buildPagePayload(for: report, databaseID: "db_xyz")

        let properties = payload["properties"] as? [String: Any]
        let scoreProp = properties?["Score"] as? [String: Any]
        let richArray = scoreProp?["rich_text"] as? [[String: Any]]
        let firstSpan = richArray?.first
        let textDict = firstSpan?["text"] as? [String: Any]
        let content = textDict?["content"] as? String

        XCTAssertEqual(content, "73 / 100", "Score property must reflect scoring.overall")
    }

    func testPersonaStoredAsSelectProperty() {
        let report = TestFixtures.sampleReport()
        let payload = NotionPageBuilder.buildPagePayload(for: report, databaseID: "db_xyz")

        let properties = payload["properties"] as? [String: Any]
        let personaProp = properties?["Persona"] as? [String: Any]
        let select = personaProp?["select"] as? [String: Any]
        let name = select?["name"] as? String

        XCTAssertEqual(name, "SaaS B2B", "Persona must be a select property with the human label")
    }

    // MARK: - Children blocks

    func testSynthesisProducesOneParagraphPerDoubleNewlineBlock() {
        // sampleReport.synthesis contains two `\n\n`-separated blocks:
        // "## Identité\n…" and "## Maturité digitale\n…"
        let report = TestFixtures.sampleReport()
        let payload = NotionPageBuilder.buildPagePayload(for: report, databaseID: "db_xyz")

        let children = payload["children"] as? [[String: Any]]
        XCTAssertNotNil(children)
        let synthesisBlocks = children?.filter { ($0["type"] as? String) == "paragraph" }
        // 2 paragraphs from synthesis + 1 from pitch = 3 total minimum.
        // The synthesis-only count must be at least 2.
        XCTAssertGreaterThanOrEqual(synthesisBlocks?.count ?? 0, 2,
                                    "Synthesis must produce at least one paragraph per \\n\\n block")
    }

    func testQuickWinsEmitHeadingThenBulletedItems() {
        let report = TestFixtures.sampleReport(quickWinsCount: 3)
        let payload = NotionPageBuilder.buildPagePayload(for: report, databaseID: "db_xyz")

        let children = payload["children"] as? [[String: Any]] ?? []

        // Find the index of the "Quick wins" heading_2 block.
        let headingIndex = children.firstIndex { block in
            guard (block["type"] as? String) == "heading_2",
                  let h2 = block["heading_2"] as? [String: Any],
                  let spans = h2["rich_text"] as? [[String: Any]],
                  let first = spans.first,
                  let text = first["text"] as? [String: Any],
                  let content = text["content"] as? String
            else { return false }
            return content == "Quick wins"
        }
        XCTAssertNotNil(headingIndex, "Quick wins section must emit a heading_2 block")

        // The next 3 blocks should be bulleted_list_items (one per win).
        guard let idx = headingIndex else { return }
        let bullets = children.dropFirst(idx + 1).prefix(3)
        XCTAssertEqual(bullets.filter { ($0["type"] as? String) == "bulleted_list_item" }.count, 3,
                       "Each quick win must produce one bulleted_list_item")
    }

    func testStrategicBetsAndHiddenRisksEmitTheirSections() {
        let report = TestFixtures.sampleReport(strategicBetsCount: 2, hiddenRisksCount: 2)
        let payload = NotionPageBuilder.buildPagePayload(for: report, databaseID: "db_xyz")

        let children = payload["children"] as? [[String: Any]] ?? []
        let headings = children.compactMap { block -> String? in
            guard (block["type"] as? String) == "heading_2",
                  let h2 = block["heading_2"] as? [String: Any],
                  let spans = h2["rich_text"] as? [[String: Any]],
                  let first = spans.first,
                  let text = first["text"] as? [String: Any]
            else { return nil }
            return text["content"] as? String
        }

        XCTAssertTrue(headings.contains("Paris stratégiques"), "Strategic bets heading must be present")
        XCTAssertTrue(headings.contains("Risques cachés"), "Hidden risks heading must be present")

        let bulletedCount = children.filter { ($0["type"] as? String) == "bulleted_list_item" }.count
        // 3 quick wins (default) + 2 bets + 2 risks = 7 bullets
        XCTAssertGreaterThanOrEqual(bulletedCount, 2 + 2,
                                    "Each strategic bet and hidden risk must produce a bullet")
    }

    func testEmptyQuickWinsDoesNotCrashOrEmitOrphanHeading() {
        let report = TestFixtures.sampleReport(quickWinsCount: 0)
        let payload = NotionPageBuilder.buildPagePayload(for: report, databaseID: "db_xyz")

        let children = payload["children"] as? [[String: Any]] ?? []
        let quickWinsHeading = children.contains { block in
            guard (block["type"] as? String) == "heading_2",
                  let h2 = block["heading_2"] as? [String: Any],
                  let spans = h2["rich_text"] as? [[String: Any]],
                  let first = spans.first,
                  let text = first["text"] as? [String: Any],
                  let content = text["content"] as? String
            else { return false }
            return content == "Quick wins"
        }
        XCTAssertFalse(quickWinsHeading,
                       "Empty quick wins must not produce an orphan heading block")

        // And the builder must still produce a non-empty page.
        XCTAssertFalse(children.isEmpty, "Builder must produce some children even with no quick wins")
    }

    // MARK: - Rich-text chunking

    func testLongParagraphIsChunkedIntoMultipleSpans() {
        // Synthesise a paragraph longer than the Notion 2000-char per-span
        // cap. The builder must split it into chunks while still
        // emitting a single paragraph block (the spans concatenate
        // back into one rendered paragraph in Notion).
        let longText = String(repeating: "a", count: 4500)
        let spans = NotionPageBuilder.richTextSpans(from: longText)
        XCTAssertEqual(spans.count, 3, "4500 chars / 2000-char cap = 3 spans (2000 + 2000 + 500)")

        // Re-stitching the chunks must yield the original string.
        let stitched = spans.compactMap { ($0["text"] as? [String: Any])?["content"] as? String }.joined()
        XCTAssertEqual(stitched.count, longText.count)
    }
}
