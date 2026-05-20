#if os(visionOS)
import SwiftUI

/// v1.0-alpha.19 — Vision Pro spatial cockpit entry point.
///
/// Three floating Liquid Glass panels in a `TabView`:
///   - `SpatialLeadsView`     — lead inbox surface
///   - `SpatialProjectsView`  — projects gallery surface
///   - `SpatialAuditTheater`  — audit theater entry / launch
///
/// Compiled only on visionOS — every other slice of MIND (iOS, iPad,
/// Mac Catalyst) treats this file as a no-op. The visionOS App slice
/// in `MINDApp.swift` mounts this view inside a `WindowGroup` with
/// `.windowStyle(.volumetric)`; the audit theater opens its own
/// `ImmersiveSpace` (see `SpatialAuditTheaterImmersive.swift`).
public struct SpatialRootView: View {

    @State private var selectedTab: SpatialTab = .leads

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            SpatialLeadsView()
                .tabItem {
                    Label(
                        String(localized: "spatial.tab.leads", defaultValue: "Leads"),
                        systemImage: "tray.fill"
                    )
                }
                .tag(SpatialTab.leads)

            SpatialProjectsView()
                .tabItem {
                    Label(
                        String(localized: "spatial.tab.projects", defaultValue: "Projets"),
                        systemImage: "square.stack.3d.up.fill"
                    )
                }
                .tag(SpatialTab.projects)

            SpatialAuditTheater()
                .tabItem {
                    Label(
                        String(localized: "spatial.tab.audit", defaultValue: "Audits"),
                        systemImage: "magnifyingglass"
                    )
                }
                .tag(SpatialTab.audit)
        }
        .onChange(of: selectedTab) { _, new in
            SpatialTelemetryBridge.shared.tabChanged(new)
        }
        .onAppear {
            SpatialTelemetryBridge.shared.appLaunched()
        }
    }
}

/// Stable enum so the tab selection round-trips through @State and
/// any future `SceneStorage` persistence without a string-typing leak.
public enum SpatialTab: String, Sendable, Hashable, CaseIterable {
    case leads
    case projects
    case audit
}
#endif
