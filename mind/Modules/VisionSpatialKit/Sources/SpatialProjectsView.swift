#if os(visionOS)
import SwiftUI

/// v1.0-alpha.19 — Projects gallery panel for the visionOS spatial
/// cockpit.
///
/// Renders the cockpit's portfolio as a 3 × 2 grid of floating
/// Liquid Glass tiles. Each tile is a hover-target with a `lift`
/// hover effect (RealityKit scales the entity 1.05× and lifts +5 mm
/// when the user's gaze settles). Tapping a tile fires telemetry; the
/// Wave B detail surface is deferred.
///
/// Like `SpatialLeadsView`, the data is injected at the call site so
/// this module doesn't link `GraphCore`. A 6-project demo seed lands
/// the surface renderable on first launch.
public struct SpatialProjectsView: View {

    public struct ProjectTile: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let name: String
        public let host: String
        public let mrrEUR: Int
        public let stage: String

        public init(
            id: UUID = UUID(),
            name: String,
            host: String,
            mrrEUR: Int,
            stage: String
        ) {
            self.id = id
            self.name = name
            self.host = host
            self.mrrEUR = mrrEUR
            self.stage = stage
        }
    }

    private let projects: [ProjectTile]

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 24),
        count: 3
    )

    public init(projects: [ProjectTile] = SpatialProjectsView.demoProjects) {
        self.projects = projects
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if projects.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(projects) { project in
                            tile(for: project)
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
            Text(String(localized: "spatial.tab.projects", defaultValue: "Projets"))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(
                String(
                    localized: "spatial.projects.subtitle",
                    defaultValue: "Galerie flottante du portfolio"
                )
            )
            .font(.system(.title3, design: .rounded, weight: .regular))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text(
                String(
                    localized: "spatial.empty.projects",
                    defaultValue: "Aucun projet dans le portfolio."
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

    private func tile(for project: ProjectTile) -> some View {
        Button {
            SpatialTelemetryBridge.shared.projectTapped(id: project.id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "globe")
                        .font(.system(.title2, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    Spacer()
                    Text(project.stage)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            Capsule(style: .continuous)
                                .fill(.thinMaterial)
                        }
                }

                Text(project.name)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .lineLimit(1)

                Text(project.host)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack {
                    Text(formattedMRR(project.mrrEUR))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .glassBackgroundEffect()
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private func formattedMRR(_ amount: Int) -> String {
        guard amount > 0 else { return "—" }
        return "\(amount) €/mo"
    }

    // MARK: - Demo seed

    public static let demoProjects: [ProjectTile] = [
        ProjectTile(name: "AZ Construction", host: "azconstruction.fr", mrrEUR: 350, stage: "Actif"),
        ProjectTile(name: "IEF & Co", host: "iefandco.fr", mrrEUR: 290, stage: "Actif"),
        ProjectTile(name: "Sconnect", host: "sconnect.fr", mrrEUR: 190, stage: "Maintenance"),
        ProjectTile(name: "Verdenomia", host: "verdenomia.fr", mrrEUR: 0, stage: "Discovery"),
        ProjectTile(name: "MonJoel", host: "monjoel.fr", mrrEUR: 0, stage: "Discovery"),
        ProjectTile(name: "Numelite", host: "numelite.fr", mrrEUR: 0, stage: "Interne"),
    ]
}
#endif
