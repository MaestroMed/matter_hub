import UserNotifications

/// v1.0-alpha.14 — APNs Notification Service Extension that decorates
/// every lead push payload before iOS displays the banner. The
/// Cloudflare Worker (mind/tools/cloudflare-worker) builds a minimal
/// payload that includes `{ aps: { alert: { title, body } }, lead: {
/// id, projectID, contactName, projectName, formType, messagePreview
/// } }`. This NSE upgrades the alert with:
///
///   - title  = `<contactName> · <projectName>`
///   - body   = first 120 chars of message (truncated with …)
///   - threadIdentifier = `lead.<projectID>` so iOS groups leads per
///     project in Notification Center.
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

        // Try the structured payload first. Worker emits `lead` as a
        // top-level userInfo dict, but we also accept it nested under
        // `aps.payload` as a backward-compatibility cushion.
        let parsed = Self.parse(userInfo: request.content.userInfo)
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
