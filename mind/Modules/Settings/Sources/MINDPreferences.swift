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
        static let healthInsightsEnabled     = "mind.pref.healthInsightsEnabled"
        static let remindersSyncEnabled      = "mind.pref.remindersSyncEnabled"
        static let notionDatabaseID          = "mind.pref.notionDatabaseID"
        static let linearDefaultTeamID       = "mind.pref.linearDefaultTeamID"
        // v0.17 — Daily morning brief (local push at user-configurable
        // wake-up hour). `dailyBriefEnabled` gates the schedule + the
        // HomeView card visibility window; `dailyBriefHour` is 0..23
        // in the user's local timezone (default 7 = 7am).
        static let dailyBriefEnabled         = "mind.pref.dailyBriefEnabled"
        static let dailyBriefHour            = "mind.pref.dailyBriefHour"
        // v0.31 — Stripe Invoice Generator. The user pastes a Stripe
        // Payment Link prefix into Settings once (e.g.
        // `https://buy.stripe.com/3cs5ll…`) and the InvoiceKit
        // builder appends the per-invoice amount on the fly. The
        // four consultant identity fields fold into every PDF the
        // renderer emits — SIRET + IBAN + VAT number show up in the
        // legal footer, address sits in the header block. All four
        // optional; empty defaults render a graceful fallback (e.g.
        // "SIRET : en cours d'immatriculation").
        static let stripePaymentLinkBase     = "mind.pref.stripePaymentLinkBase"
        static let consultantSIRET           = "mind.pref.consultantSIRET"
        static let consultantIBAN            = "mind.pref.consultantIBAN"
        static let consultantVATNumber       = "mind.pref.consultantVATNumber"
        static let consultantAddress         = "mind.pref.consultantAddress"
        // v1.0-alpha.18 — ElevenLabs voice clone. The user clones
        // their voice once via the VoiceCloneSetupSheet — we persist
        // the returned `voice_id` here so every audit can synthesize
        // its pitch in that voice without re-uploading the sample.
        // The display name lets Settings render "Voix : Mehdi Nafaa
        // ✓" without an extra ElevenLabs API call on every launch.
        static let elevenLabsVoiceID         = "mind.pref.elevenLabsVoiceID"
        static let elevenLabsVoiceName       = "mind.pref.elevenLabsVoiceName"
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

    /// HealthKit weekly insights opt-in (v0.9). False by default so the
    /// home card stays hidden and HealthKit is never queried until the
    /// user explicitly enables it from Settings. Flipping this on does
    /// NOT prompt for permission — Settings calls
    /// `HealthReader.requestAccess()` separately so the sequence stays
    /// "user taps Settings → user taps toggle → permission sheet appears".
    public var healthInsightsEnabled: Bool {
        didSet {
            defaults.set(healthInsightsEnabled, forKey: Key.healthInsightsEnabled)
        }
    }

    /// Reminders bidirectional sync opt-in (v0.10). False by default so
    /// EventKit is never asked for reminders permission and no mirror
    /// runs until the user explicitly enables it. Same toggle-then-
    /// permission-sheet sequence as the health insights opt-in.
    public var remindersSyncEnabled: Bool {
        didSet {
            defaults.set(remindersSyncEnabled, forKey: Key.remindersSyncEnabled)
        }
    }

    /// Notion database ID where MIND posts audit pages (v0.11).
    /// Persisted in UserDefaults (not Keychain) because the database ID
    /// is not a secret — it's a public identifier visible in the URL
    /// of any Notion database. The integration token *is* a secret and
    /// lives in `NotionTokenStore` (Keychain). Empty string = "not
    /// configured", and the AuditSheet "Sync to Notion" button stays
    /// hidden until both this and the token are set.
    public var notionDatabaseID: String {
        didSet {
            let trimmed = notionDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Key.notionDatabaseID)
        }
    }

    /// Linear team UUID where MIND creates QuickWin issues (v0.12).
    /// Same UserDefaults rationale as `notionDatabaseID` — the team
    /// id is not a secret. The personal API key *is* and lives in
    /// `LinearTokenStore` (Keychain). Empty string = "not configured",
    /// and the AuditSheet "Push to Linear" buttons stay hidden until
    /// both this and the token are set.
    public var linearDefaultTeamID: String {
        didSet {
            let trimmed = linearDefaultTeamID.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Key.linearDefaultTeamID)
        }
    }

    /// Daily morning brief opt-in (v0.17). False by default so the
    /// notification permission is never requested and no local
    /// notification is scheduled until the user explicitly enables it
    /// from Settings → Préférences → "Réveil matinal". Toggling on
    /// triggers the `UNUserNotificationCenter.requestAuthorization`
    /// prompt and schedules a daily `UNCalendarNotificationTrigger`
    /// at the `dailyBriefHour` wall-clock time. The HomeView card also
    /// uses this gate: when off, the morning brief card stays hidden
    /// even during the visibility window.
    public var dailyBriefEnabled: Bool {
        didSet {
            defaults.set(dailyBriefEnabled, forKey: Key.dailyBriefEnabled)
        }
    }

    /// Hour (0..23, local timezone) at which the daily morning brief
    /// notification fires (v0.17). Defaults to 7 — early enough that
    /// it lands before most users start their workday but not so early
    /// that it wakes them up. Clamped to the valid range so a bad
    /// UserDefaults edit can't break the scheduler.
    public var dailyBriefHour: Int {
        didSet {
            let clamped = max(0, min(23, dailyBriefHour))
            if clamped != dailyBriefHour {
                dailyBriefHour = clamped
                return
            }
            defaults.set(clamped, forKey: Key.dailyBriefHour)
        }
    }

    /// v0.31 — Stripe Payment Link prefix the user pasted into
    /// Settings once. Empty default = invoicing falls back to a
    /// "no link configured" PDF (Stripe block hidden, IBAN-only).
    /// The InvoiceKit `InvoiceStripeLinkBuilder` appends the
    /// `prefilled_amount=<cents>` query parameter per invoice.
    public var stripePaymentLinkBase: String {
        didSet {
            let trimmed = stripePaymentLinkBase.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Key.stripePaymentLinkBase)
        }
    }

    /// v0.31 — French SIRET number (14 digits) folded into every
    /// generated invoice's legal footer. Empty default = the PDF
    /// renders "SIRET : en cours d'immatriculation" so a freshly-
    /// installed consultant ships a legal invoice out of the box.
    public var consultantSIRET: String {
        didSet {
            let trimmed = consultantSIRET.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Key.consultantSIRET)
        }
    }

    /// v0.31 — IBAN for wire-transfer alternative to the Stripe
    /// Payment Link. Renders in the PDF "PAIEMENT" section when
    /// non-empty.
    public var consultantIBAN: String {
        didSet {
            let trimmed = consultantIBAN.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Key.consultantIBAN)
        }
    }

    /// v0.31 — French/EU VAT number (e.g. "FR12345678910"). Empty
    /// + `vatPercent == 0` → PDF appends the art. 293 B mention
    /// (auto-entrepreneur exemption). Non-empty → renders the
    /// VAT line in the legal footer.
    public var consultantVATNumber: String {
        didSet {
            let trimmed = consultantVATNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Key.consultantVATNumber)
        }
    }

    /// v0.31 — Multi-line postal address rendered under the
    /// consultant name in the invoice header. Newlines are
    /// preserved on render.
    public var consultantAddress: String {
        didSet {
            // Don't trim — multi-line addresses keep their final
            // newline conventions. Only strip trailing whitespace.
            let trimmed = consultantAddress
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Key.consultantAddress)
        }
    }

    /// v1.0-alpha.18 — Cloned voice ID returned by the ElevenLabs
    /// `POST /v1/voices/add` round-trip the first time the user runs
    /// the VoiceCloneSetupSheet. Empty default = "no voice cloned yet"
    /// and the AuditSheet pitch audio section surfaces a hint card
    /// pointing the user back to Settings.
    public var elevenLabsVoiceID: String {
        didSet {
            let trimmed = elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Key.elevenLabsVoiceID)
        }
    }

    /// v1.0-alpha.18 — Display name of the cloned voice (e.g. "Mehdi
    /// Nafaa") so the Settings row + status badge render without
    /// re-querying the ElevenLabs `/v1/voices` endpoint on every
    /// launch.
    public var elevenLabsVoiceName: String {
        didSet {
            let trimmed = elevenLabsVoiceName.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Key.elevenLabsVoiceName)
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

        // HealthKit is opt-out by default — Apple's HIG explicitly asks
        // health-data apps to surface a deliberate toggle rather than
        // prompt at first launch. Nil → false, false → false, true → true.
        let storedHealth = suite.object(forKey: Key.healthInsightsEnabled) as? Bool
        self.healthInsightsEnabled = storedHealth ?? false

        // Same opt-in contract for Reminders sync — EventKit is never
        // queried until the user explicitly flips the toggle.
        let storedReminders = suite.object(forKey: Key.remindersSyncEnabled) as? Bool
        self.remindersSyncEnabled = storedReminders ?? false

        // v0.11 — Notion database ID. Empty default = not configured;
        // the AuditSheet "Sync to Notion" CTA checks for non-empty
        // before showing the button.
        self.notionDatabaseID = suite.string(forKey: Key.notionDatabaseID) ?? ""

        // v0.12 — Linear default team UUID. Empty default = not
        // configured; the AuditSheet "Push to Linear" CTA + the bulk
        // export button both check for non-empty before rendering.
        self.linearDefaultTeamID = suite.string(forKey: Key.linearDefaultTeamID) ?? ""

        // v0.17 — Daily morning brief. Off by default (no permission
        // sheet at first launch), 7am as the default wake-up hour.
        let storedDailyBrief = suite.object(forKey: Key.dailyBriefEnabled) as? Bool
        self.dailyBriefEnabled = storedDailyBrief ?? false
        let storedBriefHour = suite.object(forKey: Key.dailyBriefHour) as? Int
        self.dailyBriefHour = storedBriefHour ?? 7

        // v0.31 — Stripe + consultant identity. Empty defaults so a
        // fresh install ships a usable (but identity-less) invoice
        // path the first time Mehdi drops a client on Won.
        self.stripePaymentLinkBase = suite.string(forKey: Key.stripePaymentLinkBase) ?? ""
        self.consultantSIRET       = suite.string(forKey: Key.consultantSIRET) ?? ""
        self.consultantIBAN        = suite.string(forKey: Key.consultantIBAN) ?? ""
        self.consultantVATNumber   = suite.string(forKey: Key.consultantVATNumber) ?? ""
        self.consultantAddress     = suite.string(forKey: Key.consultantAddress) ?? ""

        // v1.0-alpha.18 — Voice clone state. Empty defaults =
        // "voice not cloned yet"; the AuditSheet pitch audio
        // section surfaces a hint pointing back to Settings until
        // the user has flowed through the VoiceCloneSetupSheet.
        self.elevenLabsVoiceID    = suite.string(forKey: Key.elevenLabsVoiceID) ?? ""
        self.elevenLabsVoiceName  = suite.string(forKey: Key.elevenLabsVoiceName) ?? ""
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

    /// Non-Observable accessor for HealthInsights / HomeView paths that
    /// want to check the opt-in without holding the @MainActor instance.
    public static func currentHealthInsightsEnabled(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> Bool {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        return suite.object(forKey: Key.healthInsightsEnabled) as? Bool ?? false
    }

    /// Non-Observable accessor for the Reminders sync opt-in. Lets
    /// MINDApp read the flag in `onChange(of: scenePhase)` without
    /// holding a reference to the @MainActor `Preferences` instance.
    public static func currentRemindersSyncEnabled(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> Bool {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        return suite.object(forKey: Key.remindersSyncEnabled) as? Bool ?? false
    }

    /// v0.11 — Non-Observable accessor for the Notion database ID.
    /// Returns nil when empty so `AuditSheet` and downstream callers
    /// can branch on optional-binding without an extra trim check.
    public static func currentNotionDatabaseID(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> String? {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let value = suite.string(forKey: Key.notionDatabaseID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// v0.12 — Non-Observable accessor for the Linear default team ID.
    /// Same nil-on-empty contract as `currentNotionDatabaseID` so
    /// `AuditSheet` can branch on optional-binding when deciding
    /// whether to render the "Push to Linear" buttons.
    public static func currentLinearDefaultTeamID(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> String? {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let value = suite.string(forKey: Key.linearDefaultTeamID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// v0.17 — Non-Observable accessor for the daily-brief opt-in. Lets
    /// `DailyBriefScheduler.scheduleIfEnabled()` (called from MINDApp
    /// on launch + `.active` scenePhase) check the flag without holding
    /// a reference to the @MainActor `Preferences` instance.
    public static func currentDailyBriefEnabled(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> Bool {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        return suite.object(forKey: Key.dailyBriefEnabled) as? Bool ?? false
    }

    /// v0.17 — Non-Observable accessor for the daily-brief hour.
    /// Clamped to 0..23 to defend against a hand-edited UserDefaults
    /// returning a nonsensical value.
    public static func currentDailyBriefHour(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> Int {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let stored = suite.object(forKey: Key.dailyBriefHour) as? Int ?? 7
        return max(0, min(23, stored))
    }

    /// v0.31 — Non-Observable accessor for the Stripe Payment Link
    /// prefix. Returns nil when empty so the InvoiceSheet can branch
    /// on optional-binding to hide the Stripe block when the
    /// preference isn't configured yet.
    public static func currentStripePaymentLinkBase(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> String? {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let value = suite.string(forKey: Key.stripePaymentLinkBase)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// v0.31 — Non-Observable accessor for the consultant SIRET.
    public static func currentConsultantSIRET(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> String? {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let value = suite.string(forKey: Key.consultantSIRET)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// v0.31 — Non-Observable accessor for the consultant IBAN.
    public static func currentConsultantIBAN(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> String? {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let value = suite.string(forKey: Key.consultantIBAN)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// v0.31 — Non-Observable accessor for the consultant VAT number.
    public static func currentConsultantVATNumber(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> String? {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let value = suite.string(forKey: Key.consultantVATNumber)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// v0.31 — Non-Observable accessor for the consultant address.
    public static func currentConsultantAddress(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> String? {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let value = suite.string(forKey: Key.consultantAddress)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// v1.0-alpha.18 — Non-Observable accessor for the cloned voice
    /// ID. Lets AuditSheet (and any future surface — Daily Brief,
    /// outreach — that wants to read the pitch in Mehdi's voice)
    /// check whether a voice has been cloned without holding a
    /// reference to the @MainActor instance. Returns nil when empty
    /// so the caller can use `if let voiceID = …` to branch.
    public static func currentElevenLabsVoiceID(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> String? {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let value = suite.string(forKey: Key.elevenLabsVoiceID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// v1.0-alpha.18 — Non-Observable accessor for the cloned voice
    /// display name.
    public static func currentElevenLabsVoiceName(
        suiteName: String = MINDPreferences.sharedSuiteName
    ) -> String? {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        let value = suite.string(forKey: Key.elevenLabsVoiceName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }
}

public extension MINDPreferences {
    /// Preset Pomodoro-style durations exposed by the Settings picker.
    static let focusDurationPresets: [Int] = [15, 25, 45, 60, 90]

    /// v0.17 — Wake-up hour options surfaced in the Settings picker
    /// for the daily morning brief. Kept short — 4 buttons fits one
    /// row at AX1, and the 6/7/8/9 window covers ~99% of when people
    /// want a morning wake-up nudge.
    static let dailyBriefHourPresets: [Int] = [6, 7, 8, 9]
}
