import XCTest
@testable import GraphCore

/// v1.0-alpha.2 — Locks the Cockpit Studio `Lead` @Model: init
/// defaults, status enum round-trip + timestamp side-effect,
/// formType enum round-trip with `.other` fallback, optional
/// fields (`draftReply`, `contactPhone`, `clientIPHash`,
/// `userAgent`, `statusReason`) round-trip correctly.
@MainActor
final class LeadModelTests: XCTestCase {

    // MARK: - Init / defaults

    /// A bare Lead carries `.new` status, `.contact` form type,
    /// empty strings, nil optionals — exactly the shape an
    /// incoming webhook would post if every optional field was
    /// missing.
    func test_init_defaultsAreDocumented() {
        let lead = Lead()
        XCTAssertEqual(lead.statusEnum, .new,
                       "Default status is .new — every freshly arrived " +
                       "lead must hit the HomeView inbox.")
        XCTAssertEqual(lead.formTypeEnum, .contact,
                       "Default form type is .contact — the most common " +
                       "form on Numelite sites.")
        XCTAssertEqual(lead.contactName, "")
        XCTAssertEqual(lead.contactEmail, "")
        XCTAssertEqual(lead.message, "")
        XCTAssertEqual(lead.rawPayload, "")
        XCTAssertEqual(lead.sourceURL, "")
        XCTAssertNil(lead.contactPhone)
        XCTAssertNil(lead.statusReason)
        XCTAssertNil(lead.draftReply)
        XCTAssertNil(lead.clientIPHash)
        XCTAssertNil(lead.userAgent)
        XCTAssertNil(lead.project)
    }

    /// All explicit init arguments persist verbatim — round-trip
    /// guards against a stray `self.X = X` typo silently dropping
    /// a value.
    func test_init_allArgumentsPersist() {
        let now = Date()
        let lead = Lead(
            receivedAt: now,
            sourceURL: "https://www.azconstruction.fr/contact",
            formType: .devis,
            contactName: "Alice",
            contactEmail: "alice@example.com",
            contactPhone: "+33 6 12 34 56 78",
            message: "Hello",
            rawPayload: #"{"foo":"bar"}"#,
            status: .qualified,
            statusUpdatedAt: now,
            statusReason: nil,
            draftReply: "Bonjour Alice,",
            clientIPHash: "deadbeef",
            userAgent: "Mozilla/5.0"
        )
        XCTAssertEqual(lead.receivedAt, now)
        XCTAssertEqual(lead.sourceURL, "https://www.azconstruction.fr/contact")
        XCTAssertEqual(lead.formTypeEnum, .devis)
        XCTAssertEqual(lead.contactName, "Alice")
        XCTAssertEqual(lead.contactEmail, "alice@example.com")
        XCTAssertEqual(lead.contactPhone, "+33 6 12 34 56 78")
        XCTAssertEqual(lead.message, "Hello")
        XCTAssertEqual(lead.rawPayload, #"{"foo":"bar"}"#)
        XCTAssertEqual(lead.statusEnum, .qualified)
        XCTAssertEqual(lead.draftReply, "Bonjour Alice,")
        XCTAssertEqual(lead.clientIPHash, "deadbeef")
        XCTAssertEqual(lead.userAgent, "Mozilla/5.0")
    }

    // MARK: - Status transitions

    /// Setting `statusEnum` writes through to the raw String and
    /// rewrites `statusUpdatedAt` to now. Locks the side-effect
    /// the HomeView "Récemment touchés" list depends on.
    func test_statusEnum_setter_writesRawAndRefreshesTimestamp() async throws {
        let lead = Lead(statusUpdatedAt: .distantPast)
        XCTAssertEqual(lead.statusUpdatedAt, .distantPast)
        try await Task.sleep(nanoseconds: 5_000_000)
        lead.statusEnum = .contacted
        XCTAssertEqual(lead.status, "contacted")
        XCTAssertEqual(lead.statusEnum, .contacted)
        XCTAssertGreaterThan(lead.statusUpdatedAt, .distantPast,
                             "Status setter must refresh statusUpdatedAt so " +
                             "the inbox sort stays accurate.")
    }

    /// Every status value round-trips through the raw String —
    /// nothing silently drops to a default.
    func test_statusEnum_everyCase_roundTrips() {
        let lead = Lead()
        for status in LeadStatus.allCases {
            lead.statusEnum = status
            XCTAssertEqual(lead.statusEnum, status)
        }
    }

    /// Unknown raw status values fall back to `.new` rather than
    /// crashing — surfacing a freshly-arrived lead as "to review"
    /// is the safest assumption when an unknown status shows up.
    func test_statusEnum_unknownRaw_fallsBackToNew() {
        let lead = Lead()
        lead.status = "neverHeardOfIt"
        XCTAssertEqual(lead.statusEnum, .new)
    }

    /// `.lost` and `.spam` accept a `statusReason` — the Cockpit's
    /// retro-review surface relies on this field surviving the
    /// round-trip from the lose-reason dialog.
    func test_statusReason_nullableRoundTrip() {
        let lead = Lead(status: .lost, statusReason: "budget out of reach")
        XCTAssertEqual(lead.statusEnum, .lost)
        XCTAssertEqual(lead.statusReason, "budget out of reach")
        lead.statusReason = nil
        XCTAssertNil(lead.statusReason)
    }

    // MARK: - Form type

    /// Every formType value round-trips identically through the
    /// raw String.
    func test_formTypeEnum_everyCase_roundTrips() {
        let lead = Lead()
        for formType in LeadFormType.allCases {
            lead.formTypeEnum = formType
            XCTAssertEqual(lead.formTypeEnum, formType)
        }
    }

    /// Unknown raw formType values fall back to `.other` so a
    /// future custom form lands in the generic bucket rather than
    /// misrouting to `.contact`.
    func test_formTypeEnum_unknownRaw_fallsBackToOther() {
        let lead = Lead()
        lead.formType = "audit-request"
        XCTAssertEqual(lead.formTypeEnum, .other,
                       "Unknown formType raw values must surface as " +
                       "`.other` to avoid misrouting to `.contact`.")
    }

    // MARK: - Optional fields

    /// `draftReply` is nullable and round-trips both directions —
    /// the Wave C inbox surfaces a "Brouillon prêt" chip only when
    /// this is set.
    func test_draftReply_nullableRoundTrip() {
        let lead = Lead()
        XCTAssertNil(lead.draftReply)
        lead.draftReply = "Bonjour Alice, merci pour ton message…"
        XCTAssertEqual(lead.draftReply, "Bonjour Alice, merci pour ton message…")
        lead.draftReply = nil
        XCTAssertNil(lead.draftReply)
    }

    /// `clientIPHash` is nullable and round-trips both directions —
    /// the privacy contract requires hashed IPs only, never raw.
    func test_clientIPHash_nullableRoundTrip() {
        let lead = Lead()
        XCTAssertNil(lead.clientIPHash)
        lead.clientIPHash = String(repeating: "a", count: 64)
        XCTAssertEqual(lead.clientIPHash?.count, 64)
        lead.clientIPHash = nil
        XCTAssertNil(lead.clientIPHash)
    }
}
