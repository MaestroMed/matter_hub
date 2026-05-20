import Foundation
import GraphCore

/// Pure logic that diffs MIND's `Node` task list against the iOS
/// Reminders snapshot and produces a `SyncPlan` describing the writes
/// each side must apply. **No EventKit calls live here** so the entire
/// surface is unit-testable without simulator permission prompts.
///
/// Sync direction: bidirectional. Last-writer-wins on conflict, with
/// "completed" beating "open" on tie (intentional: marking a task done
/// is the action we want to propagate fastest).
///
/// The engine matches an existing pairing via three keys, in order:
///   1. `Node.reminderExternalID == ReminderSnapshot.id` — the canonical
///      pairing once a sync has happened at least once.
///   2. Title equality (case-insensitive, whitespace-trimmed) on
///      unpaired entries — covers the migration case where a user had
///      identical tasks on both sides before turning sync on.
///   3. Falls back to "create on the other side" — a brand-new entry.
public struct RemindersSyncEngine: Sendable {

    public init() {}

    /// One specific mutation to apply on either side of the sync.
    public enum Action: Sendable, Equatable {
        /// Push a new reminder to iOS Reminders. The `Node.id` is
        /// carried so the caller can write back the resulting
        /// `EKReminder.calendarItemIdentifier` into
        /// `Node.reminderExternalID` once EventKit has minted it.
        case createReminderFor(nodeID: UUID, title: String, notes: String, dueDate: Date?, isCompleted: Bool)
        /// Insert a new task Node into the graph mirroring a reminder
        /// that exists only on the iOS side.
        case createNodeFor(reminderID: String, title: String, notes: String?, dueDate: Date?, isCompleted: Bool)
        /// The iOS reminder is newer — propagate its fields onto the
        /// matching Node.
        case updateNode(nodeID: UUID, title: String, notes: String?, isCompleted: Bool)
        /// The Node is newer — propagate its fields onto the matching
        /// reminder.
        case updateReminder(reminderID: String, title: String, notes: String, isCompleted: Bool)
        /// Persist the pairing on the Node so the next diff pass uses
        /// the cheap ID-equality path. Emitted when title-fallback
        /// matched a pre-existing pair.
        case bindNodeToReminder(nodeID: UUID, reminderID: String)
    }

    /// Output of a single diff pass. Apply in the order:
    /// `bindings → creates → updates`. The caller can ignore an empty
    /// plan cheaply (`isEmpty`).
    public struct SyncPlan: Sendable, Equatable {
        public let actions: [Action]

        public init(actions: [Action]) {
            self.actions = actions
        }

        public var isEmpty: Bool { actions.isEmpty }
    }

    /// Minimal Node projection the engine needs. Decouples the diff
    /// logic from the SwiftData `@Model` so tests can hand-craft inputs
    /// without spinning up a ModelContext.
    public struct NodeProjection: Sendable, Equatable {
        public let id: UUID
        public let title: String
        public let notes: String
        public let isCompleted: Bool
        public let updatedAt: Date
        public let reminderExternalID: String?

        public init(
            id: UUID,
            title: String,
            notes: String,
            isCompleted: Bool,
            updatedAt: Date,
            reminderExternalID: String?
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.isCompleted = isCompleted
            self.updatedAt = updatedAt
            self.reminderExternalID = reminderExternalID
        }
    }

    /// Diffs two sides into a plan of mutations. Deterministic — same
    /// inputs always yield the same actions in the same order, so the
    /// caller can replay a plan safely.
    public func plan(
        nodes: [NodeProjection],
        reminders: [ReminderSnapshot]
    ) -> SyncPlan {
        let openReminders = reminders.deduplicatedByID()
        var actions: [Action] = []

        // Index reminders by id for O(1) lookup. The id-paired nodes
        // hit this first; everyone else falls through to the title
        // matcher below.
        var remindersByID: [String: ReminderSnapshot] = [:]
        for reminder in openReminders {
            remindersByID[reminder.id] = reminder
        }

        // Track which reminders have been consumed by the node loop so
        // the "reminder-only" pass at the bottom only mints nodes for
        // truly orphan reminders.
        var consumedReminderIDs = Set<String>()
        // Track nodes that fell through to title-matching so we don't
        // double-process them in the orphan pass.
        var processedNodeIDs = Set<UUID>()

        // --- Pass 1: id-paired nodes (the steady-state path) ---
        for node in nodes {
            guard let externalID = node.reminderExternalID else { continue }
            processedNodeIDs.insert(node.id)
            guard let reminder = remindersByID[externalID] else {
                // Paired reminder is gone from iOS — recreate it so the
                // pairing stays alive. (Treating deletion as "iOS won"
                // would erase the user's MIND tasks behind their back.)
                actions.append(.createReminderFor(
                    nodeID: node.id,
                    title: node.title,
                    notes: node.notes,
                    dueDate: nil,
                    isCompleted: node.isCompleted
                ))
                continue
            }
            consumedReminderIDs.insert(reminder.id)

            // Both sides exist — converge with last-writer-wins.
            if let action = reconcile(node: node, reminder: reminder) {
                actions.append(action)
            }
        }

        // --- Pass 2: unpaired nodes — try a title match before
        //     declaring them "MIND-only" and pushing to iOS. Case-
        //     insensitive comparison so "Buy milk" pairs with "buy
        //     milk" if both pre-existed before sync was enabled.
        for node in nodes where !processedNodeIDs.contains(node.id) {
            let key = normalize(node.title)
            if let match = openReminders.first(where: {
                !consumedReminderIDs.contains($0.id)
                && normalize($0.title) == key
            }) {
                consumedReminderIDs.insert(match.id)
                actions.append(.bindNodeToReminder(nodeID: node.id, reminderID: match.id))
                if let merge = reconcile(
                    node: node,
                    reminder: match
                ) {
                    actions.append(merge)
                }
            } else {
                actions.append(.createReminderFor(
                    nodeID: node.id,
                    title: node.title,
                    notes: node.notes,
                    dueDate: nil,
                    isCompleted: node.isCompleted
                ))
            }
        }

        // --- Pass 3: orphan reminders → mint new nodes on the MIND
        //     side. This is the "I added a reminder in iOS, see it
        //     appear in MIND" leg of the sync.
        for reminder in openReminders where !consumedReminderIDs.contains(reminder.id) {
            actions.append(.createNodeFor(
                reminderID: reminder.id,
                title: reminder.title,
                notes: reminder.notes,
                dueDate: reminder.dueDate,
                isCompleted: reminder.isCompleted
            ))
        }

        return SyncPlan(actions: actions)
    }

    // MARK: - Helpers

    /// Returns the propagation action that brings both sides into agreement,
    /// or nil if they already agree on every observed field.
    private func reconcile(
        node: NodeProjection,
        reminder: ReminderSnapshot
    ) -> Action? {
        let nodeTitle = node.title.trimmed
        let reminderTitle = reminder.title.trimmed
        let nodeNotes = node.notes.trimmed
        let reminderNotes = (reminder.notes ?? "").trimmed

        let agree =
            normalize(nodeTitle) == normalize(reminderTitle)
            && nodeNotes == reminderNotes
            && node.isCompleted == reminder.isCompleted

        if agree { return nil }

        // Tie-breaker: completed always beats open. Marking a task done
        // is the action we want to propagate fastest; the alternative
        // (timestamp wins) creates the awful UX of "I just checked it
        // off on my watch but it un-checks itself when I open MIND".
        if node.isCompleted != reminder.isCompleted {
            if node.isCompleted {
                return .updateReminder(
                    reminderID: reminder.id,
                    title: nodeTitle,
                    notes: nodeNotes,
                    isCompleted: true
                )
            } else {
                return .updateNode(
                    nodeID: node.id,
                    title: reminderTitle,
                    notes: reminder.notes,
                    isCompleted: true
                )
            }
        }

        // Otherwise pick the most-recently-updated side and push its
        // fields to the other.
        if node.updatedAt >= reminder.lastModified {
            return .updateReminder(
                reminderID: reminder.id,
                title: nodeTitle,
                notes: nodeNotes,
                isCompleted: node.isCompleted
            )
        } else {
            return .updateNode(
                nodeID: node.id,
                title: reminderTitle,
                notes: reminder.notes,
                isCompleted: reminder.isCompleted
            )
        }
    }

    /// Canonical comparison form: trimmed, lowercased, internal-
    /// whitespace collapsed. Lets the title-fallback matcher pair
    /// "Buy milk" with "buy   milk\n".
    private func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        return lowered
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private extension String {
    /// Whitespace-trim convenience used in several diff comparisons —
    /// kept private to the module so it doesn't conflict with any
    /// future GraphCore helper of the same name.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Node projection ergonomics

public extension RemindersSyncEngine.NodeProjection {
    /// Builds a projection from a SwiftData `Node`, filtering only for
    /// task-shaped Nodes. Returns nil for any other kind so callers can
    /// `compactMap` over the entire graph without an explicit filter.
    init?(node: Node) {
        guard node.kind == .task else { return nil }
        self.init(
            id: node.id,
            title: node.title,
            notes: node.content,
            isCompleted: node.isCompleted,
            updatedAt: node.updatedAt,
            reminderExternalID: node.reminderExternalID
        )
    }
}
