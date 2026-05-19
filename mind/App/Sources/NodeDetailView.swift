import SwiftUI
import SwiftData
import DesignSystem
import GraphCore
import Notes
import OutreachKit

/// Polymorphic full-screen rendering of any Node in the graph. Triggered
/// from NotesView (and later from search). The body adapts to the kind:
/// audits show the full Claude synthesis in markdown, clients show their
/// host + persona + a button to jump into the dedicated ClientDetailView,
/// everything else gets a friendly title + content + tags + relative
/// date treatment.
struct NodeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let node: Node

    @State private var showClientDetail: Bool = false
    /// v0.26 — Drives the OutreachSheet presentation from the client
    /// body's "Générer outreach" button. Only meaningful when the
    /// node is `.client` kind; default-body / audit-body branches
    /// never read this flag.
    @State private var showOutreach: Bool = false
    /// v0.18 — Singleton voice player drives the Listen button + the
    /// mini playback bar. SwiftUI's `@State` plus the player's
    /// `@Observable` macro reactively re-renders the icon when
    /// `isPlaying` / `currentNodeID` flip.
    @State private var voicePlayer = VoicePlayer.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    content
                }
                .padding(20)
                .padding(.top, 16)
                // v0.18 — Pad the bottom an extra ~80pt when the voice
                // mini-bar is visible so the last paragraph doesn't get
                // hidden behind the overlay.
                .padding(.bottom, isReadingThisNode ? 120 : 40)
            }
            .background {
                LiquidBackground().ignoresSafeArea()
            }

            // v0.18 — Liquid Glass mini playback bar. Shows only while
            // this Node is the one reading aloud; tapping another node
            // re-targets the player, which auto-hides the bar here.
            if isReadingThisNode {
                VoicePlaybackMiniBar(
                    voicePlayer: voicePlayer,
                    onStop: { voicePlayer.stop() }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(LiquidMetrics.spring, value: isReadingThisNode)
        .onAppear {
            node.touchAccess()
            try? context.save()
            // Re-index the node every time the user opens it so any
            // edits made since the last RootView backfill (title change,
            // new content, tag added) propagate to Spotlight without
            // waiting for the next app launch.
            SpotlightIndexer.index(node)
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
        .sheet(isPresented: $showOutreach) {
            // v0.26 — Pre-seed the prospect context from this Node so
            // the form lands populated with the client name + host
            // (URL stored in `content` for client kind) and any
            // attached audit. The user can then tweak the recent
            // trigger / industry / voice tone before hitting
            // "Générer 5 variantes".
            OutreachSheet(
                prospect: ProspectContext(
                    clientName: node.title,
                    host: clientHost ?? node.content,
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
    }

    // MARK: - Voice helpers

    /// `true` when the voice player is currently reading THIS node
    /// (as opposed to silence or a different node). Drives both the
    /// header Listen icon swap and the mini-bar visibility.
    private var isReadingThisNode: Bool {
        voicePlayer.isPlaying && voicePlayer.currentNodeID == node.id
    }

    /// Localized accessibility label for the Listen button — reflects
    /// the current state so VoiceOver users hear "Stop listening" when
    /// audio is in flight instead of always "Listen".
    private var listenLabelKey: LocalizedStringKey {
        isReadingThisNode ? "node.action.stop.listening" : "node.action.listen"
    }

    /// Toggle handler for the Listen button. Reads the node's title +
    /// content as one continuous sentence so the speaker hears the
    /// context (title) before the body.
    private func toggleListen() {
        LiquidHaptics.select()
        if isReadingThisNode {
            voicePlayer.stop()
            return
        }
        let payload = node.title.isEmpty
            ? node.content
            : node.title + ". " + node.content
        Task { await voicePlayer.play(text: payload, nodeID: node.id) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            NodeKindBadge(kind: node.kind)
            VStack(alignment: .leading, spacing: 6) {
                Text(node.title)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 10) {
                    Text(node.kind.rawValue.capitalized.uppercased())
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(node.createdAt.formatted(.relative(presentation: .named)))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            // v0.18 — Listen button reads the node aloud via
            // AVSpeechSynthesizer + Siri Natural voices. The icon
            // flips between speaker (idle) and speaker-slash (playing
            // this node) so the visual state tracks the audio state.
            Button(action: toggleListen) {
                Image(systemName: isReadingThisNode
                      ? "speaker.slash.fill"
                      : "speaker.wave.2.fill")
                    .font(.title2)
                    .foregroundStyle(isReadingThisNode
                                     ? LiquidPalette.iris
                                     : .secondary)
                    .symbolEffect(.bounce, value: isReadingThisNode)
            }
            .accessibilityLabel(Text(listenLabelKey))
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
            // v0.26 — Outreach engine entry point. Sits below the
            // audit history CTA so the user moves from "I want to
            // see what we know about this prospect" → "I want to
            // reach out" in two visually adjacent affordances.
            Button {
                LiquidHaptics.select()
                showOutreach = true
            } label: {
                HStack {
                    Image(systemName: "envelope.badge.shield.half.filled")
                    Text("node.action.outreach")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background {
                    Capsule(style: .continuous)
                        .fill(LiquidGradient.primary)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(.white.opacity(0.35), lineWidth: 1)
                        }
                }
                .shadow(color: LiquidPalette.iris.opacity(0.35), radius: 12, y: 6)
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
        // Tap-to-edit / blur-to-render markdown experience (v0.5). The
        // editor is its own subview so its FocusState + binding live
        // close to the TextEditor without rebuilding the whole detail
        // tree on every keystroke.
        MarkdownEditorCard(node: node)
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

// MARK: - Markdown editor card (v0.5)

/// Tap-to-edit / blur-to-render markdown card. Renders the Node's
/// content as a styled `MarkdownView` by default; switching to edit
/// mode swaps in a monospaced `TextEditor` bound to `node.content`.
/// On blur we persist (`context.save()`), refresh the on-device
/// embedding so semantic search stays in sync, re-index Spotlight,
/// and emit a `node.edit` telemetry breadcrumb.
private struct MarkdownEditorCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var node: Node

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                if isEditing {
                    editor
                } else {
                    renderedPreview
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.smooth(duration: 0.18), value: isEditing)
        // Treat any blur (tap outside, keyboard dismissal, programmatic
        // focus loss) as the commit signal — matches the v0.5
        // acceptance: tap to edit, blur to render.
        .onChange(of: isFocused) { _, focused in
            if !focused, isEditing {
                commitEdit()
            }
        }
    }

    // MARK: - Rendered preview (default state)

    @ViewBuilder
    private var renderedPreview: some View {
        if node.content.isEmpty {
            Button {
                enterEditMode()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(LiquidPalette.iris)
                    Text("Touche pour écrire en Markdown.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } else {
            // Tap anywhere on the rendered markdown to jump into
            // edit mode. `contentShape` makes the whole card area
            // tappable rather than only the glyphs themselves.
            MarkdownView(node.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    enterEditMode()
                }
        }
    }

    // MARK: - Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $node.content)
                .focused($isFocused)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .overlay(alignment: .topLeading) {
                    if node.content.isEmpty {
                        Text("Markdown… **gras**, *italique*, # titre, - liste, [lien](https://)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LiquidPalette.iris)
                Text("Termine pour générer l'aperçu")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Aperçu") {
                    // Drop focus and let the .onChange(isFocused) on
                    // the parent commit, so the manual button and a
                    // tap-outside share the exact same code path.
                    isFocused = false
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(LiquidPalette.iris)
            }
        }
    }

    // MARK: - State transitions

    private func enterEditMode() {
        isEditing = true
        // Defer the focus flip a tick so the TextEditor exists in the
        // hierarchy before we ask it to become first responder.
        DispatchQueue.main.async {
            isFocused = true
        }
    }

    private func commitEdit() {
        guard isEditing else { return }
        isEditing = false
        node.updatedAt = .now
        node.refreshEmbedding()
        try? context.save()
        SpotlightIndexer.index(node)
        MINDTelemetry.info(
            "node.edit",
            data: [
                "kind": node.kindRaw,
                "length": String(node.content.count),
            ]
        )
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

// MARK: - Voice playback mini-bar (v0.18)

/// Floating Liquid Glass control surface that appears at the bottom of
/// NodeDetailView while the voice player is reading this Node aloud.
/// Mirrors the lock-screen now-playing widget in spirit: a single line
/// of status, a progress capsule that fills as the read advances, and
/// a stop affordance. Pause/resume routes through the synthesizer so a
/// quick tap on the bar matches what the AirPods double-tap does.
private struct VoicePlaybackMiniBar: View {
    let voicePlayer: VoicePlayer
    let onStop: () -> Void

    var body: some View {
        LiquidCard(cornerRadius: 26) {
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(LiquidPalette.iris)
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers,
                                      options: .repeat(.continuous),
                                      isActive: voicePlayer.isPlaying)
                    Text("node.voice.playing.banner")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(LiquidPalette.iris)
                    }
                    .accessibilityLabel(Text("node.action.stop.listening"))
                }
                // Slim progress capsule. Min height keeps the geometry
                // stable when `progress` is 0 (start of read) so the bar
                // doesn't pop in height as the first delegate callback
                // fires.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(LiquidPalette.lavender.opacity(0.35))
                        Capsule()
                            .fill(LiquidGradient.glassFill)
                            .frame(width: max(4, proxy.size.width * CGFloat(voicePlayer.progress)))
                            .animation(.linear(duration: 0.25), value: voicePlayer.progress)
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }
}
