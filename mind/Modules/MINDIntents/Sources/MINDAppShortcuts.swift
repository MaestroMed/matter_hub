import AppIntents

public struct MINDAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Add to \(.applicationName)",
                "Note in \(.applicationName)",
            ],
            shortTitle: "Capture",
            systemImageName: "drop.fill"
        )

        AppShortcut(
            intent: AskMindIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask my brain in \(.applicationName)",
                "What does \(.applicationName) know about",
            ],
            shortTitle: "Ask MIND",
            systemImageName: "bubble.left.and.bubble.right.fill"
        )

        AppShortcut(
            intent: RunAuditIntent(),
            phrases: [
                "Audit in \(.applicationName)",
                "Audit a client in \(.applicationName)",
                "Run an audit in \(.applicationName)",
            ],
            shortTitle: "Audit",
            systemImageName: "magnifyingglass"
        )
    }
}
