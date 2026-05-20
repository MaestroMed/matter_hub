import XCTest
import SwiftData
@testable import GraphCore

/// v1.2.0 — Locks the idempotent upsert contract on `Project` +
/// `Lead` for Notion imports. Six tests covering insert, update,
/// notionPageID survival, GitHub-source enrichment, email dedup,
/// and the email-less Lead dedup case.
@MainActor
final class NotionUpsertTests: XCTestCase {

    func test_projectUpsert_insertsWhenNoMatch() throws {
        let context = try makeContext()
        let project = try Project.upsert(
            notionPageID: "notion_page_1",
            title: "AZ Construction",
            host: "www.az.fr",
            in: context
        )
        XCTAssertEqual(project.name, "AZ Construction")
        XCTAssertEqual(project.notionPageID, "notion_page_1")
        XCTAssertNotNil(project.lastNotionSyncAt)
        let all = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(all.count, 1)
    }

    func test_projectUpsert_updatesByNotionPageID_whenMatch() throws {
        let context = try makeContext()
        let first = try Project.upsert(
            notionPageID: "notion_page_2",
            title: "AZ",
            in: context
        )
        let firstID = first.id
        let updated = try Project.upsert(
            notionPageID: "notion_page_2",
            title: "AZ Construction",
            host: "www.az.fr",
            in: context
        )
        XCTAssertEqual(updated.id, firstID,
                       "Re-pulling the same Notion page must return the same " +
                       "Project row (same UUID), not insert a duplicate.")
        XCTAssertEqual(updated.name, "AZ Construction",
                       "The second upsert must overwrite the name with the " +
                       "freshest Notion title.")
        let all = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(all.count, 1)
    }

    func test_projectUpsert_notionPageIDSurvivesAcrossUpserts() throws {
        let context = try makeContext()
        _ = try Project.upsert(notionPageID: "notion_page_3", title: "AZ", in: context)
        _ = try Project.upsert(notionPageID: "notion_page_3", title: "AZ", in: context)
        let all = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(all.first?.notionPageID, "notion_page_3",
                       "notionPageID must persist across upserts.")
    }

    func test_projectUpsert_enrichesGitHubSourcedProject() throws {
        let context = try makeContext()
        let github = Project(
            name: "AZ Construction",
            host: "www.az.fr",
            githubRepo: "MaestroMed/AZConstruction_v0"
        )
        context.insert(github)
        try context.save()

        let enriched = try Project.upsert(
            notionPageID: "notion_page_4",
            title: "AZ Construction (Notion)",
            githubRepo: "MaestroMed/AZConstruction_v0",
            in: context
        )
        XCTAssertEqual(enriched.id, github.id,
                       "An existing GitHub-sourced Project must be enriched " +
                       "with the new notionPageID, not duplicated.")
        XCTAssertEqual(enriched.notionPageID, "notion_page_4")
        let all = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(all.count, 1)
    }

    func test_leadUpsert_deduplicatesByEmail_whenEmailNonEmpty() throws {
        let context = try makeContext()
        let webhook = Lead(contactName: "Sarah Ben", contactEmail: "sarah@example.com")
        context.insert(webhook)
        try context.save()

        let synced = try Lead.upsert(
            notionPageID: "notion_lead_1",
            contactName: "Sarah Ben",
            contactEmail: "sarah@example.com",
            in: context
        )
        XCTAssertEqual(synced.id, webhook.id,
                       "When the email matches an existing Lead the executor " +
                       "must enrich it with notionPageID rather than creating " +
                       "a second \"Sarah Ben\" inbox row.")
        XCTAssertEqual(synced.notionPageID, "notion_lead_1")
        let all = try context.fetch(FetchDescriptor<Lead>())
        XCTAssertEqual(all.count, 1)
    }

    func test_leadUpsert_emailLess_dedupsByNotionPageIDOnly() throws {
        let context = try makeContext()
        // Some Notion lead databases capture only name + message (no
        // visitor email). notionPageID must be the only deterministic
        // key for those rows.
        let first = try Lead.upsert(
            notionPageID: "notion_lead_2",
            contactName: "Anonymous",
            contactEmail: "",
            in: context
        )
        let second = try Lead.upsert(
            notionPageID: "notion_lead_2",
            contactName: "Anonymous",
            contactEmail: "",
            in: context
        )
        XCTAssertEqual(first.id, second.id,
                       "Email-less Notion leads must dedup by notionPageID.")
        let all = try context.fetch(FetchDescriptor<Lead>())
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Project.self, Lead.self, Deliverable.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
