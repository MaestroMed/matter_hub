import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers
import AuditKit
import DesignSystem
import GraphCore
import InvoiceKit
import OutreachKit

/// v0.30 — Pipeline Kanban CRM view.
///
/// The actual CRM that closes Mehdi's funnel gap. Renders a
/// horizontally-scrolling kanban of 7 stages
/// (Prospect → Contacté → Qualifié → Audit → Pitch → Won / Lost)
/// where each `.client` `Node` from the graph appears as a draggable
/// card in the column matching its `pipelineStage`. Dragging a card
/// into a different column persists `node.pipelineStage = newStage`
/// to SwiftData and dispatches a stage-specific auto-action — the
/// whole point of the kanban is that the user's manual triage
/// triggers the next move (start a follow-up sequence, open the
/// audit sheet, fire confetti + invoice template, log a lost reason).
///
/// Architecture
/// ------------
/// - `PipelineView` (this struct) owns the @Query of all Nodes and
///   filters them per column. Sheet/alert presentation lives here.
/// - `PipelineActions.action(for:)` (pure, in GraphCore) maps a stage
///   onto an `PipelineStageAction` descriptor — unit tested.
/// - `PipelineCard` renders one client; `PipelineColumn` renders one
///   stage with its drop destination.
/// - `PipelineNodePayload` is the `Transferable` wrapper carrying the
///   Node's UUID across the drag. We don't try to make the SwiftData
///   `@Model` itself Transferable — UUID round-trip + lookup at the
///   drop site is simpler and survives the cross-process drag iOS
///   uses on iPad split view.
///
/// Tab integration — `RootView` swaps the Graph slot on the iPhone
/// tab bar with a new `.pipeline` case so the kanban gets the
/// brand-defining bottom-bar real estate. Graph stays reachable via
/// the iPad sidebar.
struct PipelineView: View {
    @Environment(\.modelContext) private var context

    /// All client/prospect Nodes. Sorted by last activity so each
    /// column lists its most-recently-touched cards first.
    @Query(
        filter: #Predicate<Node> { $0.kindRaw == "client" },
        sort: [SortDescriptor(\Node.updatedAt, order: .reverse)]
    )
    private var clients: [Node]

    /// When the user drops a card into `.audit`, this drives the
    /// `.sheet(item:)` binding that presents an AuditSheet pre-
    /// seeded with the client's content (URL) so the probes start
    /// one tap later.
    @State private var auditTarget: AuditTarget?

    /// `.contacted` / `.pitch` drops both present OutreachSheet —
    /// the latter with the `pitch` angle pre-seeded. We carry the
    /// stage on the payload so the sheet knows which angle to bias.
    @State private var outreachTarget: OutreachTarget?

    /// `.won` drop fires confetti + opens the Stripe invoice helper.
    @State private var wonInvoiceTarget: WonInvoiceTarget?
    @State private var wonToastShown: Bool = false

    /// `.lost` drop opens an alert capturing a free-form reason
    /// (persisted on the Node as a tag `lost:<reason>`).
    @State private var lostTarget: LostTarget?
    @State private var lostReasonDraft: String = ""

    /// One-shot toast banner for non-action drops (e.g. dragging a
    /// card back to Qualified or Prospect). Auto-dismisses after a
    /// beat.
    @State private var droppedToast: String?

    /// Tracks the column the card hovers over so we can subtly
    /// highlight the drop zone. Nil = no drag in progress.
    @State private var hoveringStage: PipelineStage?

    // MARK: - Body

    var body: some View {
        ZStack {
            LiquidBackground().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                header

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(PipelineStage.allCases, id: \.self) { stage in
                            PipelineColumn(
                                stage: stage,
                                clients: clients(for: stage),
                                isHovering: hoveringStage == stage,
                                onDrop: { payload in
                                    handleDrop(payload: payload, into: stage)
                                },
                                onHover: { isHovering in
                                    if isHovering {
                                        hoveringStage = stage
                                    } else if hoveringStage == stage {
                                        hoveringStage = nil
                                    }
                                }
                            )
                            .frame(width: 230)
                        }
                    }
                    .padding(.horizontal, 16)
                    // Leave room for the bottom Liquid tab bar.
                    .padding(.bottom, 120)
                }
            }
            .padding(.top, 12)

            if let droppedToast {
                VStack {
                    Spacer()
                    Text(droppedToast)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            Capsule(style: .continuous)
                                .fill(LiquidPalette.iris.opacity(0.9))
                        )
                        .padding(.bottom, 140)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(LiquidMetrics.spring, value: droppedToast)
            }
        }
        // Audit sheet — pre-seeded with the client's URL (content).
        .sheet(item: $auditTarget) { target in
            AuditSheet(initialURL: target.url)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        // Outreach sheet — covers both Contacted (initial touch +
        // sequence) and Pitch (pitch angle bias).
        .sheet(item: $outreachTarget) { target in
            OutreachSheet(
                prospect: target.prospect,
                primaryContactEmail: nil,
                prospectNodeID: target.nodeID
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        // Won — v0.31 real InvoiceSheet (replaces the v0.30
        // StripeInvoicePlaceholderSheet). Mints a fresh draft via
        // `InvoiceFactory`, renders the PDF on demand, shares via
        // the system share sheet.
        .sheet(item: $wonInvoiceTarget) { target in
            InvoiceSheet(
                clientNodeID: target.nodeID,
                initialClientName: target.clientName,
                initialClientEmail: nil
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        // Won — non-blocking "Bravo" toast.
        .alert(String(localized: "pipeline.won.toast.title"),
               isPresented: $wonToastShown) {
            Button("OK", role: .cancel) {}
        }
        // Lost — reason capture alert. The text field binds to a
        // @State string we persist into Node.tags on submit.
        .alert(String(localized: "pipeline.lost.alert.title"),
               isPresented: Binding(
                get: { lostTarget != nil },
                set: { if !$0 { lostTarget = nil } }
               )) {
            TextField(String(localized: "pipeline.lost.alert.placeholder"),
                      text: $lostReasonDraft)
            Button("OK") {
                if let target = lostTarget {
                    persistLostReason(for: target.nodeID, reason: lostReasonDraft)
                }
                lostReasonDraft = ""
                lostTarget = nil
            }
            Button("Cancel", role: .cancel) {
                lostReasonDraft = ""
                lostTarget = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("pipeline.tab.title")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                Text("\(clients.count) clients")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Column slicing

    /// Returns the clients sitting in a given stage. Nodes with a
    /// nil `pipelineStage` are surfaced in the Prospect column so a
    /// freshly-created client is reachable on the kanban without
    /// asking the user to triage it first.
    private func clients(for stage: PipelineStage) -> [Node] {
        if stage == .prospect {
            return clients.filter { node in
                let s = node.pipelineStage
                return s == nil || s == .prospect
            }
        }
        return clients.filter { $0.pipelineStage == stage }
    }

    // MARK: - Drop handling

    /// Resolves the dragged Node by UUID, mutates its stage, saves,
    /// then dispatches the stage-specific auto-action.
    private func handleDrop(payload: PipelineNodePayload, into stage: PipelineStage) {
        guard let node = clients.first(where: { $0.id == payload.nodeID })
        else { return }

        let from = node.pipelineStage ?? .prospect
        guard from != stage else { return }

        let stageLabel = String(localized: localizedStageKey(stage))
        node.pipelineStage = stage
        try? context.save()

        MINDTelemetry.info(
            "pipeline.stage.changed",
            data: [
                "from": from.rawValue,
                "to":   stage.rawValue,
                "nodeID": node.id.uuidString,
            ]
        )

        switch PipelineActions.action(for: stage) {
        case .none:
            droppedToast = String(format: String(localized: "pipeline.action.dropped"),
                                  stageLabel)
            LiquidHaptics.tap()
        case .openOutreachSequence:
            outreachTarget = OutreachTarget(
                nodeID: node.id,
                prospect: buildProspectContext(from: node),
                angle: .initial
            )
            LiquidHaptics.tap()
        case .openAuditSheet:
            auditTarget = AuditTarget(nodeID: node.id, url: node.content)
            LiquidHaptics.tap()
        case .openPitchSheet:
            outreachTarget = OutreachTarget(
                nodeID: node.id,
                prospect: buildProspectContext(from: node, trigger: "Pitch"),
                angle: .pitch
            )
            LiquidHaptics.tap()
        case .celebrateAndInvoice:
            // Confetti haptic + Bravo toast + Stripe invoice placeholder.
            LiquidHaptics.success()
            wonToastShown = true
            wonInvoiceTarget = WonInvoiceTarget(
                nodeID: node.id,
                clientName: node.title
            )
            let elapsed = elapsedDays(since: node.createdAt)
            MINDTelemetry.info(
                "pipeline.won",
                data: [
                    "nodeID": node.id.uuidString,
                    "elapsedDays": "\(elapsed)",
                ]
            )
        case .askLostReason:
            LiquidHaptics.warning()
            lostTarget = LostTarget(nodeID: node.id)
        }
    }

    private func persistLostReason(for nodeID: UUID, reason: String) {
        guard let node = clients.first(where: { $0.id == nodeID })
        else { return }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = trimmed.isEmpty ? "lost:unspecified" : "lost:\(trimmed)"
        if !node.tags.contains(tag) {
            node.tags.append(tag)
        }
        try? context.save()
        MINDTelemetry.info(
            "pipeline.lost",
            data: [
                "nodeID": nodeID.uuidString,
                "reason": trimmed.isEmpty ? "unspecified" : trimmed,
            ]
        )
    }

    private func buildProspectContext(
        from node: Node,
        trigger: String? = nil
    ) -> ProspectContext {
        let host = URL(string: node.content)?.host ?? node.content
        return ProspectContext(
            clientName: node.title,
            host: host,
            auditReport: nil,
            recentTrigger: trigger,
            industry: nil,
            primaryContactName: nil,
            primaryContactRole: nil
        )
    }

    private func elapsedDays(since date: Date) -> Int {
        let seconds = Date.now.timeIntervalSince(date)
        return max(0, Int(seconds / 86_400))
    }

    private func localizedStageKey(_ stage: PipelineStage) -> String.LocalizationValue {
        switch stage {
        case .prospect:  return "pipeline.stage.prospect"
        case .contacted: return "pipeline.stage.contacted"
        case .qualified: return "pipeline.stage.qualified"
        case .audit:     return "pipeline.stage.audit"
        case .pitch:     return "pipeline.stage.pitch"
        case .won:       return "pipeline.stage.won"
        case .lost:      return "pipeline.stage.lost"
        }
    }

    // MARK: - Sheet target wrappers

    private struct AuditTarget: Identifiable {
        let id = UUID()
        let nodeID: UUID
        let url: String
    }

    private struct OutreachTarget: Identifiable {
        let id = UUID()
        let nodeID: UUID
        let prospect: ProspectContext
        /// Hint for which voice/angle to bias. `.pitch` corresponds to
        /// the user moving the deal forward; `.initial` to first touch.
        let angle: Angle
        enum Angle { case initial, pitch }
    }

    private struct WonInvoiceTarget: Identifiable {
        let id = UUID()
        let nodeID: UUID
        let clientName: String
    }

    private struct LostTarget: Identifiable {
        let id = UUID()
        let nodeID: UUID
    }
}

// MARK: - PipelineColumn

/// One kanban column. Header pill carries the stage label + count.
/// Body is a scrolling stack of `PipelineCard`s. The whole column
/// is a drop destination that bubbles the dragged payload up to
/// `PipelineView.handleDrop`.
private struct PipelineColumn: View {
    let stage: PipelineStage
    let clients: [Node]
    let isHovering: Bool
    let onDrop: (PipelineNodePayload) -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if clients.isEmpty {
                        emptyState
                    } else {
                        ForEach(clients, id: \.id) { node in
                            PipelineCard(node: node)
                                .draggable(PipelineNodePayload(nodeID: node.id))
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(minHeight: 360)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: LiquidMetrics.cornerLarge, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidMetrics.cornerLarge, style: .continuous)
                        .stroke(
                            isHovering
                                ? AnyShapeStyle(stageTint.opacity(0.9))
                                : AnyShapeStyle(LiquidGradient.glassStroke.opacity(0.4)),
                            lineWidth: isHovering ? 2 : 1
                        )
                }
        }
        .dropDestination(for: PipelineNodePayload.self) { items, _ in
            guard let payload = items.first else { return false }
            onDrop(payload)
            return true
        } isTargeted: { targeted in
            onHover(targeted)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stageTint)
                .frame(width: 8, height: 8)
            Text(stageLabelKey)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(clients.count)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous).fill(stageTint.opacity(0.8))
                )
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private var emptyState: some View {
        Text("pipeline.empty.column")
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
    }

    private var stageLabelKey: LocalizedStringKey {
        switch stage {
        case .prospect:  return "pipeline.stage.prospect"
        case .contacted: return "pipeline.stage.contacted"
        case .qualified: return "pipeline.stage.qualified"
        case .audit:     return "pipeline.stage.audit"
        case .pitch:     return "pipeline.stage.pitch"
        case .won:       return "pipeline.stage.won"
        case .lost:      return "pipeline.stage.lost"
        }
    }

    /// Each stage owns a distinct Liquid tint so the columns are
    /// visually identifiable at a glance. Won is iris (brand), Lost
    /// is muted grey.
    private var stageTint: Color {
        switch stage {
        case .prospect:  return LiquidPalette.sky
        case .contacted: return LiquidPalette.aqua
        case .qualified: return LiquidPalette.lavender
        case .audit:     return .purple
        case .pitch:     return .orange
        case .won:       return LiquidPalette.iris
        case .lost:      return .gray
        }
    }
}

// MARK: - PipelineCard

/// Compact draggable card for a single client. 180 wide × ~110 tall,
/// shows the client name, a lead-score badge (v0.27 heuristic), and
/// the last-activity timestamp.
private struct PipelineCard: View {
    let node: Node

    private var score: LeadScore {
        LeadScorer.heuristic(node: node)
    }

    /// Hot leads (score ≥ 80) earn a subtle iris glow ring so the
    /// user's eye lands on them first while triaging the kanban.
    private var isHot: Bool {
        score.temperature == .hot
    }

    private var activityLabel: String {
        let date = node.updatedAt
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.title.isEmpty ? "—" : node.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if score.total > 0 {
                    Text("\(score.total)")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous).fill(temperatureColor)
                        )
                }
            }
            Text(activityLabel)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isHot
                                ? AnyShapeStyle(LiquidPalette.iris.opacity(0.85))
                                : AnyShapeStyle(LiquidGradient.glassStroke.opacity(0.5)),
                            lineWidth: isHot ? 1.5 : 1
                        )
                }
                .shadow(color: isHot ? LiquidPalette.iris.opacity(0.35) : .black.opacity(0.05),
                        radius: isHot ? 14 : 6,
                        x: 0, y: 4)
        }
    }

    private var temperatureColor: Color {
        switch score.temperature {
        case .hot:  return .red
        case .warm: return .orange
        case .cold: return .gray
        }
    }
}

// MARK: - PipelineNodePayload

/// Drag payload wrapping a Node's UUID. Encoded as JSON so the iOS
/// system drag service can ferry it across the process boundary on
/// iPad (and across split-view boundaries in general). We resolve
/// the actual Node by lookup at the drop site rather than passing a
/// SwiftData reference, which can't survive a cross-process drag.
struct PipelineNodePayload: Codable, Transferable, Equatable {
    let nodeID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pipelineNodePayload)
    }
}

extension UTType {
    /// Custom UTI for the drag payload. Declared inline so we don't
    /// need to register it in Info.plist — SwiftUI's
    /// `CodableRepresentation` is happy with an exported subtype of
    /// `public.data`.
    static let pipelineNodePayload = UTType(exportedAs: "app.mind.ios.pipeline.node")
}
