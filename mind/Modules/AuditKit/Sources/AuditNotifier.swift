import Foundation
import UserNotifications

/// Local notification helper for audit completions. Mehdi can fire an
/// audit (manually, via Siri, or via the Action Button), background the
/// app, and get a banner when the result lands — no need to babysit the
/// 1–2 min run.
@MainActor
public final class AuditNotifier {
    public init() {}

    /// Idempotent: only triggers the system permission dialog the first
    /// time. Subsequent calls are no-ops if the user already granted or
    /// declined permission.
    public func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Posts an immediate local notification summarising the audit result.
    /// Silently no-ops if the user denied notifications.
    public func notifyAuditCompleted(report: AuditReport) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Audit terminé"
        content.subtitle = report.client.displayName
        content.body = formattedBody(for: report)
        content.sound = .default
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: "audit-\(report.client.id.uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    public func notifyAuditFailed(client: AuditClient, message: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Audit en échec"
        content.subtitle = client.displayName
        content.body = String(message.prefix(160))
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "audit-failed-\(client.id.uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private func formattedBody(for report: AuditReport) -> String {
        var parts: [String] = []
        parts.append("Score global \(report.scoring.overall)/100")
        parts.append(report.persona.label)
        if !report.quickWins.isEmpty {
            parts.append("\(report.quickWins.count) quick wins")
        }
        if !report.strategicBets.isEmpty {
            parts.append("\(report.strategicBets.count) paris stratégiques")
        }
        return parts.joined(separator: " • ")
    }
}
