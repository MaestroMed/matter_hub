import SwiftUI
import SwiftData
import UIKit
import BootstrapKit
import DesignSystem
import GraphCore

/// v1.0-alpha.6 — Bootstrap Scaffolder.
///
/// 3-step wizard that captures the data needed to mint a fresh
/// Next.js client site:
///
///   - Step 1 (Identity): name, slug (auto-derived, editable),
///     host, GitHub org.
///   - Step 2 (Stack): stack picker (Liquid pills), contract type,
///     MRR (when retainer), primary color picker (5 preset chips
///     iris/aqua/sky/orange/violet + custom hex).
///   - Step 3 (Modules): 4 toggles for the optional bundles
///     (admin / blog MDX / i18n FR-EN / Stripe).
///
/// Tap "Générer" on step 3 → produces a `BootstrapBlueprint`, mints
/// a `Project` row in SwiftData, presents `BootstrapResultSheet`
/// with the 3 export options + a "Voir le projet" CTA.
struct BootstrapWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Optional callback fired when the wizard finishes successfully.
    /// HomeView passes a closure that flips the cockpit tab to
    /// `.clients` (the projects tab) and scrolls to the new row.
    let onProjectCreated: ((Project) -> Void)?

    init(onProjectCreated: ((Project) -> Void)? = nil) {
        self.onProjectCreated = onProjectCreated
    }

    @State private var step: Int = 0

    // Step 1 — Identity
    @State private var projectName: String = ""
    @State private var slug: String = ""
    @State private var host: String = ""
    @State private var githubOrg: String = "MaestroMed"
    /// User edited the slug manually — stop auto-deriving from name.
    @State private var slugEditedManually: Bool = false

    // Step 2 — Stack
    @State private var stack: ProjectStack = .nextjs
    @State private var contractType: ProjectContractType = .oneshot
    @State private var mrr: String = ""
    @State private var primaryColor: String = "#5E5BD8"

    // Step 3 — Modules
    @State private var includeAdmin: Bool = false
    @State private var includeBlog: Bool = false
    @State private var includeI18n: Bool = false
    @State private var includeStripe: Bool = false

    /// Filled when the wizard finishes; presents the result sheet.
    @State private var resultBlueprint: BootstrapBlueprint?
    @State private var resultProject: Project?

    private let colorPresets: [(name: String, hex: String)] = [
        ("Iris",   "#5E5BD8"),
        ("Aqua",   "#3FB9AE"),
        ("Sky",    "#1F6FEB"),
        ("Orange", "#F0883E"),
        ("Violet", "#A371F7"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressDots
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                TabView(selection: $step) {
                    identityStep.tag(0)
                    stackStep.tag(1)
                    modulesStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .horizontal)

                bottomBar
            }
            .navigationTitle(Text("bootstrap.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "audit.button.cancel")) { dismiss() }
                }
            }
            .onAppear {
                MINDTelemetry.info("bootstrap.wizard.opened")
            }
            .onChange(of: projectName) { _, newValue in
                if !slugEditedManually {
                    slug = Project.normalizeSlug(newValue)
                }
            }
            .sheet(item: $resultBlueprint) { blueprint in
                BootstrapResultSheet(
                    blueprint: blueprint,
                    project: resultProject,
                    onViewProject: { project in
                        resultBlueprint = nil
                        dismiss()
                        onProjectCreated?(project)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { idx in
                Capsule(style: .continuous)
                    .fill(idx == step ? AnyShapeStyle(LiquidGradient.primary) : AnyShapeStyle(Color.secondary.opacity(0.2)))
                    .frame(width: idx == step ? 28 : 10, height: 8)
                    .animation(LiquidMetrics.spring, value: step)
            }
        }
    }

    // MARK: - Step 1: Identity

    private var identityStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepHeader(
                    title: String(localized: "bootstrap.step.identity"),
                    icon: "person.text.rectangle.fill",
                    tint: LiquidPalette.iris
                )
                LiquidCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        fieldRow(
                            label: String(localized: "bootstrap.field.name"),
                            placeholder: "AZ Construction",
                            text: $projectName,
                            autocapitalize: .words
                        )
                        Divider()
                        fieldRow(
                            label: String(localized: "bootstrap.field.slug"),
                            placeholder: "az-construction",
                            text: $slug,
                            autocapitalize: .never,
                            onEdit: { slugEditedManually = true }
                        )
                        Divider()
                        fieldRow(
                            label: String(localized: "bootstrap.field.host"),
                            placeholder: "www.azconstruction.fr",
                            text: $host,
                            autocapitalize: .never
                        )
                        Divider()
                        fieldRow(
                            label: String(localized: "bootstrap.field.org"),
                            placeholder: "MaestroMed",
                            text: $githubOrg,
                            autocapitalize: .never
                        )
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Step 2: Stack

    private var stackStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepHeader(
                    title: String(localized: "bootstrap.step.stack"),
                    icon: "shippingbox.fill",
                    tint: LiquidPalette.aqua
                )

                // Stack pills
                LiquidCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("bootstrap.field.stack")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                stackPill(.nextjs, label: String(localized: "bootstrap.stack.nextjs"))
                                stackPill(.wordpress, label: String(localized: "bootstrap.stack.wordpress"))
                                stackPill(.shopify, label: String(localized: "bootstrap.stack.shopify"))
                                stackPill(.staticSite, label: String(localized: "bootstrap.stack.static"))
                                stackPill(.other, label: String(localized: "bootstrap.stack.other"))
                            }
                        }
                    }
                    .padding(16)
                }

                // Contract type
                LiquidCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("bootstrap.field.contract")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Picker("", selection: $contractType) {
                            Text(String(localized: "bootstrap.contract.oneshot"))
                                .tag(ProjectContractType.oneshot)
                            Text(String(localized: "bootstrap.contract.retainer"))
                                .tag(ProjectContractType.retainer)
                        }
                        .pickerStyle(.segmented)

                        if contractType == .retainer {
                            HStack {
                                Text("bootstrap.field.mrr")
                                    .font(.system(.subheadline, design: .rounded))
                                Spacer()
                                TextField("290", text: $mrr)
                                    .keyboardType(.numberPad)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                                Text(verbatim: "€/mo")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                }

                // Color picker
                LiquidCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("bootstrap.field.color")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        HStack(spacing: 10) {
                            ForEach(colorPresets, id: \.hex) { preset in
                                colorChip(hex: preset.hex)
                            }
                        }
                        HStack {
                            Text("Hex")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                            TextField("#5E5BD8", text: $primaryColor)
                                .font(.system(.caption, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Step 3: Modules

    private var modulesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepHeader(
                    title: String(localized: "bootstrap.step.modules"),
                    icon: "puzzlepiece.extension.fill",
                    tint: LiquidPalette.lavender
                )
                LiquidCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        moduleToggle(
                            label: String(localized: "bootstrap.module.admin"),
                            detail: String(localized: "bootstrap.module.admin.detail"),
                            icon: "lock.shield.fill",
                            isOn: $includeAdmin
                        )
                        Divider()
                        moduleToggle(
                            label: String(localized: "bootstrap.module.blog"),
                            detail: String(localized: "bootstrap.module.blog.detail"),
                            icon: "newspaper.fill",
                            isOn: $includeBlog
                        )
                        Divider()
                        moduleToggle(
                            label: String(localized: "bootstrap.module.i18n"),
                            detail: String(localized: "bootstrap.module.i18n.detail"),
                            icon: "globe",
                            isOn: $includeI18n
                        )
                        Divider()
                        moduleToggle(
                            label: String(localized: "bootstrap.module.stripe"),
                            detail: String(localized: "bootstrap.module.stripe.detail"),
                            icon: "creditcard.fill",
                            isOn: $includeStripe
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    LiquidHaptics.select()
                    withAnimation(LiquidMetrics.spring) {
                        step -= 1
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(verbatim: "Retour")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                LiquidHaptics.tap()
                if step < 2 {
                    withAnimation(LiquidMetrics.spring) {
                        step += 1
                    }
                } else {
                    generate()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: step < 2 ? "Suivant" : String(localized: "bootstrap.cta.generate"))
                    Image(systemName: step < 2 ? "chevron.right" : "sparkles")
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background {
                    Capsule(style: .continuous)
                        .fill(LiquidGradient.primary)
                }
                .shadow(color: LiquidPalette.iris.opacity(0.35), radius: 12, y: 4)
                .opacity(canAdvance ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 0:
            return !projectName.trimmingCharacters(in: .whitespaces).isEmpty
                && !slug.trimmingCharacters(in: .whitespaces).isEmpty
                && !host.trimmingCharacters(in: .whitespaces).isEmpty
        case 1, 2:
            return true
        default:
            return false
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepHeader(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text(verbatim: "Étape \(step + 1) sur 3")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func fieldRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        autocapitalize: TextInputAutocapitalization,
        onEdit: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Text(verbatim: label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .textInputAutocapitalization(autocapitalize)
                .autocorrectionDisabled()
                .onChange(of: text.wrappedValue) { _, _ in onEdit?() }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func stackPill(_ value: ProjectStack, label: String) -> some View {
        let isActive = stack == value
        Button {
            LiquidHaptics.select()
            stack = value
        } label: {
            Text(verbatim: label)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(isActive ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            isActive
                                ? AnyShapeStyle(LiquidGradient.primary)
                                : AnyShapeStyle(.ultraThinMaterial)
                        )
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func colorChip(hex: String) -> some View {
        let isActive = primaryColor.lowercased() == hex.lowercased()
        Button {
            LiquidHaptics.select()
            primaryColor = hex
        } label: {
            Circle()
                .fill(Color(hex: hex) ?? LiquidPalette.iris)
                .frame(width: 36, height: 36)
                .overlay {
                    Circle()
                        .stroke(isActive ? Color.white : Color.clear, lineWidth: 3)
                }
                .overlay {
                    Circle()
                        .stroke(isActive ? (Color(hex: hex) ?? LiquidPalette.iris).opacity(0.5) : Color.clear, lineWidth: 5)
                        .blur(radius: 2)
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func moduleToggle(
        label: String,
        detail: String,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LiquidPalette.iris.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(verbatim: detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(LiquidPalette.iris)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Generate

    private func generate() {
        let trimmedName = projectName.trimmingCharacters(in: .whitespaces)
        let trimmedSlug = slug.trimmingCharacters(in: .whitespaces)
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        let trimmedOrg  = githubOrg.trimmingCharacters(in: .whitespaces)

        let blueprint = BootstrapBlueprint(
            projectName: trimmedName,
            slug: trimmedSlug,
            host: trimmedHost,
            githubOrg: trimmedOrg,
            stack: stack,
            primaryColor: primaryColor,
            contractType: contractType,
            monthlyRecurringRevenueEUR: contractType == .retainer ? (Int(mrr) ?? 0) : 0,
            includeAdminBackoffice: includeAdmin,
            includeBlogMDX: includeBlog,
            includeI18nFREN: includeI18n,
            includeStripe: includeStripe
        )

        let project = Project(
            id: blueprint.id,
            name: trimmedName,
            host: trimmedHost,
            slug: trimmedSlug,
            githubRepo: "\(trimmedOrg)/\(trimmedSlug)",
            stack: stack,
            contractType: contractType,
            monthlyRecurringRevenueEUR: blueprint.monthlyRecurringRevenueEUR,
            lifecycleStage: .active,
            primaryColor: primaryColor
        )
        context.insert(project)
        try? context.save()

        MINDTelemetry.info(
            "bootstrap.blueprint.created",
            data: [
                "stack": blueprint.stack.rawValue,
                "contractType": blueprint.contractType.rawValue,
                "admin": String(blueprint.includeAdminBackoffice),
                "blog": String(blueprint.includeBlogMDX),
                "i18n": String(blueprint.includeI18nFREN),
                "stripe": String(blueprint.includeStripe),
            ]
        )
        MINDTelemetry.info(
            "bootstrap.project.created",
            data: ["projectID": project.id.uuidString]
        )
        LiquidHaptics.success()
        resultProject = project
        resultBlueprint = blueprint
    }
}

// MARK: - Identifiable conformance for sheet(item:)

extension BootstrapBlueprint: Identifiable {}

// MARK: - BootstrapResultSheet

/// v1.0-alpha.6 — Result sheet shown after `BootstrapWizardSheet`
/// finishes. Surfaces the 3 export options + the "Voir le projet"
/// CTA that routes back to the cockpit.
struct BootstrapResultSheet: View {
    @Environment(\.dismiss) private var dismiss

    let blueprint: BootstrapBlueprint
    let project: Project?
    let onViewProject: ((Project) -> Void)?

    @State private var sharePayload: ShareItem?
    @State private var showCopiedToast: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    actionStack
                    detailsCard
                }
                .padding(20)
                .padding(.bottom, 60)
            }
            .navigationTitle(Text("bootstrap.result.success"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "audit.button.cancel")) { dismiss() }
                }
            }
            .sheet(item: $sharePayload) { item in
                ShareSheet(items: item.items)
                    .presentationDetents([.medium])
            }
            .overlay(alignment: .bottom) {
                if showCopiedToast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                        Text(verbatim: "Copié dans le presse-papier")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background {
                        Capsule(style: .continuous)
                            .fill(LiquidGradient.primary)
                    }
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LiquidGradient.primary)
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: LiquidPalette.iris.opacity(0.5), radius: 24, y: 8)
            Text(verbatim: blueprint.projectName)
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text(verbatim: blueprint.host)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 14)
    }

    // MARK: - Actions

    private var actionStack: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(spacing: 0) {
                actionRow(
                    icon: "doc.on.clipboard.fill",
                    label: String(localized: "bootstrap.result.copyScript"),
                    detail: "Script bash prêt à coller dans Terminal",
                    tint: LiquidPalette.iris
                ) {
                    let script = BootstrapScriptGenerator.bashScript(for: blueprint)
                    UIPasteboard.general.string = script
                    LiquidHaptics.success()
                    MINDTelemetry.info(
                        "bootstrap.script.copied",
                        data: ["slug": blueprint.slug]
                    )
                    withAnimation(LiquidMetrics.spring) { showCopiedToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation(LiquidMetrics.spring) { showCopiedToast = false }
                    }
                }
                Divider().background(LiquidPalette.iris.opacity(0.15))
                actionRow(
                    icon: "square.and.arrow.up",
                    label: String(localized: "bootstrap.result.shareScript"),
                    detail: "Partage le .sh via AirDrop / Mail / iCloud",
                    tint: LiquidPalette.aqua
                ) {
                    shareScript()
                }
                Divider().background(LiquidPalette.iris.opacity(0.15))
                actionRow(
                    icon: "archivebox.fill",
                    label: String(localized: "bootstrap.result.shareZip"),
                    detail: "Dossier scaffold complet en .zip",
                    tint: LiquidPalette.lavender
                ) {
                    shareZip()
                }
                Divider().background(LiquidPalette.iris.opacity(0.15))
                actionRow(
                    icon: "arrow.right.circle.fill",
                    label: String(localized: "bootstrap.result.viewProject"),
                    detail: "Ouvre la fiche projet dans le cockpit",
                    tint: .orange
                ) {
                    if let project { onViewProject?(project) }
                }
            }
        }
    }

    @ViewBuilder
    private func actionRow(
        icon: String,
        label: String,
        detail: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: label)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(verbatim: detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Details

    private var detailsCard: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                detailRow(label: "Repo", value: blueprint.githubRepoPath)
                Divider()
                detailRow(label: "Stack", value: blueprint.stack.rawValue.capitalized)
                Divider()
                let modules = [
                    blueprint.includeAdminBackoffice ? "Admin" : nil,
                    blueprint.includeBlogMDX ? "Blog" : nil,
                    blueprint.includeI18nFREN ? "i18n" : nil,
                    blueprint.includeStripe ? "Stripe" : nil,
                ].compactMap { $0 }.joined(separator: " · ")
                detailRow(label: "Modules", value: modules.isEmpty ? "—" : modules)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(verbatim: label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
            Text(verbatim: value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Share helpers

    private func shareScript() {
        let script = BootstrapScriptGenerator.bashScript(for: blueprint)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(blueprint.slug)-scaffold.sh")
        try? script.data(using: .utf8)?.write(to: tmpURL)
        sharePayload = ShareItem(items: [tmpURL])
        MINDTelemetry.info(
            "bootstrap.script.shared",
            data: ["slug": blueprint.slug]
        )
    }

    private func shareZip() {
        let archive = BootstrapZipBuilder.archive(for: blueprint)
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(blueprint.slug)-scaffold.zip")
        do {
            try BootstrapZipPacker.write(archive: archive, to: zipURL)
            sharePayload = ShareItem(items: [zipURL])
            MINDTelemetry.info(
                "bootstrap.zip.shared",
                data: ["slug": blueprint.slug, "bytes": String(archive.totalBytes)]
            )
        } catch {
            MINDTelemetry.error(
                "bootstrap.zip.failed",
                data: ["error": String(describing: error)]
            )
        }
    }
}

// MARK: - ShareSheet wrapper

private struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
