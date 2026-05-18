import SwiftUI
import SwiftData
import DesignSystem
import GraphCore
import Notes

/// Polymorphic full-screen rendering of any Node in the graph. Triggered
/// from NotesView (and later from search). The body adapts to the kind:
/// audits show the full Claude synthesis in markdown, clients show their
/// host + persona + a button to jump into the dedicated ClientDetailView,
/// everything else gets a friendly title + content + tags + relative
/// date treatment.
struct NodeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let node: Node

    @State private var showClientDetail: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content
            }
            .padding(20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background {
            LiquidBackground().ignoresSafeArea()
        }
        .sheet(isPresented: $showClientDetail) {
            ClientDetailView(
                client: node,
                audits: ClientsView.audits(for: node)
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            NodeKindBadge(kind: node.kind)
            VStack(alignment: .leading, spacing: 6) {
                Text(node.title)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .lineLimit(3)
                HStack(spacing: 10) {
                    Text(node.kind.rawValue.capitalized.uppercased())
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(node.createdAt.formatted(.relative(presentation: .named)))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Polymorphic content

    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .audit:   auditBody
        case .client:  clientBody
        default:       defaultBody
        }

        if !node.tags.isEmpty {
            tagsSection
        }

        if let sourceURL = sourceURL {
            sourceSection(url: sourceURL)
        }
    }

    // MARK: - Audit body

    private var auditBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let score = scoreFromTags {
                LiquidCard(cornerRadius: 22) {
                    HStack(spacing: 16) {
                        ScoreBadge(score: score)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Score global")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("\(score) / 100")
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                        }
                        Spacer()
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
            }
            LiquidCard(cornerRadius: 18) {
                MarkdownView(node.content)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private var scoreFromTags: Int? {
        node.tags
            .first { $0.hasPrefix("score-") }
            .flatMap { Int($0.dropFirst("score-".count)) }
    }

    // MARK: - Client body

    private var clientBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            LiquidCard(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    if let host = clientHost {
                        Label(host, systemImage: "globe")
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    if let personaRaw = personaTag {
                        PersonaPill(raw: personaRaw)
                    }
                    let auditCount = ClientsView.audits(for: node).count
                    Text("\(auditCount) \(auditCount == 1 ? "audit attaché" : "audits attachés")")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                showClientDetail = true
            } label: {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("Voir l'historique d'audits")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(LiquidPalette.iris)
                .padding(.horizontal, 18)
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
    }

    private var clientHost: String? {
        guard let url = URL(string: node.content),
              let host = url.host(percentEncoded: false) else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var personaTag: String? {
        node.tags.first { ["saasB2B", "tpePme", "lifestyleDTC", "other"].contains($0) }
    }

    // MARK: - Default body (notes, captures, ideas, tasks, etc.)

    private var defaultBody: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                if node.content.isEmpty {
                    Text("Pas de contenu pour le moment.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text(node.content)
                        .font(.system(.body, design: .rounded))
                        .textSelection(.enabled)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Tags + source

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags".uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, 4)
            FlowLayout(spacing: 6) {
                ForEach(node.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(LiquidPalette.lavender.opacity(0.35))
                        }
                }
            }
        }
    }

    private var sourceURL: URL? {
        guard let raw = node.sourceURL else { return nil }
        return URL(string: raw)
    }

    private func sourceSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Source".uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, 4)
            Link(destination: url) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                    Text(url.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(LiquidPalette.iris)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        }
    }
}

// MARK: - FlowLayout

/// Minimal flow layout for wrapping tag chips. Native iOS 16+ Layout
/// protocol; no external dep.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
