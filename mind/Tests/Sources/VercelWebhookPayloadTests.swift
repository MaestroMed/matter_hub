import XCTest
@testable import MIND

/// v1.1.0 — Locks the Vercel push payload parsing contract the NSE
/// (`NotificationService.parseVercel`) and the App-side mirror
/// (`PushPayloadParser.parseVercel`) both observe. The NSE lives in
/// an extension target the test bundle can't `@testable import`, so
/// these tests exercise the `PushPayloadParser` copy that ships in
/// the App target; the NSE keeps a byte-equivalent copy of the same
/// logic so both surfaces stay locked behind one suite.
final class VercelWebhookPayloadTests: XCTestCase {

    // MARK: - parseVercel(userInfo:)

    /// A fully-populated Vercel push extracts every relevant field
    /// without any fallback default.
    func test_parseVercel_extractsFullPayload() {
        let userInfo: [AnyHashable: Any] = [
            "vercel": [
                "type": "deployment.succeeded",
                "projectId": "prj_abc123",
                "deploymentId": "dpl_xyz789",
                "url": "az-construction-abc.vercel.app",
                "commitSHA": "f1e2d3c4b5a6978899aabbccddeeff0011223344",
                "commitMessage": "feat: refresh hero section",
                "authorEmail": "mehdi@example.com",
                "occurredAt": "2026-05-20T08:42:11Z",
            ],
        ]
        let parsed = PushPayloadParser.parseVercel(userInfo: userInfo)
        XCTAssertEqual(parsed?.type, "deployment.succeeded")
        XCTAssertEqual(parsed?.projectID, "prj_abc123")
        XCTAssertEqual(parsed?.deploymentID, "dpl_xyz789")
        XCTAssertEqual(parsed?.url, "az-construction-abc.vercel.app")
        XCTAssertEqual(parsed?.commitSHA, "f1e2d3c4b5a6978899aabbccddeeff0011223344")
        XCTAssertEqual(parsed?.commitMessage, "feat: refresh hero section")
        XCTAssertEqual(parsed?.authorEmail, "mehdi@example.com")
        XCTAssertEqual(parsed?.occurredAt, "2026-05-20T08:42:11Z")
        XCTAssertEqual(parsed?.commitSHAShort, "f1e2d3c")
    }

    /// Missing top-level `vercel` dict returns nil so the NSE can
    /// fall through to the lead path / raw push.
    func test_parseVercel_missingDict_returnsNil() {
        let userInfo: [AnyHashable: Any] = ["lead": ["projectID": "any"]]
        XCTAssertNil(PushPayloadParser.parseVercel(userInfo: userInfo))
    }

    /// A `vercel` dict with no `projectId` returns nil — a payload
    /// without a project ID is unroutable.
    func test_parseVercel_missingProjectID_returnsNil() {
        let userInfo: [AnyHashable: Any] = [
            "vercel": [
                "type": "deployment.error",
                "deploymentId": "dpl_alone",
            ],
        ]
        XCTAssertNil(PushPayloadParser.parseVercel(userInfo: userInfo))
    }

    /// Whitespace-only fields collapse to empty strings except for
    /// `projectID`, which fails the parse outright.
    func test_parseVercel_whitespaceFields_collapse() {
        let userInfo: [AnyHashable: Any] = [
            "vercel": [
                "type": " deployment.succeeded ",
                "projectId": "prj_real",
                "commitSHA": "   ",
                "commitMessage": "   ship it   ",
            ],
        ]
        let parsed = PushPayloadParser.parseVercel(userInfo: userInfo)
        XCTAssertEqual(parsed?.type, "deployment.succeeded")
        XCTAssertEqual(parsed?.projectID, "prj_real")
        XCTAssertEqual(parsed?.commitSHA, "")
        XCTAssertEqual(parsed?.commitMessage, "ship it")
    }

    /// Accepts the Swift-style `projectID` casing as a defensive
    /// fallback (the canonical worker payload uses `projectId`).
    func test_parseVercel_acceptsSwiftStyleProjectIDKey() {
        let userInfo: [AnyHashable: Any] = [
            "vercel": [
                "projectID": "prj_swift",
                "type": "deployment.created",
            ],
        ]
        let parsed = PushPayloadParser.parseVercel(userInfo: userInfo)
        XCTAssertEqual(parsed?.projectID, "prj_swift")
    }

    // MARK: - vercelStatusLabel(_:)

    /// Every event type the Worker emits maps to its FR label.
    func test_vercelStatusLabel_coversCanonicalEvents() {
        XCTAssertEqual(PushPayloadParser.vercelStatusLabel("deployment.created"), "Déploiement démarré")
        XCTAssertEqual(PushPayloadParser.vercelStatusLabel("deployment.succeeded"), "✓ Déploiement réussi")
        XCTAssertEqual(PushPayloadParser.vercelStatusLabel("deployment.error"), "❌ Build échoué")
        XCTAssertEqual(PushPayloadParser.vercelStatusLabel("deployment.canceled"), "Annulé")
    }

    /// Hyphenated alternates (Vercel sometimes emits `deployment-ready`)
    /// map to the same FR labels so the in-app banner stays consistent
    /// across event spellings.
    func test_vercelStatusLabel_acceptsLegacyHyphenatedSpellings() {
        XCTAssertEqual(PushPayloadParser.vercelStatusLabel("deployment-created"), "Déploiement démarré")
        XCTAssertEqual(PushPayloadParser.vercelStatusLabel("deployment-ready"), "✓ Déploiement réussi")
        XCTAssertEqual(PushPayloadParser.vercelStatusLabel("deployment-error"), "❌ Build échoué")
        XCTAssertEqual(PushPayloadParser.vercelStatusLabel("deployment-canceled"), "Annulé")
    }

    /// An unknown event type falls back to the generic catch-all
    /// label so the operator always sees something readable.
    func test_vercelStatusLabel_unknownEvent_fallsBackToGeneric() {
        XCTAssertEqual(PushPayloadParser.vercelStatusLabel("project.deleted"), "Évènement Vercel")
        XCTAssertEqual(PushPayloadParser.vercelStatusLabel(""), "Évènement Vercel")
    }

    /// The convenience `statusLabel` property routes through the
    /// pure function above, so the same vocabulary is used whether
    /// the call site is the View or the NSE.
    func test_vercelPayload_statusLabel_matchesPureFunction() {
        let payload = PushPayloadParser.VercelPayload(
            type: "deployment.error",
            projectID: "prj_any",
            deploymentID: "dpl_any",
            url: "",
            commitSHA: "",
            commitMessage: "",
            authorEmail: "",
            occurredAt: ""
        )
        XCTAssertEqual(payload.statusLabel, PushPayloadParser.vercelStatusLabel("deployment.error"))
    }
}
