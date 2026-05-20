import UIKit
import UserNotifications
import GraphCore  // for MINDTelemetry

/// v1.0-alpha.14 — Wraps the APNs registration flow so MINDApp's
/// AppDelegate adapter + Settings toggle stay tiny. The actual token
/// callback lands in `MINDPushDelegate.application(_:didRegister…)` —
/// this enum owns the permission prompt, the registration kick-off,
/// and the persisted hex-token UserDefaults read/write.
@MainActor
public enum PushRegistration {
    private static let tokenKey = "mind.apns.deviceToken"

    /// Asks the user for permission then registers with APNs. Returns
    /// `true` if permission was granted (registration kicks off
    /// asynchronously, the AppDelegate later receives the token).
    @discardableResult
    public static func registerForPushNotifications() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            if granted {
                MINDTelemetry.info("apns.permission.granted")
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                MINDTelemetry.warning("apns.permission.denied")
            }
            return granted
        } catch {
            MINDTelemetry.error(
                "apns.permission.error",
                data: ["error": String(describing: error)]
            )
            return false
        }
    }

    /// Persists the device token as hex in UserDefaults so the Settings
    /// row can show it (truncated) and copy it. Called from
    /// MINDPushDelegate.
    @discardableResult
    public static func handleDeviceToken(_ deviceToken: Data) -> String {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        return hex
    }

    /// Returns the persisted hex token, or nil if registration hasn't
    /// completed yet.
    public static var currentDeviceToken: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }
}
