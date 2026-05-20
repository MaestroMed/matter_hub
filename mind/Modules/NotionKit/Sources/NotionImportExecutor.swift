import Foundation
import SwiftData
import GraphCore

/// v1.2.0 — Bidirectional Notion sync. Actor that runs the planned
/// import: pulls rows from the configured Notion database, walks
/// every page through the matching `Project.upsert(notionPageID:...)`
/// or `Lead.upsert(notionPageID:...)`, and reports back progress.
public struct NotionImportProgress: Sendable, Equatable {
    public let databaseID: String
    public let databaseTitle: String
    public let totalRows: Int
    public let importedRows: Int
    public let updatedRows: Int
    public let failedRows: Int
    public let isComplete: Bool

    public init(
        databaseID: String,
        databaseTitle: String,
        totalRows: Int,
        importedRows: Int,
        updatedRows: Int,
        failedRows: Int,
        isComplete: Bool
    ) {
        self.databaseID = databaseID
        self.databaseTitle = databaseTitle
        self.totalRows = totalRows
        self.importedRows = importedRows
        self.updatedRows = updatedRows
        self.failedRows = failedRows
        self.isComplete = isComplete
    }
}

public actor NotionImportExecutor {

    public static let shared = NotionImportExecutor()

    private let client: NotionClient

    public init(client: NotionClient = .shared) {
        self.client = client
    }

    /// Runs a planned import against one database. Emits a
    /// `NotionImportProgress` after every successfully-imported row
    /// + a final `isComplete: true` snapshot when the pass finishes.
    public func runImport(
        database: NotionDatabase,
        mapping: NotionImportMapping,
        applyRow: @escaping @MainActor (NotionPage, NotionImportMapping) -> NotionRowOutcome
    ) -> AsyncStream<NotionImportProgress> {
        AsyncStream { continuation in
            Task {
                await MainActor.run {
                    MINDTelemetry.info("notion.import.started", data: [
                        "database.id": String(database.id.prefix(8)),
                        "kind": mapping.targetNodeKind.rawValue,
                    ])
                }
                let pages: [NotionPage]
                do {
                    pages = try await client.queryDatabase(database.id)
                } catch {
                    await MainActor.run {
                        MINDTelemetry.warning("notion.import.failed", data: [
                            "database.id": String(database.id.prefix(8)),
                            "error": String(describing: error),
                        ])
                    }
                    continuation.yield(NotionImportProgress(
                        databaseID: database.id,
                        databaseTitle: database.title,
                        totalRows: 0,
                        importedRows: 0,
                        updatedRows: 0,
                        failedRows: 0,
                        isComplete: true
                    ))
                    continuation.finish()
                    return
                }

                let total = pages.count
                var inserted = 0
                var updated = 0
                var failed = 0

                for page in pages {
                    let outcome = await MainActor.run {
                        applyRow(page, mapping)
                    }
                    switch outcome {
                    case .inserted:
                        inserted += 1
                        await MainActor.run {
                            MINDTelemetry.info("notion.import.page.imported", data: [
                                "kind": mapping.targetNodeKind.rawValue,
                                "page.id": String(page.id.prefix(8)),
                            ])
                        }
                    case .updated:
                        updated += 1
                        await MainActor.run {
                            MINDTelemetry.info("notion.import.page.imported", data: [
                                "kind": mapping.targetNodeKind.rawValue,
                                "page.id": String(page.id.prefix(8)),
                                "state": "updated",
                            ])
                        }
                    case .failed(let reason):
                        failed += 1
                        await MainActor.run {
                            MINDTelemetry.warning("notion.import.page.failed", data: [
                                "kind": mapping.targetNodeKind.rawValue,
                                "page.id": String(page.id.prefix(8)),
                                "reason": reason,
                            ])
                        }
                    case .ignored:
                        break
                    }
                    continuation.yield(NotionImportProgress(
                        databaseID: database.id,
                        databaseTitle: database.title,
                        totalRows: total,
                        importedRows: inserted,
                        updatedRows: updated,
                        failedRows: failed,
                        isComplete: false
                    ))
                }

                await MainActor.run {
                    MINDTelemetry.info("notion.import.completed", data: [
                        "database.id": String(database.id.prefix(8)),
                        "total": String(total),
                        "imported": String(inserted),
                        "updated": String(updated),
                        "failed": String(failed),
                    ])
                }
                continuation.yield(NotionImportProgress(
                    databaseID: database.id,
                    databaseTitle: database.title,
                    totalRows: total,
                    importedRows: inserted,
                    updatedRows: updated,
                    failedRows: failed,
                    isComplete: true
                ))
                continuation.finish()
            }
        }
    }

    // MARK: - Foreground bidirectional tick (v1.2.0)

    /// Refresh every Notion-sourced Project / Lead whose Notion page
    /// has been edited since `lastNotionSyncAt`. Called from
    /// `MINDApp` on `.active` scenePhase when the user has flipped
    /// `MINDPreferences.notionBidirectionalEnabled` to true.
    ///
    /// Bounded to 20 pages per call to stay friendly with Notion's
    /// 3 req/sec rate limit.
    public func runBidirectionalTick(
        projects: [(id: String, lastSync: Date?)],
        leads: [(id: String, lastSync: Date?)],
        applyProject: @escaping @MainActor (NotionPage) -> Void,
        applyLead: @escaping @MainActor (NotionPage) -> Void
    ) async {
        let limitedProjects = Array(projects.prefix(20))
        let limitedLeads = Array(leads.prefix(20))
        let combined = limitedProjects + limitedLeads
        guard !combined.isEmpty else { return }
        var synced = 0
        for entry in combined.prefix(20) {
            do {
                let page = try await client.retrievePage(entry.id)
                let lastSync = entry.lastSync ?? .distantPast
                guard page.lastEditedAt > lastSync else { continue }
                if limitedProjects.contains(where: { $0.id == entry.id }) {
                    await MainActor.run { applyProject(page) }
                } else {
                    await MainActor.run { applyLead(page) }
                }
                synced += 1
            } catch {
                await MainActor.run {
                    MINDTelemetry.warning("notion.bidirectional.failed", data: [
                        "page.id": String(entry.id.prefix(8)),
                        "error": String(describing: error),
                    ])
                }
            }
        }
        await MainActor.run {
            MINDTelemetry.info("notion.bidirectional.synced", data: [
                "count": String(synced),
            ])
        }
    }
}

/// Outcome the @MainActor `applyRow` closure reports back to the
/// executor after handling one Notion page.
public enum NotionRowOutcome: Sendable, Equatable {
    case inserted
    case updated
    case failed(String)
    case ignored
}
