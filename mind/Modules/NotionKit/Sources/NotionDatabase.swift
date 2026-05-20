import Foundation

/// v1.2.0 — Bidirectional Notion sync value types.
///
/// These three structs land alongside the existing one-way
/// `NotionPageBuilder` + `NotionClient.createAuditPage(_:in:)` surface
/// so MIND can now READ from Notion as well as WRITE to it. The MIND
/// → Notion path stays unchanged; these types describe what we pull
/// BACK from Notion when Mehdi runs the import wizard or when the
/// foreground bidirectional sync ticks.
///
/// All four are pure value types — `Sendable` so they cross the
/// `NotionClient` actor boundary, `Codable` so a future on-disk
/// cache can persist them, `Identifiable` so SwiftUI ForEach binds
/// without boilerplate.

/// One Notion database the integration has access to.
///
/// `id` is Notion's UUID-without-dashes convention.
///
/// `propertyNames` mirrors Notion's `properties` dictionary keys —
/// the title property's name is typically "Name" but in a FR-
/// localised workspace it's "Nom". The planner uses the list to
/// auto-detect which column maps to the MIND node title.
public struct NotionDatabase: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let icon: String?
    public let lastEditedAt: Date
    public let propertyNames: [String]

    public init(
        id: String,
        title: String,
        icon: String?,
        lastEditedAt: Date,
        propertyNames: [String]
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.lastEditedAt = lastEditedAt
        self.propertyNames = propertyNames
    }
}

/// One Notion page (a row in a database, or a standalone page).
///
/// `properties` flattens Notion's per-cell value into a plain `String`
/// — the import path doesn't need the full rich-text / select /
/// multi-select discrimination because every target MIND field
/// (title, notes, status) ends up as a string anyway.
public struct NotionPage: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let icon: String?
    public let createdAt: Date
    public let lastEditedAt: Date
    public let properties: [String: String]
    public let url: String
    public let parentDatabaseID: String?

    public init(
        id: String,
        title: String,
        icon: String?,
        createdAt: Date,
        lastEditedAt: Date,
        properties: [String: String],
        url: String,
        parentDatabaseID: String?
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.createdAt = createdAt
        self.lastEditedAt = lastEditedAt
        self.properties = properties
        self.url = url
        self.parentDatabaseID = parentDatabaseID
    }
}

/// One block inside a page body. The MIND import surface only needs
/// plain text + block kind ("paragraph", "heading_1",
/// "bulleted_list_item", "to_do", ...) so we flatten Notion's rich-
/// text spans into a single `plainText`. `depth` is reserved for
/// nested-list indentation in a future revision.
public struct NotionBlock: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let type: String
    public let plainText: String
    public let depth: Int

    public init(
        id: String,
        type: String,
        plainText: String,
        depth: Int
    ) {
        self.id = id
        self.type = type
        self.plainText = plainText
        self.depth = depth
    }
}

/// Optional database filter the wizard can pass to `queryDatabase`
/// when narrowing the row set (e.g. "Status = Active"). Maps to
/// Notion's filter object. Only the two most-common comparators are
/// exposed.
public struct NotionDatabaseFilter: Sendable, Codable, Equatable {
    public let property: String
    public let value: String
    public let comparator: String   // "equals" | "contains"

    public init(property: String, value: String, comparator: String = "equals") {
        self.property = property
        self.value = value
        self.comparator = comparator
    }
}
