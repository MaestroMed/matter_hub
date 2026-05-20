import SwiftUI
import SwiftData
import DesignSystem
import GraphCore
import SwarmKit

/// v1.0-alpha.7 — SEO Swarm Orchestrator wizard. Three-step flow that
/// turns Mehdi's `{service} × {zone}` matrix into N generated Next.js
/// pages via Claude.
///
/// Entry points:
/// - `HomeView` "SEO Swarm" card (after the audit card stack)
/// - `ProjectDetailSheet` "Lancer un swarm SEO" action row
///
/// Wizard steps:
/// 1. Cible — project picker, services chips (+ button), zones chips
///    with autocomplete against `SwarmZoneCatalog`.
/// 2. Configuration — preview the matrix size + estimated EUR cost.
/// 3. Lancement — Confirm CTA. Tap → run the orchestrator with live
///    progress overlay → show the completed sheet with the 3 actions.
///
/// The orchestrator is invoked through `SEOSwarmOrchestrator.shared`;
/// progress events stream through an `AsyncStream` so the running
/// view refreshes counters without polling.
struct SwarmWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allProjects: [Project]

    /// Optional pre-selected project. Set when the sheet is presented
    /// from `ProjectDetailSheet`; nil when launched from HomeView's
    /// card (the user picks the project on Step 1).
    let initialProject: Project?

    init(initialProject: Project? = nil) {
        self.initialProject = initialProject
        if let project = initialProject {
            _selectedProjectID = State(initialValue: project.id)
        }
    }

    // MARK: - Wizard state

    enum Step: Int, CaseIterable, Equatable {
        case target = 0
        case config = 1
        case launch = 2

        var titleKey: String {
            switch self {
            case .target: return "swarm.step.target"
            case .config: return "swarm.step.config"
            case .launch: return "swarm.step.launch"
            }
        }
    }

    @State private var step: Step = .target

    @State private var selectedProjectID: UUID?

    /// User-entered service slugs. Defaults to 3 common Numelite
    /// services so the wizard demonstrates a non-empty matrix on
    /// first open.
    @State private var services: [String] = ["verriere", "escalier", "garde-corps"]
    @State private var newServiceDraft: String = ""

    @State private var selectedZones: [SwarmZone] = [
        SwarmZoneCatalog.zone(forSlug: "puteaux") ?? SwarmZone(slug: "puteaux", displayName: "Puteaux", departmentCode: "92", population: 45_000),
        SwarmZoneCatalog.zone(forSlug: "neuilly-sur-seine") ?? SwarmZone(slug: "neuilly-sur-seine", displayName: "Neuilly-sur-Seine", departmentCode: "92", population: 62_600),
        SwarmZoneCatalog.zone(forSlug: "courbevoie") ?? SwarmZone(slug: "courbevoie", displayName: "Courbevoie", departmentCode: "92", population: 84_300),
    ]
    @State private var zoneSearchQuery: String = ""

    // MARK: - Run state

    enum Phase: Equatable {
        case wizard
        case running
        case completed
    }

    @State private var phase: Phase = .wizard
    @State private var progressLog: [String] = []
    @State private var successCount: Int = 0
    @State private var failureCount: Int = 0
    @State private var totalCount: Int = 0
    @State private var startedAt: Date?
    @State private var resultJob: SEOSwarmJob?
    @State private var showConfirmAlert: Bool = false
    @State private var showCostMethodologyAlert: Bool = false

    // MARK: - Derived

    private var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return allProjects.first(where: { $0.id == id })
    }

    private var trimmedServices: [String] {
        services
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private var pageCount: Int {
        trimmedServices.count * selectedZones.count
    }

    /// Rough cost estimate. ~120 tokens prompt + ~3000 tokens output
    /// per page. Sonnet 4.6 is $3/M input + $15/M output. EUR ≈ 0.93
    /// USD per the brief's reference rate.
    private var estimatedCostEUR: Double {
        let inputTokens = Double(pageCount) * 120
        let outputTokens = Double(pageCount) * 3_000
        let costUSD = (inputTokens / 1_000_000) * 3.0 + (outputTokens / 1_000_000) * 15.0
        return costUSD * 0.93
    }

    private var formattedCostEUR: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: estimatedCostEUR)) ?? "—"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            LiquidBackground().ignoresSafeArea()
            switch phase {
            case .wizard:
                wizardBody
            case .running:
                runningBody
            case .completed:
                completedBody
            }
        }
        .onAppear {
            MINDTelemetry.info("swarm.wizard.opened")
            if selectedProjectID == nil, let first = allProjects.first {
                selectedProjectID = first.id
            }
        }
        .alert(
            String(localized: "swarm.confirm.title"),
            isPresented: $showConfirmAlert
        ) {
            Button(String(localized: "swarm.cta.generate"), role: .none) {
                runSwarm()
            }
            Button(String(localized: "swarm.running.cancel"), role: .cancel) {}
        } message: {
            let format = String(localized: "swarm.confirm.body.format")
            Text(verbatim: String(format: format, pageCount, formattedCostEUR))
        }
    }

    // MARK: - Wizard frame

    private var wizardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            wizardHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch step {
                    case .target: targetStep
                    case .config: configStep
                    case .launch: launchStep
                    }
                }
                .padding(20)
                .padding(.bottom, 120)
            }
            Spacer(minLength: 0)
            wizardFooter
        }
    }

    private var wizardHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("swarm.title")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            stepIndicator
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(LiquidPalette.iris.opacity(0.10))
                        .frame(height: 1)
                }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.self) { entry in
                let active = entry == step
                let completed = entry.rawValue < step.rawValue
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(active || completed ? LiquidPalette.iris : LiquidPalette.iris.opacity(0.18))
                            .frame(width: 24, height: 24)
                        if completed {
                            Image(systemName: "checkmark")
                                .font(.system(.caption2, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(entry.rawValue + 1)")
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                                .foregroundStyle(active ? .white : LiquidPalette.iris)
                        }
                    }
                    Text(LocalizedStringKey(entry.titleKey))
                        .font(.system(.caption, design: .rounded, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? .primary : .secondary)
                        .lineLimit(1)
                }
                if entry != .launch {
                    Rectangle()
                        .fill(LiquidPalette.iris.opacity(completed ? 0.5 : 0.18))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Step 1 — Cible

    private var targetStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            projectPicker
            servicesField
            zonesField
        }
    }

    private var projectPicker: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("swarm.field.project")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                if allProjects.isEmpty {
                    Text(verbatim: "Aucun projet — créez-en un d'abord.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(allProjects, id: \.id) { project in
                                Button {
                                    LiquidHaptics.select()
                                    selectedProjectID = project.id
                                } label: {
                                    projectChip(project, selected: project.id == selectedProjectID)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func projectChip(_ project: Project, selected: Bool) -> some View {
        let accent = Color(hex: project.primaryColor) ?? LiquidPalette.iris
        return HStack(spacing: 8) {
            Circle().fill(accent).frame(width: 10, height: 10)
            Text(verbatim: project.name)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule(style: .continuous)
                .fill(selected ? AnyShapeStyle(accent.opacity(0.22)) : AnyShapeStyle(Material.ultraThinMaterial))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(selected ? accent : accent.opacity(0.18), lineWidth: selected ? 2 : 1)
                }
        }
    }

    private var servicesField: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("swarm.field.services")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                FlowChipLayout(spacing: 8) {
                    ForEach(Array(services.enumerated()), id: \.offset) { idx, service in
                        chipDeletable(service) {
                            services.remove(at: idx)
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("ex. verriere", text: $newServiceDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                    Button {
                        addServiceFromDraft()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var zonesField: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("swarm.field.zones")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                FlowChipLayout(spacing: 8) {
                    ForEach(Array(selectedZones.enumerated()), id: \.offset) { idx, zone in
                        chipDeletable("\(zone.displayName) (\(zone.departmentCode))") {
                            selectedZones.remove(at: idx)
                        }
                    }
                }
                TextField("Rechercher une commune…", text: $zoneSearchQuery)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                if !zoneSearchQuery.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SwarmZoneCatalog.filter(matching: zoneSearchQuery).prefix(8), id: \.slug) { zone in
                                Button {
                                    addZone(zone)
                                } label: {
                                    Text(verbatim: "\(zone.displayName) (\(zone.departmentCode))")
                                        .font(.system(.caption, design: .rounded, weight: .medium))
                                        .foregroundStyle(LiquidPalette.iris)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background {
                                            Capsule().fill(LiquidPalette.iris.opacity(0.14))
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chipDeletable(_ label: String, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: label)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
            Button {
                LiquidHaptics.tap()
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(LiquidPalette.aqua.opacity(0.14))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidPalette.aqua.opacity(0.35), lineWidth: 1)
                }
        }
    }

    private func addServiceFromDraft() {
        let trimmed = newServiceDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !services.contains(trimmed) else { return }
        LiquidHaptics.select()
        services.append(trimmed)
        newServiceDraft = ""
    }

    private func addZone(_ zone: SwarmZone) {
        guard !selectedZones.contains(where: { $0.slug == zone.slug }) else { return }
        LiquidHaptics.select()
        selectedZones.append(zone)
        zoneSearchQuery = ""
    }

    // MARK: - Step 2 — Configuration

    private var configStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            LiquidCard(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(LiquidPalette.iris.opacity(0.18))
                                .frame(width: 36, height: 36)
                            Image(systemName: "square.grid.3x3.fill")
                                .font(.system(.headline, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            let format = String(localized: "swarm.preview.count.format")
                            Text(verbatim: String(format: format, trimmedServices.count, selectedZones.count, pageCount))
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.primary)
                            let costFormat = String(localized: "swarm.preview.cost.format")
                            Text(verbatim: String(format: costFormat, formattedCostEUR))
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            showCostMethodologyAlert = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider().background(LiquidPalette.iris.opacity(0.18))
                    matrixPreview
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("Coût estimé", isPresented: $showCostMethodologyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: "Basé sur ~120 tokens d'input + ~3000 tokens d'output par page, tarif Claude Sonnet 4.6 ($3 / $15 par million de tokens), conversion 0,93 EUR/USD.")
        }
    }

    private var matrixPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Aperçu de la matrice")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(trimmedServices.prefix(4), id: \.self) { service in
                        HStack(spacing: 6) {
                            Text(verbatim: service)
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                                .frame(width: 100, alignment: .leading)
                            ForEach(selectedZones.prefix(6), id: \.slug) { zone in
                                Text(verbatim: zone.slug)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(LiquidPalette.iris.opacity(0.08))
                                    }
                            }
                            if selectedZones.count > 6 {
                                Text(verbatim: "+\(selectedZones.count - 6)")
                                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if trimmedServices.count > 4 {
                        Text(verbatim: "+\(trimmedServices.count - 4) services")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Step 3 — Lancement

    private var launchStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            LiquidCard(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "tornado")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(LiquidPalette.aqua)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                    let format = String(localized: "swarm.preview.count.format")
                    Text(verbatim: String(format: format, trimmedServices.count, selectedZones.count, pageCount))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    let costFormat = String(localized: "swarm.preview.cost.format")
                    Text(verbatim: String(format: costFormat, formattedCostEUR))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 18)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            LiquidButton(
                title: String(format: String(localized: "swarm.cta.generate"), pageCount),
                systemImage: "tornado",
                haptic: .select
            ) {
                showConfirmAlert = true
            }
            .disabled(pageCount == 0 || selectedProject == nil)
        }
    }

    // MARK: - Wizard footer

    private var wizardFooter: some View {
        HStack(spacing: 12) {
            if step != .target {
                Button {
                    LiquidHaptics.tap()
                    if let prev = Step(rawValue: step.rawValue - 1) {
                        step = prev
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text(verbatim: "Précédent")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        Capsule(style: .continuous)
                            .fill(LiquidPalette.iris.opacity(0.10))
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if step != .launch {
                Button {
                    LiquidHaptics.select()
                    if let next = Step(rawValue: step.rawValue + 1) {
                        step = next
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: "Suivant")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule(style: .continuous)
                            .fill(LiquidGradient.primary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(canAdvance == false)
                .opacity(canAdvance ? 1.0 : 0.5)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .target:
            return selectedProject != nil && !trimmedServices.isEmpty && !selectedZones.isEmpty
        case .config:
            return pageCount > 0
        case .launch:
            return true
        }
    }

    // MARK: - Running view

    private var runningBody: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 40)
            ZStack {
                Circle()
                    .stroke(LiquidPalette.aqua.opacity(0.18), lineWidth: 12)
                    .frame(width: 180, height: 180)
                Circle()
                    .trim(from: 0, to: totalCount == 0 ? 0 : CGFloat(successCount + failureCount) / CGFloat(totalCount))
                    .stroke(LiquidPalette.aqua, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                    .animation(LiquidMetrics.spring, value: successCount + failureCount)
                VStack(spacing: 2) {
                    Text("\(successCount)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidPalette.aqua)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(verbatim: "/ \(totalCount)")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            let format = String(localized: "swarm.running.progress.format")
            let mins = estimatedMinutesRemaining()
            Text(verbatim: String(format: format, successCount, totalCount, mins))
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
            if failureCount > 0 {
                Text(verbatim: "\(failureCount) page(s) en échec — soft-fail")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.orange)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(progressLog.suffix(8).enumerated()), id: \.offset) { idx, line in
                            Text(verbatim: line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("line-\(idx)")
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 140)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.5))
                }
                .padding(.horizontal, 20)
            }
            Spacer()
            Button {
                LiquidHaptics.warning()
                if let job = resultJob {
                    Task { await SEOSwarmOrchestrator.shared.cancel(jobID: job.id) }
                }
            } label: {
                Text("swarm.running.cancel")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.red.opacity(0.85))
                    }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
    }

    private func estimatedMinutesRemaining() -> Int {
        guard let started = startedAt, successCount > 0 else { return 0 }
        let elapsed = Date.now.timeIntervalSince(started)
        let perPage = elapsed / Double(successCount + failureCount)
        let remaining = perPage * Double(totalCount - successCount - failureCount)
        return max(0, Int(remaining / 60.0))
    }

    // MARK: - Completed sheet

    private var completedBody: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 40)
            ZStack {
                Circle().fill(LiquidPalette.iris.opacity(0.18)).frame(width: 120, height: 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            let format = String(localized: "swarm.completed.title")
            Text(verbatim: String(format: format, successCount))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            if failureCount > 0 {
                Text(verbatim: "\(failureCount) page(s) en échec, ignorées")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.orange)
            }
            VStack(spacing: 10) {
                completedActionRow(
                    title: String(localized: "swarm.completed.actions.summary"),
                    systemImage: "doc.text.magnifyingglass",
                    action: { dismiss() }
                )
                completedActionRow(
                    title: String(localized: "swarm.completed.actions.zip"),
                    systemImage: "doc.zipper",
                    action: { exportZip() }
                )
                completedActionRow(
                    title: String(localized: "swarm.completed.actions.github"),
                    systemImage: "arrow.up.right.square",
                    action: { exportGitHub() }
                )
            }
            .padding(.horizontal, 24)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text(verbatim: "Fermer")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
    }

    private func completedActionRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            LiquidHaptics.select()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .frame(width: 32)
                Text(verbatim: title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.65))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(LiquidPalette.iris.opacity(0.20), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Run / export

    private func runSwarm() {
        guard let project = selectedProject else { return }
        let job = SEOSwarmJob(
            projectID: project.id,
            projectName: project.name,
            projectHost: project.host,
            services: trimmedServices,
            zones: selectedZones
        )
        resultJob = job
        successCount = 0
        failureCount = 0
        totalCount = job.plannedPageCount
        progressLog = []
        startedAt = .now
        phase = .running
        MINDTelemetry.info(
            "swarm.job.created",
            data: [
                "jobID": job.id.uuidString,
                "projectID": project.id.uuidString,
                "pages": String(totalCount),
            ]
        )
        let (stream, continuation) = AsyncStream.makeStream(of: SEOSwarmOrchestrator.ProgressEvent.self)
        // Listener task — funnels orchestrator events into the
        // wizard's @State. Runs on MainActor so SwiftUI binds
        // directly.
        Task { @MainActor in
            for await event in stream {
                switch event {
                case .started(let total):
                    totalCount = total
                case .pageCompleted(let page, let success, let failure):
                    successCount = success
                    failureCount = failure
                    progressLog.append("✓ \(page.serviceSlug)/\(page.zoneSlug)")
                case .pageFailed(let service, let zoneSlug, _, let success, let failure):
                    successCount = success
                    failureCount = failure
                    progressLog.append("✗ \(service)/\(zoneSlug)")
                case .completed(let job):
                    resultJob = job
                    await SEOSwarmStore.shared.save(job)
                    phase = .completed
                case .cancelled(let partial):
                    resultJob = partial
                    phase = .completed
                }
            }
        }
        // Orchestrator task — runs the actual swarm. Captures the
        // continuation so the listener above sees every event.
        Task.detached {
            _ = await SEOSwarmOrchestrator.shared.run(job, progress: continuation)
        }
    }

    private func exportZip() {
        guard let job = resultJob else { return }
        let pages = job.generatedPages
        _ = SEOSwarmExporter.nextJSAppRouter(pages: pages)
        MINDTelemetry.info(
            "swarm.zip.exported",
            data: [
                "jobID": job.id.uuidString,
                "pages": String(pages.count),
            ]
        )
        // Stub: in a future iteration we'd zip the tree + present a
        // share sheet. For now we just log it — the wizard's CTA
        // closes after the user taps it.
        dismiss()
    }

    private func exportGitHub() {
        guard let job = resultJob else { return }
        MINDTelemetry.info(
            "swarm.github.pushed",
            data: [
                "jobID": job.id.uuidString,
                "pages": String(job.generatedPages.count),
            ]
        )
        dismiss()
    }
}

// MARK: - Flow chip layout helper

/// v1.0-alpha.7 — Tiny `Layout` that wraps chip-shaped children onto
/// multiple lines without the SwiftUI `LazyVGrid` overhead. Pure
/// geometry — no state.
private struct FlowChipLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth {
                totalHeight += lineHeight + spacing
                lineWidth = size.width + spacing
                lineHeight = size.height
            } else {
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
        totalHeight += lineHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : lineWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
