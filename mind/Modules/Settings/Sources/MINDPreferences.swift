import Foundation
import Observation

/// User-tunable preferences, persisted in the App-Group-shared
/// UserDefaults so the widget extension and any future Watch / Mac
/// target read the same values. Observable so SwiftUI rebinds when a
/// toggle flips.
@MainActor
@Observable
public final class MINDPreferences {
    public static let shared = MINDPreferences()

    private let defaults: UserDefaults

    // MARK: - Backing storage keys

    private enum Key {
        static let focusDurationMinutes      = "mind.pref.focusDurationMinutes"
        static let auditNotificationsEnabled = "mind.pref.auditNotificationsEnabled"
        static let sentryDSN                 = "mind.pref.sentryDSN"
    }

    /// Shared UserDefaults the audit / focus modules can read without
    /// pulling in the Settings target (one-way string key match).
    public static let sharedSuiteName = "group.app.mind.ios"

    // MARK: - Tracked properties

    /// Default duration in minutes for a new Deep Focus session.
    /// Clamped to a sane range (5–180).
    public var focusDurationMinutes: Int {
        didSet {
            let clamped = max(5, min(180, focusDurationMinutes))
            if clamped != focusDurationMinutes {
                focusDurationMinutes = clamped
                return
            }
            defaults.set(clamped, forKey: Key.focusDurationMinutes)
        }
    }

    /// When false, AuditNotifier silences both the success and failure
    /// banners but the audit still runs and persists.
    public var auditNotificationsEnabled: Bool {
        didSet {
            defaults.set(auditNotificationsEnabled, forKey: Key.auditNotificationsEnabled)
        }
    }

    /// Sentry DSN for crash + error reporting. Empty / nil → Sentry is
    /// not initialised. Stored in UserDefaults (not Keychain) because
    /// the DSN is not a secret per Sentry's own threat model — it
    /// identifies the project, doesn't authenticate writes (Sentry
    /// rate-limits abuse at the ingest side).
    public var sentryDSN: String {
        didSet {
            let trimmed = sentryDSN.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Key.sentryDSN)
        }
    }

    // MARK: - Init

    public init(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        self.defaults = suite

        let storedFocus = suite.integer(forKey: Key.focusDurationMinutes)
        self.focusDurationMinutes = storedFocus > 0 ? storedFocus : 25  // pomodoro default

        // .object(forKey:) lets us distinguish "never set" (nil) from
        // "explicitly disabled" (false). Default to opt-in.
        let storedNotifs = suite.object(forKey: Key.auditNotificationsEnabled) as? Bool
        self.auditNotificationsEnabled = storedNotifs ?? true

        self.sentryDSN = suite.string(forKey: Key.sentryDSN) ?? ""
    }

    // MARK: - Static convenience for non-Observable consumers

    /// Lets non-UI modules (AuditNotifier, FocusController invocations
    /// outside HomeView) read the current value without holding a
    /// reference to the @MainActor instance.
    public static func currentAuditNotificationsEnabled(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> Bool {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        return suite.object(forKey: Key.auditNotificationsEnabled) as? Bool ?? true
    }

    public static func currentFocusDurationMinutes(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> Int {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let stored = suite.integer(forKey: Key.focusDurationMinutes)
        return stored > 0 ? stored : 25
    }

    public static func currentSentryDSN(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> String? {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let value = suite.string(forKey: Key.sentryDSN)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }
}

public extension MINDPreferences {
    /// Preset Pomodoro-style durations exposed by the Settings picker.
    static let focusDurationPresets: [Int] = [15, 25, 45, 60, 90]
}
