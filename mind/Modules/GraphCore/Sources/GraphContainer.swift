import Foundation
import SwiftData

public enum GraphCore {
    public static let appGroupIdentifier = "group.app.mind.ios"
    public static let cloudKitContainerIdentifier = "iCloud.app.mind.ios"

    // v1.0-alpha.2 — Cockpit Studio data spine. `Project`, `Lead`,
    // and `Deliverable` land alongside the legacy `Node` / `Edge` /
    // `FocusSessionRecord` rows: the CloudKit mirror keeps the old
    // schema regardless of what the UI surfaces, so the pivot stays
    // additive at the data layer. Wave C routes HomeView / Projects /
    // Pipeline onto the new models without dropping the legacy ones.
    public static let schema = Schema([
        Node.self,
        Edge.self,
        FocusSessionRecord.self,
        Project.self,
        Lead.self,
        Deliverable.self,
        // v1.1.0 — Lighthouse trend snapshots. One row per Lighthouse
        // probe (manual + scheduled), filtered by `projectID` from
        // ProjectDetailSheet's sparkline grid. Additive: existing
        // CloudKit zones absorb the new entity on first sync.
        LighthouseSnapshot.self,
    ])

    @MainActor
    public static let sharedContainer: ModelContainer = makeContainer()

    /// True when the host runtime can actually serve the App Group container
    /// (signed app + matching provisioning entitlement). False on unsigned
    /// Simulators, where asking SwiftData for a groupContainer crashes
    /// before `try?` ever sees the failure.
    public static var hasAppGroup: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) != nil
    }

    @MainActor
    private static func makeContainer() -> ModelContainer {
        // Try the richest configuration first and fall back step by step:
        //   1. App Group + CloudKit  → production signed device with iCloud sign-in
        //   2. App Group only        → production without iCloud sign-in
        //   3. CloudKit only         → signed but no App Group entitlement
        //   4. Local                 → unsigned Simulator dev loop
        // App-Group-bearing configurations are only attempted when
        // `hasAppGroup` is true; otherwise the SwiftData initializer
        // crashes outside any `try?` boundary on iOS 26.
        var attempts: [ModelConfiguration] = []
        if hasAppGroup {
            attempts.append(ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .identifier(appGroupIdentifier),
                cloudKitDatabase: .private(cloudKitContainerIdentifier)
            ))
            attempts.append(ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .identifier(appGroupIdentifier),
                cloudKitDatabase: .none
            ))
        }
        attempts.append(ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        ))
        attempts.append(ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        ))

        for configuration in attempts {
            if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
                return container
            }
        }
        fatalError("Failed to create ModelContainer for MIND graph")
    }
}
