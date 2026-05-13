import SwiftUI
import SwiftData
import DesignSystem
import GraphCore
import Intelligence

@main
struct MINDApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(.light)
        }
        .modelContainer(GraphCore.sharedContainer)
    }
}

@Observable
@MainActor
final class AppModel {
    var intelligence = IntelligenceService()
    var graph = GraphService()
}
