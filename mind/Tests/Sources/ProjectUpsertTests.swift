import XCTest
import SwiftData
@testable import GraphCore

/// v1.0-alpha.11 — Locks `Project.upsert(from:in:)` — the idempotent
/// insert-or-update used by the Bulk Import wizard. Pure SwiftData in
/// memory; no Keychain, no network. Each test owns its own
/// `ModelContainer` so the schema reset is total.
@MainActor
final class ProjectUpsertTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Project.self, Lead.self, Deliverable.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func record(
        repo: String = "MaestroMed/AZConstruction_v0",
        name: String = "AZ Construction",
        host: String = "www.azconstruction.fr",
        slug: String = "az-construction",
        color: String = "#1F6FEB",
        stack: ProjectStack = .nextjs
    ) -> BulkImportRecord {
        BulkImportRecord(
            githubRepo: repo,
            suggestedSlug: slug,
            suggestedName: name,
            suggestedHost: host,
            suggestedPrimaryColor: color,
            stack: stack
        )
    }

    /// First call inserts a new Project row with every suggested
    /// column written through.
    func test_upsert_insertsWhenNotExists() throws {
        let ctx = try makeContext()
        let project = try Project.upsert(from: record(), in: ctx)
        XCTAssertEqual(project.name, "AZ Construction")
        XCTAssertEqual(project.host, "www.azconstruction.fr")
        XCTAssertEqual(project.slug, "az-construction")
        XCTAssertEqual(project.githubRepo, "MaestroMed/AZConstruction_v0")
        XCTAssertEqual(project.primaryColor, "#1F6FEB")
        XCTAssertEqual(project.stackEnum, .nextjs)
        let all = try ctx.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(all.count, 1)
    }

    /// Second call with a changed host updates the existing row
    /// rather than inserting a duplicate.
    func test_upsert_updatesWhenExists() throws {
        let ctx = try makeContext()
        _ = try Project.upsert(from: record(), in: ctx)
        let updated = try Project.upsert(
            from: record(host: "azconstruction.new.fr", color: "#F0883E"),
            in: ctx
        )
        XCTAssertEqual(updated.host, "azconstruction.new.fr")
        XCTAssertEqual(updated.primaryColor, "#F0883E")
        let all = try ctx.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(all.count, 1,
                       "Upsert must NEVER duplicate on a matching githubRepo.")
    }

    /// Running upsert twice with identical input is a no-op apart
    /// from the activity timestamp refresh.
    func test_upsert_idempotentOnIdenticalInput() throws {
        let ctx = try makeContext()
        let first = try Project.upsert(from: record(), in: ctx)
        let firstID = first.id
        let firstName = first.name
        let second = try Project.upsert(from: record(), in: ctx)
        XCTAssertEqual(second.id, firstID,
                       "Re-running upsert must return the same Project ref.")
        XCTAssertEqual(second.name, firstName)
        let all = try ctx.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(all.count, 1)
    }

    /// The returned Project is the live SwiftData ref — mutating it
    /// after the upsert call is visible in subsequent fetches.
    func test_upsert_returnsLiveProjectReference() throws {
        let ctx = try makeContext()
        let project = try Project.upsert(from: record(), in: ctx)
        project.notes = "edited after upsert"
        try ctx.save()
        let refetched = try ctx.fetch(FetchDescriptor<Project>()).first
        XCTAssertEqual(refetched?.notes, "edited after upsert")
    }

    /// Two different `githubRepo` values mint two different rows.
    func test_upsert_distinctRepos_insertsBothRows() throws {
        let ctx = try makeContext()
        _ = try Project.upsert(from: record(), in: ctx)
        _ = try Project.upsert(
            from: record(
                repo: "MaestroMed/IEFCo_v0",
                name: "IEF & Co",
                host: "www.iefandco.com",
                slug: "ief-and-co",
                color: "#A371F7"
            ),
            in: ctx
        )
        let all = try ctx.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(all.count, 2)
    }

    /// Every upsert refreshes `lastActivityAt` so the cockpit's
    /// "Récent" sort floats freshly-touched projects upward.
    func test_upsert_refreshesLastActivityAt() throws {
        let ctx = try makeContext()
        let first = try Project.upsert(from: record(), in: ctx)
        first.lastActivityAt = .distantPast
        try ctx.save()
        let second = try Project.upsert(from: record(), in: ctx)
        XCTAssertGreaterThan(second.lastActivityAt, .distantPast,
                             "lastActivityAt must be refreshed on every upsert " +
                             "call so the cockpit sort surfaces the row.")
    }
}
