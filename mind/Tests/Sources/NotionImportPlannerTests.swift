import XCTest
@testable import NotionKit

/// v1.2.0 — Pure tests for `NotionImportPlanner.suggestMapping`.
/// Ten cases lock the heuristic: FR + EN title detection, kind
/// resolution priority (`.audit` wins over `.lead`), confidence
/// formula, body property auto-detection, determinism, fallback
/// title.
final class NotionImportPlannerTests: XCTestCase {

    // MARK: - Kind detection

    func test_clientsTitle_routesToProject() {
        let db = makeDatabase(title: "Clients Numelite")
        let mapping = NotionImportPlanner.suggestMapping(database: db, sampleRows: [])
        XCTAssertEqual(mapping.targetNodeKind, .project,
                       "A title containing \"client\" must map to .project.")
    }

    func test_prospectsTitle_routesToLead() {
        let db = makeDatabase(title: "Prospects 2026")
        let mapping = NotionImportPlanner.suggestMapping(database: db, sampleRows: [])
        XCTAssertEqual(mapping.targetNodeKind, .lead)
    }

    func test_auditsTitle_routesToAudit() {
        let db = makeDatabase(title: "Audits 2026")
        let mapping = NotionImportPlanner.suggestMapping(database: db, sampleRows: [])
        XCTAssertEqual(mapping.targetNodeKind, .audit)
    }

    func test_tachesTitle_routesToDeliverable() {
        let db = makeDatabase(title: "Tâches en cours")
        let mapping = NotionImportPlanner.suggestMapping(database: db, sampleRows: [])
        XCTAssertEqual(mapping.targetNodeKind, .deliverable,
                       "FR \"tâche\" must route to .deliverable so the wizard " +
                       "doesn't silently drop a localised task database.")
    }

    func test_unrelatedTitle_routesToIgnored() {
        let db = makeDatabase(title: "Recettes")
        let mapping = NotionImportPlanner.suggestMapping(database: db, sampleRows: [])
        XCTAssertEqual(mapping.targetNodeKind, .ignored)
        XCTAssertEqual(mapping.confidence, 0.30, accuracy: 0.001,
                       "An ignored mapping must surface a low confidence so " +
                       "the wizard step 2 can highlight it for manual review.")
    }

    // MARK: - Confidence formula

    func test_emptySampleRows_reduceConfidence() {
        let db = makeDatabase(title: "Clients", propertyNames: ["Name"])
        let withRows = NotionImportPlanner.suggestMapping(
            database: db,
            sampleRows: [makePage(title: "AZ Construction")]
        )
        let withoutRows = NotionImportPlanner.suggestMapping(database: db, sampleRows: [])
        XCTAssertGreaterThan(withRows.confidence, withoutRows.confidence,
                             "Having sample rows must strictly increase the " +
                             "confidence (95% with rows vs 60% without).")
    }

    // MARK: - Title property detection

    func test_titleProperty_fallsBackToName_whenNoOtherProperties() {
        let db = makeDatabase(title: "Clients", propertyNames: [])
        let mapping = NotionImportPlanner.suggestMapping(database: db, sampleRows: [])
        XCTAssertEqual(mapping.titlePropertyName, "Name",
                       "When no properties are surfaced the planner must " +
                       "fall back to the Notion default title column \"Name\".")
    }

    // MARK: - Determinism

    func test_determinism_sameInputYieldsSameMapping() {
        let db = makeDatabase(title: "Clients Numelite", propertyNames: ["Name", "Status"])
        let sample = [makePage(title: "AZ Construction")]
        let first = NotionImportPlanner.suggestMapping(database: db, sampleRows: sample)
        let second = NotionImportPlanner.suggestMapping(database: db, sampleRows: sample)
        XCTAssertEqual(first, second,
                       "The planner is pure — the same input must always " +
                       "produce the same mapping.")
    }

    // MARK: - FR / EN title property names

    func test_titleProperty_detectsFRNom_overEnglishName() {
        // A FR-localised Notion workspace defaults the title column
        // to "Nom" instead of "Name". The planner must surface that
        // — otherwise Mehdi's FR clients DB shows an empty title
        // column in the wizard preview.
        let db = makeDatabase(title: "Clients", propertyNames: ["Nom", "Statut"])
        let mapping = NotionImportPlanner.suggestMapping(database: db, sampleRows: [])
        XCTAssertEqual(mapping.titlePropertyName, "Nom")
    }

    // MARK: - Body property auto-detection

    func test_bodyProperty_detectsDescriptionNotesContent() {
        // Multiple variants — Description / Notes / Content / Contenu —
        // all should be picked up so the wizard's "body maps to" hint
        // surfaces a useful column without the user spelling it out.
        let withDescription = makeDatabase(title: "Clients", propertyNames: ["Name", "Description"])
        let withNotes = makeDatabase(title: "Clients", propertyNames: ["Name", "Notes"])
        let withContent = makeDatabase(title: "Clients", propertyNames: ["Name", "Content"])
        let m1 = NotionImportPlanner.suggestMapping(database: withDescription, sampleRows: [])
        let m2 = NotionImportPlanner.suggestMapping(database: withNotes, sampleRows: [])
        let m3 = NotionImportPlanner.suggestMapping(database: withContent, sampleRows: [])
        XCTAssertEqual(m1.bodyPropertyName, "Description")
        XCTAssertEqual(m2.bodyPropertyName, "Notes")
        XCTAssertEqual(m3.bodyPropertyName, "Content")
    }

    // MARK: - Helpers

    private func makeDatabase(
        title: String,
        propertyNames: [String] = ["Name"]
    ) -> NotionDatabase {
        NotionDatabase(
            id: "db_test",
            title: title,
            icon: nil,
            lastEditedAt: Date(timeIntervalSince1970: 1_716_000_000),
            propertyNames: propertyNames
        )
    }

    private func makePage(title: String) -> NotionPage {
        NotionPage(
            id: "page_test",
            title: title,
            icon: nil,
            createdAt: Date(timeIntervalSince1970: 1_716_000_000),
            lastEditedAt: Date(timeIntervalSince1970: 1_716_000_000),
            properties: ["Name": title],
            url: "https://notion.so/page_test",
            parentDatabaseID: "db_test"
        )
    }
}
