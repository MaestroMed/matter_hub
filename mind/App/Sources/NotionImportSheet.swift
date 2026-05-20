import SwiftUI
import SwiftData
import DesignSystem
import GraphCore
import NotionKit

/// v1.2.0 — Bidirectional Notion sync UI.
///
/// 3-step wizard that pulls Notion databases the user has shared
/// with the integration, lets Mehdi pick which ones to import, and
/// runs the planned import through `NotionImportExecutor`.
///
/// Entry point: Settings → "Notion sync" → "Importer depuis Notion".
@MainActor
struct NotionImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    enum Step: Int, Hashable, CaseIterable {
        case databases
        case mapping
        case run
    }

    @State private var step: Step = .databases

    // Step 1 — list of databases the integration has access to.
    @State private var databases: [NotionDatabase] = []
    @State private var selectedDatabaseIDs: Set<String> = []
    @State private var isLoadingDatabases: Bool = false
    @State private var loadError: String?

    // Step 2 — per-database mapping, keyed by database ID.
    @State private var mappings: [String: NotionImportMapping] = [:]
    @State private var sampleRowCounts: [String: Int] = [:]

    // Step 3 — per-database run progress.
    @State private var progressByDatabaseID: [String: NotionImportProgress] = [:]
    @State private var totalImported: Int = 0
    @State private var totalUpdated: Int = 0
    @State private var isRunComplete: Bool = false

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
                        case .databases:
                            databasesStep
                        case .mapping:
                            mappingStep
                        case .run:
                            runStep
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    bottomBar
                }
                .padding(.bottom, 8)
            }
            .navigationTitle(Text("notion.import.title", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                await loadDatabases()
            }
        }
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { dot in
                Circle()
                    .fill(dot.rawValue <= step.rawValue
                          ? LiquidPalette.iris
                          : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Step 1 — Databases

    @ViewBuilder
    private var databasesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isLoadingDatabases {
                    HStack {
                        ProgressView()
                        Text("notion.import.databases.loading", bundle: .main)
                            .font(.system(.subheadline, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if let loadError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text(loadError)
                            .font(.system(.subheadline, design: .rounded))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if databases.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("notion.import.databases.empty", bundle: .main)
                            .font(.system(.subheadline, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(databases) { database in
                        databaseRow(database)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func databaseRow(_ database: NotionDatabase) -> some View {
        let isSelected = selectedDatabaseIDs.contains(database.id)
        return Button {
            if isSelected {
                selectedDatabaseIDs.remove(database.id)
            } else {
                selectedDatabaseIDs.insert(database.id)
            }
            LiquidHaptics.selection()
        } label: {
            HStack(spacing: 12) {
                Text(database.icon ?? "🗂️")
                    .font(.title2)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(database.title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(database.propertyNames.prefix(4).joined(separator: " · "))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? LiquidPalette.iris : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2 — Mapping

    @ViewBuilder
    private var mappingStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("notion.import.mapping.title", bundle: .main)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                ForEach(selectedDatabases) { database in
                    mappingCard(database)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func mappingCard(_ database: NotionDatabase) -> some View {
        let current = mappings[database.id]
            ?? NotionImportPlanner.suggestMapping(database: database, sampleRows: [])
        let kindBinding = Binding<TargetKind>(
            get: { current.targetNodeKind },
            set: { newValue in
                let updated = NotionImportMapping(
                    targetNodeKind: newValue,
                    titlePropertyName: current.titlePropertyName,
                    bodyPropertyName: current.bodyPropertyName,
                    confidence: current.confidence,
                    detectedFields: current.detectedFields
                )
                mappings[database.id] = updated
            }
        )
        let confidencePercent = Int(current.confidence * 100)
        let confidenceFormat = String(localized: "notion.import.mapping.confidence.format", bundle: .main)
        let previewFormat = String(localized: "notion.import.mapping.preview.format", bundle: .main)
        let kindLabel = kindLocalizedTitle(current.targetNodeKind)
        let rowCount = sampleRowCounts[database.id] ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(database.icon ?? "🗂️")
                    .font(.title3)
                Text(database.title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Spacer()
                Text(String(format: confidenceFormat, confidencePercent))
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        Capsule(style: .continuous)
                            .fill(LiquidPalette.iris.opacity(0.18))
                    }
                    .foregroundStyle(LiquidPalette.iris)
            }

            Picker(String(localized: "notion.import.mapping.title", bundle: .main),
                   selection: kindBinding) {
                ForEach(TargetKind.allCases, id: \.self) { kind in
                    Text(kindLocalizedTitle(kind)).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Text(String(format: previewFormat, rowCount, kindLabel))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
        .padding(.horizontal, 16)
    }

    private func kindLocalizedTitle(_ kind: TargetKind) -> String {
        switch kind {
        case .project:     return String(localized: "notion.import.mapping.kind.project", bundle: .main)
        case .lead:        return String(localized: "notion.import.mapping.kind.lead", bundle: .main)
        case .deliverable: return String(localized: "notion.import.mapping.kind.deliverable", bundle: .main)
        case .audit:       return String(localized: "notion.import.mapping.kind.audit", bundle: .main)
        case .ignored:     return String(localized: "notion.import.mapping.kind.ignored", bundle: .main)
        }
    }

    private var selectedDatabases: [NotionDatabase] {
        databases.filter { selectedDatabaseIDs.contains($0.id) }
    }

    // MARK: - Step 3 — Run

    @ViewBuilder
    private var runStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(selectedDatabases) { database in
                    runRow(database)
                }
                if isRunComplete {
                    let toastFormat = String(localized: "notion.import.success.toast.format", bundle: .main)
                    Text(String(format: toastFormat, totalImported, totalUpdated))
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background {
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(LiquidPalette.iris.opacity(0.5), lineWidth: 1)
                                }
                        }
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func runRow(_ database: NotionDatabase) -> some View {
        let progress = progressByDatabaseID[database.id]
        let total = progress?.totalRows ?? 0
        let done = (progress?.importedRows ?? 0) + (progress?.updatedRows ?? 0)
        let progressFormat = String(localized: "notion.import.run.progress.format", bundle: .main)
        let value = total == 0 ? 0 : Double(done) / Double(total)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(database.icon ?? "🗂️")
                    .font(.title3)
                Text(database.title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Spacer()
                Text(String(format: progressFormat, done, total))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: value, total: 1)
                .progressViewStyle(.linear)
                .tint(LiquidPalette.iris)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step != .databases {
                Button(String(localized: "settings.button.back", bundle: .main)) {
                    if let previous = Step(rawValue: step.rawValue - 1) {
                        step = previous
                    }
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
            LiquidButton(
                title: ctaTitle,
                systemImage: ctaIcon
            ) {
                advance()
            }
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var ctaTitle: String {
        switch step {
        case .databases: return String(localized: "settings.button.next", bundle: .main)
        case .mapping:   return String(localized: "settings.button.next", bundle: .main)
        case .run:
            return isRunComplete
                ? String(localized: "settings.button.done", bundle: .main)
                : String(localized: "settings.button.running", bundle: .main)
        }
    }

    private var ctaIcon: String {
        switch step {
        case .databases, .mapping: return "arrow.right"
        case .run: return isRunComplete ? "checkmark" : "hourglass"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .databases: return !selectedDatabaseIDs.isEmpty
        case .mapping:   return true
        case .run:       return isRunComplete
        }
    }

    private func advance() {
        switch step {
        case .databases:
            primeMappings()
            step = .mapping
        case .mapping:
            step = .run
            Task { await runAllImports() }
        case .run:
            dismiss()
        }
    }

    // MARK: - Networking

    private func loadDatabases() async {
        isLoadingDatabases = true
        loadError = nil
        do {
            let fetched = try await NotionClient.shared.listDatabases()
            databases = fetched
            MINDTelemetry.info("notion.databases.fetched", data: [
                "count": String(fetched.count),
            ])
        } catch {
            let format = String(localized: "notion.import.error.http", bundle: .main)
            loadError = String(format: format, String(describing: error))
            if case NotionClientError.noToken = error {
                loadError = String(localized: "notion.import.error.token", bundle: .main)
            }
        }
        isLoadingDatabases = false
    }

    /// Builds the default mapping for every selected database +
    /// stages the sample row count by querying 5 pages per DB.
    /// Soft-fails — a DB that can't be sampled still gets a default
    /// mapping built from the title heuristic alone.
    private func primeMappings() {
        Task {
            for db in selectedDatabases where mappings[db.id] == nil {
                let sample = (try? await NotionClient.shared.queryDatabase(db.id, pageSize: 5)) ?? []
                let mapping = NotionImportPlanner.suggestMapping(database: db, sampleRows: sample)
                await MainActor.run {
                    mappings[db.id] = mapping
                    sampleRowCounts[db.id] = sample.count
                }
            }
        }
    }

    private func runAllImports() async {
        totalImported = 0
        totalUpdated = 0
        for db in selectedDatabases {
            guard let mapping = mappings[db.id], mapping.targetNodeKind != .ignored else { continue }
            let stream = await NotionImportExecutor.shared.runImport(
                database: db,
                mapping: mapping
            ) { page, mapping in
                applyImportedRow(page: page, mapping: mapping)
            }
            for await snapshot in stream {
                progressByDatabaseID[db.id] = snapshot
                if snapshot.isComplete {
                    totalImported += snapshot.importedRows
                    totalUpdated += snapshot.updatedRows
                }
            }
        }
        isRunComplete = true
        LiquidHaptics.success()
    }

    /// Per-row SwiftData write. Stays on @MainActor because
    /// `Project.upsert` / `Lead.upsert` are bound there.
    @MainActor
    private func applyImportedRow(
        page: NotionPage,
        mapping: NotionImportMapping
    ) -> NotionRowOutcome {
        let title = page.properties[mapping.titlePropertyName] ?? page.title
        let body = mapping.bodyPropertyName.flatMap { page.properties[$0] }
        do {
            switch mapping.targetNodeKind {
            case .project:
                _ = try Project.upsert(
                    notionPageID: page.id,
                    title: title,
                    host: page.properties["URL"] ?? page.properties["Website"] ?? page.properties["Site"],
                    notes: body,
                    githubRepo: nil,
                    in: context
                )
                return .inserted
            case .lead:
                _ = try Lead.upsert(
                    notionPageID: page.id,
                    contactName: title,
                    contactEmail: page.properties["Email"] ?? "",
                    message: body ?? "",
                    sourceURL: page.url,
                    in: context
                )
                return .inserted
            case .deliverable, .audit:
                // v1.2.0 only wires Project + Lead. Deliverable +
                // Audit upserts ride the same pattern but the
                // SwiftData targets aren't ready yet — they land in
                // v1.2.1. We persist the row as a Project for now
                // so Mehdi sees the imported content rather than
                // silently dropping it.
                _ = try Project.upsert(
                    notionPageID: page.id,
                    title: title,
                    notes: body,
                    in: context
                )
                return .inserted
            case .ignored:
                return .ignored
            }
        } catch {
            return .failed(String(describing: error))
        }
    }
}
