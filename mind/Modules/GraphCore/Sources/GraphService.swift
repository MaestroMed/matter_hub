import Foundation
import SwiftData

@MainActor
@Observable
public final class GraphService {
    public init() {}

    public func createNode(
        in context: ModelContext,
        kind: NodeKind,
        title: String,
        content: String = "",
        tags: [String] = []
    ) -> Node {
        let node = Node(kind: kind, title: title, content: content, tags: tags)
        context.insert(node)
        try? context.save()
        return node
    }

    public func link(
        in context: ModelContext,
        from: Node,
        to: Node,
        kind: EdgeKind = .relatedTo
    ) {
        let edge = Edge(kind: kind, from: from, to: to)
        context.insert(edge)
        try? context.save()
    }

    public func search(in context: ModelContext, query: String, kinds: Set<NodeKind>? = nil) -> [Node] {
        let lowered = query.lowercased()
        let descriptor = FetchDescriptor<Node>(
            predicate: #Predicate { node in
                node.title.localizedStandardContains(lowered) ||
                node.content.localizedStandardContains(lowered)
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let results = (try? context.fetch(descriptor)) ?? []
        if let kinds {
            return results.filter { kinds.contains($0.kind) }
        }
        return results
    }
}
