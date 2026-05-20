import XCTest
@testable import GraphCore

/// Locks the v0.14 Mail capture contract. Three layers under test:
///
///   1. `MailParser.parse(rawText:)` — pure header/body extraction.
///      Handles the canonical RFC 822 envelope (`From:` / `Subject:`
///      / `Date:` / blank line / body), tolerates missing fields,
///      and degrades gracefully when there's no envelope at all.
///   2. `ShareInbox.Payload.mailPayload(rawText:userComment:)` — pure
///      factory wired into the Share Extension's mail branch. Builds
///      the cross-process payload the host drains into a `mail` Node.
///   3. Codable round-trip of `Payload(kind: .mail)` through the
///      on-disk JSON queue, with the backward-compat path for older
///      payloads that don't carry the new kind value.
///
/// All tests are hermetic: parsing is framework-free, queue I/O
/// goes to an isolated temp file, and no Mail.app-private types
/// are imported.
final class ShareInboxMailTests: XCTestCase {

    private var queueURL: URL!

    override func setUp() {
        super.setUp()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareInboxMailTests-\(UUID().uuidString)")
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

    /// Canonical RFC 822 envelope — what Mail.app surfaces when the
    /// user picks "Share" on a message. Multi-line body, the From
    /// header carries both a display name and an angle-bracketed
    /// address, and there's a blank line separating headers from body.
    private let canonicalMail = """
    From: Jane Doe <jane@acme.com>
    Subject: Welcome to the beta
    Date: Mon, 13 May 2026 14:30:00 +0200
    To: john@example.com

    Hi John,

    Thanks for signing up. Here's what to expect this week.

    — Jane
    """

    /// Edge case: subject contains special characters (colon, em-dash,
    /// emoji-adjacent punctuation). The parser must not split on the
    /// embedded `:` — only the *first* colon on a header line is the
    /// name/value separator.
    private let mailWithSpecialSubject = """
    From: ops@example.com
    Subject: Q3: Heads-up — the deploy window shifts to 18:00 UTC

    Body text.
    """

    /// Edge case: the share carries a body but no From header (e.g.
    /// the user shared a draft from Mail.app's Drafts folder). The
    /// parser surfaces `nil` for the sender and the consumer falls
    /// back to the localised "Untitled email" string.
    private let mailWithoutFromHeader = """
    Subject: Reminder: stand-up at 10am

    Don't forget the stand-up.
    """

    /// Edge case: no envelope at all — the user shared a snippet of
    /// text from a forwarded email body. The parser must not crash,
    /// must surface no headers, and the consumer must keep the raw
    /// text intact in the body so nothing is lost.
    private let mailWithoutHeaders = """
    Hey,

    just FYI — we're moving the meeting to Friday.
    """

    // MARK: - MailParser — canonical envelope

    /// Acceptance criterion: a canonical RFC 822 share produces a
    /// parsed value with subject, sender email, sender display name,
    /// and a trimmed body. This is the happy path the v0.14
    /// acceptance criterion exercises end-to-end via the simulator.
    func test_parse_canonicalEnvelope_extractsAllFields() {
        let parsed = MailParser.parse(rawText: canonicalMail)

        XCTAssertEqual(parsed.subject, "Welcome to the beta")
        XCTAssertEqual(parsed.senderEmail, "jane@acme.com")
        XCTAssertEqual(parsed.senderDisplayName, "Jane Doe")
        XCTAssertTrue(parsed.body.hasPrefix("Hi John,"))
        XCTAssertTrue(parsed.body.contains("Thanks for signing up."))
        XCTAssertTrue(parsed.body.contains("— Jane"))
    }

    // MARK: - MailParser — header value parsing

    /// `From:` can carry just an email, an `<email>` form, a `display
    /// <email>` form, or a quoted display name. Lock each one so a
    /// future regression doesn't drop the sender domain (which we
    /// use to tag the resulting Node).
    func test_parse_fromHeader_recognisesEveryShape() {
        XCTAssertEqual(
            MailParser.parse(rawText: "From: jane@acme.com\n\nbody").senderEmail,
            "jane@acme.com"
        )
        let bracketed = MailParser.parse(
            rawText: "From: <jane@acme.com>\n\nbody"
        )
        XCTAssertEqual(bracketed.senderEmail, "jane@acme.com")
        XCTAssertNil(bracketed.senderDisplayName)

        let withName = MailParser.parse(
            rawText: "From: Jane Doe <jane@acme.com>\n\nbody"
        )
        XCTAssertEqual(withName.senderEmail, "jane@acme.com")
        XCTAssertEqual(withName.senderDisplayName, "Jane Doe")

        let quotedName = MailParser.parse(
            rawText: "From: \"Doe, Jane\" <jane@acme.com>\n\nbody"
        )
        XCTAssertEqual(quotedName.senderEmail, "jane@acme.com")
        XCTAssertEqual(quotedName.senderDisplayName, "Doe, Jane")
    }

    // MARK: - MailParser — subjects with embedded colons

    /// A subject like `Q3: Heads-up` contains a literal colon that
    /// must NOT be treated as a second header separator. The parser
    /// keeps the whole substring after the first colon as the value.
    func test_parse_subjectWithEmbeddedColon_isPreservedIntact() {
        let parsed = MailParser.parse(rawText: mailWithSpecialSubject)
        XCTAssertEqual(
            parsed.subject,
            "Q3: Heads-up — the deploy window shifts to 18:00 UTC"
        )
        XCTAssertEqual(parsed.senderEmail, "ops@example.com")
        XCTAssertEqual(parsed.body, "Body text.")
    }

    // MARK: - MailParser — graceful degradation

    /// Missing `From:` header: subject still resolves, sender comes
    /// back nil, body is intact. The consumer routes the nil sender
    /// to "no email domain tag" — Node still gets created.
    func test_parse_missingFromHeader_returnsNilSender() {
        let parsed = MailParser.parse(rawText: mailWithoutFromHeader)
        XCTAssertEqual(parsed.subject, "Reminder: stand-up at 10am")
        XCTAssertNil(parsed.senderEmail)
        XCTAssertEqual(parsed.body, "Don't forget the stand-up.")
    }

    /// No envelope at all: parser returns nil for every header,
    /// surfaces the raw text as the body. Critical safety net —
    /// the user must never lose content to an over-eager parse.
    func test_parse_textWithoutHeaders_treatsEverythingAsBody() {
        let parsed = MailParser.parse(rawText: mailWithoutHeaders)
        XCTAssertNil(parsed.subject)
        XCTAssertNil(parsed.senderEmail)
        // No header-shaped lines at all — the entire text is body.
        XCTAssertTrue(parsed.body.contains("just FYI"))
        XCTAssertTrue(parsed.body.contains("Hey,"))
    }

    // MARK: - mailPayload — pure factory

    /// `mailPayload` strings together MailParser + Payload assembly.
    /// Canonical envelope → kind `.mail`, title = subject,
    /// attendees = [sender], content = body. The host drainer reads
    /// every one of these.
    func test_mailPayload_canonicalEnvelope_populatesAllSlots() {
        let payload = ShareInbox.Payload.mailPayload(
            rawText: canonicalMail,
            userComment: ""
        )

        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.kind, .mail)
        XCTAssertEqual(payload?.title, "Welcome to the beta")
        XCTAssertEqual(payload?.attendees, ["jane@acme.com"])
        XCTAssertEqual(payload?.primaryEmailDomain, "acme.com")
        let body = payload?.contentBody ?? ""
        XCTAssertTrue(body.contains("Thanks for signing up."))
    }

    /// User typed a comment in the share sheet → it lands above the
    /// quoted body in the resulting Node so a "FYI" note shows
    /// before the email content in MarkdownView.
    func test_mailPayload_withUserComment_prependsCommentToBody() {
        let payload = ShareInbox.Payload.mailPayload(
            rawText: canonicalMail,
            userComment: "Suivi prospect Jane"
        )
        let body = payload?.contentBody ?? ""
        XCTAssertTrue(
            body.hasPrefix("Suivi prospect Jane"),
            "User comment should be the very first line of the body"
        )
        XCTAssertTrue(body.contains("Thanks for signing up."))
    }

    /// Empty input → nil payload. The Share Extension drops it on
    /// the floor rather than polluting the queue with an empty Node.
    func test_mailPayload_emptyInput_returnsNil() {
        XCTAssertNil(ShareInbox.Payload.mailPayload(rawText: "", userComment: ""))
        XCTAssertNil(ShareInbox.Payload.mailPayload(rawText: "   \n  \n", userComment: ""))
    }

    /// No headers + no body → still nil. Different code path from
    /// the empty-string case (the parser runs, finds nothing useful,
    /// and the factory rejects).
    func test_mailPayload_textWithoutHeaders_stillProducesPayload() {
        let payload = ShareInbox.Payload.mailPayload(
            rawText: mailWithoutHeaders,
            userComment: ""
        )
        // Even without an envelope, we keep the user's text intact
        // as the body so nothing is lost. Title is nil → consumer
        // falls back to the localized "Untitled email" string.
        XCTAssertNotNil(payload)
        XCTAssertNil(payload?.title)
        XCTAssertEqual(payload?.kind, .mail)
        let body = payload?.contentBody ?? ""
        XCTAssertTrue(body.contains("just FYI"))
    }

    // MARK: - JSON codable round-trip

    /// Mail payloads round-trip through the on-disk JSON queue.
    /// Every field that matters (`kind`, `title`, `content`,
    /// `attendees`) survives enqueue → drain unchanged.
    func test_mailPayload_roundTripsThroughJSONQueue() {
        let original = ShareInbox.Payload.mailPayload(
            rawText: canonicalMail,
            userComment: "follow up",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )!

        XCTAssertTrue(ShareInbox.enqueue(original, at: queueURL))
        let drained = ShareInbox.drain(at: queueURL)

        XCTAssertEqual(drained.count, 1)
        let restored = drained.first
        XCTAssertEqual(restored?.kind, .mail)
        XCTAssertEqual(restored?.title, "Welcome to the beta")
        XCTAssertEqual(restored?.attendees, ["jane@acme.com"])
        XCTAssertEqual(restored?.id, original.id)
        let body = restored?.contentBody ?? ""
        XCTAssertTrue(body.hasPrefix("follow up"))
        XCTAssertTrue(body.contains("Thanks for signing up."))
    }

    /// Backward compatibility: an extension that emits a `kind`
    /// the host doesn't recognise (e.g. a hypothetical future
    /// `.slack`) decodes cleanly as `.link` instead of failing the
    /// whole drain pass. This is what unblocks an extension/host
    /// version skew.
    func test_unknownKindValue_decodesAsLinkFallback() throws {
        let forwardJSON = """
        [
          {
            "id" : "11111111-2222-3333-4444-555566667777",
            "kind" : "slack",
            "text" : "some forward-incompatible payload",
            "capturedAt" : "2026-05-19T10:00:00Z"
          }
        ]
        """.data(using: .utf8)!

        try forwardJSON.write(to: queueURL)
        let drained = ShareInbox.drain(at: queueURL)

        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained.first?.kind, .link)
        XCTAssertEqual(drained.first?.text, "some forward-incompatible payload")
    }
}
