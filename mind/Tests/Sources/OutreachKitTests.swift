import XCTest
@testable import OutreachKit
@testable import AuditKit

/// v0.26 — Locks the pure parts of the AI Sales Email Generator:
/// `OutreachPromptBuilder` (prompt body shape + JSON parse round-
/// trip) and `OutreachMailto` (URL escaping contract). The
/// `OutreachEmailGenerator` actor's network path can't be exercised
/// from a hosted unit test (no Anthropic key in CI), so the contract
/// covered here is everything observable from the builders.
final class OutreachKitTests: XCTestCase {

    // MARK: - Fixtures

    private func sampleProspect(
        name: String = "Acme Corp",
        host: String = "acme.com",
        audit: AuditReport? = nil,
        trigger: String? = nil,
        industry: String? = nil
    ) -> ProspectContext {
        ProspectContext(
            clientName: name,
            host: host,
            auditReport: audit,
            recentTrigger: trigger,
            industry: industry
        )
    }

    private func sampleSender(
        voice: SenderProfile.VoiceTone = .friendly
    ) -> SenderProfile {
        SenderProfile(
            name: "Mehdi Nafaa",
            title: "Senior Digital Consultant",
            signature: "— Mehdi",
            voice: voice
        )
    }

    private func sampleAudit(
        clientName: String = "Acme Corp",
        host: String = "acme.com"
    ) -> AuditReport {
        let scoring = AuditReport.Scoring(
            overall: 71, performance: 64, seo: 78,
            security: 82, brand: 65, mobile: 70
        )
        let client = AuditClient(
            url: URL(string: "https://\(host)")!,
            name: clientName
        )
        let wins = [
            AuditReport.QuickWin(
                title: "Compress hero image",
                detail: "Drop hero PNG from 3.4 MB to ~280 KB via AVIF.",
                effortDays: 0.5, impact: .high
            ),
            AuditReport.QuickWin(
                title: "Add HSTS header",
                detail: "Missing Strict-Transport-Security.",
                effortDays: 0.25, impact: .medium
            ),
        ]
        let risks = [
            AuditReport.HiddenRisk(
                title: "DKIM signature missing",
                detail: "Mail flagged as spam by Gmail filters.",
                severity: .high
            )
        ]
        return AuditReport(
            client: client,
            persona: .saasB2B,
            scoring: scoring,
            performance: nil,
            synthesis: "Synthesis copy.",
            quickWins: wins,
            strategicBets: [],
            hiddenRisks: risks,
            pitch: "Sample pitch."
        )
    }

    // MARK: - OutreachPromptBuilder — structural anchors

    /// The prompt must surface the prospect identity (name + host)
    /// so Claude grounds the angles in the actual prospect, not a
    /// generic placeholder.
    func test_build_includesClientNameAndHost() {
        let prompt = OutreachPromptBuilder.build(
            prospect: sampleProspect(),
            sender: sampleSender(),
            variantCount: 5
        )
        XCTAssertTrue(prompt.contains("Acme Corp"),
                      "Client name must appear in the prompt body")
        XCTAssertTrue(prompt.contains("acme.com"),
                      "Host must appear in the prompt body")
    }

    /// The voice tone instruction must be rendered so Claude
    /// actually adopts the right register. Locking each of the
    /// three tones prevents a future enum case from silently
    /// shipping without a prompt instruction.
    func test_build_includesVoiceToneInstruction() {
        for tone in SenderProfile.VoiceTone.allCases {
            let prompt = OutreachPromptBuilder.build(
                prospect: sampleProspect(),
                sender: sampleSender(voice: tone),
                variantCount: 5
            )
            XCTAssertTrue(
                prompt.contains(tone.rawValue),
                "Voice tone '\(tone.rawValue)' must appear in the prompt body"
            )
        }
    }

    /// The output contract must be JSON-only. Locking the "JSON"
    /// clause + the schema field names prevents a future prompt
    /// edit from silently breaking `parse(response:)`.
    func test_build_asksForJSONOutput() {
        let prompt = OutreachPromptBuilder.build(
            prospect: sampleProspect(),
            sender: sampleSender(),
            variantCount: 5
        )
        XCTAssertTrue(prompt.contains("STRICTLY with valid JSON"),
                      "Prompt must instruct the model to return JSON only")
        XCTAssertTrue(prompt.contains("\"subject\""),
                      "Schema field name must be locked in the prompt")
        XCTAssertTrue(prompt.contains("\"body\""),
                      "Schema field name must be locked in the prompt")
        XCTAssertTrue(prompt.contains("\"angle\""),
                      "Schema field name must be locked in the prompt")
    }

    /// The prompt must ask for exactly N variants — locking this
    /// keeps the UI's "5 shimmer cards then 5 result cards"
    /// expectation honest. Clamps must be tested too: 0 → 1, 999 → 10.
    func test_build_requestsExactlyNVariants() {
        let three = OutreachPromptBuilder.build(
            prospect: sampleProspect(),
            sender: sampleSender(),
            variantCount: 3
        )
        XCTAssertTrue(three.contains("Generate 3 distinct"),
                      "Prompt must request exactly 3 variants when caller asks for 3")
        XCTAssertTrue(three.contains("Exactly 3 variants"),
                      "Prompt rules section must restate the variant count")
        let clamped = OutreachPromptBuilder.build(
            prospect: sampleProspect(),
            sender: sampleSender(),
            variantCount: 999
        )
        XCTAssertTrue(clamped.contains("Generate 10 distinct"),
                      "Variant count > 10 must clamp down to the max of 10")
        let lowerClamp = OutreachPromptBuilder.build(
            prospect: sampleProspect(),
            sender: sampleSender(),
            variantCount: 0
        )
        XCTAssertTrue(lowerClamp.contains("Generate 1 distinct"),
                      "Variant count < 1 must clamp up to the min of 1")
    }

    /// When an audit report is provided, its quick wins must appear
    /// verbatim in the prompt so Claude can name concrete findings
    /// in the ROI / Quick-Win variants instead of inventing them.
    func test_build_includesAuditContextWhenPresent() {
        let audit = sampleAudit()
        let prompt = OutreachPromptBuilder.build(
            prospect: sampleProspect(audit: audit),
            sender: sampleSender(),
            variantCount: 5
        )
        XCTAssertTrue(prompt.contains("Compress hero image"),
                      "First quick win title must appear in the prompt body")
        XCTAssertTrue(prompt.contains("Add HSTS header"),
                      "Second quick win title must appear in the prompt body")
        XCTAssertTrue(prompt.contains("71/100"),
                      "Overall audit score must appear in the prompt grounding")
    }

    /// When no audit is attached, the prompt must explicitly state
    /// "NONE" so Claude knows to pivot to industry-prior angles
    /// rather than hallucinate fake scores.
    func test_build_fallsBackGracefullyWhenAuditNil() {
        let prompt = OutreachPromptBuilder.build(
            prospect: sampleProspect(audit: nil),
            sender: sampleSender(),
            variantCount: 5
        )
        XCTAssertTrue(prompt.contains("Audit findings: NONE"),
                      "Prompt must explicitly state when no audit is attached")
        XCTAssertTrue(prompt.contains("Never invent fake audit numbers"),
                      "Prompt must instruct Claude not to fabricate metrics")
    }

    /// When a recent trigger is provided, it must appear verbatim
    /// so the funding-angle variant can reference it directly.
    func test_build_includesRecentTriggerWhenPresent() {
        let prompt = OutreachPromptBuilder.build(
            prospect: sampleProspect(trigger: "raised €15M Series A 2 weeks ago"),
            sender: sampleSender(),
            variantCount: 5
        )
        XCTAssertTrue(prompt.contains("raised €15M Series A 2 weeks ago"),
                      "Recent trigger must appear verbatim in the prompt")
    }

    /// The prompt must be deterministic for identical inputs.
    /// Future caching of "régénérer" depends on this property; a
    /// non-deterministic builder would silently bust the cache.
    func test_build_isDeterministicForSameInput() {
        let a = OutreachPromptBuilder.build(
            prospect: sampleProspect(
                trigger: "shipped v2",
                industry: "fintech"
            ),
            sender: sampleSender(voice: .direct),
            variantCount: 5
        )
        let b = OutreachPromptBuilder.build(
            prospect: sampleProspect(
                trigger: "shipped v2",
                industry: "fintech"
            ),
            sender: sampleSender(voice: .direct),
            variantCount: 5
        )
        XCTAssertEqual(a, b,
                       "Builder must be pure — identical inputs → identical prompt")
    }

    // MARK: - OutreachPromptBuilder — response parsing

    /// Round-trip a well-formed JSON payload through the parser. All
    /// 5 variants must come back with their angle decoded.
    func test_parse_roundTripsWellFormedPayload() {
        let response = """
        {
          "variants": [
            { "subject": "Quick ROI angle", "body": "Hi Acme,\\n\\nNumbers convert.\\n\\n— Mehdi", "angle": "roi" },
            { "subject": "One quick win", "body": "Hi Acme,\\n\\nDrop hero img.\\n\\n— Mehdi", "angle": "quickWin" },
            { "subject": "Stripe comparison", "body": "Hi Acme,\\n\\nStripe ships X.\\n\\n— Mehdi", "angle": "competitor" },
            { "subject": "Congrats on the round", "body": "Hi Acme,\\n\\nCongrats.\\n\\n— Mehdi", "angle": "funding" },
            { "subject": "One question", "body": "Hi Acme,\\n\\nQuick q?\\n\\n— Mehdi", "angle": "question" }
          ]
        }
        """
        let variants = OutreachPromptBuilder.parse(response: response)
        XCTAssertEqual(variants.count, 5)
        XCTAssertEqual(variants[0].angle, .roi)
        XCTAssertEqual(variants[1].angle, .quickWin)
        XCTAssertEqual(variants[2].angle, .competitor)
        XCTAssertEqual(variants[3].angle, .funding)
        XCTAssertEqual(variants[4].angle, .question)
    }

    // MARK: - OutreachMailto — escaping contract

    /// Subject text containing spaces and punctuation must end up
    /// percent-escaped in the final URL — otherwise iOS Mail opens
    /// with a truncated subject.
    func test_mailto_escapesSubject() throws {
        let url = try XCTUnwrap(OutreachMailto.mailtoURL(
            to: "ceo@acme.com",
            subject: "Hi from MIND — quick question",
            body: "Body."
        ))
        let absolute = url.absoluteString
        // Space must be encoded (`%20` or `+`). URLComponents picks
        // `%20` for the query value, which is correct for mailto.
        XCTAssertTrue(absolute.contains("Hi%20from%20MIND"),
                      "Subject spaces must be percent-escaped: \(absolute)")
        XCTAssertFalse(absolute.contains("Hi from MIND"),
                       "Raw unescaped subject must not appear in the URL")
    }

    /// Body text with newlines must round-trip via URLComponents
    /// so Mail.app receives the multi-paragraph layout.
    func test_mailto_escapesBody() throws {
        let body = "Hi Acme,\n\nQuick ROI angle.\n\n— Mehdi"
        let url = try XCTUnwrap(OutreachMailto.mailtoURL(
            to: "ceo@acme.com",
            subject: "S",
            body: body
        ))
        let absolute = url.absoluteString
        XCTAssertTrue(absolute.contains("%0A") || absolute.contains("%0D%0A"),
                      "Newlines in body must be percent-escaped: \(absolute)")
    }

    /// When the recipient is nil, the URL must omit the recipient
    /// slot so iOS Mail opens a fresh compose with the To: field
    /// empty — and crucially the subject + body must still arrive.
    func test_mailto_handlesNilRecipient() throws {
        let url = try XCTUnwrap(OutreachMailto.mailtoURL(
            to: nil,
            subject: "S",
            body: "B"
        ))
        let absolute = url.absoluteString
        XCTAssertTrue(absolute.hasPrefix("mailto:?"),
                      "Nil recipient must produce 'mailto:?…' (no address): \(absolute)")
        XCTAssertTrue(absolute.contains("subject=S"),
                      "Subject must survive in the query string")
        XCTAssertTrue(absolute.contains("body=B"),
                      "Body must survive in the query string")
    }

    /// Accented characters in subject + body must end up
    /// percent-escaped (UTF-8 byte sequences) so Mail.app on iOS
    /// renders them correctly.
    func test_mailto_encodesAccents() throws {
        let url = try XCTUnwrap(OutreachMailto.mailtoURL(
            to: "marie@société.fr",
            subject: "Méthodologie d'audit",
            body: "Bonjour, voici la méthode."
        ))
        let absolute = url.absoluteString
        // 'é' = U+00E9, UTF-8 = 0xC3 0xA9 → "%C3%A9".
        XCTAssertTrue(absolute.contains("%C3%A9"),
                      "Accented 'é' must be percent-escaped as %C3%A9: \(absolute)")
    }

    /// Very large bodies (5000+ chars) must still produce a valid
    /// URL — empirically iOS Mail handles up to ~80k char URLs but
    /// the parser must not choke or truncate.
    func test_mailto_handlesLargeBody() throws {
        let body = String(repeating: "ab cd ", count: 1000) // 6000 chars
        let url = try XCTUnwrap(OutreachMailto.mailtoURL(
            to: "ceo@acme.com",
            subject: "S",
            body: body
        ))
        let absolute = url.absoluteString
        XCTAssertTrue(absolute.hasPrefix("mailto:ceo@acme.com?"),
                      "URL must begin with the recipient slot for large bodies")
        XCTAssertGreaterThan(absolute.count, 6_000,
                             "URL must carry the full encoded body, no truncation")
    }
}
