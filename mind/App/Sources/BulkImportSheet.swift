import SwiftUI
import SwiftData
import BootstrapKit
import DesignSystem
import GraphCore
import ProjectHealthKit

/// v1.0-alpha.11 — Bulk Import GitHub repos.
///
/// 3-step wizard that replaces the 5-hardcoded-client seed path with
/// a real GitHub-API-backed importer:
///
///   - Step 1 (Scan)    : GET /user/repos, then fan out
///     `extractMetadata` calls in parallel (TaskGroup, max 5
///     in-flight) and feed the results to `BulkImportPlanner.plan`.
///   - Step 2 (Review)  : 2 sections — "Recommandés" (default ON
///     toggles) and "Ignorés (vérifie)" (default OFF + reason
///     label + "Importer quand même" CTA per row). Tap a row →
///     inline expand showing the full `RepoMetadata`.
///   - Step 3 (Import)  : loops the accepted `PlannedImport`s and
///     calls `Project.upsert(from:in:)` on each. Progress bar
///     0..N. Final toast: "N projets importés ✓".
///
/// Idempotency lives in `Project.upsert` itself — running the wizard
/// twice doesn't create duplicates because `githubRepo` is the
/// upsert key.
///
/// Two entry points:
///   - Settings → "Importer mes repos GitHub" button (gated on a
///     saved GitHub token; the wizard shows an error state if no
///     token is configured).
///   - OnboardingView's new "Tes projets" step — the wizard
///     calls `onCompleted` so onboarding advances to "Ready" after
///     the import finishes.
@MainActor
struct BulkImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Fired after the user taps "Importer N projets" + the import
    /// loop completes (or fails). Onboarding listens to this to
    /// advance to "Ready" without the user having to dismiss the
    /// sheet manually.
    let onCompleted: (() -> Void)?

    init(onCompleted: (() -> Void)? = nil) {
        self.onCompleted = onCompleted
    }

    enum Step: Int, Hashable, CaseIterable {
        case scan
        case review
        case importing
    }

    @State private var step: Step = .scan

    @State private var scanError: String?
    @State private var repos: [GitHubRepoSummary] = []
    @State private var detections: [String: RepoStackDetection] = [:]
    @State private var plan: BulkImportPlan?

    @State private var importedCount: Int = 0
    @State private var importTotal: Int = 0
    @State private var importErrorCount: Int = 0
    @State private var showSuccessToast: Bool = false

    /// Per-row expansion state in the review step.
    @State private var expandedRecommendedID: UUID?
    @State private var expandedSkippedID: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    progressDots
                        .padding(.top, 8)
                        .padding(.bottom, 14)

                    Group {
                        switch step {
                        case .scan:
                            scanStep
                        case .review:
                            reviewStep
                        case .importing:
                            importStep
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    bottomBar
                }
                .padding(.bottom, 8)

                if showSuccessToast {
                    successToast
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .navigationTitle(Text("bulkImport.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "audit.button.cancel")) { dismiss() }
                }
            }
            .onAppear {
                MINDTelemetry.info("bulkImport.opened")
                Task { await runScan() }
            }
        }
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 10) {
            ForEach(Step.allCases, id: \.self) { s in
                Capsule(style: .continuous)
                    .fill(
                        s == step
                            ? AnyShapeStyle(LiquidGradient.primary)
                            : AnyShapeStyle(Color.secondary.opacity(0.2))
                    )
                    .frame(width: s == step ? 28 : 10, height: 8)
                    .animation(LiquidMetrics.spring, value: step)
            }
        }
    }

    // MARK: - Step 1: Scan

    private var scanStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(LiquidGradient.primary)
                    .padding(.top, 40)

                Text("bulkImport.step.scan")
                    .font(.system(.title2, design: .rounded, weight: .semibold))

                if let scanError {
                    LiquidCard(cornerRadius: 18) {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(.title, design: .rounded))
                                .foregroundStyle(.orange)
                            Text(scanError)
                                .font(.system(.subheadline, design: .rounded))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                } else if repos.isEmpty {
                    ProgressView()
                        .scaleEffect(1.4)
                        .padding(.top, 20)
                    Text("bulkImport.scan.empty")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding(.top, 10)
                    Text(String(
                        format: NSLocalizedString(
                            "bulkImport.scan.loading.format",
                            comment: ""
                        ),
                        repos.count
                    ))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Step 2: Review

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let plan {
                    if !plan.recommendedImports.isEmpty {
                        Text("bulkImport.recommended.title")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .padding(.horizontal, 20)
                        LiquidCard(cornerRadius: 18) {
                            VStack(spacing: 0) {
                                ForEach(Array(plan.recommendedImports.enumerated()), id: \.element.id) { idx, item in
                                    recommendedRow(at: idx, item: item)
                                    if idx < plan.recommendedImports.count - 1 {
                                        Divider().background(.white.opacity(0.15))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .padding(.horizontal, 20)
                    }

                    if !plan.skippedRepos.isEmpty {
                        Text("bulkImport.skipped.title")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                        LiquidCard(cornerRadius: 18) {
                            VStack(spacing: 0) {
                                ForEach(Array(plan.skippedRepos.enumerated()), id: \.element.id) { idx, item in
                                    skippedRow(item: item)
                                    if idx < plan.skippedRepos.count - 1 {
                                        Divider().background(.white.opacity(0.15))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .padding(.horizontal, 20)
                    }

                    if plan.recommendedImports.isEmpty && plan.skippedRepos.isEmpty {
                        Text("bulkImport.scan.empty")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 40)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func recommendedRow(at idx: Int, item: PlannedImport) -> some View {
        let isExpanded = expandedRecommendedID == item.id
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: item.metadata.suggestedPrimaryColor) ?? LiquidPalette.iris)
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.metadata.suggestedName)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text(verbatim: item.metadata.suggestedHost)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                frameworkBadge(item.metadata.detection.framework)
                confidencePill(item.metadata.detection.confidence)
                Toggle("", isOn: Binding(
                    get: { item.accepted },
                    set: { newValue in toggleAccepted(item, to: newValue) }
                ))
                .labelsHidden()
                .tint(LiquidPalette.iris)
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    detailRow("GitHub", item.metadata.summary.fullName)
                    detailRow("Slug", item.metadata.suggestedSlug)
                    detailRow("Stars", "\(item.metadata.summary.stars)")
                    if let version = item.metadata.detection.version {
                        detailRow("Version", version)
                    }
                    if !item.metadata.detection.signals.isEmpty {
                        detailRow(
                            "Signaux",
                            item.metadata.detection.signals.joined(separator: " · ")
                        )
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(LiquidMetrics.spring) {
                expandedRecommendedID = isExpanded ? nil : item.id
            }
        }
    }

    @ViewBuilder
    private func skippedRow(item: SkippedRepo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.fullName)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                    Text(verbatim: item.reason)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "bulkImport.skipped.action.importAnyway")) {
                    importSkippedAnyway(item)
                }
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(LiquidPalette.iris)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: label)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(verbatim: value)
                .font(.system(.caption, design: .rounded))
            Spacer()
        }
    }

    private func frameworkBadge(_ framework: String) -> some View {
        Text(verbatim: frameworkLabel(framework))
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(frameworkTint(framework).opacity(0.18))
            }
            .foregroundStyle(frameworkTint(framework))
    }

    private func confidencePill(_ confidence: Double) -> some View {
        let percentage = Int((confidence * 100).rounded())
        return Text(verbatim: String(format: "%d%%", percentage))
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                    }
            }
    }

    private func frameworkLabel(_ key: String) -> String {
        switch key {
        case "nextjs":    return String(localized: "bulkImport.row.framework.nextjs")
        case "wordpress": return String(localized: "bulkImport.row.framework.wordpress")
        case "shopify":   return String(localized: "bulkImport.row.framework.shopify")
        case "static":    return String(localized: "bulkImport.row.framework.static")
        default:          return String(localized: "bulkImport.row.framework.other")
        }
    }

    private func frameworkTint(_ key: String) -> Color {
        switch key {
        case "nextjs":    return LiquidPalette.iris
        case "wordpress": return LiquidPalette.aqua
        case "shopify":   return .green
        case "static":    return .orange
        default:          return .secondary
        }
    }

    // MARK: - Step 3: Importing

    private var importStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(LiquidGradient.primary)
                .padding(.top, 60)

            if importedCount < importTotal {
                Text(String(format: NSLocalizedString(
                    "bulkImport.import.progress.format", comment: ""
                ), importedCount, importTotal))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)

                ProgressView(value: Double(importedCount), total: Double(max(importTotal, 1)))
                    .progressViewStyle(.linear)
                    .tint(LiquidPalette.iris)
                    .padding(.horizontal, 40)
            } else {
                Text(String(format: NSLocalizedString(
                    "bulkImport.success.toast.format", comment: ""
                ), importedCount))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
            }

            Spacer()
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Spacer()
            switch step {
            case .scan:
                EmptyView()
            case .review:
                LiquidButton(
                    title: String(format: NSLocalizedString(
                        "bulkImport.review.cta.format", comment: ""
                    ), plan?.acceptedCount ?? 0),
                    systemImage: "tray.and.arrow.down.fill"
                ) {
                    Task { await runImport() }
                }
                .disabled((plan?.acceptedCount ?? 0) == 0)
            case .importing:
                if importedCount >= importTotal {
                    LiquidButton(
                        title: String(localized: "onboarding.next"),
                        systemImage: "checkmark"
                    ) {
                        onCompleted?()
                        dismiss()
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Success toast

    private var successToast: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(String(format: NSLocalizedString(
                    "bulkImport.success.toast.format", comment: ""
                ), importedCount))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                    }
            }
            .padding(.top, 60)
            Spacer()
        }
    }

    // MARK: - Logic

    private func toggleAccepted(_ item: PlannedImport, to value: Bool) {
        guard var current = plan else { return }
        if let idx = current.recommendedImports.firstIndex(where: { $0.id == item.id }) {
            var mutated = current.recommendedImports
            mutated[idx].accepted = value
            current = BulkImportPlan(
                recommendedImports: mutated,
                skippedRepos: current.skippedRepos
            )
            plan = current
        }
    }

    private func importSkippedAnyway(_ skipped: SkippedRepo) {
        guard let repo = repos.first(where: { $0.fullName == skipped.fullName }) else {
            return
        }
        let detection = detections[skipped.fullName] ?? RepoStackDetection(
            framework: "other",
            version: nil,
            confidence: 0.0,
            signals: []
        )
        let metadata = RepoMetadata.derive(repo: repo, detection: detection)
        let record = bulkImportRecord(from: metadata)
        do {
            _ = try Project.upsert(from: record, in: context)
            MINDTelemetry.info("bulkImport.project.created", data: ["repo": record.githubRepo])
        } catch {
            MINDTelemetry.error(
                "bulkImport.project.failed",
                data: ["repo": record.githubRepo, "error": String(describing: error)]
            )
        }
        // Remove the skipped row from view state.
        guard var current = plan else { return }
        current = BulkImportPlan(
            recommendedImports: current.recommendedImports,
            skippedRepos: current.skippedRepos.filter { $0.id != skipped.id }
        )
        plan = current
    }

    private func runScan() async {
        scanError = nil
        repos = []
        detections = [:]
        plan = nil

        // 1. Token check.
        guard let token = GitHubTokenStore.read(), !token.isEmpty else {
            scanError = String(localized: "bulkImport.error.token.missing")
            MINDTelemetry.warning("bulkImport.scan.failed", data: ["reason": "no token"])
            return
        }

        // 2. List repos.
        let fetched: [GitHubRepoSummary]
        do {
            fetched = try await GitHubClient.shared.listMyRepos(limit: 100)
        } catch {
            scanError = String(describing: error)
            MINDTelemetry.error(
                "bulkImport.scan.failed",
                data: ["error": String(describing: error)]
            )
            return
        }
        await MainActor.run {
            repos = fetched
        }
        MINDTelemetry.info("bulkImport.scan.started", data: ["repoCount": "\(fetched.count)"])

        // 3. Fan out detectStack with a capped TaskGroup.
        let result = await withTaskGroup(
            of: (String, RepoStackDetection?).self
        ) { group -> [String: RepoStackDetection] in
            var inFlight = 0
            var queue = fetched
            var dict: [String: RepoStackDetection] = [:]
            while !queue.isEmpty || inFlight > 0 {
                while inFlight < 5, let repo = queue.first {
                    queue.removeFirst()
                    let name = repo.fullName
                    group.addTask { @Sendable in
                        do {
                            let detection = try await GitHubClient.shared.detectStack(repo: name)
                            return (name, detection)
                        } catch {
                            return (name, nil)
                        }
                    }
                    inFlight += 1
                }
                if let next = await group.next() {
                    inFlight -= 1
                    if let detection = next.1 {
                        dict[next.0] = detection
                    } else {
                        dict[next.0] = RepoStackDetection(
                            framework: "other",
                            version: nil,
                            confidence: 0.0,
                            signals: ["detect failed"]
                        )
                    }
                }
            }
            return dict
        }

        await MainActor.run {
            detections = result
            let newPlan = BulkImportPlanner.plan(repos: fetched, detections: result)
            plan = newPlan
            withAnimation(LiquidMetrics.spring) {
                step = .review
            }
            MINDTelemetry.info(
                "bulkImport.scan.completed",
                data: [
                    "recommended": "\(newPlan.recommendedImports.count)",
                    "skipped": "\(newPlan.skippedRepos.count)",
                ]
            )
        }
    }

    private func runImport() async {
        guard let plan else { return }
        let accepted = plan.recommendedImports.filter(\.accepted)
        importTotal = accepted.count
        importedCount = 0
        importErrorCount = 0
        withAnimation(LiquidMetrics.spring) { step = .importing }
        MINDTelemetry.info(
            "bulkImport.import.started",
            data: ["count": "\(accepted.count)"]
        )
        MINDTelemetry.info(
            "bulkImport.review.accepted.count",
            data: ["count": "\(accepted.count)"]
        )
        for item in accepted {
            let record = bulkImportRecord(from: item.metadata)
            do {
                let existed = try Self.projectExists(
                    githubRepo: record.githubRepo,
                    in: context
                )
                _ = try Project.upsert(from: record, in: context)
                MINDTelemetry.info(
                    existed
                        ? "bulkImport.project.updated"
                        : "bulkImport.project.created",
                    data: ["repo": record.githubRepo]
                )
            } catch {
                importErrorCount += 1
                MINDTelemetry.error(
                    "bulkImport.project.failed",
                    data: ["repo": record.githubRepo, "error": String(describing: error)]
                )
            }
            importedCount += 1
        }
        MINDTelemetry.info(
            "bulkImport.import.completed",
            data: [
                "imported": "\(importedCount)",
                "errors": "\(importErrorCount)",
            ]
        )
        withAnimation(LiquidMetrics.spring) {
            showSuccessToast = true
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        withAnimation(LiquidMetrics.spring) {
            showSuccessToast = false
        }
    }

    private func bulkImportRecord(from metadata: RepoMetadata) -> BulkImportRecord {
        let stack = Self.projectStack(from: metadata.detection.framework)
        return BulkImportRecord(
            githubRepo: metadata.summary.fullName,
            suggestedSlug: metadata.suggestedSlug,
            suggestedName: metadata.suggestedName,
            suggestedHost: metadata.suggestedHost,
            suggestedPrimaryColor: metadata.suggestedPrimaryColor,
            stack: stack
        )
    }

    static func projectStack(from framework: String) -> ProjectStack {
        switch framework {
        case "nextjs":    return .nextjs
        case "wordpress": return .wordpress
        case "shopify":   return .shopify
        case "static":    return .staticSite
        default:          return .other
        }
    }

    static func projectExists(
        githubRepo: String,
        in context: ModelContext
    ) throws -> Bool {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.githubRepo == githubRepo
            }
        )
        return try !context.fetch(descriptor).isEmpty
    }
}
