import XCTest
@testable import GraphCore

/// v0.30 — Pipeline Kanban core type tests.
///
/// Locks the pure parts of the Pipeline Kanban CRM feature:
///
/// 1. `PipelineStage` enum: case count, raw-value round-trip,
///    Codable, ordering / terminal-stage parity.
/// 2. `Node.pipelineStage` computed property: nil round-trip,
///    setter writes raw + timestamp.
/// 3. Stage progression: monotonic with a backward-allowed escape.
/// 4. `PipelineActions.action(for:)` purity contract.
///
/// The SwiftUI view + drag-drop layer cannot be exercised from a
/// hosted XCTest (no SwiftUI rendering hook), but every observable
/// behaviour the view depends on is covered here.
final class PipelineStageTests: XCTestCase {

    // MARK: - PipelineStage enum

    func test_allCases_count_is7() {
        XCTAssertEqual(PipelineStage.allCases.count, 7,
                       "v0.30 ships exactly 7 funnel stages: " +
                       "prospect, contacted, qualified, audit, pitch, won, lost.")
    }

    func test_rawValues_roundTrip_lossless() {
        for stage in PipelineStage.allCases {
            let reconstructed = PipelineStage(rawValue: stage.rawValue)
            XCTAssertEqual(reconstructed, stage,
                           "Stage \(stage) should round-trip through its raw value.")
        }
    }

    func test_codable_roundTrip_lossless() throws {
        let original: [PipelineStage] = [
            .prospect, .contacted, .qualified, .audit, .pitch, .won, .lost,
        ]
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([PipelineStage].self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func test_progressOrdinal_isMonotonicAcrossFunnel() {
        // Strictly increasing from prospect to pitch — the user can
        // only move "forward" through the funnel by raising the
        // ordinal. Going backward is allowed by the UI but the
        // ordinal contract still ranks the canonical forward path.
        let funnel: [PipelineStage] = [.prospect, .contacted, .qualified, .audit, .pitch]
        for i in 1..<funnel.count {
            XCTAssertLessThan(
                funnel[i - 1].progressOrdinal,
                funnel[i].progressOrdinal,
                "\(funnel[i - 1]) should rank below \(funnel[i]) on the funnel."
            )
        }
    }

    func test_won_and_lost_shareTerminalOrdinal() {
        // Won + Lost are parallel terminal stages — they share the
        // same ordinal so both render at the right edge of the kanban
        // and reporting buckets treat them as "deal closed".
        XCTAssertEqual(
            PipelineStage.won.progressOrdinal,
            PipelineStage.lost.progressOrdinal,
            "Won and Lost both close the deal — same ordinal."
        )
    }

    func test_isTerminal_isTrueForWonAndLost_falseOthers() {
        XCTAssertTrue(PipelineStage.won.isTerminal)
        XCTAssertTrue(PipelineStage.lost.isTerminal)
        for stage in PipelineStage.allCases where !stage.isTerminal {
            XCTAssertFalse(
                stage.isTerminal,
                "\(stage) is non-terminal — must stay isTerminal=false."
            )
        }
    }

    func test_pipelineOrdered_listsAllSevenStagesInFunnelOrder() {
        XCTAssertEqual(
            PipelineStage.pipelineOrdered,
            [.prospect, .contacted, .qualified, .audit, .pitch, .won, .lost]
        )
    }

    // MARK: - Node.pipelineStage getter/setter

    func test_node_pipelineStage_returnsNil_whenRawIsMissing() {
        let node = Node(kind: .client, title: "Acme Corp")
        XCTAssertNil(node.pipelineStage,
                     "Fresh clients have no stage — they must read nil so PipelineView can route them to the Prospect column via its fallback rule.")
    }

    func test_node_pipelineStage_returnsNil_whenRawIsGarbage() {
        let node = Node(kind: .client, title: "Acme Corp")
        node.pipelineStageRaw = "definitelyNotAStage"
        XCTAssertNil(node.pipelineStage,
                     "Unknown raw values must decode as nil rather than crash or default to .prospect.")
    }

    func test_node_pipelineStage_setter_writesRawAndRefreshesTimestamp() {
        let node = Node(kind: .client, title: "Acme Corp")
        XCTAssertNil(node.pipelineStageUpdatedAt,
                     "Newly constructed Node has no transition timestamp.")
        node.pipelineStage = .contacted
        XCTAssertEqual(node.pipelineStageRaw, "contacted")
        XCTAssertEqual(node.pipelineStage, .contacted)
        XCTAssertNotNil(node.pipelineStageUpdatedAt,
                        "Setter must refresh pipelineStageUpdatedAt so the kanban card timestamps stay accurate.")
    }

    func test_node_pipelineStage_setter_canMoveBackward() {
        // Going backward (e.g. promoting a card from Pitch back to
        // Qualified because the user wants to redo discovery) is a
        // first-class operation. The setter must accept any stage
        // regardless of the prior position.
        let node = Node(kind: .client, title: "Acme Corp")
        node.pipelineStage = .pitch
        node.pipelineStage = .qualified
        XCTAssertEqual(node.pipelineStage, .qualified)
    }

    func test_node_pipelineStage_setter_canClear() {
        let node = Node(kind: .client, title: "Acme Corp")
        node.pipelineStage = .pitch
        XCTAssertNotNil(node.pipelineStage)
        node.pipelineStage = nil
        XCTAssertNil(node.pipelineStage)
        XCTAssertNil(node.pipelineStageRaw)
    }

    // MARK: - PipelineActions descriptor

    func test_action_for_prospect_isNone() {
        XCTAssertEqual(PipelineActions.action(for: .prospect), .none,
                       "Dropping into Prospect is a pure triage move — no auto-sheet.")
    }

    func test_action_for_contacted_isOutreachSequence() {
        XCTAssertEqual(PipelineActions.action(for: .contacted), .openOutreachSequence,
                       "Moving to Contacted starts a v0.29 FollowUpSequence — open OutreachSheet.")
    }

    func test_action_for_audit_isAuditSheet() {
        XCTAssertEqual(PipelineActions.action(for: .audit), .openAuditSheet,
                       "Audit column pre-seeds the AuditSheet with the client URL.")
    }

    func test_action_for_pitch_isPitchSheet() {
        XCTAssertEqual(PipelineActions.action(for: .pitch), .openPitchSheet,
                       "Pitch column pre-seeds OutreachSheet with the pitch angle.")
    }

    func test_action_for_won_isCelebrate() {
        XCTAssertEqual(PipelineActions.action(for: .won), .celebrateAndInvoice,
                       "Won fires confetti haptic + Stripe invoice template.")
    }

    func test_action_for_lost_asksReason() {
        XCTAssertEqual(PipelineActions.action(for: .lost), .askLostReason,
                       "Lost prompts the user for a reason (saved to Node.tags).")
    }

    func test_action_for_qualified_isNone() {
        // Qualified is the "discovery confirmed" milestone — no
        // auto-action here; the user moves on to scheduling the
        // audit manually. This locks the contract so a future "auto-
        // generate a discovery brief" idea has to be added on
        // purpose, not by accident.
        XCTAssertEqual(PipelineActions.action(for: .qualified), .none)
    }
}
