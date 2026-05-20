import SwiftUI
import SwiftData
import DesignSystem
import GraphCore
import OutreachKit
import AuditKit   // v0.27 — LeadScorer + LeadScore + LeadTemperature

/// v0.27 — Sort modes for the ClientsView segmented control.
/// `.score` is the default so Mehdi opens the Clients tab and
/// immediately sees who to call next.
enum ClientSortMode: String, CaseIterable, Identifiable {
    case score
    case recent
    case alphabetical
    var id: String { rawValue }
}

struct ClientsView: View {
    @Query(sort: \Node.createdAt, order: .reverse) private var allNodes: [Node]
    @State private var searchText: String = ""
    @State private var selected: Node?
    /// Set when the user taps one of the demo audit suggestions in the
    /// empty state. Drives a .sheet that presents AuditSheet pre-seeded
    /// with the chosen URL so they go from blank → audit running in
    /// one tap.
    @State private var demoAuditURL: DemoAuditTarget?
    /// v0.26 — Set when the user picks "Outreach" from a client
    /// card's context menu. Drives the OutreachSheet presentation
    /// pre-populated with that client's identity. Distinct from
    /// `selected` so the two sheets don't conflict on dismissal.
    @State private var outreachClient: Node?
    /// v0.27 — Set when the user taps the LeadScoreBadge on any
    /// ClientCard. Drives the LeadScoreBreakdownSheet that explains
    /// the 0–100 score and surfaces the per-axis reasoning bullets.
    @State private var breakdownTarget: LeadBreakdownTarget?
    /// v0.27 — Active sort mode. Defaults to .score so the freshest
    /// "who do I call next" lead lands at the top of the list every
    /// time Mehdi opens the tab.
    @State private var sortMode: ClientSortMode = .score

    private var clients: [Node] {
        allNodes.filter { $0.kindRaw == "client" }
    }

    /// v0.27 — Search + sort pipeline. Score sort is the default;
    /// recent sort = lastAccessedAt ?? createdAt, desc; alphabetical
    /// sort = `title`, ascending, case-insensitive. The score path
    /// re-computes the heuristic per render — cheap enough (< 50µs
    /// per node) that we don't bother caching.
    private var filtered: [Node] {
        let base: [Node]
        if searchText.isEmpty {
            base = clients
        } else {
            let needle = searchText.lowercased()
            base = clients.filter {
                $0.title.lowercased().contains(needle) ||
                $0.tags.joined().lowercased().contains(needle) ||
                $0.content.lowercased().contains(needle)
            }
        }
        return ClientsView.sort(base, mode: sortMode)
    }

    /// Pure sort helper extracted so the same projection can power
    /// the HomeView "Top leads" card. Score sort uses
    /// `LeadScorer.heuristic` desc with `createdAt` as a tie-breaker
    /// (newest wins on identical scores).
    static func sort(_ clients: [Node], mode: ClientSortMode) -> [Node] {
        switch mode {
        case .score:
            return clients.sorted { lhs, rhs in
                let l = LeadScorer.heuristic(node: lhs).total
                let r = LeadScorer.heuristic(node: rhs).total
                if l != r { return l > r }
                return lhs.createdAt > rhs.createdAt
            }
        case .recent:
            return clients.sorted { lhs, rhs in
                let l = lhs.lastAccessedAt ?? lhs.createdAt
                let r = rhs.lastAccessedAt ?? rhs.createdAt
                return l > r
            }
        case .alphabetical:
            return clients.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                searchField
                if !clients.isEmpty {
                    sortPicker
                }
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
                                    audits: ClientsView.audits(for: client),
                                    onBadgeTap: { score in
                                        LiquidHaptics.select()
                                        breakdownTarget = LeadBreakdownTarget(
                                            client: client,
                                            score: score
                                        )
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                            // v0.26 — Long-press a client card to
                            // jump straight into the OutreachSheet.
                            // Context menu is the lightest-touch
                            // affordance here — no chrome added to
                            // the card itself, and the discovery
                            // moment matches iOS standard
                            // (long-press = secondary actions).
                            .contextMenu {
                                Button {
                                    outreachClient = client
                                } label: {
                                    Label(
                                        String(localized: "node.action.outreach"),
                                        systemImage: "envelope.badge.shield.half.filled"
                                    )
                                }
                            }
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
        .sheet(item: $outreachClient) { client in
            // v0.26 — Pre-seed the prospect context from the
            // tapped client Node. URL lives in `content` for client
            // kind; host derived from it powers the prompt
            // grounding so Claude knows which prospect we mean.
            OutreachSheet(
                prospect: ProspectContext(
                    clientName: client.title,
                    host: ClientsView.host(of: client) ?? client.content,
                    auditReport: nil,
                    recentTrigger: nil,
                    industry: nil,
                    primaryContactName: nil,
                    primaryContactRole: nil
                )
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        // v0.27 — Lead score breakdown modal. Triggered by tapping
        // the LeadScoreBadge on any ClientCard. Shows the 0–100
        // total, the three sub-scores with progress bars, and the
        // reasoning bullets verbatim so Mehdi can audit the
        // heuristic at any time.
        .sheet(item: $breakdownTarget) { target in
            LeadScoreBreakdownSheet(client: target.client, score: target.score)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    /// Best-effort host extraction from a client Node's stored URL.
    /// Returns nil when the URL string is empty / malformed; the
    /// OutreachSheet caller then falls back to the raw content
    /// string so the form lands populated either way.
    static func host(of client: Node) -> String? {
        guard let url = URL(string: client.content),
              let host = url.host(percentEncoded: false) else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("clients.header.title")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text(subtitle)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        switch clients.count {
        case 0:  return String(localized: "clients.subtitle.none")
        case 1:  return String(localized: "clients.subtitle.one")
        default:
            let format = String(localized: "clients.subtitle.many")
            return String(format: format, clients.count)
        }
    }

    private var searchField: some View {
        LiquidCard(cornerRadius: 20) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "clients.search.placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    /// v0.27 — Sort segmented control. Three modes: by lead score
    /// (default), by most-recently-opened, alphabetical. Picker
    /// style `.segmented` matches iOS standard so the affordance
    /// reads instantly. Wrapped in a LiquidCard so it shares the
    /// glass aesthetic of the search field above.
    private var sortPicker: some View {
        Picker(
            String(localized: "lead.sort.label"),
            selection: $sortMode
        ) {
            Text(String(localized: "lead.sort.score")).tag(ClientSortMode.score)
            Text(String(localized: "lead.sort.recent")).tag(ClientSortMode.recent)
            Text(String(localized: "lead.sort.alphabetical")).tag(ClientSortMode.alphabetical)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 4)
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
                    // 40pt illustration glyph kept fixed (display-only).
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(LiquidGradient.primary)
                    Text("clients.empty.title")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .minimumScaleFactor(0.85)
                        .lineLimit(2)
                    Text("clients.empty.detail")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "clients.demo.section").uppercased())
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
                // 40pt illustration glyph kept fixed (display-only).
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(LiquidGradient.primary)
                Text("clients.noresults.title")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.85)
                    .lineLimit(2)
                Text("clients.noresults.detail")
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
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(target.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.name)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.85)
                            .lineLimit(2)
                        Text(target.url)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
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
    /// to a given client, newest first. Coalesces `incoming` against nil
    /// because the relationship is typed `[Edge]?` for CloudKit
    /// compatibility — empty graph or freshly fetched record may surface
    /// nil rather than an empty array.
    static func audits(for client: Node) -> [Node] {
        (client.incoming ?? [])
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
    /// v0.27 — Tap callback for the LeadScoreBadge. Receives the
    /// computed score so the parent doesn't have to re-run the
    /// heuristic when opening the breakdown modal.
    var onBadgeTap: ((LeadScore) -> Void)? = nil

    /// v0.27 — Live heuristic score. Recomputed on every render
    /// (cheap — ~50µs per node) so the badge always reflects the
    /// freshest tags / lastAccessedAt without any cache to
    /// invalidate.
    private var leadScore: LeadScore {
        LeadScorer.heuristic(node: client)
    }

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
                    // v0.27 — Lead score badge always renders (every
                    // prospect gets a number, even if 0). Audit score
                    // tile renders only when an audit exists,
                    // tucked underneath in the second row so the
                    // hierarchy reads: who do I call → audit health.
                    LeadScoreBadge(score: leadScore) {
                        onBadgeTap?(leadScore)
                    }
                }

                HStack(spacing: 10) {
                    if let persona = personaTag {
                        PersonaPill(raw: persona)
                    }
                    if let lastAudit = audits.first {
                        Label("\(Self.score(of: lastAudit))",
                              systemImage: "speedometer")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
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

// MARK: - v0.27 Lead score UI

/// v0.27 — Identifiable wrapper used by the
/// `breakdownTarget` `.sheet(item:)` presentation in ClientsView.
/// Carries the computed score so the breakdown modal doesn't have
/// to re-run the heuristic — keeps the sheet render perfectly in
/// sync with the badge the user tapped.
struct LeadBreakdownTarget: Identifiable, Hashable {
    let client: Node
    let score: LeadScore
    var id: UUID { client.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(client.id)
        hasher.combine(score.total)
    }

    static func == (lhs: LeadBreakdownTarget, rhs: LeadBreakdownTarget) -> Bool {
        lhs.client.id == rhs.client.id && lhs.score == rhs.score
    }
}

/// v0.27 — Color-coded lead score capsule. Three temperatures map
/// to three gradients: iris-red (hot 🔥), orange (warm ☀️), sky-blue
/// (cold ❄️). Tap fires the parent's breakdown-modal callback +
/// emits a `lead.score.breakdown.opened` telemetry breadcrumb.
///
/// Why a capsule, not a circle: capsule comfortably holds two
/// digits + emoji at Dynamic Type sizes without elliptical
/// distortion, while still being unmistakably a "score" affordance.
struct LeadScoreBadge: View {
    let score: LeadScore
    let onTap: () -> Void

    var body: some View {
        Button {
            MINDTelemetry.info(
                "lead.score.breakdown.opened",
                data: [
                    "total": String(score.total),
                    "temperature": score.temperature.rawValue,
                ]
            )
            onTap()
        } label: {
            HStack(spacing: 4) {
                Text(score.temperature.emoji)
                    .font(.system(.caption, design: .rounded))
                Text("\(score.total)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(Self.gradient(for: score.temperature))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: Self.shadowColor(for: score.temperature), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("lead.score.label"))
        .accessibilityValue(Text("\(score.total), \(Self.tempLabel(score.temperature))"))
    }

    /// Three palette-aligned gradients. Hot leans on `iris` (the
    /// brand red-purple) — the visual cue is "this needs heat".
    /// Warm uses an orange/blush mix to read as sun. Cold blends
    /// `aqua` + `sky` for an unmistakable cool-blue band.
    static func gradient(for temp: LeadTemperature) -> LinearGradient {
        switch temp {
        case .hot:
            return LinearGradient(
                colors: [LiquidPalette.iris, LiquidPalette.blush],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .warm:
            return LinearGradient(
                colors: [Color.orange, LiquidPalette.blush],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cold:
            return LinearGradient(
                colors: [LiquidPalette.sky, LiquidPalette.aqua],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func shadowColor(for temp: LeadTemperature) -> Color {
        switch temp {
        case .hot:  return LiquidPalette.iris.opacity(0.35)
        case .warm: return Color.orange.opacity(0.30)
        case .cold: return LiquidPalette.sky.opacity(0.30)
        }
    }

    static func tempLabel(_ temp: LeadTemperature) -> String {
        switch temp {
        case .hot:  return String(localized: "lead.temperature.hot")
        case .warm: return String(localized: "lead.temperature.warm")
        case .cold: return String(localized: "lead.temperature.cold")
        }
    }
}

/// v0.27 — Modal that explains the 0–100 lead score: the temperature
/// band, the three sub-scores as horizontal bars, and the verbatim
/// reasoning bullets so Mehdi can sanity-check the heuristic at any
/// time. Presented from ClientsView when the LeadScoreBadge is
/// tapped, and from HomeView when a "Top leads" row is tapped.
struct LeadScoreBreakdownSheet: View {
    let client: Node
    let score: LeadScore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                totalCard
                breakdownBars
                reasoningCard
            }
            .padding(24)
            .padding(.top, 24)
            .padding(.bottom, 80)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(client.title)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .lineLimit(2)
            Text(String(localized: "lead.breakdown.title"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var totalCard: some View {
        LiquidCard(cornerRadius: 24) {
            HStack(alignment: .center, spacing: 16) {
                Text(score.temperature.emoji)
                    .font(.system(size: 44))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(score.total) / 100")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text(LeadScoreBadge.tempLabel(score.temperature))
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var breakdownBars: some View {
        VStack(alignment: .leading, spacing: 12) {
            BreakdownRow(
                label: String(localized: "lead.breakdown.icpFit"),
                value: score.icpFit,
                ceiling: 40,
                tint: LiquidPalette.iris
            )
            BreakdownRow(
                label: String(localized: "lead.breakdown.buyingSignals"),
                value: score.buyingSignals,
                ceiling: 40,
                tint: Color.orange
            )
            BreakdownRow(
                label: String(localized: "lead.breakdown.engagement"),
                value: score.engagement,
                ceiling: 20,
                tint: LiquidPalette.sky
            )
        }
    }

    private var reasoningCard: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(score.reasoning, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(LiquidPalette.iris)
                            .padding(.top, 6)
                        Text(bullet)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// v0.27 — One row of the breakdown sheet: label, current value,
/// gradient bar fill against a ceiling, current/ceiling label on
/// the right. Pure presentational helper — no business logic.
private struct BreakdownRow: View {
    let label: String
    let value: Int
    let ceiling: Int
    let tint: Color

    private var fraction: CGFloat {
        guard ceiling > 0 else { return 0 }
        return min(1, max(0, CGFloat(value) / CGFloat(ceiling)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                Spacer()
                Text("\(value) / \(ceiling)")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [tint, tint.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 10)
        }
    }
}
