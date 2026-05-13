import Foundation
import SwiftData

public enum GraphCore {
    public static let schema = Schema([Node.self, Edge.self])

    @MainActor
    public static let sharedContainer: ModelContainer = {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.app.mind.ios")
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
