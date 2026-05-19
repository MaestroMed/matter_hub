import XCTest
@testable import RemindersKit

/// Locks the pure diff logic that drives the bidirectional Reminders ↔
/// MIND tasks sync (v0.10). We deliberately stay off of EventKit here —
/// `RemindersStore` is the only EventKit-touching surface and is
/// exercised end-to-end on the simulator via the vision-verification
/// screenshot.
final class RemindersSyncEngineTests: XCTestCase {

    private let engine = RemindersSyncEngine()

    // MARK: - ReminderSnapshot value type

    func test_snapshot_initPreservesAllFields() {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let modified = due.addingTimeInterval(60)
        let snapshot = ReminderSnapshot(
            id: "abc",
            title: "Call Mehdi",
            notes: "About v0.10",
            dueDate: due,
            isCompleted: true,
            lastModified: modified
        )
        XCTAssertEqual(snapshot.id, "abc")
        XCTAssertEqual(snapshot.title, "Call Mehdi")
        XCTAssertEqual(snapshot.notes, "About v0.10")
        XCTAssertEqual(snapshot.dueDate, due)
        XCTAssertTrue(snapshot.isCompleted)
        XCTAssertEqual(snapshot.lastModified, modified)
    }

    func test_snapshot_defaultsAreSafe() {
        let snapshot = ReminderSnapshot(id: "x", title: "Buy milk")
        XCTAssertNil(snapshot.notes)
        XCTAssertNil(snapshot.dueDate)
        XCTAssertFalse(snapshot.isCompleted)
        XCTAssertEqual(snapshot.lastModified, .distantPast)
    }

    // MARK: - Array helpers

    func test_deduplicatedByID_keepsFirstWinner() {
        let a1 = ReminderSnapshot(id: "dup", title: "First")
        let a2 = ReminderSnapshot(id: "dup", title: "Second")
        let b  = ReminderSnapshot(id: "b",   title: "Other")
        let result = [a1, a2, b].deduplicatedByID()
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.title, "First")
    }

    func test_openOnly_dropsCompleted() {
        let open  = ReminderSnapshot(id: "1", title: "Open")
        let done  = ReminderSnapshot(id: "2", title: "Done", isCompleted: true)
        XCTAssertEqual([open, done].openOnly().map(\.id), ["1"])
    }

    // MARK: - Plan: empty input

    func test_plan_emptyInputs_yieldsEmptyPlan() {
        XCTAssertTrue(engine.plan(nodes: [], reminders: []).isEmpty)
    }

    // MARK: - Plan: MIND → Reminders (create on iOS)

    func test_plan_orphanNode_createsReminder() {
        let nodeID = UUID()
        let node = RemindersSyncEngine.NodeProjection(
            id: nodeID,
            title: "Send brief",
            notes: "draft is ready",
            isCompleted: false,
            updatedAt: .now,
            reminderExternalID: nil
        )
        let plan = engine.plan(nodes: [node], reminders: [])
        XCTAssertEqual(plan.actions.count, 1)
        guard case let .createReminderFor(id, title, notes, _, isCompleted) = plan.actions[0] else {
            return XCTFail("Expected createReminderFor, got \(plan.actions[0])")
        }
        XCTAssertEqual(id, nodeID)
        XCTAssertEqual(title, "Send brief")
        XCTAssertEqual(notes, "draft is ready")
        XCTAssertFalse(isCompleted)
    }

    // MARK: - Plan: Reminders → MIND (create on graph side)

    func test_plan_orphanReminder_createsNode() {
        let reminder = ReminderSnapshot(
            id: "r-1",
            title: "Préparer keynote",
            notes: "slides 1-12",
            isCompleted: false
        )
        let plan = engine.plan(nodes: [], reminders: [reminder])
        XCTAssertEqual(plan.actions.count, 1)
        guard case let .createNodeFor(id, title, notes, _, isCompleted) = plan.actions[0] else {
            return XCTFail("Expected createNodeFor, got \(plan.actions[0])")
        }
        XCTAssertEqual(id, "r-1")
        XCTAssertEqual(title, "Préparer keynote")
        XCTAssertEqual(notes, "slides 1-12")
        XCTAssertFalse(isCompleted)
    }

    // MARK: - Plan: paired entries stay quiet when both agree

    func test_plan_pairedEntries_whenAgreed_noActions() {
        let nodeID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let node = RemindersSyncEngine.NodeProjection(
            id: nodeID,
            title: "Buy beans",
            notes: "Arabica only",
            isCompleted: false,
            updatedAt: timestamp,
            reminderExternalID: "r-7"
        )
        let reminder = ReminderSnapshot(
            id: "r-7",
            title: "Buy beans",
            notes: "Arabica only",
            isCompleted: false,
            lastModified: timestamp
        )
        XCTAssertTrue(engine.plan(nodes: [node], reminders: [reminder]).isEmpty)
    }

    // MARK: - Plan: completion always wins

    func test_plan_completedNodeBeatsOpenReminder() {
        let nodeID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        // Reminder was updated AFTER the node, but the node is the
        // completed side. Completion must still propagate to iOS.
        let node = RemindersSyncEngine.NodeProjection(
            id: nodeID,
            title: "Done thing",
            notes: "",
            isCompleted: true,
            updatedAt: timestamp,
            reminderExternalID: "r-9"
        )
        let reminder = ReminderSnapshot(
            id: "r-9",
            title: "Done thing",
            notes: nil,
            isCompleted: false,
            lastModified: timestamp.addingTimeInterval(60_000)
        )
        let plan = engine.plan(nodes: [node], reminders: [reminder])
        XCTAssertEqual(plan.actions.count, 1)
        guard case let .updateReminder(_, _, _, isCompleted) = plan.actions[0] else {
            return XCTFail("Expected updateReminder")
        }
        XCTAssertTrue(isCompleted, "Completion wins regardless of timestamps")
    }

    func test_plan_completedReminderBeatsOpenNode() {
        let nodeID = UUID()
        let node = RemindersSyncEngine.NodeProjection(
            id: nodeID,
            title: "Open thing",
            notes: "",
            isCompleted: false,
            updatedAt: .now,
            reminderExternalID: "r-11"
        )
        let reminder = ReminderSnapshot(
            id: "r-11",
            title: "Open thing",
            notes: nil,
            isCompleted: true,
            lastModified: .distantPast
        )
        let plan = engine.plan(nodes: [node], reminders: [reminder])
        XCTAssertEqual(plan.actions.count, 1)
        guard case let .updateNode(_, _, _, isCompleted) = plan.actions[0] else {
            return XCTFail("Expected updateNode")
        }
        XCTAssertTrue(isCompleted)
    }

    // MARK: - Plan: last-writer-wins on title / notes drift

    func test_plan_pairedDiff_newerNodeWinsTitle() {
        let nodeID = UUID()
        let nodeUpdated = Date(timeIntervalSince1970: 1_800_005_000)
        let node = RemindersSyncEngine.NodeProjection(
            id: nodeID,
            title: "Call Cécile",
            notes: "tarif Q2",
            isCompleted: false,
            updatedAt: nodeUpdated,
            reminderExternalID: "r-13"
        )
        let reminder = ReminderSnapshot(
            id: "r-13",
            title: "Call C.",
            notes: nil,
            isCompleted: false,
            lastModified: nodeUpdated.addingTimeInterval(-60)
        )
        let plan = engine.plan(nodes: [node], reminders: [reminder])
        XCTAssertEqual(plan.actions.count, 1)
        guard case let .updateReminder(id, title, notes, _) = plan.actions[0] else {
            return XCTFail("Expected updateReminder")
        }
        XCTAssertEqual(id, "r-13")
        XCTAssertEqual(title, "Call Cécile")
        XCTAssertEqual(notes, "tarif Q2")
    }

    func test_plan_pairedDiff_newerReminderWinsNotes() {
        let nodeID = UUID()
        let nodeUpdated = Date(timeIntervalSince1970: 1_800_005_000)
        let node = RemindersSyncEngine.NodeProjection(
            id: nodeID,
            title: "Daily standup",
            notes: "10am",
            isCompleted: false,
            updatedAt: nodeUpdated,
            reminderExternalID: "r-15"
        )
        let reminder = ReminderSnapshot(
            id: "r-15",
            title: "Daily standup",
            notes: "moved to 11am",
            isCompleted: false,
            lastModified: nodeUpdated.addingTimeInterval(30)
        )
        let plan = engine.plan(nodes: [node], reminders: [reminder])
        XCTAssertEqual(plan.actions.count, 1)
        guard case let .updateNode(_, _, notes, _) = plan.actions[0] else {
            return XCTFail("Expected updateNode")
        }
        XCTAssertEqual(notes, "moved to 11am")
    }

    // MARK: - Plan: title fallback for unpaired pre-existing entries

    func test_plan_titleFallback_bindsThenReconciles() {
        let nodeID = UUID()
        let node = RemindersSyncEngine.NodeProjection(
            id: nodeID,
            title: "Buy milk",
            notes: "",
            isCompleted: false,
            updatedAt: .now,
            reminderExternalID: nil
        )
        // Same logical task, different surface — different ID (because
        // they were created independently before sync turned on),
        // whitespace + case variants on the title.
        let reminder = ReminderSnapshot(
            id: "r-fallback",
            title: "buy   Milk",
            notes: nil,
            isCompleted: false,
            lastModified: .distantPast
        )
        let plan = engine.plan(nodes: [node], reminders: [reminder])
        // First action MUST be the binding so the caller persists the
        // pairing before applying any field-level update.
        XCTAssertGreaterThanOrEqual(plan.actions.count, 1)
        guard case let .bindNodeToReminder(boundNode, boundReminder) = plan.actions[0] else {
            return XCTFail("Expected bindNodeToReminder first, got \(plan.actions[0])")
        }
        XCTAssertEqual(boundNode, nodeID)
        XCTAssertEqual(boundReminder, "r-fallback")
        // No orphan-create should have been emitted — the pre-existing
        // pair was matched.
        XCTAssertFalse(plan.actions.contains(where: {
            if case .createReminderFor = $0 { return true }
            if case .createNodeFor = $0 { return true }
            return false
        }))
    }

    // MARK: - Plan: paired but reminder vanished from iOS

    func test_plan_pairedNodeWithMissingReminder_recreatesReminder() {
        let nodeID = UUID()
        let node = RemindersSyncEngine.NodeProjection(
            id: nodeID,
            title: "Resurrected task",
            notes: "",
            isCompleted: false,
            updatedAt: .now,
            reminderExternalID: "deleted-on-ios"
        )
        let plan = engine.plan(nodes: [node], reminders: [])
        XCTAssertEqual(plan.actions.count, 1)
        guard case let .createReminderFor(id, title, _, _, _) = plan.actions[0] else {
            return XCTFail("Expected createReminderFor for the missing pair")
        }
        XCTAssertEqual(id, nodeID)
        XCTAssertEqual(title, "Resurrected task")
    }

    // MARK: - Plan: deterministic action ordering

    func test_plan_isDeterministic() {
        let nodeA = RemindersSyncEngine.NodeProjection(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "A", notes: "", isCompleted: false, updatedAt: .now, reminderExternalID: nil
        )
        let nodeB = RemindersSyncEngine.NodeProjection(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "B", notes: "", isCompleted: false, updatedAt: .now, reminderExternalID: nil
        )
        let r1 = ReminderSnapshot(id: "r-1", title: "Z1")
        let r2 = ReminderSnapshot(id: "r-2", title: "Z2")
        let plan1 = engine.plan(nodes: [nodeA, nodeB], reminders: [r1, r2])
        let plan2 = engine.plan(nodes: [nodeA, nodeB], reminders: [r1, r2])
        XCTAssertEqual(plan1, plan2, "Identical inputs must yield byte-identical plans")
    }
}
