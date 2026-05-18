import SwiftUI
import DesignSystem
import GraphCore

struct ClientDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let client: Node
    let audits: [Node]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                summaryCard
                if audits.isEmpty {
                    emptyAuditsState
                } else {
                    auditsTimeline
                }
            }
            .padding(20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background {
            LiquidBackground().ignoresSafeArea()
        }
        .onAppear {
            client.touchAccess()
            try? context.save()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(client.title)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                if let host = hostLabel {
                    Text(host)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if let personaRaw = personaTag {
                    PersonaPill(raw: personaRaw)
                        .padding(.top, 2)
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

    private var hostLabel: String? {
        guard let url = URL(string: client.content),
              let host = url.host(percentEncoded: false) else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var personaTag: String? {
        client.tags.first { ["saasB2B", "tpePme", "lifestyleDTC", "other"].contains($0) }
    }

    // MARK: - Summary card

    @ViewBuilder
    private var summaryCard: some View {
        LiquidCard(cornerRadius: 22) {
            HStack(spacing: 16) {
                if let latest = audits.first {
                    ScoreBadge(score: score(of: latest))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dernier score")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(score(of: latest)) / 100")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                        Text(latest.createdAt.formatted(.relative(presentation: .named)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(LiquidGradient.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aucun audit")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Text("Relance un audit pour mettre à jour le score.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                trendBadge
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var trendBadge: some View {
        if audits.count >= 2 {
            let latest = score(of: audits[0])
            let previous = score(of: audits[1])
            let delta = latest - previous
            HStack(spacing: 4) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("\(delta >= 0 ? "+" : "")\(delta)")
                    .monospacedDigit()
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(delta >= 0 ? .green : .red)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill((delta >= 0 ? Color.green : Color.red).opacity(0.15))
            }
        }
    }

    // MARK: - Timeline

    private var auditsTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Historique d'audits".uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, 4)

            ForEach(audits) { audit in
                AuditTimelineCard(audit: audit)
            }
        }
    }

    @ViewBuilder
    private var emptyAuditsState: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(spacing: 8) {
                Text("Aucun audit attaché à ce client.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Le client a été créé mais l'audit lié n'est pas encore disponible.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private func score(of audit: Node) -> Int {
        audit.tags
            .first { $0.hasPrefix("score-") }
            .flatMap { Int($0.dropFirst("score-".count)) } ?? 0
    }
}

// MARK: - Audit timeline card

private struct AuditTimelineCard: View {
    let audit: Node

    var body: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    ScoreBadge(score: score)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audit.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(audit.createdAt.formatted(.relative(presentation: .named)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(audit.content)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var score: Int {
        audit.tags
            .first { $0.hasPrefix("score-") }
            .flatMap { Int($0.dropFirst("score-".count)) } ?? 0
    }
}
