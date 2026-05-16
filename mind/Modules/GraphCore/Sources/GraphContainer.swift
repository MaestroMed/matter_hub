import Foundation
import SwiftData

public enum GraphCore {
    public static let schema = Schema([Node.self, Edge.self])

    @MainActor
    public static let sharedContainer: ModelContainer = {
        // CloudKit-backed private DB. Requires a signed app with iCloud entitlements
        // (real device with provisioning profile, or Simulator with a signed-in Apple ID
        // and proper signing). Falls back to local-only storage otherwise so the app
        // still runs on unsigned Simulators and first-launch before iCloud sign-in.
        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.app.mind.ios")
        )
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
            return container
        }
        let localConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [localConfiguration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
