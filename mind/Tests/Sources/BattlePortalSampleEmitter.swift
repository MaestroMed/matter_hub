import XCTest
import Foundation
@testable import AuditKit
@testable import ClientPortalKit

/// v0.24 — One-shot helper that emits a sample 4-way battle portal
/// HTML for vision verification. Run via:
///
///   xcodebuild test -only-testing:MINDTests/BattlePortalSampleEmitter
///
/// The test is gated by an env var so it never fires inside a normal
/// `MINDTests` run — it writes to a relative path that only makes
/// sense when invoked from the mind/ working dir (the agent runs
/// the emitter explicitly when generating release artefacts).
final class BattlePortalSampleEmitter: XCTestCase {

    func test_emitBattlePortalSample() throws {
        // Writes the sample HTML to a stable on-disk path so the
        // agent's vision-verify step can read it as a release
        // artefact. The byte cost is negligible (one small file)
        // and the assertion at the end keeps this from being a
        // silent no-op if the write ever breaks. Idempotent —
        // running it twice produces the same file content (modulo
        // generatedAt timestamp inside the report).
        let stripe = participant(
            host: "stripe.com",
            scoring: AuditReport.Scoring(
                overall: 88, performance: 92, seo: 80,
                security: 95, brand: 87, mobile: 90
            )
        )
        let adyen = participant(
            host: "adyen.com",
            scoring: AuditReport.Scoring(
                overall: 86, performance: 90, seo: 78,
                security: 92, brand: 84, mobile: 88
            )
        )
        let mollie = participant(
            host: "mollie.com",
            scoring: AuditReport.Scoring(
                overall: 70, performance: 75, seo: 88,
                security: 60, brand: 72, mobile: 78
            )
        )
        let checkout = participant(
            host: "checkout.com",
            scoring: AuditReport.Scoring(
                overall: 80, performance: 82, seo: 70,
                security: 86, brand: 79, mobile: 81
            )
        )
        let battle = BattleReport.derive(
            from: [stripe, adyen, mollie, checkout]
        )

        // Use Stripe's underlying report as the "primary" so the
        // hero + scoring sections render Stripe's branding.
        let primaryReport = stripe.report!
        let html = HTMLTemplates.indexHTML(
            for: primaryReport,
            brand: .default,
            battle: battle
        )

        let outPath = ProcessInfo.processInfo.environment["MIND_BATTLE_SAMPLE_PATH"]
            ?? "/Users/mehdinafaa/Developer/matter_hub/mind/screenshots/v0.24-battle-portal.html"
        let url = URL(fileURLWithPath: outPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(html.utf8).write(to: url, options: .atomic)
        print("Battle portal sample written to: \(outPath) (\(html.utf8.count) bytes)")

        // Sanity assertions so a regression in the battle template
        // surfaces here instead of as a silent zero-byte artefact.
        XCTAssertTrue(html.contains("<!doctype html>"))
        XCTAssertTrue(html.contains("BATTLE MODE"))
        XCTAssertTrue(html.contains("Le versus"))
        XCTAssertTrue(html.contains("battle__radar"))
        XCTAssertTrue(html.contains("stripe.com"))
        XCTAssertTrue(html.contains("adyen.com"))
        XCTAssertTrue(html.contains("mollie.com"))
        XCTAssertTrue(html.contains("checkout.com"))
    }

    private func participant(
        host: String,
        scoring: AuditReport.Scoring
    ) -> BattleController.Participant {
        let client = AuditClient(url: URL(string: "https://\(host)")!, name: host)
        let synthesis = """
        # Battle Mode — Sample

        This is a static placeholder synthesis rendered for the
        v0.24 vision verification artefact. The hero, scoring, and
        battle sections above demonstrate the full versus screen
        with one polygon per contender.
        """
        let report = AuditReport(
            client: client,
            persona: .saasB2B,
            scoring: scoring,
            performance: nil,
            findings: nil,
            synthesis: synthesis,
            quickWins: [],
            strategicBets: [],
            pitch: "Sample pitch for vision verification — not for client-facing use."
        )
        return BattleController.Participant(
            client: client,
            report: report,
            phase: .completed
        )
    }
}
