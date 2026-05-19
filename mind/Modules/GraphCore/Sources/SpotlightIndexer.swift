import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Thin wrapper around CSSearchableIndex that turns Nodes into rows in
/// the iOS Spotlight search results — typing "stripe" on the Home
/// Screen surfaces the matching client, tapping it deep-links into
/// MIND's NodeDetailView.
///
/// Why Core Spotlight rather than Quick Look or App Intents donations:
/// - Spotlight is the lowest-friction surface for the user, no
///   activation, no Siri summoning.
/// - The index is local-only, persisted by iOS, deduplicated by
///   `uniqueIdentifier`. Re-indexing the same Node just overwrites the
///   previous row.
/// - One framework (`CoreSpotlight`), one type (`CSSearchableItem`),
///   no entitlement, no Info.plist key required for indexing.
///
/// Deep-link contract:
/// - `domainIdentifier` = "app.mind.ios.nodes" (used to wipe all index
///   entries in one call when needed).
/// - `uniqueIdentifier` = node.id.uuidString. The host app reads this
///   in `.onContinueUserActivity(CSSearchableItemActionType:)` to fetch
///   the right Node from SwiftData and present its detail view.
public enum SpotlightIndexer {
    public static let domainIdentifier = "app.mind.ios.nodes"

    /// Indexes a single Node (insert or update). Cheap, non-blocking —
    /// the Spotlight framework dispatches the write to its own queue.
    /// Safe to call on every node mutation; iOS rate-limits internally.
    public static func index(_ node: Node) {
        let item = makeSearchableItem(for: node)
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                // Silent failure — Spotlight indexing is a "nice to have",
                // never fatal. Logged only when DEBUG so prod stays quiet.
                #if DEBUG
                print("SpotlightIndexer: index failed for \(node.id): \(error)")
                #endif
            }
        }
    }

    /// Bulk-index every Node passed in. Used at first launch to backfill
    /// pre-existing nodes that were created before this code shipped.
    public static func indexAll(_ nodes: [Node]) {
        guard !nodes.isEmpty else { return }
        let items = nodes.map(makeSearchableItem(for:))
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                #if DEBUG
                print("SpotlightIndexer: bulk index of \(nodes.count) nodes failed: \(error)")
                #endif
            }
        }
    }

    /// Removes a single Node from the Spotlight index. Call when the
    /// user deletes a Node from SwiftData so Spotlight doesn't show a
    /// stale row that opens an empty NodeDetailView.
    public static func remove(_ nodeID: UUID) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: [nodeID.uuidString]) { _ in }
    }

    /// Wipes every MIND-indexed row. Used by Settings "Reset Spotlight
    /// index" debug button or by a future store-reset flow.
    public static func removeAll() {
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in }
    }

    // MARK: - Internals

    /// Builds the CSSearchableItem that represents one Node. The
    /// attribute set covers: title (matched first by Spotlight), content
    /// snippet (matched second), keywords (tags), kind label, and a
    /// content type that influences which result-row icon Spotlight
    /// uses.
    ///
    /// `internal` (not `private`) so the test target can verify the
    /// mapping without touching the real CSSearchableIndex singleton.
    static func makeSearchableItem(for node: Node) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: contentType(for: node.kind))

        attrs.title = node.title
        attrs.displayName = node.title

        // Content snippet capped — Spotlight already truncates but
        // sending less data keeps the index file lean.
        let snippet = String(node.content.prefix(500))
        attrs.contentDescription = snippet

        // Keywords boost recall: tags + the kind raw value, so typing
        // "client" surfaces every Node of kind .client even without
        // matching the title.
        var keywords: [String] = node.tags
        keywords.append(node.kindRaw)
        attrs.keywords = keywords

        attrs.contentCreationDate = node.createdAt
        attrs.contentModificationDate = node.updatedAt

        let item = CSSearchableItem(
            uniqueIdentifier: node.id.uuidString,
            domainIdentifier: domainIdentifier,
            attributeSet: attrs
        )
        // Indefinite — let iOS evict on storage pressure rather than
        // expiring rows after an arbitrary delay.
        item.expirationDate = .distantFuture
        return item
    }

    /// Picks a UTType that roughly matches the node kind so Spotlight
    /// renders an appropriate fallback icon when the app isn't yet
    /// providing a custom thumbnail. `internal` for the same reason
    /// as `makeSearchableItem`.
    static func contentType(for kind: NodeKind) -> UTType {
        switch kind {
        case .note, .journal, .idea, .capture:
            return .plainText
        case .task, .habit, .goal:
            return .item
        case .event:
            return .calendarEvent
        case .person, .client:
            return .contact
        case .place:
            return .url
        case .file:
            return .data
        case .audit:
            return .pdf
        }
    }
}
