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
/// 3. Draft reply — editable text editor. If empty, a "Générer brouillon"
///    CTA fires `OutreachEmailGenerator.shared.generate(...)` using the
///    same `ProspectContext` pipeline OutreachSheet uses. The first
///    returned variant's body is written back into `lead.draftReply`.
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

    @Bindable var lead: Lead

    /// Local mirror of `lead.draftReply` so the TextEditor binds to a
    /// non-optional. Pushed back on every edit.
    @State private var draftReply: String

    /// Latch while the OutreachEmailGenerator round-trips so the
    /// "Générer brouillon" CTA can swap to a progress label.
    @State private var isGeneratingDraft: Bool = false

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

    // MARK: - Draft reply

    private var draftReplySection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("lead.detail.draftReply")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    if isGeneratingDraft {
                        ProgressView().controlSize(.small)
                    }
                }
                if draftReply.isEmpty && !isGeneratingDraft {
                    Button {
                        Task { await generateDraft() }
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
                        .onChange(of: draftReply) { _, newValue in
                            lead.draftReply = newValue.isEmpty ? nil : newValue
                            try? context.save()
                        }
                }
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

    private func generateDraft() async {
        isGeneratingDraft = true
        generationError = nil
        defer { isGeneratingDraft = false }
        let prospect = ProspectContext(
            clientName: lead.project?.name ?? lead.contactName,
            host: lead.project?.host ?? "",
            recentTrigger: lead.message,
            primaryContactName: lead.contactName.isEmpty ? nil : lead.contactName
        )
        do {
            let variants = try await OutreachEmailGenerator.shared.generate(
                prospect: prospect,
                variantCount: 1
            )
            guard let first = variants.first else {
                generationError = String(localized: "lead.detail.generate.failed")
                return
            }
            draftReply = first.body
            lead.draftReply = first.body
            try? context.save()
        } catch {
            generationError = error.localizedDescription
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
