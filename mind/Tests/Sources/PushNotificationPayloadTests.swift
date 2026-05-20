import XCTest
@testable import MIND

/// v1.0-alpha.14 — Locks the pure parse + truncate contract the NSE
/// (`NotificationService`) and the App-side mirror (`PushPayloadParser`)
/// both observe. The NSE lives in an extension target that the test
/// bundle can't `@testable import`, so these tests exercise the
/// `PushPayloadParser` copy that ships with the App target; the NSE
/// keeps a byte-equivalent copy of the same logic so both surfaces
/// stay locked behind one suite.
final class PushNotificationPayloadTests: XCTestCase {

    // MARK: - parse(userInfo:) field extraction

    /// A fully-populated lead userInfo extracts every relevant field
    /// without applying any fallback default.
    func test_parse_extractsContactNameProjectNameProjectIDAndMessage() {
        let userInfo: [AnyHashable: Any] = [
            "lead": [
                "id": "test-id",
                "contactName": "Sarah Demo",
                "projectName": "AZ Construction",
                "projectID": "C3F8D2A8-7B7A-4C39-8C66-7BCCD2FBE40B",
                "messagePreview": "Bonjour Mehdi, votre site m'intéresse pour notre lancement.",
            ],
        ]
        let parsed = PushPayloadParser.parse(userInfo: userInfo)
        XCTAssertEqual(parsed?.contactName, "Sarah Demo")
        XCTAssertEqual(parsed?.projectName, "AZ Construction")
        XCTAssertEqual(parsed?.projectID, "C3F8D2A8-7B7A-4C39-8C66-7BCCD2FBE40B")
        XCTAssertEqual(parsed?.messagePreview, "Bonjour Mehdi, votre site m'intéresse pour notre lancement.")
    }

    /// Missing `contactName` falls back to "Nouveau lead" so the
    /// banner still reads cleanly.
    func test_parse_missingContactName_fallsBackToNouveauLead() {
        let userInfo: [AnyHashable: Any] = [
            "lead": [
                "projectName": "AZ Construction",
                "projectID": "proj-1",
                "messagePreview": "Bonjour",
            ],
        ]
        let parsed = PushPayloadParser.parse(userInfo: userInfo)
        XCTAssertEqual(parsed?.contactName, "Nouveau lead")
    }

    /// Missing `projectID` defaults to "unknown" so the NSE can still
    /// build a stable threadIdentifier.
    func test_parse_missingProjectID_fallsBackToUnknown() {
        let userInfo: [AnyHashable: Any] = [
            "lead": [
                "contactName": "Sarah Demo",
                "projectName": "AZ Construction",
            ],
        ]
        let parsed = PushPayloadParser.parse(userInfo: userInfo)
        XCTAssertEqual(parsed?.projectID, "unknown")
    }

    /// A messagePreview longer than 120 chars gets truncated at the
    /// last whitespace boundary before the cap, plus the ellipsis.
    func test_truncate_longMessage_isCutAt120CharsWithEllipsis() {
        let longBody = String(repeating: "Bonjour Mehdi, ", count: 30) // ~450 chars
        let trimmed = PushPayloadParser.truncate(longBody, to: 120)
        XCTAssertLessThanOrEqual(trimmed.count, 121, "Truncated string includes ellipsis but stays close to limit.")
        XCTAssertTrue(trimmed.hasSuffix("…"))
    }

    /// When the worker omits `messagePreview` but includes the legacy
    /// `message` field, the parser falls back to it.
    func test_parse_missingPreview_fallsBackToMessage() {
        let userInfo: [AnyHashable: Any] = [
            "lead": [
                "contactName": "Sarah Demo",
                "projectID": "proj-1",
                "message": "Bonjour, j'ai besoin d'un site rapidement.",
            ],
        ]
        let parsed = PushPayloadParser.parse(userInfo: userInfo)
        XCTAssertEqual(parsed?.messagePreview, "Bonjour, j'ai besoin d'un site rapidement.")
    }

    /// An empty userInfo (no `lead`, no `aps.payload`) returns nil so
    /// the NSE knows to fall back to the raw alert.
    func test_parse_emptyUserInfo_returnsNil() {
        let userInfo: [AnyHashable: Any] = [:]
        XCTAssertNil(PushPayloadParser.parse(userInfo: userInfo))
    }

    /// Backward-compatibility cushion: lead dict nested under
    /// `aps.payload` (the legacy worker shape) is still parsed.
    func test_parse_nestedUnderApsPayload_isAccepted() {
        let userInfo: [AnyHashable: Any] = [
            "aps": [
                "payload": [
                    "contactName": "Legacy",
                    "projectName": "Legacy Project",
                    "projectID": "legacy-1",
                    "messagePreview": "Old payload shape",
                ],
            ],
        ]
        let parsed = PushPayloadParser.parse(userInfo: userInfo)
        XCTAssertEqual(parsed?.contactName, "Legacy")
        XCTAssertEqual(parsed?.projectName, "Legacy Project")
        XCTAssertEqual(parsed?.projectID, "legacy-1")
    }

    /// Whitespace-only fields collapse to their fallbacks — defensive
    /// against a worker bug that ships `" "` instead of `null`.
    func test_parse_whitespaceFields_useFallbacks() {
        let userInfo: [AnyHashable: Any] = [
            "lead": [
                "contactName": "   ",
                "projectName": "\n\t ",
                "projectID": " ",
                "messagePreview": "   Hello   ",
            ],
        ]
        let parsed = PushPayloadParser.parse(userInfo: userInfo)
        XCTAssertEqual(parsed?.contactName, "Nouveau lead")
        XCTAssertEqual(parsed?.projectName, "")
        XCTAssertEqual(parsed?.projectID, "unknown")
        // messagePreview is trimmed but kept (non-fallback)
        XCTAssertEqual(parsed?.messagePreview, "Hello")
    }
}
