import Foundation

/// v1.0-alpha.14 — Pure mirror of the `NotificationService` parsing
/// + truncation logic. The NSE lives in its own extension target so
/// the unit-test bundle can't `@testable import` it directly; this
/// helper ships in the App target with the same name + same shape so
/// both surfaces (the NSE banner decoration and the in-app
/// MINDPushDelegate tap routing) share one set of locked tests. Keep
/// this file byte-for-byte in step with
/// `mind/PushExtension/Sources/NotificationService.swift` — any
/// behaviour drift surfaces as a divergent test failure.
public enum PushPayloadParser {

    /// Projection of the relevant fields from a `userInfo` dict.
    public struct LeadPayload: Equatable {
        public var contactName: String
        public var projectName: String
        public var projectID: String
        public var messagePreview: String

        public init(
            contactName: String,
            projectName: String,
            projectID: String,
            messagePreview: String
        ) {
            self.contactName = contactName
            self.projectName = projectName
            self.projectID = projectID
            self.messagePreview = messagePreview
        }
    }

    /// v1.1.0 — Projection of the Vercel push payload shipped under
    /// `userInfo["vercel"]`. The decoder is intentionally lenient —
    /// missing keys collapse to empty strings rather than failing the
    /// parse, so the NSE always lands a sensible banner.
    public struct VercelPayload: Equatable {
        public var type: String
        public var projectID: String
        public var deploymentID: String
        public var url: String
        public var commitSHA: String
        public var commitMessage: String
        public var authorEmail: String
        public var occurredAt: String

        public init(
            type: String,
            projectID: String,
            deploymentID: String,
            url: String,
            commitSHA: String,
            commitMessage: String,
            authorEmail: String,
            occurredAt: String
        ) {
            self.type = type
            self.projectID = projectID
            self.deploymentID = deploymentID
            self.url = url
            self.commitSHA = commitSHA
            self.commitMessage = commitMessage
            self.authorEmail = authorEmail
            self.occurredAt = occurredAt
        }

        /// Convenience: short-form commit SHA used by the NSE body
        /// and the in-app Lock Screen / banner formatter.
        public var commitSHAShort: String {
            String(commitSHA.prefix(7))
        }

        /// FR human label for the event type. Mirrors the Worker side
        /// and the NSE so every surface reads the same vocabulary.
        public var statusLabel: String {
            PushPayloadParser.vercelStatusLabel(type)
        }
    }

    /// Extracts the LeadPayload from a `userInfo` dictionary. Returns
    /// nil only when no `lead` (or nested `aps.payload`) dict is
    /// present — every other branch falls back to sensible defaults so
    /// the NSE always lands a reasonable banner.
    public static func parse(userInfo: [AnyHashable: Any]) -> LeadPayload? {
        let leadDict = (userInfo["lead"] as? [String: Any])
            ?? ((userInfo["aps"] as? [String: Any])?["payload"] as? [String: Any])
        guard let lead = leadDict else { return nil }

        let contactName = trim(lead["contactName"] as? String, fallback: "Nouveau lead")
        let projectName = trim(lead["projectName"] as? String, fallback: "")
        let projectID = trim(lead["projectID"] as? String, fallback: "unknown")
        // Prefer messagePreview, but fall back to `message` for any
        // older worker version that emits the full body.
        let messageSource = (lead["messagePreview"] as? String)
            ?? (lead["message"] as? String)
            ?? ""
        let messagePreview = messageSource.trimmingCharacters(in: .whitespacesAndNewlines)
        return LeadPayload(
            contactName: contactName,
            projectName: projectName,
            projectID: projectID,
            messagePreview: messagePreview
        )
    }

    /// v1.1.0 — Extracts the VercelPayload from a `userInfo` dict.
    /// Returns nil when the `vercel` sub-dict is missing or carries
    /// no `projectId`. The decoder accepts both `projectId`
    /// (Worker / Vercel canonical) and `projectID` (defensive against
    /// a hand-typed test fixture using Swift-style casing).
    public static func parseVercel(userInfo: [AnyHashable: Any]) -> VercelPayload? {
        guard let vercel = userInfo["vercel"] as? [String: Any] else { return nil }
        let projectIDRaw = (vercel["projectId"] as? String) ?? (vercel["projectID"] as? String)
        let projectID = trim(projectIDRaw, fallback: "")
        guard !projectID.isEmpty else { return nil }
        let deploymentRaw = (vercel["deploymentId"] as? String) ?? (vercel["deploymentID"] as? String)
        return VercelPayload(
            type: trim(vercel["type"] as? String, fallback: ""),
            projectID: projectID,
            deploymentID: trim(deploymentRaw, fallback: ""),
            url: trim(vercel["url"] as? String, fallback: ""),
            commitSHA: trim(vercel["commitSHA"] as? String, fallback: ""),
            commitMessage: trim(vercel["commitMessage"] as? String, fallback: ""),
            authorEmail: trim(vercel["authorEmail"] as? String, fallback: ""),
            occurredAt: trim(vercel["occurredAt"] as? String, fallback: "")
        )
    }

    /// FR labels per Vercel event type. Mirrors the Worker-side
    /// `vercelStatusLabel(type:)` so any divergence surfaces in the
    /// `VercelWebhookPayloadTests` suite.
    public static func vercelStatusLabel(_ type: String) -> String {
        switch type {
        case "deployment.created", "deployment-created", "deployment":
            return "Déploiement démarré"
        case "deployment.succeeded",
             "deployment-succeeded",
             "deployment-ready",
             "deployment.ready":
            return "✓ Déploiement réussi"
        case "deployment.error", "deployment-error":
            return "❌ Build échoué"
        case "deployment.canceled", "deployment-canceled":
            return "Annulé"
        default:
            return "Évènement Vercel"
        }
    }

    /// Whitespace-collapsing extraction helper. Returns `fallback`
    /// when the input is nil, empty, or whitespace-only.
    private static func trim(_ value: String?, fallback: String) -> String {
        guard let raw = value else { return fallback }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// Truncates `text` at the last whitespace before `limit` and
    /// appends `…`. Empty input returns the empty string verbatim so
    /// the body field stays valid for UNNotificationContent.
    public static func truncate(_ text: String, to limit: Int) -> String {
        guard !text.isEmpty else { return text }
        if text.count <= limit { return text }
        let prefix = text.prefix(limit)
        // Walk back to the last whitespace so we don't cut a word in
        // half. Falls back to a hard cut if no whitespace was seen.
        if let lastSpace = prefix.lastIndex(where: { $0.isWhitespace }) {
            return String(prefix[..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }
}
