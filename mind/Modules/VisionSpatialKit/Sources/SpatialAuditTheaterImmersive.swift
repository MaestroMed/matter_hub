#if os(visionOS)
import SwiftUI

/// v1.0-alpha.19 — Audit Theater immersive surface for visionOS.
///
/// When the viewer taps "Présenter en immersion" on a finished audit,
/// MIND opens this `ImmersiveSpace`. The synthesis text floats on a
/// large central panel at `TheaterPlacement.synthesisPanel`; every
/// quick win curls around the viewer on a half-arc per
/// `TheaterPlacement.placements(count:)`. The arc is bounded to 8
/// cards by the placement math.
///
/// Liquid Glass treatment
/// ----------------------
/// Every panel is built on `.ultraThinMaterial` + `glassBackgroundEffect()`
/// so the visionOS compositor renders the per-panel refraction +
/// edge highlight Apple ships natively. The synthesis panel sits a
/// touch larger (0.8 × 0.6 m) than the quick-win cards (0.45 × 0.35 m)
/// so the synthesis reads as the hero of the theater.
public struct SpatialAuditTheaterImmersive: View {

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    private let synthesis: String
    private let quickWins: [QuickWin]

    public struct QuickWin: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let title: String
        public let detail: String

        public init(
            id: UUID = UUID(),
            title: String,
            detail: String
        ) {
            self.id = id
            self.title = title
            self.detail = detail
        }
    }

    public init(
        synthesis: String = SpatialAuditTheaterImmersive.demoSynthesis,
        quickWins: [QuickWin] = SpatialAuditTheaterImmersive.demoQuickWins
    ) {
        self.synthesis = synthesis
        self.quickWins = quickWins
    }

    public var body: some View {
        ZStack {
            synthesisPanel
                .offset(z: CGFloat(TheaterPlacement.synthesisPanel.z * 100))
                .offset(
                    x: CGFloat(TheaterPlacement.synthesisPanel.x * 100),
                    y: CGFloat(-TheaterPlacement.synthesisPanel.y * 100)
                )

            ForEach(Array(quickWinPlacements.enumerated()), id: \.element.placement.index) { pair in
                quickWinCard(for: pair.element.quickWin)
                    .offset(z: CGFloat(pair.element.placement.z * 100))
                    .offset(
                        x: CGFloat(pair.element.placement.x * 100),
                        y: CGFloat(-pair.element.placement.y * 100)
                    )
            }
        }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            exitButton
        }
        .onDisappear {
            SpatialTelemetryBridge.shared.theaterExited()
        }
    }

    // MARK: - Subviews

    private var synthesisPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "spatial.audit.theater.synthesis.title",
                        defaultValue: "Synthèse"))
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(synthesis)
                .font(.system(.title3, design: .rounded, weight: .regular))
                .lineLimit(nil)
        }
        .padding(28)
        .frame(width: 560, height: 360, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .glassBackgroundEffect()
    }

    private func quickWinCard(for quickWin: QuickWin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quickWin.title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .lineLimit(2)
            Text(quickWin.detail)
                .font(.system(.subheadline, design: .rounded, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(width: 240, height: 160, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .glassBackgroundEffect()
        .hoverEffect(.lift)
    }

    private var exitButton: some View {
        Button {
            SpatialTelemetryBridge.shared.theaterExited()
            Task {
                await dismissImmersiveSpace()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                Text(String(
                    localized: "spatial.audit.theater.exit",
                    defaultValue: "Quitter l'immersion"
                ))
                .font(.system(.headline, design: .rounded, weight: .semibold))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    // MARK: - Derived

    /// Pairs every quick-win input with its computed placement on the
    /// half-arc. The pure `TheaterPlacement` enum clamps the input to
    /// `maxPlacements` so this never returns more than 8 pairs.
    private var quickWinPlacements: [(quickWin: QuickWin, placement: TheaterPlacement.Placement)] {
        let placements = TheaterPlacement.placements(count: quickWins.count)
        return zip(quickWins, placements).map { (quickWin: $0.0, placement: $0.1) }
    }

    // MARK: - Demo seed

    public static let demoSynthesis: String = """
    Site marketing performant sur mobile (LCP 2.1 s, FID 30 ms) mais Core Web Vitals dégradés sur desktop (CLS 0.24).
    Hidden risks : pas de tracking de conversion, contact form sans rate limiting, headers de sécurité partiellement implémentés.
    Priorité : sécuriser le formulaire + déployer les meta open-graph + corriger le CLS via image dimensions.
    """

    public static let demoQuickWins: [QuickWin] = [
        QuickWin(
            title: "Fixer le CLS desktop",
            detail: "Déclarer width/height sur les images hero."
        ),
        QuickWin(
            title: "Headers de sécurité",
            detail: "Ajouter HSTS, CSP, X-Frame-Options."
        ),
        QuickWin(
            title: "Tracking conversion",
            detail: "Plug GA4 + Plausible sur /contact submit."
        ),
        QuickWin(
            title: "Rate limit form",
            detail: "Cloudflare Turnstile sur /api/leads."
        ),
        QuickWin(
            title: "OG meta",
            detail: "Set og:image 1200x630 sur chaque page."
        ),
    ]
}
#endif
