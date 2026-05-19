import XCTest
import CoreSpotlight
import UniformTypeIdentifiers
@testable import GraphCore

/// Verifies the contract between Node and the CSSearchableItem
/// shipped to iOS Spotlight. We never hit the real index in tests —
/// just inspect the pure mapping. If any of these break, a Spotlight
/// row stops opening the right NodeDetailView (deep-link via
/// `uniqueIdentifier`) or stops surfacing the right keywords.
final class SpotlightIndexerTests: XCTestCase {

    // MARK: - Identifiers

    func test_makeSearchableItem_usesUUIDStringAsUniqueIdentifier() {
        let node = makeNode(kind: .note, title: "Hello")
        let item = SpotlightIndexer.makeSearchableItem(for: node)
        XCTAssertEqual(item.uniqueIdentifier, node.id.uuidString,
                       "Deep-link contract requires uniqueIdentifier == node.id.uuidString")
    }

    func test_makeSearchableItem_setsExpectedDomainIdentifier() {
        let item = SpotlightIndexer.makeSearchableItem(for: makeNode(kind: .note))
        XCTAssertEqual(item.domainIdentifier, SpotlightIndexer.domainIdentifier)
        XCTAssertEqual(item.domainIdentifier, "app.mind.ios.nodes",
                       "domainIdentifier is matched by Settings → Reset Spotlight, must not drift")
    }

    // MARK: - Attribute set

    func test_makeSearchableItem_setsTitleAndDisplayName() {
        let node = makeNode(kind: .client, title: "Stripe")
        let item = SpotlightIndexer.makeSearchableItem(for: node)
        XCTAssertEqual(item.attributeSet.title, "Stripe")
        XCTAssertEqual(item.attributeSet.displayName, "Stripe")
    }

    func test_makeSearchableItem_truncatesContentTo500Chars() {
        // 800-char body, should be capped at 500.
        let body = String(repeating: "a", count: 800)
        let node = makeNode(kind: .note, title: "Long", content: body)
        let item = SpotlightIndexer.makeSearchableItem(for: node)
        XCTAssertEqual(item.attributeSet.contentDescription?.count, 500,
                       "Snippet must be capped to keep the on-disk index lean")
    }

    func test_makeSearchableItem_keywordsContainTagsAndKindRaw() {
        let node = makeNode(
            kind: .client,
            title: "Stripe",
            tags: ["fintech", "prospect"]
        )
        let item = SpotlightIndexer.makeSearchableItem(for: node)
        let keywords = item.attributeSet.keywords ?? []
        XCTAssertTrue(keywords.contains("fintech"))
        XCTAssertTrue(keywords.contains("prospect"))
        XCTAssertTrue(keywords.contains("client"),
                      "kindRaw boosts recall when the user types the category instead of a name")
    }

    func test_makeSearchableItem_setsCreationAndModificationDates() {
        let node = makeNode(kind: .note, title: "T")
        let item = SpotlightIndexer.makeSearchableItem(for: node)
        XCTAssertEqual(item.attributeSet.contentCreationDate, node.createdAt)
        XCTAssertEqual(item.attributeSet.contentModificationDate, node.updatedAt)
    }

    func test_makeSearchableItem_expirationDateIsDistantFuture() {
        let item = SpotlightIndexer.makeSearchableItem(for: makeNode(kind: .note))
        XCTAssertEqual(item.expirationDate, .distantFuture,
                       "We want iOS to evict on storage pressure, not on a fixed TTL")
    }

    // MARK: - Content type mapping

    func test_contentType_maps_note_to_plainText() {
        XCTAssertEqual(SpotlightIndexer.contentType(for: .note), .plainText)
        XCTAssertEqual(SpotlightIndexer.contentType(for: .journal), .plainText)
        XCTAssertEqual(SpotlightIndexer.contentType(for: .idea), .plainText)
        XCTAssertEqual(SpotlightIndexer.contentType(for: .capture), .plainText)
    }

    func test_contentType_maps_person_and_client_to_contact() {
        XCTAssertEqual(SpotlightIndexer.contentType(for: .person), .contact)
        XCTAssertEqual(SpotlightIndexer.contentType(for: .client), .contact)
    }

    func test_contentType_maps_event_to_calendarEvent() {
        XCTAssertEqual(SpotlightIndexer.contentType(for: .event), .calendarEvent)
    }

    func test_contentType_maps_audit_to_pdf() {
        XCTAssertEqual(SpotlightIndexer.contentType(for: .audit), .pdf,
                       "Audit nodes carry a PDF export so Spotlight shows the right icon")
    }

    func test_contentType_maps_file_to_data() {
        XCTAssertEqual(SpotlightIndexer.contentType(for: .file), .data)
    }

    // MARK: - Helpers

    private func makeNode(
        kind: NodeKind,
        title: String = "Sample",
        content: String = "",
        tags: [String] = []
    ) -> Node {
        Node(kind: kind, title: title, content: content, tags: tags)
    }
}
