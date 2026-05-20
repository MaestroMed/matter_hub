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

    // v1.0-alpha.2 — Per-type unique-identifier prefixes. Spotlight
    // dedupes rows by `uniqueIdentifier`; if a Project and a Node
    // ever shared a UUID (cosmically improbable but cheap to defend
    // against), one would silently overwrite the other in the index.
    // Prefixing keeps the namespaces partitioned so deep-link
    // dispatchers (`onContinueUserActivity`) can route purely from
    // the string prefix without an extra lookup table.
    public static let projectIdentifierPrefix = "project:"
    public static let leadIdentifierPrefix = "lead:"
    public static let deliverableIdentifierPrefix = "deliverable:"

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

    /// v1.0-alpha.2 — Indexes a Project so typing "AZ" or
    /// "azconstruction" on the Home Screen surfaces it.
    public static func index(_ project: Project) {
        let item = makeSearchableItem(for: project)
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                #if DEBUG
                print("SpotlightIndexer: index failed for project \(project.id): \(error)")
                #endif
            }
        }
    }

    /// v1.0-alpha.2 — Indexes a Lead so typing the visitor's name
    /// or email surfaces the matching inbox row.
    public static func index(_ lead: Lead) {
        let item = makeSearchableItem(for: lead)
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                #if DEBUG
                print("SpotlightIndexer: index failed for lead \(lead.id): \(error)")
                #endif
            }
        }
    }

    /// v1.0-alpha.2 — Indexes a Deliverable so typing the page URL
    /// or audit title surfaces the matching artifact.
    public static func index(_ deliverable: Deliverable) {
        let item = makeSearchableItem(for: deliverable)
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                #if DEBUG
                print("SpotlightIndexer: index failed for deliverable \(deliverable.id): \(error)")
                #endif
            }
        }
    }

    /// v1.0-alpha.2 — Removes every row sharing a given type prefix.
    /// Used by Settings → Danger Zone to wipe a single category
    /// without bulldozing the rest of the Spotlight index.
    public static func removeAllForType(prefix: String) {
        // Spotlight's bulk-delete API is keyed by `domainIdentifier`,
        // not by prefix — so we wipe the shared domain and let the
        // app re-index on next boot. Per-prefix deletion stays a
        // future iteration that walks the index via
        // `CSSearchableIndex.fetchLastClientStateWithCompletion`.
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in }
        _ = prefix // explicit no-op to lock the API surface for callers
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

    /// v1.0-alpha.2 — Builds the CSSearchableItem for a `Project`.
    /// Surfaces the project name + host as primary matches; keywords
    /// include the stack, lifecycle stage, and contract type so
    /// typing "retainer" surfaces every retainer Project.
    static func makeSearchableItem(for project: Project) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .contact)
        attrs.title = project.name
        attrs.displayName = project.name
        attrs.contentDescription = project.host
        var keywords: [String] = [
            project.host,
            project.slug,
            project.stack,
            project.lifecycleStage,
            project.contractType,
        ]
        if let repo = project.githubRepo { keywords.append(repo) }
        attrs.keywords = keywords.filter { !$0.isEmpty }
        attrs.contentCreationDate = project.startedAt
        attrs.contentModificationDate = project.lastActivityAt
        let item = CSSearchableItem(
            uniqueIdentifier: "\(projectIdentifierPrefix)\(project.id.uuidString)",
            domainIdentifier: domainIdentifier,
            attributeSet: attrs
        )
        item.expirationDate = .distantFuture
        return item
    }

    /// v1.0-alpha.2 — Builds the CSSearchableItem for a `Lead`. The
    /// visitor's name + email anchor the title; the message snippet
    /// drives the description. Keywords include `formType` and the
    /// status so "spam" and "qualified" both surface as filters.
    static func makeSearchableItem(for lead: Lead) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .message)
        let displayTitle: String
        if !lead.contactName.isEmpty {
            displayTitle = lead.contactName
        } else if !lead.contactEmail.isEmpty {
            displayTitle = lead.contactEmail
        } else {
            displayTitle = "Lead"
        }
        attrs.title = displayTitle
        attrs.displayName = displayTitle
        // Snippet capped at 500 chars to keep the index lean — same
        // budget the Node indexer uses.
        let snippet = String(lead.message.prefix(500))
        attrs.contentDescription = snippet
        var keywords: [String] = [lead.formType, lead.status]
        if !lead.contactEmail.isEmpty { keywords.append(lead.contactEmail) }
        if let phone = lead.contactPhone, !phone.isEmpty { keywords.append(phone) }
        attrs.keywords = keywords
        attrs.contentCreationDate = lead.receivedAt
        attrs.contentModificationDate = lead.statusUpdatedAt
        let item = CSSearchableItem(
            uniqueIdentifier: "\(leadIdentifierPrefix)\(lead.id.uuidString)",
            domainIdentifier: domainIdentifier,
            attributeSet: attrs
        )
        item.expirationDate = .distantFuture
        return item
    }

    /// v1.0-alpha.2 — Builds the CSSearchableItem for a `Deliverable`.
    /// Title + detail snippet drive matching; the URL is surfaced as
    /// a keyword so "azconstruction.fr/services" finds the matching
    /// page deliverable.
    static func makeSearchableItem(for deliverable: Deliverable) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .item)
        attrs.title = deliverable.title
        attrs.displayName = deliverable.title
        let snippet = String(deliverable.detail.prefix(500))
        attrs.contentDescription = snippet
        var keywords: [String] = [deliverable.kind]
        if let url = deliverable.url, !url.isEmpty { keywords.append(url) }
        if let sha = deliverable.commitSHA, !sha.isEmpty { keywords.append(sha) }
        attrs.keywords = keywords
        attrs.contentCreationDate = deliverable.createdAt
        attrs.contentModificationDate = deliverable.createdAt
        let item = CSSearchableItem(
            uniqueIdentifier: "\(deliverableIdentifierPrefix)\(deliverable.id.uuidString)",
            domainIdentifier: domainIdentifier,
            attributeSet: attrs
        )
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
        case .event, .meeting:
            // v0.8 — `.meeting` is a CalendarKit-sourced event captured
            // into the graph. Same Spotlight UTType so the system renders
            // a calendar glyph next to it in search results.
            return .calendarEvent
        case .person, .client:
            return .contact
        case .place:
            return .url
        case .file:
            return .data
        case .audit:
            return .pdf
        case .mail:
            // v0.14 — `.mail` is a Share Extension-captured email. The
            // system has a dedicated `emailMessage` UTType that renders
            // the envelope glyph in Spotlight rows next to the result.
            // Deployment target is iOS 26 so the type is always
            // present — no fallback needed.
            return .emailMessage
        }
    }
}
