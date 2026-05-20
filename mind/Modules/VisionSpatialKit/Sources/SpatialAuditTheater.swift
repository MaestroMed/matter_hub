#if os(visionOS)
import SwiftUI

/// v1.0-alpha.19 — Audit Theater entry panel for the visionOS spatial
/// cockpit.
///
/// Surfaces a single CTA — "Présenter en immersion" — that opens the
/// `AuditTheater` `ImmersiveSpace` on tap. Inside the immersive space,
/// the audit's synthesis floats on a central panel and every quick
/// win curls around the viewer on a half-circle (the placement math
/// lives in `TheaterPlacement`).
///
/// The viewer chooses which audit to present from a list of finished
/// audits — for v1.0-alpha.19 the list seeds with a single demo audit
/// so the surface lands renderable on first launch. Wave B wires the
/// list to the host App's `AuditReportArchive` reader.
public struct SpatialAuditTheater: View {

    public struct AuditCard: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let clientName: String
        public let synthesisPreview: String
        public let quickWinCount: Int

        public init(
            id: UUID = UUID(),
            clientName: String,
            synthesisPreview: String,
            quickWinCount: Int
        ) {
            self.id = id
            self.clientName = clientName
            self.synthesisPreview = synthesisPreview
            self.quickWinCount = quickWinCount
        }
    }

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    private let audits: [AuditCard]

    public init(audits: [AuditCard] = SpatialAuditTheater.demoAudits) {
        self.audits = audits
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if audits.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(audits) { audit in
                            card(for: audit)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "spatial.tab.audit", defaultValue: "Audits"))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(
                String(
                    localized: "spatial.audit.subtitle",
                    defaultValue: "Théâtre d'immersion pour les rapports finis"
                )
            )
            .font(.system(.title3, design: .rounded, weight: .regular))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized: "spatial.empty.audits",
                    defaultValue: "Aucun audit terminé à présenter."
                )
            )
            .font(.system(.title3, design: .rounded, weight: .regular))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        }
        .padding(48)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .glassBackgroundEffect()
    }

    private func card(for audit: AuditCard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(audit.clientName)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text("\(audit.quickWinCount) quick wins")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }

            Text(audit.synthesisPreview)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(4)

            Button {
                SpatialTelemetryBridge.shared.theaterOpened(auditID: audit.id)
                Task {
                    await openImmersiveSpace(id: SpatialAuditTheater.immersiveSpaceID)
                }
            } label: {
                Text(
                    String(
                        localized: "spatial.audit.theater.button",
                        defaultValue: "Présenter en immersion"
                    )
                )
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background {
                    Capsule(style: .continuous)
                        .fill(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .glassBackgroundEffect()
    }

    // MARK: - Constants

    /// The id the visionOS `ImmersiveSpace` is registered under in
    /// `MINDApp.body`. Kept in one place so both the opener and the
    /// `ImmersiveSpace` declaration reference the exact same string.
    public static let immersiveSpaceID: String = "AuditTheater"

    // MARK: - Demo seed

    public static let demoAudits: [AuditCard] = [
        AuditCard(
            clientName: "AZ Construction",
            synthesisPreview: """
            Site marketing performant sur mobile (LCP 2.1 s) mais Core Web Vitals dégradés sur desktop (CLS 0.24).
            Hidden risks : pas de tracking de conversion, contact form fragile.
            """,
            quickWinCount: 5
        ),
        AuditCard(
            clientName: "IEF & Co",
            synthesisPreview: """
            Excellente accessibilité (axe-core score 96) mais SEO technique laissé en jachère : sitemap absent, robots.txt non-canonique.
            """,
            quickWinCount: 4
        ),
    ]
}
#endif
