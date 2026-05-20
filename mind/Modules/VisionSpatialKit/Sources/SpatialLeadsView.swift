#if os(visionOS)
import SwiftUI

/// v1.0-alpha.19 — Lead inbox panel for the visionOS spatial cockpit.
///
/// Renders the cockpit's lead inbox as a vertical column of floating
/// Liquid Glass cards. Each card is a hover-target with a subtle
/// scale + lift transform via `.hoverEffect()`; tapping a card opens
/// the lead detail in a fullscreen spatial sheet (Wave B — for
/// v1.0-alpha.19 the tap surface fires telemetry only).
///
/// Data binding
/// ------------
/// The visionOS slice does not link `GraphCore` (see
/// `MIND_BLOCKER_visionos_runtime.md` for the rationale): the App
/// target hands the inbox to this view via the
/// `SpatialLeadsView.Snapshot` value type. Until the visionOS
/// runtime is installed and the App target's destinations include
/// `.visionOS`, the inbox seeds with three demo cards so the visionOS
/// surface lands renderable on first launch.
public struct SpatialLeadsView: View {

    public struct LeadCard: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let contactName: String
        public let messagePreview: String
        public let projectName: String

        public init(
            id: UUID = UUID(),
            contactName: String,
            messagePreview: String,
            projectName: String
        ) {
            self.id = id
            self.contactName = contactName
            self.messagePreview = messagePreview
            self.projectName = projectName
        }
    }

    private let leads: [LeadCard]

    public init(leads: [LeadCard] = SpatialLeadsView.demoLeads) {
        self.leads = leads
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                if leads.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(leads) { lead in
                            card(for: lead)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
        }
        .navigationTitle(
            String(localized: "spatial.window.title", defaultValue: "MIND Cockpit")
        )
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "spatial.tab.leads", defaultValue: "Leads"))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(
                String(
                    localized: "spatial.leads.subtitle",
                    defaultValue: "Boîte d'entrée flottante"
                )
            )
            .font(.system(.title3, design: .rounded, weight: .regular))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized: "spatial.empty.leads",
                    defaultValue: "Aucun lead — la boîte d'entrée est vide."
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

    private func card(for lead: LeadCard) -> some View {
        Button {
            SpatialTelemetryBridge.shared.leadTapped(id: lead.id)
        } label: {
            HStack(alignment: .top, spacing: 16) {
                Circle()
                    .fill(LinearGradient(
                        colors: [.purple.opacity(0.7), .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(initials(for: lead.contactName))
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(lead.contactName)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                    Text(lead.projectName)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(lead.messagePreview)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .glassBackgroundEffect()
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    // MARK: - Helpers

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let firstInitial = parts.first?.first.map(String.init) ?? "?"
        let lastInitial = parts.dropFirst().last?.first.map(String.init) ?? ""
        return (firstInitial + lastInitial).uppercased()
    }

    // MARK: - Demo seed

    public static let demoLeads: [LeadCard] = [
        LeadCard(
            contactName: "Camille Lefèvre",
            messagePreview: "Bonjour, j'aimerais discuter d'un site vitrine pour mon agence.",
            projectName: "AZ Construction"
        ),
        LeadCard(
            contactName: "Théo Marchand",
            messagePreview: "Pouvez-vous m'envoyer un devis pour 5 pages e-commerce ?",
            projectName: "IEF & Co"
        ),
        LeadCard(
            contactName: "Sara Benali",
            messagePreview: "Le formulaire de contact ne fonctionne plus depuis hier.",
            projectName: "Sconnect"
        ),
    ]
}
#endif
