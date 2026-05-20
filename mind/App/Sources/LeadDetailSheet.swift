import SwiftUI
import SwiftData
import AuditKit
import DesignSystem
import GraphCore
import OutreachKit

/// v1.0-alpha.3 — Per-Lead detail surface. Presented from HomeView's
/// "Aujourd'hui" inbox row tap and from ProjectDetailSheet's recent
/// leads list. Five sections from top to bottom:
///
/// 1. Header — contact name, project name + chip, form-type pill.
/// 2. Message — the raw lead.message (selectable text).
/// 3. Draft reply — editable text editor. v1.0-alpha.13 adds the
///    AI Reply Composer: tapping the "Générer 3 variantes" CTA shows
///    a shimmer skeleton over the textarea while
///    `OutreachEmailGenerator.shared.leadReply(...)` returns 3
///    variants tagged with distinct angles (direct / consultative /
///    similarCase). Tab pills above the editor let the user pick
///    one — picking swaps the textarea in (haptic .select). The
///    edited draft saves to `lead.draftReply` on every keystroke
///    (debounced 500ms via a Task-cancellation latch) + emits the
///    `lead.draft.saved` breadcrumb on persist.
/// 4. Actions — qualified / won (opens InvoiceSheet) / lost (alert
///    for reason) / spam.
/// 5. Metadata — sourceURL, receivedAt, formType, userAgent, IP hash
///    in a collapsible disclosure group.
///
/// Every status mutation persists via `try? context.save()` and
/// fires a `lead.status.changed` MINDTelemetry breadcrumb so the
/// timeline shows the triage flow.
struct LeadDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Pull every Project so the AI Reply Composer can suggest a
    /// "similar past engagement" for the `similarCase` angle. The
    /// sheet itself only ever surfaces 3 variants — the filtering
    /// happens before the composer fires.
    @Query private var allProjects: [Project]

    @Bindable var lead: Lead

    /// Local mirror of `lead.draftReply` so the TextEditor binds to a
    /// non-optional. Pushed back on every edit.
    @State private var draftReply: String

    /// Latch while the OutreachEmailGenerator round-trips so the
    /// "Générer brouillon" CTA can swap to a shimmer skeleton.
    @State private var isGeneratingDraft: Bool = false

    /// The 3 reply variants returned by the latest composer call.
    /// Empty until the user taps "Générer 3 variantes". Cleared on
    /// every re-generation so the tab pills always reflect the most-
    /// recent batch.
    @State private var replyVariants: [OutreachReply] = []

    /// The currently-selected reply angle. Drives both the tab pill
    /// highlight and the textarea content swap. nil when no variant
    /// is selected yet (initial state + immediately after a
    /// re-generation).
    @State private var selectedReplyAngle: OutreachReply.Angle?

    /// Flashed when the debounced auto-save persists a draft edit.
    /// Used to render the small green check + accessibility "Brouillon
    /// enregistré" announce. Resets after a 1.5s window via
    /// `.task(id:)`.
    @State private var lastSavedAt: Date?

    /// Task handle for the debounced auto-save. Cancelled on every
    /// keystroke so only the trailing edit (500ms after the last
    /// keystroke) hits SwiftData.
    @State private var saveTask: Task<Void, Never>?

    /// Bound to the "Marquer perdu" alert so the user can supply a
    /// short reason without bouncing through a separate sheet.
    @State private var showLostReasonPrompt: Bool = false
    @State private var lostReason: String = ""

    /// Drives the InvoiceSheet presentation that fires after
    /// "Marquer gagné" — the natural next step in the Numelite
    /// funnel once a lead converts.
    @State private var presentingInvoiceForWon: Bool = false

    /// User-facing error message when Claude generation fails. Nil
    /// = no banner.
    @State private var generationError: String?

    init(lead: Lead) {
        self.lead = lead
        _draftReply = State(initialValue: lead.draftReply ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                messageSection
                draftReplySection
                actionsSection
                metadataSection
            }
            .padding(20)
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .background {
            LiquidBackground().ignoresSafeArea()
        }
        .onAppear {
            MINDTelemetry.info(
                "lead.detail.opened",
                data: [
                    "leadID": lead.id.uuidString,
                    "status": lead.status,
                ]
            )
        }
        // v1.0-alpha.3 — Surface a short alert when the user picks
        // "Marquer perdu" so a reason can be captured without
        // detouring through a separate sheet.
        .alert(
            String(localized: "lead.action.lost.reasonTitle"),
            isPresented: $showLostReasonPrompt
        ) {
            TextField(
                String(localized: "lead.action.lost.reasonPlaceholder"),
                text: $lostReason
            )
            Button(String(localized: "lead.action.lost.confirm"), role: .destructive) {
                applyStatus(.lost, reason: lostReason.isEmpty ? nil : lostReason)
                lostReason = ""
            }
            Button(String(localized: "audit.button.cancel"), role: .cancel) {
                lostReason = ""
            }
        } message: {
            Text(verbatim: lead.contactName)
        }
        .sheet(isPresented: $presentingInvoiceForWon) {
            // Reuse the existing v0.31 invoice surface — pre-seeded
            // with the lead's contact info so the line items can be
            // typed without re-keying who the invoice is for.
            // `clientNodeID` is synthesized from the Lead's UUID
            // namespace so the invoice store has a stable id even
            // though leads aren't Nodes.
            InvoiceSheet(
                clientNodeID: lead.id,
                initialClientName: lead.contactName.isEmpty ? (lead.project?.name ?? "Client") : lead.contactName,
                initialClientEmail: lead.contactEmail.isEmpty ? nil : lead.contactEmail
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                avatarCircle
                VStack(alignment: .leading, spacing: 4) {
                    Text(lead.contactName.isEmpty ? lead.contactEmail : lead.contactName)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .lineLimit(2)
                    if let projectName = lead.project?.name {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(projectAccent)
                                .frame(width: 8, height: 8)
                            Text(verbatim: projectName)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                formTypePill
            }
            statusPill
        }
    }

    private var avatarCircle: some View {
        ZStack {
            Circle().fill(projectAccent.opacity(0.18))
                .frame(width: 48, height: 48)
            Text(Self.initials(of: lead.contactName.isEmpty ? lead.contactEmail : lead.contactName))
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(projectAccent)
        }
    }

    private var projectAccent: Color {
        if let hex = lead.project?.primaryColor, let color = Color(hex: hex) {
            return color
        }
        return LiquidPalette.iris
    }

    private var formTypePill: some View {
        let label: String = {
            switch lead.formTypeEnum {
            case .contact:    return String(localized: "lead.formType.contact")
            case .devis:      return String(localized: "lead.formType.devis")
            case .newsletter: return String(localized: "lead.formType.newsletter")
            case .other:      return String(localized: "lead.formType.other")
            }
        }()
        return Text(label.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(LiquidPalette.iris)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(LiquidPalette.lavender.opacity(0.35))
            }
    }

    private var statusPill: some View {
        let tint: Color
        let label: String
        switch lead.statusEnum {
        case .new:        tint = LiquidPalette.iris;     label = String(localized: "lead.status.new")
        case .qualified:  tint = .orange;                 label = String(localized: "lead.status.qualified")
        case .contacted:  tint = LiquidPalette.aqua;     label = String(localized: "lead.status.contacted")
        case .won:        tint = .green;                  label = String(localized: "lead.status.won")
        case .lost:       tint = .red;                    label = String(localized: "lead.status.lost")
        case .spam:       tint = .gray;                   label = String(localized: "lead.status.spam")
        }
        return HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            Text(lead.receivedAt.formatted(.relative(presentation: .named)))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Message

    private var messageSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("lead.detail.message")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text(verbatim: lead.message)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Draft reply (v1.0-alpha.13 — AI Reply Composer)

    /// 3-angle composer card. Sections from top to bottom:
    ///   1. Header (title + saved-check + spinner during generation)
    ///   2. Tab pills (one per variant, rendered after variants land)
    ///   3. Either:
    ///      - "Générer 3 variantes" CTA (empty initial state), or
    ///      - Shimmer skeleton (while generating), or
    ///      - The editable TextEditor pre-populated with the chosen
    ///        variant's body
    ///   4. Optional inline error banner
    private var draftReplySection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                draftReplyHeader
                if !replyVariants.isEmpty {
                    variantTabPills
                }
                draftReplyBody
                if let generationError {
                    Text(verbatim: generationError)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var draftReplyHeader: some View {
        HStack(spacing: 8) {
            Text("lead.detail.draftReply")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Spacer()
            if isGeneratingDraft {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("lead.reply.generating.label")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if savedRecently {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("lead.reply.saved.toast")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.green)
                }
                .transition(.opacity)
            } else if !replyVariants.isEmpty {
                Button {
                    Task { await generateReplyVariants() }
                } label: {
                    Label(
                        String(localized: "lead.reply.regenerate"),
                        systemImage: "arrow.clockwise"
                    )
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("lead.reply.regenerate"))
            }
        }
    }

    /// Tab pill row driving angle selection. Renders 3 capsules
    /// (Direct / Consultatif / Cas similaire) once the composer has
    /// returned. Tap = haptic .select + textarea body swap.
    private var variantTabPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(replyVariants) { variant in
                    let isSelected = selectedReplyAngle == variant.angle
                    Button {
                        LiquidHaptics.select()
                        selectedReplyAngle = variant.angle
                        draftReply = variant.body
                        scheduleDraftSave(force: true)
                        MINDTelemetry.info(
                            "lead.reply.angle.picked",
                            data: [
                                "leadID": lead.id.uuidString,
                                "angle": variant.angle.rawValue,
                            ]
                        )
                    } label: {
                        Text(variant.angle.localizedLabel)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : LiquidPalette.iris)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(
                                        isSelected
                                            ? LiquidPalette.iris.opacity(0.92)
                                            : LiquidPalette.iris.opacity(0.14)
                                    )
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(
                                        LiquidPalette.iris.opacity(isSelected ? 0.0 : 0.35),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
                Text(verbatim: " ")
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(Text("lead.reply.pick.label"))
    }

    /// Either the CTA, the shimmer skeleton, or the editable textarea
    /// depending on isGeneratingDraft + replyVariants state.
    @ViewBuilder
    private var draftReplyBody: some View {
        if isGeneratingDraft {
            shimmerSkeleton
        } else if replyVariants.isEmpty && draftReply.isEmpty {
            Button {
                Task { await generateReplyVariants() }
            } label: {
                Label(
                    String(localized: "lead.detail.generateDraft"),
                    systemImage: "sparkles"
                )
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    Capsule(style: .continuous)
                        .fill(LiquidPalette.iris.opacity(0.16))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidPalette.iris.opacity(0.35), lineWidth: 1)
                }
                .foregroundStyle(LiquidPalette.iris)
            }
            .buttonStyle(.plain)
        } else {
            TextEditor(text: $draftReply)
                .font(.system(.body, design: .rounded))
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .onChange(of: draftReply) { _, _ in
                    scheduleDraftSave(force: false)
                }
        }
    }

    /// Pulsing skeleton placeholder rendered over the textarea
    /// position while the composer is generating. Three stacked
    /// capsules approximate the variant-tab + first-line shape.
    private var shimmerSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                shimmerPill(width: 70)
                shimmerPill(width: 92)
                shimmerPill(width: 110)
            }
            VStack(spacing: 10) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LiquidPalette.iris.opacity(0.14))
                        .frame(height: 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .opacity(0.85)
        .symbolEffect(.pulse, options: .repeating)
        .accessibilityLabel(Text("lead.reply.generating.label"))
    }

    @ViewBuilder
    private func shimmerPill(width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(LiquidPalette.iris.opacity(0.18))
            .frame(width: width, height: 22)
    }

    /// True while the auto-save check icon should be visible. The
    /// flag flips off after a 1.5s window via a `.task(id:)` watcher
    /// attached to `lastSavedAt`.
    private var savedRecently: Bool {
        guard let lastSavedAt else { return false }
        return Date.now.timeIntervalSince(lastSavedAt) < 1.5
    }

    /// Generate 3 reply variants from the cloud LLM. Wipes the
    /// previous batch so the tab pills always reflect the latest
    /// generation. Telemetry is fired by the actor itself.
    @MainActor
    private func generateReplyVariants() async {
        isGeneratingDraft = true
        generationError = nil
        replyVariants = []
        selectedReplyAngle = nil
        defer { isGeneratingDraft = false }

        // Heuristic for the `similarCase` angle — find up to 3
        // active retainer projects with the same contract type as
        // the lead's project. Empty array is fine; the builder
        // gracefully falls back to a generic "peer client" line.
        let similar = similarProjectsForLead()

        do {
            let variants = try await generateLeadReply(
                lead: lead,
                project: lead.project,
                similarProjects: similar
            )
            guard !variants.isEmpty else {
                generationError = String(localized: "lead.detail.generate.failed")
                return
            }
            replyVariants = variants
            if let first = variants.first {
                selectedReplyAngle = first.angle
                draftReply = first.body
                scheduleDraftSave(force: true)
            }
        } catch {
            generationError = error.localizedDescription
        }
    }

    /// Best-effort similar-project picker for the `similarCase`
    /// grounding block. Filters to:
    ///   - Same contract type as the lead's project (oneshot ↔
    ///     oneshot, retainer ↔ retainer) so the reference matches
    ///     the buying pattern.
    ///   - lifecycleStage active or maintenance — referencing an
    ///     archived engagement weakens the warm-reply tone.
    ///   - Excluding the lead's own project (no "your project is
    ///     similar to your project" loops).
    /// Returns up to 3 candidates ordered by recent activity so
    /// the freshest case study comes first.
    private func similarProjectsForLead() -> [Project] {
        guard let leadProject = lead.project else {
            // No project context — return the top 3 most-active
            // projects so Claude still has something to reference.
            return Array(
                allProjects
                    .filter {
                        $0.lifecycleStageEnum == .active ||
                        $0.lifecycleStageEnum == .maintenance
                    }
                    .sorted { $0.lastActivityAt > $1.lastActivityAt }
                    .prefix(3)
            )
        }
        return Array(
            allProjects
                .filter { project in
                    project.id != leadProject.id &&
                    project.contractTypeEnum == leadProject.contractTypeEnum &&
                    (project.lifecycleStageEnum == .active ||
                     project.lifecycleStageEnum == .maintenance)
                }
                .sorted { $0.lastActivityAt > $1.lastActivityAt }
                .prefix(3)
        )
    }

    /// Schedules a debounced save. `force: true` flushes immediately
    /// (used after variant selection where the user *intended* the
    /// swap). `force: false` waits 500ms after the last keystroke so
    /// every character doesn't hit SwiftData.
    private func scheduleDraftSave(force: Bool) {
        saveTask?.cancel()
        let valueAtSchedule = draftReply
        saveTask = Task {
            if !force {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            if Task.isCancelled { return }
            // Read latest value off MainActor to avoid stale writes.
            await MainActor.run {
                let valueToPersist = draftReply
                guard valueAtSchedule == valueToPersist || force else { return }
                lead.draftReply = valueToPersist.isEmpty ? nil : valueToPersist
                try? context.save()
                lastSavedAt = .now
                MINDTelemetry.info(
                    "lead.draft.saved",
                    data: [
                        "leadID": lead.id.uuidString,
                        "length": String(valueToPersist.count),
                    ]
                )
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(spacing: 12) {
                actionRow(
                    icon: "checkmark.circle.fill",
                    tint: .orange,
                    title: String(localized: "lead.action.qualified"),
                    enabled: lead.statusEnum != .qualified
                ) {
                    applyStatus(.qualified)
                }
                actionRow(
                    icon: "trophy.fill",
                    tint: .green,
                    title: String(localized: "lead.action.won"),
                    enabled: lead.statusEnum != .won
                ) {
                    applyStatus(.won)
                    presentingInvoiceForWon = true
                }
                actionRow(
                    icon: "xmark.octagon.fill",
                    tint: .red,
                    title: String(localized: "lead.action.lost"),
                    enabled: lead.statusEnum != .lost
                ) {
                    showLostReasonPrompt = true
                }
                actionRow(
                    icon: "trash.slash.fill",
                    tint: .gray,
                    title: String(localized: "lead.action.spam"),
                    enabled: lead.statusEnum != .spam
                ) {
                    applyStatus(.spam)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func actionRow(
        icon: String,
        tint: Color,
        title: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            LiquidHaptics.select()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(verbatim: title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .opacity(enabled ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func applyStatus(_ newStatus: LeadStatus, reason: String? = nil) {
        let from = lead.status
        lead.statusEnum = newStatus
        lead.statusReason = reason
        // Touch the parent Project so the activity feed reflects the
        // triage event without the user having to reload.
        lead.project?.touchActivity()
        try? context.save()
        MINDTelemetry.info(
            "lead.status.changed",
            data: [
                "leadID": lead.id.uuidString,
                "from": from,
                "to": newStatus.rawValue,
            ]
        )
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        LiquidCard(cornerRadius: 20) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    metadataRow(
                        label: String(localized: "lead.metadata.sourceURL"),
                        value: lead.sourceURL.isEmpty ? "—" : lead.sourceURL
                    )
                    metadataRow(
                        label: String(localized: "lead.metadata.receivedAt"),
                        value: lead.receivedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    metadataRow(
                        label: String(localized: "lead.metadata.formType"),
                        value: lead.formType
                    )
                    if let ua = lead.userAgent {
                        metadataRow(label: String(localized: "lead.metadata.userAgent"), value: ua)
                    }
                    if let ip = lead.clientIPHash {
                        metadataRow(label: String(localized: "lead.metadata.ipHash"), value: ip)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("lead.detail.metadata")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text(verbatim: value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    // MARK: - Helpers

    /// Lift first letter of first + last word, capitalised. "Sarah
    /// Bensalem" → "SB"; an email-only fallback yields the first
    /// two letters before `@`.
    static func initials(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("@") {
            return String(trimmed.split(separator: "@").first?.prefix(2) ?? "?").uppercased()
        }
        let words = trimmed.split(separator: " ")
        guard let first = words.first?.first else { return "?" }
        if let last = words.dropFirst().last?.first {
            return String([first, last]).uppercased()
        }
        return String(first).uppercased()
    }
}

// MARK: - Reply angle label

/// Localized label for the AI Reply Composer tab pills. Lives in the
/// App layer because the FR/EN copy is the UI surface — the
/// OutreachKit `OutreachReply.Angle` enum stays a pure data type.
extension OutreachReply.Angle {
    /// FR/EN label rendered on the tab pill, sourced from
    /// `lead.reply.angle.*` in the Localizable.xcstrings catalog.
    var localizedLabel: String {
        switch self {
        case .direct:
            return String(localized: "lead.reply.angle.direct")
        case .consultative:
            return String(localized: "lead.reply.angle.consultative")
        case .similarCase:
            return String(localized: "lead.reply.angle.similarCase")
        }
    }
}

// MARK: - Color hex helper

/// Lightweight hex → Color helper used by both LeadDetailSheet and
/// ProjectsView so per-project primary colors round-trip from the
/// `Project.primaryColor` stored hex string into a SwiftUI Color
/// without dragging in a heavier color-math helper.
extension Color {
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else {
            return nil
        }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
