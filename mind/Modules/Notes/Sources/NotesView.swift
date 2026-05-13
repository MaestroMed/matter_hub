import SwiftUI
import SwiftData
import DesignSystem
import GraphCore

public struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<Node> { node in
            node.kindRaw == "note" || node.kindRaw == "capture"
        },
        sort: [SortDescriptor(\Node.updatedAt, order: .reverse)]
    )
    private var nodes: [Node]

    @State private var searchText: String = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text("\(filtered.count) thoughts in your brain.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                LiquidCard(cornerRadius: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search your brain…", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .rounded))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { node in
                            NoteCardView(node: node)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.top, 40)
            .padding(.bottom, 120)
        }
    }

    private var filtered: [Node] {
        guard !searchText.isEmpty else { return nodes }
        return nodes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        LiquidCard {
            VStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(LiquidGradient.primary)
                Text("Empty for now")
                    .font(.system(.headline, design: .rounded))
                Text("Tap the + button to capture your first thought.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }
}

struct NoteCardView: View {
    let node: Node

    var body: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(node.title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .lineLimit(2)
                if !node.content.isEmpty {
                    Text(node.content)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if !node.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(node.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background {
                                    Capsule().fill(LiquidPalette.lavender.opacity(0.35))
                                }
                        }
                    }
                }
                Text(node.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
