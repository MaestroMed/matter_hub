import AppIntents
import Foundation
import AuditKit
import GraphCore
import SwiftData

/// "Hey Siri, audit Stripe" → MIND runs a full digital audit, persists
/// the report into the graph, and replies with the headline score.
public struct RunAuditIntent: AppIntent {
    public static let title: LocalizedStringResource = "Audit a client"
    public static let description = IntentDescription(
        "Lance un audit digital complet d'un prospect et sauvegarde le rapport dans MIND."
    )
    public static let openAppWhenRun: Bool = false

    @Parameter(
        title: "URL du site",
        description: "L'URL du site à auditer, ex. stripe.com",
        requestValueDialog: "Quelle URL veux-tu auditer ?"
    )
    public var urlString: String

    public init() {}

    public init(urlString: String) {
        self.urlString = urlString
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Je n'ai pas d'URL à auditer.")
        }
        let candidate = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        guard let resolvedURL = URL(string: candidate),
              resolvedURL.host(percentEncoded: false) != nil else {
            return .result(dialog: "Cette URL ne semble pas valide.")
        }

        let client = AuditClient(url: resolvedURL)

        // A dedicated controller instance so the intent doesn't fight with
        // the in-app shared controller if Mehdi launched a manual audit at
        // the same time from HomeView.
        let controller = AuditController()
        controller.run(for: client)

        // App Intents can run for a couple of minutes when invoked from
        // Shortcuts or the Action Button; iOS gives us up to ~30s in Siri
        // and longer in the Shortcuts app. We poll the controller until
        // it leaves the running state.
        while controller.isRunning {
            try await Task.sleep(for: .seconds(2))
        }

        guard let report = controller.report else {
            let reason = controller.error ?? "raison inconnue"
            return .result(dialog: IntentDialog(stringLiteral: "Audit en échec : \(reason)"))
        }

        persist(report: report)

        let dialog = "Audit \(report.client.displayName) terminé. Score global \(report.scoring.overall) sur 100. Le rapport est dans ton graphe."
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }

    @MainActor
    private func persist(report: AuditReport) {
        let context = ModelContext(GraphCore.sharedContainer)

        let clientNode = Node(
            kind: .client,
            title: report.client.displayName,
            content: report.client.url.absoluteString,
            tags: [report.persona.rawValue],
            sourceURL: report.client.url.absoluteString
        )
        context.insert(clientNode)
        clientNode.refreshEmbedding()

        let auditNode = Node(
            kind: .audit,
            title: "Audit — \(report.client.displayName)",
            content: report.synthesis,
            tags: ["audit", report.persona.rawValue, "score-\(report.scoring.overall)"],
            sourceURL: report.client.url.absoluteString
        )
        context.insert(auditNode)
        auditNode.refreshEmbedding()

        let edge = Edge(kind: .derivedFrom, from: auditNode, to: clientNode)
        context.insert(edge)

        try? context.save()
    }
}
