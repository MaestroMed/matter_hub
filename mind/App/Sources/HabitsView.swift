import SwiftUI
import SwiftData
import DesignSystem
import GraphCore

/// Daily habits surface — each habit is a NodeKind.habit, and the daily
/// check-in is stored as a tag `"done-YYYY-MM-DD"` so the schema
/// stays additive. List shows today's habits with a tap-to-check
/// circle; current streak per habit shown trailing.
struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Node.createdAt, order: .forward) private var allNodes: [Node]
    @State private var showAdd: Bool = false

    private var habits: [Node] {
        allNodes.filter { $0.kindRaw == "habit" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if habits.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(habits) { habit in
                            habitRow(habit)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .overlay(alignment: .bottomTrailing) { addButton }
        .sheet(isPresented: $showAdd) {
            AddHabitSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Habits")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("\(habits.count) habitudes suivies")
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
                Image(systemName: "repeat.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LiquidGradient.primary)
                Text("Aucune habitude")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text("Tape sur + pour ajouter une habitude à suivre quotidiennement.")
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

    // MARK: - Row

    private func habitRow(_ habit: Node) -> some View {
        let todayKey = HabitsView.dayTag(for: .now)
        let isCheckedToday = habit.tags.contains(todayKey)
        let streak = currentStreak(for: habit)

        return LiquidCard(cornerRadius: 16) {
            HStack(spacing: 14) {
                Button {
                    withAnimation(LiquidMetrics.spring) {
                        toggleToday(habit: habit, todayKey: todayKey)
                    }
                } label: {
                    Image(systemName: isCheckedToday ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isCheckedToday ? .green : LiquidPalette.iris)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    if !habit.content.isEmpty {
                        Text(habit.content)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if streak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("\(streak)")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
            .padding(14)
        }
    }

    private func toggleToday(habit: Node, todayKey: String) {
        if let idx = habit.tags.firstIndex(of: todayKey) {
            habit.tags.remove(at: idx)
        } else {
            habit.tags.append(todayKey)
        }
        habit.updatedAt = .now
        try? context.save()
    }

    /// Consecutive days with a check-in, ending today (inclusive).
    private func currentStreak(for habit: Node) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var cursor = calendar.startOfDay(for: .now)
        while habit.tags.contains(HabitsView.dayTag(for: cursor)) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    static func dayTag(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "done-" + formatter.string(from: date)
    }

    static func checkedTodayCount(in nodes: [Node]) -> Int {
        let todayKey = dayTag(for: .now)
        return nodes
            .filter { $0.kindRaw == "habit" }
            .filter { $0.tags.contains(todayKey) }
            .count
    }
}

// MARK: - Add habit sheet

private struct AddHabitSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var details: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Nouvelle habitude")
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
                    TextField("Méditer 10 min, courir 5km, lire 20 pages…", text: $title)
                        .focused($focused)
                        .font(.system(.body, design: .rounded, weight: .medium))
                    Divider().background(.white.opacity(0.2))
                    TextField("Détail / pourquoi (optionnel)", text: $details, axis: .vertical)
                        .font(.system(.body, design: .rounded))
                        .lineLimit(2...4)
                }
                .padding(18)
            }
            .padding(.horizontal, 20)

            LiquidButton(title: "Créer l'habitude", systemImage: "plus.circle.fill") {
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
        let habit = Node(
            kind: .habit,
            title: trimmed,
            content: details.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: ["habit"]
        )
        context.insert(habit)
        habit.refreshEmbedding()
        try? context.save()
        dismiss()
    }
}
