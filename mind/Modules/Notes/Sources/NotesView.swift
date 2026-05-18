import SwiftUI
import SwiftData
import DesignSystem
import GraphCore

public struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Node.updatedAt, order: .reverse) private var allNodes: [Node]

    @State private var searchText: String = ""

    /// Callback fired when a Node is tapped. Lets the embedding view
    /// (RootView) present a polymorphic detail sheet without forcing the
    /// Notes module to depend on the app target.
    private let onSelectNode: (Node) -> Void

    public init(onSelectNode: @escaping (Node) -> Void = { _ in }) {
        self.onSelectNode = onSelectNode
    }

    private var displayNodes: [Node] {
        // Show every kind that lives in the graph today. The kind icon
        // tells them apart visually; future filter chips can narrow if
        // the list grows long.
        allNodes
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text("\(filtered.count) \(filtered.count == 1 ? "thought" : "thoughts") dans ton graphe.")
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
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { node in
                            Button {
                                onSelectNode(node)
                            } label: {
                                NodeRowCard(node: node)
                            }
                            .buttonStyle(.plain)
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
        guard !searchText.isEmpty else { return displayNodes }
        let needle = searchText.lowercased()
        return displayNodes.filter {
            $0.title.lowercased().contains(needle) ||
            $0.content.lowercased().contains(needle) ||
            $0.tags.joined(separator: " ").lowercased().contains(needle)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        LiquidCard {
            VStack(spacing: 14) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LiquidGradient.primary)
                Text(allNodes.isEmpty ? "Empty for now" : "Aucun résultat")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text(allNodes.isEmpty
                     ? "Tap the + button to capture your first thought."
                     : "Essaie un autre mot-clé.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(36)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Row card

struct NodeRowCard: View {
    let node: Node

    var body: some View {
        LiquidCard(cornerRadius: 20) {
            HStack(alignment: .top, spacing: 12) {
                NodeKindBadge(kind: node.kind)
                VStack(alignment: .leading, spacing: 6) {
                    Text(node.title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    if !node.content.isEmpty {
                        Text(node.content)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    HStack(spacing: 6) {
                        if !node.tags.isEmpty {
                            ForEach(node.tags.prefix(3), id: \.self) { tag in
                                TagChip(text: tag)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(node.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Compact tinted disc with the kind glyph. Color-codes the kind so the
/// list scans visually without forcing the user to read labels.
public struct NodeKindBadge: View {
    let kind: NodeKind

    public init(kind: NodeKind) {
        self.kind = kind
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(palette.tint.opacity(0.20))
                .frame(width: 36, height: 36)
            Image(systemName: palette.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.tint)
        }
    }

    private var palette: (symbol: String, tint: Color) {
        switch kind {
        case .note:    return ("doc.text",                            LiquidPalette.iris)
        case .capture: return ("drop.fill",                           LiquidPalette.iris)
        case .audit:   return ("magnifyingglass",                     .orange)
        case .client:  return ("person.text.rectangle.fill",          .indigo)
        case .task:    return ("checkmark.circle",                    .green)
        case .event:   return ("calendar",                            .blue)
        case .person:  return ("person.crop.circle",                  .pink)
        case .place:   return ("mappin.and.ellipse",                  .red)
        case .file:    return ("doc",                                 .gray)
        case .idea:    return ("lightbulb",                           .yellow)
        case .habit:   return ("repeat.circle",                       .teal)
        case .goal:    return ("target",                              .purple)
        case .journal: return ("book.closed",                         .brown)
        }
    }
}

private struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(LiquidPalette.lavender.opacity(0.35))
            }
            .lineLimit(1)
    }
}
