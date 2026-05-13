import SwiftUI
import SwiftData
import DesignSystem
import GraphCore

@main
struct MINDApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
        .modelContainer(GraphCore.sharedContainer)
    }
}
