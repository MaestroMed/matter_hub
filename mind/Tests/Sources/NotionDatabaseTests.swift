import XCTest
@testable import NotionKit

/// v1.2.0 — Locks the Codable round-trip + Identifiable conformance
/// of the new bidirectional value types: NotionDatabase, NotionPage,
/// NotionBlock, NotionDatabaseFilter, NotionImportMapping. Six tests
/// covering all four types + the Equatable contract.
final class NotionDatabaseTests: XCTestCase {

    func test_notionDatabase_codableRoundTrip() throws {
        let original = NotionDatabase(
            id: "abc123",
            title: "Clients Numelite",
            icon: "🗂️",
            lastEditedAt: Date(timeIntervalSince1970: 1_716_000_000),
            propertyNames: ["Name", "Status", "Owner"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotionDatabase.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, "abc123",
                       "Identifiable conformance must surface the Notion UUID.")
    }

    func test_notionPage_codableRoundTrip() throws {
        let original = NotionPage(
            id: "page42",
            title: "Sarah Ben",
            icon: nil,
            createdAt: Date(timeIntervalSince1970: 1_716_000_000),
            lastEditedAt: Date(timeIntervalSince1970: 1_716_001_000),
            properties: ["Email": "sarah@example.com", "Status": "Qualified"],
            url: "https://notion.so/page42",
            parentDatabaseID: "db_leads"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotionPage.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_notionBlock_codableRoundTrip() throws {
        let original = NotionBlock(
            id: "block1",
            type: "paragraph",
            plainText: "Hello world",
            depth: 0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotionBlock.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_notionDatabaseFilter_defaultComparator() {
        let filter = NotionDatabaseFilter(property: "Status", value: "Active")
        XCTAssertEqual(filter.comparator, "equals",
                       "Default comparator stays `equals` so the wizard's " +
                       "most common case (\"this column = that value\") works " +
                       "without an extra argument at every call site.")
    }

    func test_notionDatabaseFilter_explicitContains() {
        let filter = NotionDatabaseFilter(property: "Name", value: "Sarah", comparator: "contains")
        XCTAssertEqual(filter.comparator, "contains")
    }

    func test_notionImportMapping_codableRoundTrip() throws {
        let mapping = NotionImportMapping(
            targetNodeKind: .project,
            titlePropertyName: "Name",
            bodyPropertyName: "Description",
            confidence: 0.95,
            detectedFields: ["status": "detected"]
        )
        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(NotionImportMapping.self, from: data)
        XCTAssertEqual(decoded, mapping)
    }
}
