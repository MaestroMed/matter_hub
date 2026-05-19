import SwiftUI
import SwiftData
import DesignSystem
import GraphCore

public struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Node.updatedAt, order: .reverse) private var allNodes: [Node]

    @State private var searchText: String = ""

    /// Cached embedding for the current search query. Recomputed via
    /// .onChange so we don't pay the ~10-30ms model call on every
    /// keystroke when reading the same query through `filtered`.
    @State private var queryEmbedding: [Float]?

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
                        if semanticIsActive {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .animation(.smooth, value: semanticIsActive)
                }
                .onChange(of: searchText) { _, newValue in
                    refreshQueryEmbedding(for: newValue)
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

    /// Hybrid ranking: when the search query has a usable embedding, we
    /// score every embedded Node with 60 % cosine similarity + 40 %
    /// text-match signal (title hit > content hit > tag hit > none).
    /// Falls back to pure text search when no query embedding is
    /// available (model unsupported language, empty query input, etc.).
    private var filtered: [Node] {
        guard !searchText.isEmpty else { return displayNodes }
        let needle = searchText.lowercased()

        if let queryEmbedding {
            let scored = displayNodes.map { node -> (node: Node, score: Float) in
                (node, hybridScore(
                    node: node,
                    needle: needle,
                    queryEmbedding: queryEmbedding
                ))
            }
            let keep = scored
                .filter { $0.score >= 0.18 }            // noise floor
                .sorted { $0.score > $1.score }
                .map(\.node)
            if !keep.isEmpty { return keep }
        }

        return displayNodes.filter {
            $0.title.lowercased().contains(needle) ||
            $0.content.lowercased().contains(needle) ||
            $0.tags.joined(separator: " ").lowercased().contains(needle)
        }
    }

    /// True when the active search is actually using vector ranking, so
    /// the search field shows a discreet `sparkles` indicator.
    private var semanticIsActive: Bool {
        !searchText.isEmpty && queryEmbedding != nil
    }

    // MARK: - Ranking helpers

    private func hybridScore(
        node: Node,
        needle: String,
        queryEmbedding: [Float]
    ) -> Float {
        let textScore = textMatchScore(for: node, needle: needle)
        let semanticScore: Float = {
            guard let nodeEmbedding = node.embedding else { return 0 }
            // cosine ∈ [-1, 1]; clamp to [0, 1] for clean blending.
            let raw = EmbeddingService.cosineSimilarity(queryEmbedding, nodeEmbedding)
            return max(0, raw)
        }()
        return textScore * 0.4 + semanticScore * 0.6
    }

    private func textMatchScore(for node: Node, needle: String) -> Float {
        if node.title.lowercased().contains(needle) { return 1.0 }
        if node.content.lowercased().contains(needle) { return 0.6 }
        if node.tags.joined(separator: " ").lowercased().contains(needle) { return 0.4 }
        return 0
    }

    private func refreshQueryEmbedding(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            queryEmbedding = nil
            return
        }
        queryEmbedding = EmbeddingService.embed(trimmed)
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
        case .meeting: return ("calendar.badge.clock",                LiquidPalette.iris)
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
