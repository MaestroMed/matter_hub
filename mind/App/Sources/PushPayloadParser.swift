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
