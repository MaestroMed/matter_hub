import SwiftUI
import SwiftData
import DesignSystem
import GraphCore

/// "Reprendre" — horizontal snap carousel on top of HomeView surfacing the
/// most recently opened Node(.client) entries. Lets Mehdi jump back into
/// a prospect with one tap, instead of going through the Clients tab.
struct ResumeCarousel: View {
    let clients: [Node]
    let onSelect: (Node) -> Void

    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reprendre".uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(clients) { client in
                        Button {
                            onSelect(client)
                        } label: {
                            ResumeCard(
                                client: client,
                                latestAudit: ResumeCarousel.latestAudit(for: client)
                            )
                            .frame(width: cardWidth, height: cardHeight)
                        }
                        .buttonStyle(.plain)
                        .scrollTransition(.animated.threshold(.visible(0.4))) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.55)
                                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                                .blur(radius: phase.isIdentity ? 0 : 1.5)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .frame(height: cardHeight + 6)
        }
    }

    // MARK: - Graph helpers

    /// Latest audit attached to the client through Edge.derivedFrom.
    static func latestAudit(for client: Node) -> Node? {
        client.incoming
            .compactMap { $0.from }
            .filter { $0.kindRaw == "audit" }
            .max(by: { $0.createdAt < $1.createdAt })
    }
}

// MARK: - Card

private struct ResumeCard: View {
    let client: Node
    let latestAudit: Node?

    var body: some View {
        LiquidCard(cornerRadius: 22) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REPRENDRE")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(LiquidPalette.iris)
                    Text(client.title)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    if let persona = personaTag(for: client) {
                        PersonaPill(raw: persona)
                    }
                    Spacer(minLength: 0)
                    Text(lastTouchedLabel)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let audit = latestAudit {
                    VStack(alignment: .trailing, spacing: 6) {
                        ScoreBadge(score: score(of: audit))
                        Text("score")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(LiquidGradient.primary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var lastTouchedLabel: String {
        if let touched = client.lastAccessedAt {
            return "Vu " + touched.formatted(.relative(presentation: .named))
        }
        return "Ajouté " + client.createdAt.formatted(.relative(presentation: .named))
    }

    private func personaTag(for node: Node) -> String? {
        node.tags.first { ["saasB2B", "tpePme", "lifestyleDTC", "other"].contains($0) }
    }

    private func score(of audit: Node) -> Int {
        audit.tags
            .first { $0.hasPrefix("score-") }
            .flatMap { Int($0.dropFirst("score-".count)) } ?? 0
    }
}
