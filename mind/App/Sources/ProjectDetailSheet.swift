import SwiftUI
import SwiftData
import AuditKit
import DesignSystem
import GraphCore
import SwarmKit

/// v1.0-alpha.3 — Project detail surface. Five sections from top to
/// bottom:
///
/// 1. Header — name, stack badge, MRR pill, host
/// 2. Aperçu — host link, GitHub repo link, last activity timestamp
/// 3. Leads récents — last 5 leads (tap → LeadDetailSheet)
/// 4. Livrables — kind-iconed deliverable rows
/// 5. Actions — launch audit / view all leads / archive
/// 6. Notes — multi-line markdown text editor
struct ProjectDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var project: Project

    @State private var notesDraft: String
    @State private var isAuditing: Bool = false
    @State private var isSwarming: Bool = false
    @State private var selectedLead: Lead?
    @State private var showLeadsListSheet: Bool = false
    @State private var showArchiveConfirm: Bool = false

    init(project: Project) {
        self.project = project
        _notesDraft = State(initialValue: project.notes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                overviewSection
                recentLeadsSection
                deliverablesSection
                actionsSection
                notesSection
            }
            .padding(20)
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .onAppear {
            MINDTelemetry.info(
                "project.detail.opened",
                data: ["projectID": project.id.uuidString]
            )
        }
        .sheet(isPresented: $isAuditing) {
            AuditSheet(initialURL: "https://\(project.host)")
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isSwarming) {
            SwarmWizardSheet(initialProject: project)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $selectedLead) { lead in
            LeadDetailSheet(lead: lead)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showLeadsListSheet) {
            ProjectLeadsListSheet(project: project)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .alert(
            String(localized: "project.action.archive.confirm"),
            isPresented: $showArchiveConfirm
        ) {
            Button(String(localized: "project.action.archive"), role: .destructive) {
                project.lifecycleStageEnum = .archived
                project.touchActivity()
                try? context.save()
                dismiss()
            }
            Button(String(localized: "audit.button.cancel"), role: .cancel) {}
        } message: {
            Text(verbatim: project.name)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: project.name)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .lineLimit(2)
                    Text(verbatim: project.host)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                mrrPill
            }
            HStack(spacing: 8) {
                stackBadge
                contractPill
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.22))
                .frame(width: 56, height: 56)
            Text(String(project.name.first ?? "?").uppercased())
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(accent)
        }
    }

    private var accent: Color {
        Color(hex: project.primaryColor) ?? LiquidPalette.iris
    }

    private var mrrPill: some View {
        let label: String
        if project.contractTypeEnum == .retainer {
            label = ProjectMRR.formatEUR(project.monthlyRecurringRevenueEUR)
        } else {
            let format = String(localized: "project.list.oneshot.format")
            label = String(format: format, project.oneShotRevenueEUR)
        }
        return Text(verbatim: label)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background { Capsule().fill(accent.opacity(0.92)) }
    }

    private var stackBadge: some View {
        Text(stackLabel.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background { Capsule().fill(accent.opacity(0.16)) }
    }

    private var contractPill: some View {
        let label: String = project.contractTypeEnum == .retainer
            ? String(localized: "project.contract.retainer")
            : String(localized: "project.contract.oneshot")
        return Text(label.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background { Capsule().fill(.ultraThinMaterial) }
    }

    private var stackLabel: String {
        switch project.stackEnum {
        case .nextjs:     return "Next.js"
        case .wordpress:  return "WordPress"
        case .shopify:    return "Shopify"
        case .staticSite: return "Static"
        case .other:      return "Custom"
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("project.detail.overview")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                overviewRow(
                    icon: "globe",
                    label: String(localized: "project.detail.host"),
                    value: project.host,
                    url: URL(string: "https://\(project.host)")
                )
                if let repo = project.githubRepo {
                    overviewRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        label: "GitHub",
                        value: repo,
                        url: URL(string: "https://github.com/\(repo)")
                    )
                }
                overviewRow(
                    icon: "clock.fill",
                    label: String(localized: "project.detail.lastActivity"),
                    value: project.lastActivityAt.formatted(.relative(presentation: .named)),
                    url: nil
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func overviewRow(
        icon: String,
        label: String,
        value: String,
        url: URL?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let url {
                    Link(destination: url) {
                        Text(verbatim: value)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(LiquidPalette.iris)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text(verbatim: value)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    // MARK: - Recent leads

    private var recentLeads: [Lead] {
        let all = project.leads ?? []
        return Array(LeadInboxSorter.sort(all, by: .dateDescending).prefix(5))
    }

    private var recentLeadsSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("project.detail.leads.recent")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    Text("\(project.leads?.count ?? 0)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if recentLeads.isEmpty {
                    Text("project.detail.leads.empty")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(recentLeads) { lead in
                            Button {
                                selectedLead = lead
                            } label: {
                                leadRow(lead)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func leadRow(_ lead: Lead) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: lead.contactName.isEmpty ? lead.contactEmail : lead.contactName)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(verbatim: lead.message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(lead.receivedAt.formatted(.relative(presentation: .named)))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Deliverables

    private var deliverablesSection: some View {
        let deliverables = (project.deliverables ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(6)
        return LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("project.detail.deliverables")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                if deliverables.isEmpty {
                    Text("project.detail.deliverables.empty")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(deliverables)) { deliverable in
                            HStack(spacing: 10) {
                                Image(systemName: Self.icon(for: deliverable.kindEnum))
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: deliverable.title)
                                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(deliverable.createdAt.formatted(.relative(presentation: .named)))
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func icon(for kind: DeliverableKind) -> String {
        switch kind {
        case .page:       return "doc.text.fill"
        case .screenshot: return "photo.fill"
        case .audit:      return "speedometer"
        case .invoice:    return "doc.richtext.fill"
        case .asset:      return "shippingbox.fill"
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(spacing: 12) {
                actionRow(
                    icon: "magnifyingglass",
                    tint: LiquidPalette.iris,
                    title: String(localized: "project.action.audit")
                ) {
                    isAuditing = true
                }
                actionRow(
                    icon: "tornado",
                    tint: LiquidPalette.aqua,
                    title: "Lancer un swarm SEO"
                ) {
                    isSwarming = true
                }
                actionRow(
                    icon: "tray.full.fill",
                    tint: LiquidPalette.aqua,
                    title: String(localized: "project.action.leads")
                ) {
                    showLeadsListSheet = true
                }
                actionRow(
                    icon: "archivebox.fill",
                    tint: .gray,
                    title: String(localized: "project.action.archive"),
                    enabled: project.lifecycleStageEnum != .archived
                ) {
                    showArchiveConfirm = true
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
        enabled: Bool = true,
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

    // MARK: - Notes

    private var notesSection: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("project.detail.notes")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                TextEditor(text: $notesDraft)
                    .font(.system(.body, design: .rounded))
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .onChange(of: notesDraft) { _, newValue in
                        project.notes = newValue
                        try? context.save()
                    }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - ProjectLeadsListSheet

/// v1.0-alpha.3 — Full per-Project lead list (vs. the top-5 preview
/// on the detail sheet). Reuses LeadInboxSorter for consistency.
struct ProjectLeadsListSheet: View {
    let project: Project

    @State private var sortKey: LeadInboxSorter.SortKey = .dateDescending
    @State private var selectedLead: Lead?

    private var sortedLeads: [Lead] {
        LeadInboxSorter.sort(project.leads ?? [], by: sortKey)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("project.detail.leads.recent")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text(verbatim: project.name)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Picker(
                    String(localized: "lead.sort.label"),
                    selection: $sortKey
                ) {
                    Text(String(localized: "lead.sort.recent")).tag(LeadInboxSorter.SortKey.dateDescending)
                    Text(String(localized: "lead.sort.status")).tag(LeadInboxSorter.SortKey.statusPriority)
                }
                .pickerStyle(.segmented)
                if sortedLeads.isEmpty {
                    Text("project.detail.leads.empty")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(sortedLeads) { lead in
                            Button {
                                selectedLead = lead
                            } label: {
                                LiquidCard(cornerRadius: 16) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(verbatim: lead.contactName.isEmpty ? lead.contactEmail : lead.contactName)
                                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(verbatim: lead.message)
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        Text(lead.receivedAt.formatted(.relative(presentation: .named)))
                                            .font(.system(.caption2, design: .rounded))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(12)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .sheet(item: $selectedLead) { lead in
            LeadDetailSheet(lead: lead)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }
}

// MARK: - NewProjectSheet

/// v1.0-alpha.3 — Minimal "Nouveau projet" form. Captures the fields
/// the cockpit list needs immediately; v1.0-alpha.6 will replace
/// this with the full scaffolder wizard.
struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var githubRepo: String = ""
    @State private var stack: ProjectStack = .nextjs
    @State private var contractType: ProjectContractType = .oneshot
    @State private var mrr: String = ""
    @State private var oneShot: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "project.new.section.identity")) {
                    TextField(String(localized: "project.new.name"), text: $name)
                    TextField(String(localized: "project.new.host"), text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(String(localized: "project.new.repo"), text: $githubRepo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section(String(localized: "project.new.section.stack")) {
                    Picker(String(localized: "project.new.stack"), selection: $stack) {
                        ForEach(ProjectStack.allCases, id: \.self) { value in
                            Text(verbatim: value.rawValue.capitalized).tag(value)
                        }
                    }
                }
                Section(String(localized: "project.new.section.revenue")) {
                    Picker(String(localized: "project.new.contract"), selection: $contractType) {
                        Text(String(localized: "project.contract.oneshot")).tag(ProjectContractType.oneshot)
                        Text(String(localized: "project.contract.retainer")).tag(ProjectContractType.retainer)
                    }
                    if contractType == .retainer {
                        TextField(String(localized: "project.new.mrr"), text: $mrr)
                            .keyboardType(.numberPad)
                    } else {
                        TextField(String(localized: "project.new.oneshot"), text: $oneShot)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle(Text("project.new.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "audit.button.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "project.new.save")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let project = Project(
            name: name.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            githubRepo: githubRepo.isEmpty ? nil : githubRepo,
            stack: stack,
            contractType: contractType,
            monthlyRecurringRevenueEUR: contractType == .retainer ? (Int(mrr) ?? 0) : 0,
            oneShotRevenueEUR: contractType == .oneshot ? (Int(oneShot) ?? 0) : 0
        )
        context.insert(project)
        try? context.save()
        MINDTelemetry.info(
            "project.new.created",
            data: [
                "projectID": project.id.uuidString,
                "stack": project.stack,
                "contractType": project.contractType,
            ]
        )
        dismiss()
    }
}
