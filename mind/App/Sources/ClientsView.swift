import SwiftUI
import SwiftData
import DesignSystem
import GraphCore

struct ClientsView: View {
    @Query(sort: \Node.createdAt, order: .reverse) private var allNodes: [Node]
    @State private var searchText: String = ""
    @State private var selected: Node?
    /// Set when the user taps one of the demo audit suggestions in the
    /// empty state. Drives a .sheet that presents AuditSheet pre-seeded
    /// with the chosen URL so they go from blank → audit running in
    /// one tap.
    @State private var demoAuditURL: DemoAuditTarget?

    private var clients: [Node] {
        allNodes.filter { $0.kindRaw == "client" }
    }

    private var filtered: [Node] {
        guard !searchText.isEmpty else { return clients }
        let needle = searchText.lowercased()
        return clients.filter {
            $0.title.lowercased().contains(needle) ||
            $0.tags.joined().lowercased().contains(needle) ||
            $0.content.lowercased().contains(needle)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                searchField
                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { client in
                            Button {
                                selected = client
                            } label: {
                                ClientCard(
                                    client: client,
                                    audits: ClientsView.audits(for: client)
                                )
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
        .sheet(item: $selected) { client in
            ClientDetailView(
                client: client,
                audits: ClientsView.audits(for: client)
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $demoAuditURL) { target in
            AuditSheet(initialURL: target.url)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Clients")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text(subtitle)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        switch clients.count {
        case 0:  return "Aucun client audité pour le moment."
        case 1:  return "1 prospect dans ton graphe."
        default: return "\(clients.count) prospects dans ton graphe."
        }
    }

    private var searchField: some View {
        LiquidCard(cornerRadius: 20) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search clients…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if clients.isEmpty {
            firstRunEmptyState
        } else {
            noResultsEmptyState
        }
    }

    /// First-run empty state: surfaces three well-known SaaS targets as
    /// one-tap audit starters so the user goes from "I just installed
    /// MIND" to "I'm watching Claude synthesise a Stripe audit" in a
    /// single tap, without having to switch tabs or type a URL.
    private var firstRunEmptyState: some View {
        VStack(spacing: 16) {
            LiquidCard {
                VStack(spacing: 14) {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(LiquidGradient.primary)
                    Text("Pas encore de client")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Text("Tape un domaine pour lancer un audit, ou essaie un des exemples ci-dessous.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Essaie avec".uppercased())
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .padding(.leading, 4)

                ForEach(Self.demoTargets) { target in
                    demoAuditRow(target)
                }
            }
        }
    }

    private var noResultsEmptyState: some View {
        LiquidCard {
            VStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(LiquidGradient.primary)
                Text("Aucun résultat")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text("Essaie un autre terme de recherche.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(36)
            .frame(maxWidth: .infinity)
        }
    }

    private func demoAuditRow(_ target: DemoAuditTarget) -> some View {
        LiquidCard(cornerRadius: 18) {
            Button {
                LiquidHaptics.select()
                demoAuditURL = target
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(target.tint.opacity(0.20))
                            .frame(width: 42, height: 42)
                        Image(systemName: target.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(target.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.name)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(target.url)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Audit \(target.name)")
        }
    }

    /// Three SaaS targets that consistently produce rich audit reports
    /// (good PageSpeed score, complete security headers, a registered
    /// iOS companion app) — chosen so the first-run user sees the full
    /// surface area of what MIND can synthesize.
    static let demoTargets: [DemoAuditTarget] = [
        DemoAuditTarget(
            name: "Stripe",
            url: "https://stripe.com",
            icon: "creditcard.fill",
            tint: .purple
        ),
        DemoAuditTarget(
            name: "Linear",
            url: "https://linear.app",
            icon: "checklist",
            tint: .blue
        ),
        DemoAuditTarget(
            name: "Notion",
            url: "https://notion.so",
            icon: "doc.richtext.fill",
            tint: .orange
        ),
    ]

    // MARK: - Graph helpers

    /// Walks the Edge.derivedFrom relationship to find every audit attached
    /// to a given client, newest first.
    static func audits(for client: Node) -> [Node] {
        client.incoming
            .compactMap { $0.from }
            .filter { $0.kindRaw == "audit" }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Demo audit target

/// One of the "Try with" cards in the first-run empty state. Stored
/// as a plain struct so it can be Identifiable (drives the .sheet
/// item-based presentation in ClientsView) without leaking into the
/// SwiftData @Model graph.
struct DemoAuditTarget: Identifiable, Hashable {
    var id: String { url }   // URL is unique enough across the three demos
    let name: String
    let url: String
    let icon: String
    let tint: Color
}

// MARK: - Client card

private struct ClientCard: View {
    let client: Node
    let audits: [Node]

    var body: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.title)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        if let host = hostLabel {
                            Text(host)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if let lastAudit = audits.first {
                        ScoreBadge(score: Self.score(of: lastAudit))
                    }
                }

                HStack(spacing: 10) {
                    if let persona = personaTag {
                        PersonaPill(raw: persona)
                    }
                    Label(auditCountLabel, systemImage: "doc.text.magnifyingglass")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let lastAudit = audits.first {
                        Text(lastAudit.createdAt.formatted(.relative(presentation: .named)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var auditCountLabel: String {
        switch audits.count {
        case 0:  return "Aucun audit"
        case 1:  return "1 audit"
        default: return "\(audits.count) audits"
        }
    }

    static func score(of audit: Node) -> Int {
        audit.tags
            .first { $0.hasPrefix("score-") }
            .flatMap { Int($0.dropFirst("score-".count)) } ?? 0
    }
}

// MARK: - Shared little views

struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background {
                Circle().fill(color.opacity(0.92))
            }
            .overlay {
                Circle().stroke(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: color.opacity(0.35), radius: 6, y: 2)
    }

    private var color: Color {
        switch score {
        case 80...:   return .green
        case 50..<80: return .orange
        default:      return .red
        }
    }
}

struct PersonaPill: View {
    let raw: String

    var body: some View {
        Text(label.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(LiquidPalette.iris)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(LiquidPalette.lavender.opacity(0.4))
            }
    }

    private var label: String {
        switch raw {
        case "saasB2B":      return "SaaS B2B"
        case "tpePme":       return "TPE / PME"
        case "lifestyleDTC": return "DTC"
        default:             return "Other"
        }
    }
}
