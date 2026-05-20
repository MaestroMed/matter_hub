import UserNotifications

/// v1.0-alpha.14 — APNs Notification Service Extension that decorates
/// every push payload before iOS displays the banner. The Cloudflare
/// Worker (mind/tools/cloudflare-worker) emits two payload shapes:
///
/// 1. Lead pushes: `{ aps: { alert: { title, body } }, lead: { id,
///    projectID, contactName, projectName, formType, messagePreview } }`
/// 2. v1.1.0 — Vercel deployment pushes: `{ aps: { alert, sound,
///    "thread-id" }, vercel: { type, projectId, deploymentId, url,
///    commitSHA, commitMessage, authorEmail, occurredAt } }`
///
/// This NSE upgrades each banner with:
///
///   - Lead → `title = <contactName> · <projectName>`,
///     `body = first 120 chars of message`,
///     `threadIdentifier = lead.<projectID>`.
///   - Vercel → `title = MIND · <name>`,
///     `body = <FR status label> · <commit-sha-7> <commit-message>`,
///     `threadIdentifier = vercel.<projectId>`.
///
/// Soft-fails to passthrough when the payload is malformed — better
/// to show the raw push than to silently drop it.
final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let best = bestAttempt else {
            contentHandler(request.content)
            return
        }

        let userInfo = request.content.userInfo

        // v1.1.0 — Vercel payload takes precedence so a project that
        // ships both lead + deploy events under the same APNs topic
        // still surfaces a deploy banner without colliding with the
        // lead path.
        if let vercel = Self.parseVercel(userInfo: userInfo) {
            best.title = vercel.title
            best.body = Self.truncate(vercel.body, to: 120)
            best.threadIdentifier = "vercel.\(vercel.projectID)"
            best.sound = best.sound ?? .default
            contentHandler(best)
            return
        }

        // Try the structured payload first. Worker emits `lead` as a
        // top-level userInfo dict, but we also accept it nested under
        // `aps.payload` as a backward-compatibility cushion.
        let parsed = Self.parse(userInfo: userInfo)
        guard let lead = parsed else {
            // No structured payload — pass through the raw alert. The
            // Worker's fallback title (`Nouveau lead`) is already
            // human-readable so the user isn't lost.
            contentHandler(best)
            return
        }

        best.title = lead.projectName.isEmpty
            ? lead.contactName
            : "\(lead.contactName) · \(lead.projectName)"
        best.body = lead.messagePreview.isEmpty
            ? "Nouveau lead reçu."
            : Self.truncate(lead.messagePreview, to: 120)
        best.threadIdentifier = "lead.\(lead.projectID)"
        best.sound = best.sound ?? .default

        contentHandler(best)
    }

    override func serviceExtensionTimeWillExpire() {
        // 30s deadline expiring — ship whatever we have rather than
        // letting the system suppress the notification entirely.
        if let contentHandler, let bestAttempt {
            contentHandler(bestAttempt)
        }
    }

    /// v1.0-alpha.14 — Pure projection of the relevant fields from a
    /// `userInfo` dict. Isolated as a value type + `static parse(...)`
    /// helper so `PushNotificationPayloadTests` can exercise every
    /// branch without standing up `UNUserNotificationCenter`.
    struct LeadPayload: Equatable {
        var contactName: String
        var projectName: String
        var projectID: String
        var messagePreview: String
    }

    /// Extracts the LeadPayload from a `userInfo` dictionary. Returns
    /// nil only when no `lead` (or nested `aps.payload`) dict is
    /// present — every other branch falls back to sensible defaults so
    /// the NSE always lands a reasonable banner.
    static func parse(userInfo: [AnyHashable: Any]) -> LeadPayload? {
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

    /// v1.1.0 — Pure projection of the Vercel push payload. Mirrors
    /// the Worker side's `VercelPushPayload` byte-for-byte; the App
    /// target ships a structurally identical helper in
    /// `PushPayloadParser` so the unit tests can exercise the same
    /// logic without `@testable import`-ing the NSE.
    struct VercelDecoration: Equatable {
        var title: String
        var body: String
        var projectID: String
    }

    /// Extracts a `VercelDecoration` from a `userInfo` dict shipped by
    /// the Worker's `/v1/vercel-webhook` handler. Returns nil when the
    /// `vercel` sub-dict is missing or carries no `projectId`.
    static func parseVercel(userInfo: [AnyHashable: Any]) -> VercelDecoration? {
        guard let vercel = userInfo["vercel"] as? [String: Any] else { return nil }
        let projectIDRaw = (vercel["projectId"] as? String) ?? (vercel["projectID"] as? String)
        let projectID = trim(projectIDRaw, fallback: "unknown")
        guard projectID != "unknown" else { return nil }

        let projectName = (userInfo["aps"] as? [String: Any]).flatMap { aps -> String? in
            (aps["alert"] as? [String: Any])?["title"] as? String
        }
        let titleFallback = projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (titleFallback?.isEmpty == false) ? titleFallback! : "MIND · Vercel"

        let typeRaw = (vercel["type"] as? String) ?? ""
        let label = vercelStatusLabel(typeRaw)
        let shaShort: String = {
            guard let sha = vercel["commitSHA"] as? String else { return "" }
            return String(sha.prefix(7))
        }()
        let message = (vercel["commitMessage"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parts: [String] = [label]
        if !shaShort.isEmpty { parts.append(shaShort) }
        if !message.isEmpty { parts.append(message) }
        let body = parts.joined(separator: " · ")
        return VercelDecoration(title: title, body: body, projectID: projectID)
    }

    /// FR labels per Vercel event type. Mirrors the Worker-side
    /// `vercelStatusLabel(type:)` so any divergence surfaces in the
    /// PushPayloadParser test suite.
    static func vercelStatusLabel(_ type: String) -> String {
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
    static func truncate(_ text: String, to limit: Int) -> String {
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
