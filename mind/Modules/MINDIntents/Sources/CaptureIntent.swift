import AppIntents
import Foundation
import GraphCore
import SwiftData

public struct CaptureIntent: AppIntent {
    public static let title: LocalizedStringResource = "Capture a thought"
    public static let description = IntentDescription(
        "Save a quick note, idea, or reminder into MIND."
    )
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Thought", description: "What's on your mind?", requestValueDialog: "What do you want to capture?")
    public var text: String

    public init() {}

    public init(text: String) {
        self.text = text
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(GraphCore.sharedContainer)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        let node = Node(
            kind: .capture,
            title: String(firstLine.prefix(80)),
            content: trimmed
        )
        context.insert(node)
        try context.save()

        return .result(dialog: "Captured. Stored in your second brain.")
    }
}
