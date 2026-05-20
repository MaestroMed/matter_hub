import SwiftUI
import SwiftData
import DesignSystem
import GraphCore

/// Lightweight task surface — every NodeKind.task lives here. Open
/// tasks at the top sorted by creation date, completed ones collapsed
/// below. New task creation via an inline sheet (no modal page) so the
/// loop "tap + → type → save" stays sub-3-seconds.
struct TasksView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Node.createdAt, order: .reverse) private var allNodes: [Node]
    @State private var showAddSheet: Bool = false

    private var openTasks: [Node] {
        allNodes.filter { $0.kindRaw == "task" && $0.completedAt == nil }
    }

    private var completedTasks: [Node] {
        allNodes
            .filter { $0.kindRaw == "task" && $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if openTasks.isEmpty && completedTasks.isEmpty {
                    emptyState
                } else {
                    if !openTasks.isEmpty {
                        sectionHeader("À faire", count: openTasks.count)
                        VStack(spacing: 10) {
                            ForEach(openTasks) { taskRow($0) }
                        }
                    }
                    if !completedTasks.isEmpty {
                        sectionHeader("Terminées", count: completedTasks.count)
                        VStack(spacing: 10) {
                            ForEach(completedTasks.prefix(20)) { taskRow($0) }
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .overlay(alignment: .bottomTrailing) { addButton }
        .sheet(isPresented: $showAddSheet) {
            AddTaskSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tasks")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text(openTasks.count == 1
                     ? "1 tâche à faire"
                     : "\(openTasks.count) tâches à faire")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text("· \(count)")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.leading, 4)
        .padding(.top, 6)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        LiquidCard {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(LiquidGradient.primary)
                Text("Aucune tâche")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text("Tape sur + pour créer ta première tâche.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Add button

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(LiquidGradient.primary)
                    .frame(width: 56, height: 56)
                    .shadow(color: LiquidPalette.iris.opacity(0.45), radius: 14, y: 6)
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.trailing, 22)
        .padding(.bottom, 32)
    }

    // MARK: - Task row

    private func taskRow(_ task: Node) -> some View {
        LiquidCard(cornerRadius: 16) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(LiquidMetrics.spring) {
                        task.toggleCompletion()
                        try? context.save()
                    }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(task.isCompleted ? .green : LiquidPalette.iris)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .lineLimit(2)
                    if !task.content.isEmpty {
                        Text(task.content)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button {
                    withAnimation { context.delete(task); try? context.save() }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Add task sheet

private struct AddTaskSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var details: String = ""
    @FocusState private var focusedField: Field?

    private enum Field { case title, details }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Nouvelle tâche")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            LiquidCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Titre", text: $title)
                        .focused($focusedField, equals: .title)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .submitLabel(.next)
                        .onSubmit { focusedField = .details }
                    Divider().background(.white.opacity(0.2))
                    TextField("Détails (optionnel)", text: $details, axis: .vertical)
                        .focused($focusedField, equals: .details)
                        .font(.system(.body, design: .rounded))
                        .lineLimit(2...5)
                }
                .padding(18)
            }
            .padding(.horizontal, 20)

            LiquidButton(title: "Créer la tâche", systemImage: "plus.circle.fill") {
                save()
            }
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)

            Spacer()
        }
        .onAppear { focusedField = .title }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        let task = Node(
            kind: .task,
            title: trimmedTitle,
            content: trimmedDetails,
            tags: ["task"]
        )
        context.insert(task)
        task.refreshEmbedding()
        try? context.save()
        dismiss()
    }
}
