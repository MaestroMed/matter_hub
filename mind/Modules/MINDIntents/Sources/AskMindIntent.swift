import AppIntents
import Foundation
import GraphCore
import Intelligence
import SwiftData

public struct AskMindIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask MIND"
    public static let description = IntentDescription(
        "Ask your second brain anything. Uses Claude with your graph as context."
    )
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Question", description: "What do you want to ask?", requestValueDialog: "What do you want to ask MIND?")
    public var question: String

    public init() {}

    public init(question: String) {
        self.question = question
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(GraphCore.sharedContainer)
        let descriptor = FetchDescriptor<Node>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let recent = Array((try? context.fetch(descriptor))?.prefix(30) ?? [])

        let cloud = CloudIntelligence()
        do {
            let answer = try await cloud.complete(prompt: question, contextNodes: recent)
            return .result(dialog: IntentDialog(stringLiteral: answer))
        } catch {
            return .result(dialog: "I couldn't reach Claude: \(error.localizedDescription)")
        }
    }
}
