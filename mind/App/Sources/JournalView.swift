import SwiftUI
import SwiftData
import DesignSystem
import GraphCore

/// Daily journal surface — each entry is a NodeKind.journal. Today's
/// entry pinned at the top (created or edited inline), past entries
/// listed below, most-recent first.
struct JournalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Node.createdAt, order: .reverse) private var allNodes: [Node]
    @State private var todayDraft: String = ""
    @State private var todayNodeID: UUID?

    private var entries: [Node] {
        allNodes.filter { $0.kindRaw == "journal" }
    }

    private var todayEntry: Node? {
        let calendar = Calendar.current
        return entries.first {
            calendar.isDateInToday($0.createdAt)
        }
    }

    private var pastEntries: [Node] {
        entries.filter { $0.id != todayEntry?.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                todayCard
                if !pastEntries.isEmpty {
                    pastSection
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .onAppear { loadToday() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Journal")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text(Date.now.formatted(date: .complete, time: .omitted).capitalized)
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

    private var todayCard: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Aujourd'hui".uppercased())
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .tracking(0.8)
                TextEditor(text: $todayDraft)
                    .scrollContentBackground(.hidden)
                    .font(.system(.body, design: .rounded))
                    .frame(minHeight: 140)
                HStack {
                    Spacer()
                    LiquidButton(
                        title: todayNodeID == nil ? "Enregistrer" : "Mettre à jour",
                        systemImage: "drop.fill"
                    ) {
                        saveToday()
                    }
                    .disabled(todayDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(18)
        }
    }

    private var pastSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Entrées passées".uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, 4)
            ForEach(pastEntries.prefix(30)) { entry in
                pastEntryCard(entry)
            }
        }
    }

    private func pastEntryCard(_ entry: Node) -> some View {
        LiquidCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .tracking(0.6)
                Text(entry.content)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Persistence

    private func loadToday() {
        guard let today = todayEntry else { return }
        todayDraft = today.content
        todayNodeID = today.id
    }

    private func saveToday() {
        let text = todayDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let title = String(text.prefix(60))

        if let existingID = todayNodeID,
           let existing = entries.first(where: { $0.id == existingID }) {
            existing.content = text
            existing.title = title
            existing.updatedAt = .now
            existing.refreshEmbedding()
        } else {
            let node = Node(
                kind: .journal,
                title: title,
                content: text,
                tags: ["journal"]
            )
            context.insert(node)
            node.refreshEmbedding()
            todayNodeID = node.id
        }
        try? context.save()
    }
}
