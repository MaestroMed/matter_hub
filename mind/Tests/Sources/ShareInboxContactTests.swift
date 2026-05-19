import XCTest
import Contacts
@testable import GraphCore

/// Locks the v0.13 Contacts integration contract. Two layers under
/// test:
///
///   1. The framework-free `ShareInbox.Payload.contactPayload(...)`
///      pure factory, fed the kind of fields the Share Extension
///      pulls off `CNContactVCardSerialization.contacts(with:)`.
///   2. The codable round-trip of `Payload(kind: .contact)` through
///      the on-disk JSON queue — older shipped payloads (no `kind`
///      key) must still decode as `.link` so a host-update / ext-
///      update mismatch never drops a share.
///
/// The vCard string fixture mirrors what `CNContactVCardSerialization`
/// emits for a typical Contacts.app share. We round-trip it through
/// `contacts(with:)` once to confirm parsing works on-device, then
/// drive the rest of the assertions off the pure builder so the
/// suite is hermetic.
final class ShareInboxContactTests: XCTestCase {

    private var queueURL: URL!

    override func setUp() {
        super.setUp()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareInboxContactTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        queueURL = directory.appendingPathComponent("ShareInbox.json")
    }

    override func tearDown() {
        if let queueURL {
            try? FileManager.default.removeItem(
                at: queueURL.deletingLastPathComponent()
            )
        }
        queueURL = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A reasonably realistic vCard (4.0) — name + email + phone +
    /// company. iOS's `CNContactVCardSerialization` is tolerant on
    /// version so this still round-trips on iOS 26 simulators.
    private let fullVCard = """
    BEGIN:VCARD
    VERSION:3.0
    N:Doe;Jane;;;
    FN:Jane Doe
    ORG:Acme;
    EMAIL;type=INTERNET;type=WORK:jane.doe@acme.com
    EMAIL;type=INTERNET;type=HOME:jane@personal.test
    TEL;type=CELL:+15551234567
    END:VCARD
    """

    private let emailOnlyVCard = """
    BEGIN:VCARD
    VERSION:3.0
    N:;;;;
    FN:
    EMAIL;type=INTERNET:hello@example.com
    END:VCARD
    """

    private let emptyVCard = """
    BEGIN:VCARD
    VERSION:3.0
    N:;;;;
    FN:
    END:VCARD
    """

    private func parseFirst(_ vcard: String) -> CNContact? {
        guard let data = vcard.data(using: .utf8) else { return nil }
        return (try? CNContactVCardSerialization.contacts(with: data))?.first
    }

    // MARK: - Pure builder — full vCard

    /// Acceptance criterion: a contact share with name + email + phone
    /// + company produces a `Payload(kind: .contact)` carrying all the
    /// fields the host turns into a Node. The first email is the
    /// primary attendee, both emails are preserved in `attendees`, and
    /// the title is the formatted full name.
    func test_contactPayload_withFullVCardFields_populatesAllSlots() {
        guard let contact = parseFirst(fullVCard) else {
            XCTFail("CNContactVCardSerialization should parse a vCard 3.0 fixture")
            return
        }

        let emails = contact.emailAddresses.map { String($0.value) }
        let phones = contact.phoneNumbers.map { $0.value.stringValue }
        let organization = contact.organizationName
        let fullName = CNContactFormatter.string(from: contact, style: .fullName)

        let payload = ShareInbox.Payload.contactPayload(
            fullName: fullName,
            emails: emails,
            phones: phones,
            organization: organization
        )

        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.kind, .contact)
        XCTAssertEqual(payload?.title, "Jane Doe")
        XCTAssertEqual(payload?.attendees?.first, "jane.doe@acme.com")
        XCTAssertEqual(payload?.attendees?.count, 2)
        // Content body should mention every field the user supplied.
        let body = payload?.contentBody ?? ""
        XCTAssertTrue(body.contains("jane.doe@acme.com"))
        XCTAssertTrue(body.contains("jane@personal.test"))
        XCTAssertTrue(body.contains("+15551234567"))
        XCTAssertTrue(body.contains("Acme"))
    }

    // MARK: - Pure builder — fallback chain

    /// A vCard with only an email (no `FN`, no `ORG`) must still
    /// produce a Node — title falls back to the email address so the
    /// user sees something useful instead of "Untitled".
    func test_contactPayload_withOnlyEmail_fallsBackToEmailAsTitle() {
        let payload = ShareInbox.Payload.contactPayload(
            fullName: nil,
            emails: ["hello@example.com"],
            phones: [],
            organization: ""
        )
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.title, "hello@example.com")
        XCTAssertEqual(payload?.attendees, ["hello@example.com"])
    }

    /// Multiple emails: the first survives as the "primary" attendee,
    /// the rest are preserved in source order. The host uses
    /// `primaryEmailDomain` to tag the resulting Node with the
    /// company domain.
    func test_contactPayload_withMultipleEmails_keepsFirstAsPrimary() {
        let payload = ShareInbox.Payload.contactPayload(
            fullName: "Multi Email",
            emails: ["primary@first.com", "backup@second.com", "third@last.io"],
            phones: [],
            organization: ""
        )
        XCTAssertEqual(payload?.attendees?.first, "primary@first.com")
        XCTAssertEqual(payload?.attendees?.count, 3)
        XCTAssertEqual(payload?.primaryEmailDomain, "first.com")
    }

    /// A vCard with literally no identifying info (no name, no
    /// email, no company) returns `nil` rather than crashing or
    /// producing an empty Node. The Share Extension drops the
    /// payload on the floor so the host's queue isn't polluted.
    func test_contactPayload_withNoIdentifyingInfo_returnsNil() {
        let payload = ShareInbox.Payload.contactPayload(
            fullName: nil,
            emails: [],
            phones: [],
            organization: ""
        )
        XCTAssertNil(payload)
    }

    /// An empty vCard either fails to parse (returns no CNContact)
    /// or parses to a CNContact with empty fields — either way the
    /// builder must reject it instead of producing a "Untitled" Node.
    /// We exercise the builder branch directly here (the parser
    /// branch is implicitly covered by the other two vCard tests).
    func test_contactPayload_fromEmptyVCard_returnsNil() {
        // Drive the equivalent of an empty CNContact through the
        // pure builder. CNContactVCardSerialization is allowed to
        // either return an empty array OR a placeholder contact —
        // both branches converge on `nil` here.
        if let contact = parseFirst(emptyVCard) {
            let fullName = CNContactFormatter.string(from: contact, style: .fullName)
            let payload = ShareInbox.Payload.contactPayload(
                fullName: fullName,
                emails: contact.emailAddresses.map { String($0.value) },
                phones: contact.phoneNumbers.map { $0.value.stringValue },
                organization: contact.organizationName
            )
            XCTAssertNil(payload, "Empty vCard contact should not produce a payload")
        } else {
            // Parser dropped it on the floor — also acceptable.
            // Confirm the pure builder agrees an all-empty input
            // produces no payload.
            let payload = ShareInbox.Payload.contactPayload(
                fullName: nil,
                emails: [],
                phones: [],
                organization: ""
            )
            XCTAssertNil(payload)
        }
    }

    /// An email-only vCard goes through the parser cleanly and
    /// surfaces the email as the title.
    func test_contactPayload_fromEmailOnlyVCard_usesEmailAsTitle() {
        guard let contact = parseFirst(emailOnlyVCard) else {
            XCTFail("CNContactVCardSerialization should parse a vCard with an EMAIL field")
            return
        }
        let fullName = CNContactFormatter.string(from: contact, style: .fullName)
        let payload = ShareInbox.Payload.contactPayload(
            fullName: fullName,
            emails: contact.emailAddresses.map { String($0.value) },
            phones: [],
            organization: ""
        )
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.title, "hello@example.com")
        XCTAssertEqual(payload?.attendees?.first, "hello@example.com")
    }

    // MARK: - Email domain extraction

    /// `john@acme.com` → `acme.com`. Used by the host to tag the
    /// resulting `person` Node with the company domain so a search
    /// across NotesView surfaces the contact when the user is
    /// browsing prospects from that company.
    func test_emailDomain_extractsLowercasedHost() {
        XCTAssertEqual(ShareInbox.Payload.emailDomain(from: "John@Acme.COM"), "acme.com")
        XCTAssertEqual(ShareInbox.Payload.emailDomain(from: " jane@personal.test "), "personal.test")
    }

    /// Malformed addresses (no `@`) return nil rather than crashing.
    /// The drain handler treats nil as "no tag" — the Node still gets
    /// created, just without the domain tag.
    func test_emailDomain_returnsNilForMalformedAddress() {
        XCTAssertNil(ShareInbox.Payload.emailDomain(from: "no-at-sign"))
        XCTAssertNil(ShareInbox.Payload.emailDomain(from: "trailing@"))
    }

    // MARK: - JSON codable round-trip (backward compatibility)

    /// Contact payloads round-trip through the on-disk JSON queue
    /// (the cross-process bridge between the extension and the host).
    /// All four contact-specific fields (`kind`, `title`, `content`,
    /// `attendees`) survive enqueue → drain unchanged.
    func test_contactPayload_roundTripsThroughJSONQueue() {
        let original = ShareInbox.Payload.contactPayload(
            fullName: "Round Trip",
            emails: ["rt@example.com"],
            phones: ["+15555555555"],
            organization: "Loop Co",
            userComment: "Met at conf",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )!

        XCTAssertTrue(ShareInbox.enqueue(original, at: queueURL))
        let drained = ShareInbox.drain(at: queueURL)

        XCTAssertEqual(drained.count, 1)
        let restored = drained.first
        XCTAssertEqual(restored?.kind, .contact)
        XCTAssertEqual(restored?.title, "Round Trip")
        XCTAssertEqual(restored?.attendees, ["rt@example.com"])
        XCTAssertEqual(restored?.id, original.id)
        let body = restored?.contentBody ?? ""
        XCTAssertTrue(body.contains("rt@example.com"))
        XCTAssertTrue(body.contains("+15555555555"))
        XCTAssertTrue(body.contains("Loop Co"))
        XCTAssertTrue(body.contains("Met at conf"))
    }

    /// Backward compatibility: a payload serialised by the v0.3 →
    /// v0.12 extension (no `kind` key, no contact-specific fields)
    /// decodes cleanly as a `.link` payload. A host build that ships
    /// after a stale extension still drains pre-existing queue
    /// entries instead of crashing the JSON decoder.
    func test_legacyJSONWithoutKindKey_decodesAsLinkPayload() throws {
        let legacyJSON = """
        [
          {
            "id" : "11111111-2222-3333-4444-555566667777",
            "url" : "https://stripe.com/pricing",
            "text" : "old extension payload",
            "capturedAt" : "2025-12-01T08:00:00Z"
          }
        ]
        """.data(using: .utf8)!

        try legacyJSON.write(to: queueURL)
        let drained = ShareInbox.drain(at: queueURL)

        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained.first?.kind, .link)
        XCTAssertEqual(drained.first?.url, URL(string: "https://stripe.com/pricing"))
        XCTAssertEqual(drained.first?.text, "old extension payload")
        XCTAssertNil(drained.first?.attendees)
        XCTAssertNil(drained.first?.title)
    }

    // MARK: - Title/body accessors for contact payloads

    /// `titleCandidate` prefers the explicit title (full name) over
    /// the URL host fallback — link payloads still use the URL host,
    /// contact payloads must use the human-readable name.
    func test_titleCandidate_prefersContactTitleOverFallbacks() {
        let payload = ShareInbox.Payload(
            kind: .contact,
            title: "Jane Doe",
            content: "jane@acme.com",
            attendees: ["jane@acme.com"]
        )
        XCTAssertEqual(payload.titleCandidate, "Jane Doe")
    }

    /// `contentBody` uses the pre-rendered `content` from contact
    /// payloads rather than rebuilding from URL+text (which are nil
    /// for contacts).
    func test_contentBody_usesPreRenderedContactContent() {
        let payload = ShareInbox.Payload(
            kind: .contact,
            title: "Jane Doe",
            content: "jane@acme.com\n+15551234567\nAcme",
            attendees: ["jane@acme.com"]
        )
        XCTAssertEqual(payload.contentBody, "jane@acme.com\n+15551234567\nAcme")
    }
}
