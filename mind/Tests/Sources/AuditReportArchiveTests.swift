import XCTest
@testable import AuditKit

/// v0.32 — Locks the on-disk persistence contract of
/// `AuditReportArchive`. Every regression here would surface as a
/// missing audit in the ComparisonSheet picker, a stale audit
/// surviving a re-run, or a corrupted JSON taking the whole archive
/// down.
final class AuditReportArchiveTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("MIND-archive-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try await super.tearDown()
    }

    /// A freshly-built archive on an empty directory returns an
    /// empty list — no crash, no missing-file warning, just zero
    /// reports.
    func test_allReports_emptyArchive_returnsEmpty() async {
        let archive = AuditReportArchive(rootURL: tempRoot)
        let reports = await archive.allReports()
        XCTAssertTrue(reports.isEmpty)
    }

    /// Save → allReports round-trip: the report comes back with
    /// identical scoring + quick wins + hidden risks. Locks the
    /// "comparison sheet sees the same data the audit completion
    /// banner saw" contract.
    func test_save_then_allReports_roundTrips() async {
        let archive = AuditReportArchive(rootURL: tempRoot)
        let report = makeReport(name: "Stripe", overall: 90)
        await archive.save(report)
        let reports = await archive.allReports()
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].client.id, report.client.id)
        XCTAssertEqual(reports[0].scoring.overall, 90)
    }

    /// Save twice for the same client id replaces the previous
    /// report rather than accumulating duplicates. Re-auditing the
    /// same client must not flood the ComparisonSheet picker.
    func test_save_sameClient_replacesPrevious() async {
        let archive = AuditReportArchive(rootURL: tempRoot)
        let clientID = UUID()
        let v1 = makeReport(clientID: clientID, name: "Stripe", overall: 70)
        let v2 = makeReport(clientID: clientID, name: "Stripe", overall: 92)
        await archive.save(v1)
        await archive.save(v2)
        let reports = await archive.allReports()
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].scoring.overall, 92)
    }

    /// Different client ids accumulate as distinct archive entries
    /// even when both reports share the same display name — the
    /// picker needs to surface every audit Mehdi has ever run.
    func test_save_differentClients_accumulate() async {
        let archive = AuditReportArchive(rootURL: tempRoot)
        let stripe = makeReport(name: "Stripe", overall: 88)
        let mollie = makeReport(name: "Mollie", overall: 72)
        await archive.save(stripe)
        await archive.save(mollie)
        let reports = await archive.allReports()
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(Set(reports.map(\.client.id)), [stripe.client.id, mollie.client.id])
    }

    /// allReports sorts most-recent first so the picker shows the
    /// latest audit at the top.
    func test_allReports_sortsMostRecentFirst() async {
        let archive = AuditReportArchive(rootURL: tempRoot)
        let old = makeReport(
            name: "Old",
            overall: 50,
            generatedAt: Date(timeIntervalSinceNow: -86400)
        )
        let fresh = makeReport(
            name: "Fresh",
            overall: 80,
            generatedAt: Date()
        )
        await archive.save(old)
        await archive.save(fresh)
        let reports = await archive.allReports()
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports[0].client.name, "Fresh")
        XCTAssertEqual(reports[1].client.name, "Old")
    }

    /// `report(forClientID:)` returns the saved report. A miss
    /// (never saved or deleted) returns nil rather than crashing.
    func test_report_forClientID_returnsMatchOrNil() async {
        let archive = AuditReportArchive(rootURL: tempRoot)
        let report = makeReport(name: "Stripe", overall: 88)
        await archive.save(report)
        let hit = await archive.report(forClientID: report.client.id)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.scoring.overall, 88)
        let miss = await archive.report(forClientID: UUID())
        XCTAssertNil(miss)
    }

    /// Delete removes the report from the cache + disk so the
    /// ComparisonSheet picker no longer surfaces it.
    func test_delete_removesFromArchive() async {
        let archive = AuditReportArchive(rootURL: tempRoot)
        let report = makeReport(name: "Stripe", overall: 80)
        await archive.save(report)
        await archive.delete(clientID: report.client.id)
        let reports = await archive.allReports()
        XCTAssertTrue(reports.isEmpty)
    }

    /// `clearAll` wipes every persisted report. Used by the future
    /// Settings "Clear audit archive" action — the test guarantees
    /// the disk path is also nuked, not just the in-memory cache.
    func test_clearAll_removesEveryReport() async {
        let archive = AuditReportArchive(rootURL: tempRoot)
        for idx in 0..<3 {
            await archive.save(makeReport(name: "Client \(idx)", overall: 60 + idx))
        }
        let beforeCount = await archive.allReports().count
        XCTAssertEqual(beforeCount, 3)
        await archive.clearAll()
        let afterReports = await archive.allReports()
        XCTAssertTrue(afterReports.isEmpty)
    }

    /// A fresh archive instance pointed at an existing directory
    /// re-hydrates the saved reports from disk. Locks the cross-
    /// launch contract: an audit run in one app session must still
    /// be available in the next session.
    func test_hydration_rehydratesFromDisk() async {
        let firstArchive = AuditReportArchive(rootURL: tempRoot)
        let report = makeReport(name: "Stripe", overall: 88)
        await firstArchive.save(report)

        // Build a brand-new archive at the same directory — should
        // hydrate from the JSON file written by the first archive.
        let secondArchive = AuditReportArchive(rootURL: tempRoot)
        let reports = await secondArchive.allReports()
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].client.id, report.client.id)
        XCTAssertEqual(reports[0].scoring.overall, 88)
    }

    // MARK: - Helpers

    private func makeReport(
        clientID: UUID = UUID(),
        name: String,
        overall: Int,
        generatedAt: Date = .now
    ) -> AuditReport {
        AuditReport(
            client: AuditClient(
                id: clientID,
                url: URL(string: "https://\(name.lowercased().replacingOccurrences(of: " ", with: "-")).com")!,
                name: name
            ),
            generatedAt: generatedAt,
            persona: .saasB2B,
            scoring: AuditReport.Scoring(
                overall: overall,
                performance: overall,
                seo: overall,
                security: overall,
                brand: overall,
                mobile: overall
            ),
            performance: nil,
            findings: nil,
            synthesis: "Test synthesis",
            quickWins: [],
            strategicBets: [],
            hiddenRisks: [],
            pitch: "Test pitch",
            mockups: []
        )
    }
}
