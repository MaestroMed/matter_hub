import SwiftUI
import SwiftData
import DesignSystem
import GraphCore

/// Goals surface — each goal is a NodeKind.goal with a progress
/// percentage stored in a tag `"progress-XX"` (0–100). LiquidCard per
/// goal with a tappable progress bar.
struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Node.createdAt, order: .reverse) private var allNodes: [Node]
    @State private var showAdd: Bool = false

    private var goals: [Node] {
        allNodes.filter { $0.kindRaw == "goal" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if goals.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(goals) { goalRow($0) }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .overlay(alignment: .bottomTrailing) { addButton }
        .sheet(isPresented: $showAdd) {
            AddGoalSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Goals")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("\(goals.count) objectifs en cours")
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

    private var emptyState: some View {
        LiquidCard {
            VStack(spacing: 12) {
                Image(systemName: "target")
                    .font(.system(size: 40))
                    .foregroundStyle(LiquidGradient.primary)
                Text("Aucun objectif")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text("Tape sur + pour fixer ton premier objectif.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private var addButton: some View {
        Button { showAdd = true } label: {
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

    private func goalRow(_ goal: Node) -> some View {
        let progress = GoalsView.progress(of: goal)
        return LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        if !goal.content.isEmpty {
                            Text(goal.content)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Text("\(progress)%")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(progressColor(progress))
                        .contentTransition(.numericText())
                }
                GoalProgressBar(progress: progress) { newProgress in
                    updateProgress(goal: goal, to: newProgress)
                }
            }
            .padding(14)
        }
    }

    private func updateProgress(goal: Node, to value: Int) {
        goal.tags.removeAll { $0.hasPrefix("progress-") }
        goal.tags.append("progress-\(value)")
        goal.updatedAt = .now
        try? context.save()
    }

    private func progressColor(_ value: Int) -> Color {
        switch value {
        case 100:    return .green
        case 60...:  return LiquidPalette.iris
        case 30...:  return .orange
        default:     return .gray
        }
    }

    static func progress(of goal: Node) -> Int {
        goal.tags
            .first { $0.hasPrefix("progress-") }
            .flatMap { Int($0.dropFirst("progress-".count)) } ?? 0
    }
}

// MARK: - Progress bar

private struct GoalProgressBar: View {
    let progress: Int
    let onUpdate: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LiquidPalette.lavender.opacity(0.4))
                    Capsule()
                        .fill(LiquidGradient.primary)
                        .frame(width: max(8, geo.size.width * CGFloat(progress) / 100))
                }
            }
            .frame(height: 10)

            HStack(spacing: 8) {
                ForEach([0, 25, 50, 75, 100], id: \.self) { step in
                    Button {
                        onUpdate(step)
                    } label: {
                        Text("\(step)")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(progress == step ? .white : LiquidPalette.iris)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                Capsule().fill(progress == step
                                    ? AnyShapeStyle(LiquidGradient.primary)
                                    : AnyShapeStyle(LiquidPalette.lavender.opacity(0.35)))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Add goal sheet

private struct AddGoalSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var details: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Nouvel objectif")
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
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Atteindre 10 clients, lire 24 livres…", text: $title)
                        .focused($focused)
                        .font(.system(.body, design: .rounded, weight: .medium))
                    Divider().background(.white.opacity(0.2))
                    TextField("Pourquoi ce goal (optionnel)", text: $details, axis: .vertical)
                        .font(.system(.body, design: .rounded))
                        .lineLimit(2...4)
                }
                .padding(18)
            }
            .padding(.horizontal, 20)

            LiquidButton(title: "Créer l'objectif", systemImage: "target") {
                save()
            }
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)

            Spacer()
        }
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let goal = Node(
            kind: .goal,
            title: trimmed,
            content: details.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: ["goal", "progress-0"]
        )
        context.insert(goal)
        goal.refreshEmbedding()
        try? context.save()
        dismiss()
    }
}
