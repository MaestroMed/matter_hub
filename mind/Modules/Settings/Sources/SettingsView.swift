import SwiftUI
import SwiftData
import CloudKit
import UIKit
import AuditKit
import DesignSystem
import GraphCore
import HealthInsights
import Intelligence
import InvoiceKit
import LinearKit
import NotionKit
import RemindersKit
import VisualKit

public struct SettingsView: View {
    /// v0.20 — Used by the Beta section to open the TestFlight
    /// universal feedback URL and the public join link without
    /// pulling UIKit into the Settings module.
    @Environment(\.openURL) private var openURL

    @State private var apiKey: String = ""
    @State private var keySaved: Bool = false
    @State private var openAIKey: String = ""
    @State private var openAIKeySaved: Bool = false
    @State private var selectedModel: String = "claude-sonnet-4-6"
    @State private var preferOnDevice: Bool = true
    @State private var showKey: Bool = false
    @State private var showOpenAIKey: Bool = false
    @State private var prefs = MINDPreferences.shared

    // v0.11 — Notion sync. Token in Keychain (paste integration token
    // from notion.so/my-integrations), database ID in UserDefaults.
    @State private var notionToken: String = ""
    @State private var notionTokenSaved: Bool = false
    @State private var showNotionToken: Bool = false
    /// nil = unchecked / never validated. true / false = result of the
    /// last `NotionClient.validateToken()` call. Drives the green /
    /// red status dot next to the token field.
    @State private var notionTokenValid: Bool? = nil
    @State private var notionTestToast: String?
    @State private var notionBusy: Bool = false

    // v0.12 — Linear sync. Personal API key in Keychain (paste from
    // linear.app/settings/api), team UUID in UserDefaults. Same shape
    // as the Notion state above for symmetry.
    @State private var linearToken: String = ""
    @State private var linearTokenSaved: Bool = false
    @State private var showLinearToken: Bool = false
    /// nil = unchecked / never validated. true / false = result of the
    /// last `LinearClient.validateToken()` call. Drives the green /
    /// red status dot next to the token field.
    @State private var linearTokenValid: Bool? = nil
    @State private var linearBusy: Bool = false
    /// Cached teams returned by the last `LinearClient.shared.teams()`
    /// call. Empty until the user taps "Load teams" after their token
    /// validates. Picker hides itself when empty.
    @State private var linearTeams: [LinearTeam] = []
    @State private var linearToast: String?

    // v0.31 — Stripe Invoice section. Test-invoice CTA writes a
    // sample PDF to a temp file and presents the system share sheet
    // so Mehdi can validate his SIRET/IBAN/address branding without
    // having to first close + reopen the Pipeline / Won flow.
    @State private var invoiceTestURL: URL?
    @State private var showInvoiceShare: Bool = false

    // v1.0-alpha.5 — Lead Webhook section. The HMAC secret is the
    // shared key the deployed Cloudflare Worker uses to verify
    // inbound `/v1/leads` POSTs (see `mind/tools/cloudflare-worker`).
    // Stored in `WebhookSecretStore` (Keychain), never UserDefaults.
    // The Project ID copier surfaces the per-Project UUID Mehdi
    // pastes into the client site's `MIND_PROJECT_ID` env var.
    @State private var webhookSecret: String = ""
    @State private var webhookSecretSaved: Bool = false
    @State private var showWebhookSecret: Bool = false
    @State private var webhookProjects: [Project] = []
    @State private var webhookProjectIDCopiedToast: String?

    // Danger-zone confirmation alerts. Two-step UX so the user can't
    // accidentally wipe their second brain by misclicking — the alert
    // is the second tap.
    @State private var confirmClearAllData: Bool = false
    @State private var confirmResetSpotlight: Bool = false
    @State private var dangerZoneToast: String?

    /// Live CloudKit account status. Refreshed .onAppear and when iOS
    /// posts `CKAccountChanged` (sign in / out, restrict toggle).
    @State private var cloudKitStatus: CKAccountStatus = .couldNotDetermine

    private let availableModels: [(id: String, name: String)] = [
        ("claude-sonnet-4-6", "Claude Sonnet 4.6"),
        ("claude-opus-4-7", "Claude Opus 4.7"),
        ("claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                section(localized: "settings.section.anthropicKey") {
                    VStack(spacing: 12) {
                        keyField
                        HStack(spacing: 8) {
                            LiquidButton(
                                title: String(localized: keySaved ? "settings.button.saved" : "settings.button.save", bundle: .main),
                                systemImage: keySaved ? "checkmark" : "key.fill"
                            ) {
                                APIKeyStore.save(apiKey)
                                keySaved = true
                            }
                            .disabled(apiKey.isEmpty)

                            Button(String(localized: "settings.button.clear", bundle: .main)) {
                                APIKeyStore.clear()
                                apiKey = ""
                                keySaved = false
                            }
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                section(localized: "settings.section.openAIKey") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Clé sk-… utilisée pour générer les boards visuels GPT Image 2 dans l'audit. Stockée dans le Keychain.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)

                        openAIKeyField

                        HStack(spacing: 8) {
                            LiquidButton(
                                title: String(localized: openAIKeySaved ? "settings.button.saved" : "settings.button.save", bundle: .main),
                                systemImage: openAIKeySaved ? "checkmark" : "key.fill"
                            ) {
                                OpenAIAPIKeyStore.save(openAIKey)
                                openAIKeySaved = true
                            }
                            .disabled(openAIKey.isEmpty)

                            Button(String(localized: "settings.button.clear", bundle: .main)) {
                                OpenAIAPIKeyStore.clear()
                                openAIKey = ""
                                openAIKeySaved = false
                            }
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                section(localized: "settings.section.intelligence") {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Prefer on-device")
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                Text("Use Apple Intelligence first, fall back to Claude only for hard prompts.")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            LiquidToggle(isOn: $preferOnDevice)
                        }

                        Divider().background(.white.opacity(0.2))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cloud model")
                                .font(.system(.body, design: .rounded, weight: .medium))
                            VStack(spacing: 6) {
                                ForEach(availableModels, id: \.id) { model in
                                    modelRow(id: model.id, name: model.name)
                                }
                            }
                        }
                    }
                }

                notionSection

                linearSection

                invoiceSection

                section(localized: "settings.section.sentry") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Colle ton DSN Sentry (sentry.io → projet → Client Keys). Vide = télémétrie désactivée.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("https://xxx@sentry.io/yyy", text: $prefs.sentryDSN)
                                .textFieldStyle(.plain)
                                .font(.system(.caption, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background {
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                                }
                        }
                        Text("Redémarre l'app après modification pour appliquer.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }

                section(localized: "settings.section.preferences") {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifications audit")
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                Text("Reçois un banner quand un audit se termine en arrière-plan.")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            LiquidToggle(isOn: $prefs.auditNotificationsEnabled)
                        }

                        Divider().background(.white.opacity(0.2))

                        // v0.9 — HealthKit opt-in. Toggle on triggers the
                        // permission prompt. Toggle off only flips the
                        // local flag; iOS doesn't expose a way to
                        // revoke from the app, the user has to go to
                        // Réglages → Santé → MIND to revoke entirely.
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Données santé")
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                Text("Active la lecture pas / sommeil / minutes actives sur 7 jours pour la carte « Cette semaine » de l'accueil.")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            LiquidToggle(isOn: Binding(
                                get: { prefs.healthInsightsEnabled },
                                set: { newValue in
                                    prefs.healthInsightsEnabled = newValue
                                    if newValue {
                                        // Kick the authorization sheet on
                                        // toggle-on. requestAccess() is
                                        // idempotent — already-granted
                                        // permissions short-circuit and
                                        // the user sees nothing.
                                        Task {
                                            _ = await HealthReader.shared.requestAccess()
                                        }
                                    }
                                }
                            ))
                        }

                        Divider().background(.white.opacity(0.2))

                        // v0.10 — Reminders bidirectional sync opt-in.
                        // Toggle on triggers the EventKit reminders
                        // permission sheet. Toggle off only flips the
                        // local flag; iOS doesn't expose a programmatic
                        // revoke, the user has to go to Réglages →
                        // Confidentialité → Rappels → MIND to revoke
                        // entirely.
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("settings.preferences.reminders.title", bundle: .main)
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                Text("settings.preferences.reminders.detail", bundle: .main)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            LiquidToggle(isOn: Binding(
                                get: { prefs.remindersSyncEnabled },
                                set: { newValue in
                                    prefs.remindersSyncEnabled = newValue
                                    if newValue {
                                        // Kick the authorization sheet on
                                        // toggle-on. requestAccess() is
                                        // idempotent — already-granted
                                        // permissions short-circuit and
                                        // the user sees nothing.
                                        Task {
                                            _ = await RemindersStore.shared.requestAccess()
                                        }
                                    }
                                }
                            ))
                        }

                        Divider().background(.white.opacity(0.2))

                        // v0.17 — Daily morning brief opt-in + hour
                        // picker. Toggle-on requests the
                        // UNUserNotificationCenter permission and
                        // schedules a daily local notification at the
                        // chosen wall-clock hour. Toggle-off cancels
                        // the schedule. Changing the hour while
                        // enabled re-schedules immediately so the next
                        // morning fires at the new time without
                        // requiring the user to relaunch.
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("settings.brief.enable", bundle: .main)
                                        .font(.system(.body, design: .rounded, weight: .medium))
                                    Text("settings.brief.subtitle", bundle: .main)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                LiquidToggle(isOn: Binding(
                                    get: { prefs.dailyBriefEnabled },
                                    set: { newValue in
                                        prefs.dailyBriefEnabled = newValue
                                        if newValue {
                                            Task {
                                                let granted = await DailyBriefScheduler.requestAuthorization()
                                                if granted {
                                                    await DailyBriefScheduler.schedule(
                                                        hour: prefs.dailyBriefHour
                                                    )
                                                }
                                            }
                                        } else {
                                            DailyBriefScheduler.cancel()
                                        }
                                    }
                                ))
                            }

                            if prefs.dailyBriefEnabled {
                                HStack(spacing: 8) {
                                    ForEach([6, 7, 8, 9], id: \.self) { hour in
                                        briefHourPill(hour: hour)
                                    }
                                }
                            }
                        }

                        Divider().background(.white.opacity(0.2))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Durée Deep Focus")
                                .font(.system(.body, design: .rounded, weight: .medium))
                            Text("Durée par défaut quand tu démarres une session depuis l'écran d'accueil.")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(MINDPreferences.focusDurationPresets, id: \.self) { minutes in
                                    durationPill(minutes: minutes)
                                }
                            }
                        }
                    }
                }

                // v1.0-alpha.5 — Lead Webhook section. Sits just above
                // the iCloud status so the operator can verify "Worker
                // wired" right next to "iCloud connected" at a glance.
                webhookSection

                iCloudSection

                // v0.20 — Beta-only section: lives just above About so a
                // tester landing on Settings sees "Beta" pinned at the top
                // of the metadata block. Hidden on stable (>= 1.0.0)
                // builds via `Self.isBetaBuild`.
                if Self.isBetaBuild {
                    betaSection
                }

                section(localized: "settings.section.about") {
                    VStack(alignment: .leading, spacing: 12) {
                        // v0.20 — BETA capsule pinned at the top of the
                        // About card when the running binary is pre-1.0.
                        // Iris-tinted, white text, uppercase tracking —
                        // matches the rest of the Liquid Glass tone.
                        if Self.isBetaBuild {
                            betaBadge
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            infoRow(label: "Version", value: Self.appVersion)
                            infoRow(label: "Build", value: Self.appBuild)
                            infoRow(label: "Bundle", value: Self.appBundleID)
                            infoRow(label: "iOS target", value: "26.0")
                            infoRow(label: "Made for", value: "Mehdi 👋")
                        }
                    }
                }

                dangerZone
            }
            .padding(20)
            .padding(.top, 40)
            .padding(.bottom, 120)
        }
        .onAppear {
            if let stored = APIKeyStore.read() {
                apiKey = stored
                keySaved = true
            }
            if let stored = OpenAIAPIKeyStore.read() {
                openAIKey = stored
                openAIKeySaved = true
            }
            if let stored = NotionTokenStore.read() {
                notionToken = stored
                notionTokenSaved = true
            }
            if let stored = LinearTokenStore.read() {
                linearToken = stored
                linearTokenSaved = true
            }
            if let stored = WebhookSecretStore.read() {
                webhookSecret = stored
                webhookSecretSaved = true
            }
            loadWebhookProjects()
            refreshCloudKitStatus()
        }
        .alert(String(localized: "settings.notion.test.done", bundle: .main),
               isPresented: Binding(get: { notionTestToast != nil },
                                    set: { if !$0 { notionTestToast = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notionTestToast ?? "")
        }
        .alert(String(localized: "audit.export.linear.toast.title", bundle: .main),
               isPresented: Binding(get: { linearToast != nil },
                                    set: { if !$0 { linearToast = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(linearToast ?? "")
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .CKAccountChanged)
        ) { _ in
            // Fires when the user signs in / out of iCloud, or flips
            // restricted mode in System Settings. We re-fetch on the
            // main thread so the indicator updates live.
            refreshCloudKitStatus()
        }
        .alert("Wipe all data?",
               isPresented: $confirmClearAllData) {
            Button("Wipe everything", role: .destructive) {
                wipeAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes every note, capture, audit, client, focus session, and edge from this device. iCloud sync will pick up the deletion across your other devices. This cannot be undone.")
        }
        .alert("Reset Spotlight index?",
               isPresented: $confirmResetSpotlight) {
            Button("Reset", role: .destructive) {
                SpotlightIndexer.removeAll()
                dangerZoneToast = "Spotlight index cleared. It rebuilds the next time you open MIND."
                LiquidHaptics.success()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes every MIND row from iOS Spotlight. Your data stays intact — only the search index is wiped. Useful when results look stale.")
        }
        .alert("Done",
               isPresented: Binding(get: { dangerZoneToast != nil },
                                    set: { if !$0 { dangerZoneToast = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dangerZoneToast ?? "")
        }
        // v1.0-alpha.5 — Confirmation toast after the operator taps a
        // "Copier Project ID" row in the Lead Webhook section. Same
        // shape as the dangerZoneToast above — minimal one-button
        // OK alert, no haptic on the alert itself (the row tap
        // already fires `LiquidHaptics.success()`).
        .alert(String(localized: "settings.webhook.copied.title", bundle: .main),
               isPresented: Binding(
                get: { webhookProjectIDCopiedToast != nil },
                set: { if !$0 { webhookProjectIDCopiedToast = nil } }
               )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(webhookProjectIDCopiedToast ?? "")
        }
        // v0.31 — System share sheet hosting the freshly-rendered
        // sample invoice PDF so Mehdi can validate the branding
        // (SIRET, IBAN, address) without leaving Settings.
        .sheet(isPresented: $showInvoiceShare) {
            if let url = invoiceTestURL {
                InvoiceTestActivityView(items: [url])
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Notion sync (v0.11)

    /// Section that holds the paste-integration-token field, the
    /// target database ID field, and a "Test sync" button. Token is
    /// stored in `NotionTokenStore` (Keychain), database ID in
    /// `MINDPreferences.notionDatabaseID` (App Group UserDefaults).
    /// The green / red dot reflects the last `validateToken()` call —
    /// blank until the user taps "Save token".
    private var notionSection: some View {
        section(localized: "settings.notion.section") {
            VStack(alignment: .leading, spacing: 12) {
                Text("settings.notion.subtitle", bundle: .main)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                notionTokenField

                HStack(spacing: 8) {
                    LiquidButton(
                        title: notionTokenSaved
                            ? String(localized: "settings.button.saved", bundle: .main)
                            : String(localized: "settings.button.save", bundle: .main),
                        systemImage: notionTokenSaved ? "checkmark" : "key.fill"
                    ) {
                        saveNotionToken()
                    }
                    .disabled(notionToken.isEmpty || notionBusy)

                    Button(String(localized: "settings.button.clear", bundle: .main)) {
                        NotionTokenStore.clear()
                        notionToken = ""
                        notionTokenSaved = false
                        notionTokenValid = nil
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)

                    Spacer()

                    notionStatusDot
                }

                Divider().background(.white.opacity(0.2))

                Text("settings.notion.db.label", bundle: .main)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                notionDatabaseIDField

                LiquidButton(
                    title: String(localized: "settings.notion.test.button", bundle: .main),
                    systemImage: "arrow.up.right.circle.fill"
                ) {
                    runNotionTest()
                }
                .disabled(
                    notionToken.isEmpty
                    || prefs.notionDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || notionBusy
                )
            }
        }
    }

    private var notionTokenField: some View {
        HStack {
            Group {
                if showNotionToken {
                    TextField("ntn_…", text: $notionToken)
                } else {
                    SecureField("ntn_…", text: $notionToken)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: notionToken) { _, _ in
                notionTokenSaved = false
                notionTokenValid = nil
            }

            Button {
                showNotionToken.toggle()
            } label: {
                Image(systemName: showNotionToken ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
    }

    private var notionDatabaseIDField: some View {
        HStack {
            TextField("4f8e2c9f1a2b4c5d…", text: $prefs.notionDatabaseID)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var notionStatusDot: some View {
        if let valid = notionTokenValid {
            HStack(spacing: 6) {
                Circle()
                    .fill(valid ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (valid ? Color.green : Color.red).opacity(0.5), radius: 4)
                Text(valid
                     ? String(localized: "settings.notion.status.ok", bundle: .main)
                     : String(localized: "settings.notion.status.fail", bundle: .main))
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else if notionBusy {
            ProgressView().controlSize(.mini)
        } else {
            EmptyView()
        }
    }

    private func saveNotionToken() {
        notionBusy = true
        let trimmed = notionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        NotionTokenStore.save(trimmed)
        notionTokenSaved = true
        MINDTelemetry.info("notion.token.saved", data: ["length": "\(trimmed.count)"])
        Task {
            let valid = await NotionClient.shared.validateToken()
            await MainActor.run {
                notionTokenValid = valid
                notionBusy = false
                MINDTelemetry.info("notion.token.validated", data: ["valid": valid ? "true" : "false"])
                if !valid {
                    LiquidHaptics.warning()
                } else {
                    LiquidHaptics.success()
                }
            }
        }
    }

    private func runNotionTest() {
        notionBusy = true
        let dbID = prefs.notionDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines)
        let dummy = makeNotionTestReport()
        Task {
            do {
                let url = try await NotionClient.shared.createAuditPage(dummy, in: dbID)
                await MainActor.run {
                    notionBusy = false
                    notionTestToast = String(
                        format: String(localized: "settings.notion.test.success", bundle: .main),
                        url
                    )
                    LiquidHaptics.success()
                    MINDTelemetry.info("notion.page.created", data: ["surface": "settings.test"])
                }
            } catch {
                await MainActor.run {
                    notionBusy = false
                    notionTestToast = String(
                        format: String(localized: "settings.notion.test.error", bundle: .main),
                        String(describing: error)
                    )
                    LiquidHaptics.error()
                    MINDTelemetry.warning("notion.page.failed", data: [
                        "surface": "settings.test",
                        "error": String(describing: error),
                    ])
                }
            }
        }
    }

    /// Builds a tiny AuditReport used solely by "Test sync" so the
    /// real audit data never leaves the device during a connectivity
    /// check. Title = "Test depuis MIND".
    private func makeNotionTestReport() -> AuditReport {
        let client = AuditClient(
            url: URL(string: "https://mind.ios.app")!,
            name: String(localized: "settings.notion.test.pageTitle", bundle: .main)
        )
        return AuditReport(
            client: client,
            persona: .other,
            scoring: .init(overall: 0, performance: 0, seo: 0, security: 0, brand: 0, mobile: 0),
            performance: nil,
            findings: nil,
            synthesis: String(localized: "settings.notion.test.body", bundle: .main),
            quickWins: [],
            strategicBets: [],
            hiddenRisks: [],
            pitch: ""
        )
    }

    // MARK: - Linear sync (v0.12)

    /// Section that holds the paste-personal-API-key field, the team
    /// picker, and the save/validate button. Token is stored in
    /// `LinearTokenStore` (Keychain), default team UUID in
    /// `MINDPreferences.linearDefaultTeamID` (App Group UserDefaults).
    /// The green / red dot reflects the last `validateToken()` call —
    /// blank until the user taps "Save token". Once the token
    /// validates, "Load teams" fetches the workspace's teams via
    /// `LinearClient.shared.teams()` and renders them as a horizontal
    /// Liquid pill picker.
    private var linearSection: some View {
        section(localized: "settings.linear.section") {
            VStack(alignment: .leading, spacing: 12) {
                Text("settings.linear.subtitle", bundle: .main)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                linearTokenField

                HStack(spacing: 8) {
                    LiquidButton(
                        title: linearTokenSaved
                            ? String(localized: "settings.button.saved", bundle: .main)
                            : String(localized: "settings.button.save", bundle: .main),
                        systemImage: linearTokenSaved ? "checkmark" : "key.fill"
                    ) {
                        saveLinearToken()
                    }
                    .disabled(linearToken.isEmpty || linearBusy)

                    Button(String(localized: "settings.button.clear", bundle: .main)) {
                        LinearTokenStore.clear()
                        linearToken = ""
                        linearTokenSaved = false
                        linearTokenValid = nil
                        linearTeams = []
                        prefs.linearDefaultTeamID = ""
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)

                    Spacer()

                    linearStatusDot
                }

                Divider().background(.white.opacity(0.2))

                Text("settings.linear.team.label", bundle: .main)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))

                if linearTeams.isEmpty {
                    Text("settings.linear.team.empty", bundle: .main)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    linearTeamPicker
                }

                LiquidButton(
                    title: String(localized: "settings.linear.team.fetch", bundle: .main),
                    systemImage: "arrow.down.circle.fill"
                ) {
                    fetchLinearTeams()
                }
                .disabled(linearToken.isEmpty || linearBusy)
            }
        }
    }

    private var linearTokenField: some View {
        HStack {
            Group {
                if showLinearToken {
                    TextField("lin_api_…", text: $linearToken)
                } else {
                    SecureField("lin_api_…", text: $linearToken)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: linearToken) { _, _ in
                linearTokenSaved = false
                linearTokenValid = nil
            }

            Button {
                showLinearToken.toggle()
            } label: {
                Image(systemName: showLinearToken ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
    }

    /// Horizontal Liquid pill picker. The selected team's UUID lives
    /// in `prefs.linearDefaultTeamID`; tapping a pill assigns its `id`
    /// to that property. Liquid Glass tokens only — capsule
    /// `.continuous`, `.ultraThinMaterial`, iris highlight for the
    /// active pill.
    private var linearTeamPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(linearTeams) { team in
                    Button {
                        prefs.linearDefaultTeamID = team.id
                        LiquidHaptics.select()
                    } label: {
                        HStack(spacing: 6) {
                            Text(team.key)
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(team.name)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            Capsule(style: .continuous)
                                .fill(
                                    prefs.linearDefaultTeamID == team.id
                                    ? LiquidPalette.iris.opacity(0.32)
                                    : Color.clear
                                )
                                .overlay {
                                    Capsule(style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .opacity(prefs.linearDefaultTeamID == team.id ? 0 : 1)
                                }
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(
                                            prefs.linearDefaultTeamID == team.id
                                            ? LiquidPalette.iris
                                            : .white.opacity(0.15),
                                            lineWidth: 1
                                        )
                                }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var linearStatusDot: some View {
        if let valid = linearTokenValid {
            HStack(spacing: 6) {
                Circle()
                    .fill(valid ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (valid ? Color.green : Color.red).opacity(0.5), radius: 4)
                Text(valid
                     ? String(localized: "settings.linear.status.ok", bundle: .main)
                     : String(localized: "settings.linear.status.fail", bundle: .main))
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else if linearBusy {
            ProgressView().controlSize(.mini)
        } else {
            EmptyView()
        }
    }

    private func saveLinearToken() {
        linearBusy = true
        let trimmed = linearToken.trimmingCharacters(in: .whitespacesAndNewlines)
        LinearTokenStore.save(trimmed)
        linearTokenSaved = true
        MINDTelemetry.info("linear.token.saved", data: ["length": "\(trimmed.count)"])
        Task {
            let valid = await LinearClient.shared.validateToken()
            await MainActor.run {
                linearTokenValid = valid
                linearBusy = false
                MINDTelemetry.info("linear.token.validated", data: ["valid": valid ? "true" : "false"])
                if !valid {
                    LiquidHaptics.warning()
                } else {
                    LiquidHaptics.success()
                }
            }
        }
    }

    private func fetchLinearTeams() {
        linearBusy = true
        Task {
            do {
                let fetched = try await LinearClient.shared.teams()
                await MainActor.run {
                    linearTeams = fetched
                    linearBusy = false
                    LiquidHaptics.success()
                    // If the user previously selected a team that no
                    // longer exists in the workspace, clear it.
                    if !fetched.contains(where: { $0.id == prefs.linearDefaultTeamID }) {
                        prefs.linearDefaultTeamID = ""
                    }
                }
            } catch {
                await MainActor.run {
                    linearBusy = false
                    linearToast = String(
                        format: String(localized: "audit.export.linear.error", bundle: .main),
                        String(describing: error)
                    )
                    LiquidHaptics.error()
                }
            }
        }
    }

    // MARK: - Invoice billing (v0.31)

    /// "Facturation" section — Stripe Payment Link prefix + the four
    /// consultant identity fields (SIRET, IBAN, VAT number, address)
    /// the InvoiceKit PDF renderer folds into every generated invoice.
    /// "Générer une facture test" CTA emits a sample PDF and presents
    /// the system share sheet so Mehdi can validate his branding
    /// without having to first drop a client onto the Pipeline Won
    /// column.
    private var invoiceSection: some View {
        section(localized: "settings.invoice.section") {
            VStack(alignment: .leading, spacing: 14) {
                // Stripe Payment Link prefix.
                VStack(alignment: .leading, spacing: 6) {
                    Text("settings.invoice.stripeLink", bundle: .main)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    TextField("https://buy.stripe.com/...", text: $prefs.stripePaymentLinkBase)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background {
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                                }
                        }
                }

                Divider().background(.white.opacity(0.18))

                identityFieldRow(
                    label: "SIRET",
                    placeholder: "12345678901234",
                    binding: $prefs.consultantSIRET,
                    monospace: true
                )
                identityFieldRow(
                    label: "TVA",
                    placeholder: "FR12345678910",
                    binding: $prefs.consultantVATNumber,
                    monospace: true
                )
                identityFieldRow(
                    label: "IBAN",
                    placeholder: "FR76 3000 6000 0112 3456 7890 189",
                    binding: $prefs.consultantIBAN,
                    monospace: true
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Adresse")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    TextField(
                        "12 rue du Code\n75011 Paris",
                        text: $prefs.consultantAddress,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .rounded))
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }

                Divider().background(.white.opacity(0.18))

                LiquidButton(
                    title: String(localized: "settings.invoice.test", bundle: .main),
                    systemImage: "doc.text.fill"
                ) {
                    generateTestInvoice()
                }
            }
        }
    }

    @ViewBuilder
    private func identityFieldRow(
        label: String,
        placeholder: String,
        binding: Binding<String>,
        monospace: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            TextField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: monospace ? .monospaced : .rounded))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                        }
                }
        }
    }

    private func generateTestInvoice() {
        let branding = ConsultantBranding(
            name: "Mehdi Nafaa",
            address: MINDPreferences.currentConsultantAddress(),
            siret: MINDPreferences.currentConsultantSIRET(),
            vatNumber: MINDPreferences.currentConsultantVATNumber(),
            iban: MINDPreferences.currentConsultantIBAN(),
            email: "meehdi.n@gmail.com",
            phone: nil
        )
        let sample = Invoice(
            number: "MIND-TEST-0001",
            clientNodeID: UUID(),
            clientName: "Acme SAS (exemple)",
            clientEmail: "ops@acme.com",
            amountEUR: 4_500,
            vatPercent: 20,
            description: "Mission audit + recommandations pour Acme SAS",
            stripePaymentLinkURL: MINDPreferences.currentStripePaymentLinkBase().flatMap {
                InvoiceStripeLinkBuilder.appendAmount(base: $0, amountEUR: 4500 * 1.20)
            },
            consultantBranding: branding
        )
        let pdfData = InvoicePDFRenderer.render(sample)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MIND-test-invoice.pdf")
        do {
            try pdfData.write(to: url, options: [.atomic])
            invoiceTestURL = url
            showInvoiceShare = true
            MINDTelemetry.info(
                "invoice.pdf.exported",
                data: ["origin": "settings.test"]
            )
        } catch {
            MINDTelemetry.warning(
                "invoice.test.write.failed",
                data: ["error": String(describing: error)]
            )
        }
    }

    // MARK: - Lead Webhook (v1.0-alpha.5)

    /// "Lead Webhook" section — paste the HMAC shared secret used by
    /// the deployed Cloudflare Worker (`mind/tools/cloudflare-worker`)
    /// to verify inbound `/v1/leads` POSTs, plus a "Copier Project ID"
    /// row per Project so Mehdi can drop the matching UUID into each
    /// client site's `MIND_PROJECT_ID` env var without round-tripping
    /// through the Cockpit list.
    ///
    /// Secret persistence shape mirrors the Anthropic / OpenAI /
    /// Notion / Linear sections: Keychain via `WebhookSecretStore`,
    /// "Save" → "Saved ✓" CTA, "Clear" secondary, eye toggle on the
    /// secret field. No round-trip validation — the Worker isn't
    /// reachable from inside the iOS sandbox without a network call
    /// the user hasn't consented to; the first real lead POST is the
    /// canonical "did it work" signal.
    private var webhookSection: some View {
        section(localized: "settings.webhook.section") {
            VStack(alignment: .leading, spacing: 12) {
                Text("settings.webhook.subtitle", bundle: .main)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                webhookSecretField

                HStack(spacing: 8) {
                    LiquidButton(
                        title: webhookSecretSaved
                            ? String(localized: "settings.button.saved", bundle: .main)
                            : String(localized: "settings.button.save", bundle: .main),
                        systemImage: webhookSecretSaved ? "checkmark" : "key.fill"
                    ) {
                        saveWebhookSecret()
                    }
                    .disabled(webhookSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(String(localized: "settings.button.clear", bundle: .main)) {
                        WebhookSecretStore.clear()
                        webhookSecret = ""
                        webhookSecretSaved = false
                        MINDTelemetry.info("webhook.secret.cleared")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Divider().background(.white.opacity(0.2))

                Text("settings.webhook.projects.label", bundle: .main)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))

                if webhookProjects.isEmpty {
                    Text("settings.webhook.projects.empty", bundle: .main)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(webhookProjects, id: \.id) { project in
                            webhookProjectRow(project)
                        }
                    }
                }
            }
        }
    }

    private var webhookSecretField: some View {
        HStack {
            Group {
                if showWebhookSecret {
                    TextField("64-char hex secret", text: $webhookSecret)
                } else {
                    SecureField("64-char hex secret", text: $webhookSecret)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: webhookSecret) { _, _ in webhookSecretSaved = false }

            Button {
                showWebhookSecret.toggle()
            } label: {
                Image(systemName: showWebhookSecret ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func webhookProjectRow(_ project: Project) -> some View {
        Button {
            copyWebhookProjectID(project)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LiquidPalette.iris.opacity(0.22))
                        .frame(width: 32, height: 32)
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(project.id.uuidString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "doc.on.clipboard")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func saveWebhookSecret() {
        let trimmed = webhookSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        WebhookSecretStore.save(trimmed)
        webhookSecretSaved = true
        LiquidHaptics.success()
        MINDTelemetry.info("webhook.secret.saved", data: ["length": "\(trimmed.count)"])
    }

    private func loadWebhookProjects() {
        let context = ModelContext(GraphCore.sharedContainer)
        var descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\Project.name, order: .forward)]
        )
        descriptor.fetchLimit = 32
        if let fetched = try? context.fetch(descriptor) {
            webhookProjects = fetched
        } else {
            webhookProjects = []
        }
    }

    private func copyWebhookProjectID(_ project: Project) {
        UIPasteboard.general.string = project.id.uuidString
        LiquidHaptics.success()
        MINDTelemetry.info("webhook.projectID.copied", data: ["project": project.slug])
        let template = String(localized: "settings.webhook.copied.body", bundle: .main)
        webhookProjectIDCopiedToast = String(format: template, project.name)
    }

    // MARK: - iCloud sync indicator

    /// Live CloudKit status row so Mehdi can verify sync actually works
    /// between his two iPhones without leaving the app. Colour-coded
    /// dot + human-readable label. The container identifier is shown
    /// in monospaced caption so it's easy to spot at a glance and
    /// matches what the iCloud settings page expects.
    private var iCloudSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.section.iCloud", bundle: .main).uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            LiquidCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Self.statusDotColor(for: cloudKitStatus))
                            .frame(width: 10, height: 10)
                            .shadow(color: Self.statusDotColor(for: cloudKitStatus).opacity(0.5),
                                    radius: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.statusLabel(for: cloudKitStatus))
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            Text(Self.statusDetail(for: cloudKitStatus))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Divider().background(.white.opacity(0.2))

                    HStack {
                        Text("Container")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(GraphCore.cloudKitContainerIdentifier)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Async fetches the account status off-main and writes it back to
    /// the @State on the main actor. CKContainer.accountStatus is the
    /// canonical "can MIND sync" probe.
    private func refreshCloudKitStatus() {
        Task {
            let container = CKContainer(identifier: GraphCore.cloudKitContainerIdentifier)
            do {
                let status = try await container.accountStatus()
                await MainActor.run { cloudKitStatus = status }
            } catch {
                await MainActor.run { cloudKitStatus = .couldNotDetermine }
            }
        }
    }

    private static func statusLabel(for status: CKAccountStatus) -> String {
        switch status {
        case .available:           return "Synced"
        case .noAccount:           return "Sign in to iCloud"
        case .restricted:          return "Restricted by profile"
        case .couldNotDetermine:   return "Checking…"
        case .temporarilyUnavailable: return "Temporarily unavailable"
        @unknown default:          return "Unknown"
        }
    }

    private static func statusDetail(for status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "Tes notes, captures et audits se synchronisent sur tes autres appareils Apple."
        case .noAccount:
            return "Ouvre Réglages → Apple ID pour activer iCloud Drive."
        case .restricted:
            return "Un profil de configuration (école / entreprise) bloque l'accès iCloud."
        case .couldNotDetermine:
            return "Demande en cours auprès d'iCloud…"
        case .temporarilyUnavailable:
            return "iCloud est en maintenance ou hors ligne. Réessaie dans quelques minutes."
        @unknown default:
            return "État iCloud inconnu — vérifie Réglages → Apple ID."
        }
    }

    private static func statusDotColor(for status: CKAccountStatus) -> Color {
        switch status {
        case .available:           return .green
        case .noAccount:           return .orange
        case .restricted:          return .red
        case .couldNotDetermine:   return .secondary
        case .temporarilyUnavailable: return .yellow
        @unknown default:          return .secondary
        }
    }

    // MARK: - Danger zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.section.dangerZone", bundle: .main).uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.red.opacity(0.85))
                .padding(.leading, 4)

            LiquidCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    dangerRow(
                        icon: "arrow.counterclockwise.circle.fill",
                        title: String(localized: "settings.danger.restartOnboarding.title", bundle: .main),
                        detail: "Re-shows the 4-page welcome flow on next app launch. Doesn't touch your data — only flips the @AppStorage flag.",
                        action: {
                            LiquidHaptics.tap()
                            // Clear @AppStorage flag through UserDefaults
                            // since SettingsView isn't the owner of the
                            // flag. RootView reads it on next render.
                            UserDefaults.standard.set(false, forKey: "mind.onboarding.completed")
                            dangerZoneToast = "Onboarding reset. Force-quit MIND and relaunch to see the flow."
                        }
                    )

                    Divider().background(.white.opacity(0.2))

                    dangerRow(
                        icon: "magnifyingglass.circle.fill",
                        title: String(localized: "settings.danger.resetSpotlight.title", bundle: .main),
                        detail: "Wipe every MIND row from iOS Spotlight. Data stays intact.",
                        action: {
                            LiquidHaptics.warning()
                            confirmResetSpotlight = true
                        }
                    )

                    Divider().background(.white.opacity(0.2))

                    dangerRow(
                        icon: "trash.circle.fill",
                        title: String(localized: "settings.danger.wipeAll.title", bundle: .main),
                        detail: "Delete every note, capture, audit, client, edge, and focus session. iCloud will sync the deletion.",
                        action: {
                            LiquidHaptics.warning()
                            confirmClearAllData = true
                        }
                    )
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func dangerRow(
        icon: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.red.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.85)
                        .lineLimit(2)
                    Text(detail)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    /// Deletes every Node / Edge / FocusSessionRecord from the shared
    /// container. SwiftData's batch-delete API doesn't span all model
    /// types in a single call, so we iterate the three types.
    @MainActor
    private func wipeAllData() {
        let context = ModelContext(GraphCore.sharedContainer)
        do {
            try context.delete(model: Node.self)
            try context.delete(model: Edge.self)
            try context.delete(model: FocusSessionRecord.self)
            try context.save()
            SpotlightIndexer.removeAll()
            dangerZoneToast = "Tout est parti. iCloud va synchroniser la suppression sur tes autres appareils."
            LiquidHaptics.success()
        } catch {
            dangerZoneToast = "Échec : \(error.localizedDescription)"
            LiquidHaptics.error()
        }
    }

    // MARK: - About metadata

    /// Pulled from Info.plist at runtime so the About row never drifts
    /// from what's actually shipping in the binary. Fallback strings
    /// keep the row usable in tests / previews where the bundle isn't
    /// the production bundle.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private static var appBundleID: String {
        Bundle.main.bundleIdentifier ?? "app.mind.ios"
    }

    // MARK: - Beta build detection (v0.20)

    /// True when the currently-running binary is a pre-1.0 build —
    /// i.e. a TestFlight beta. Drives the BETA badge in the About
    /// section, the Beta section with the "Send feedback" + "Join the
    /// beta" rows, and the dismissible welcome banner on HomeView.
    ///
    /// Reads `CFBundleShortVersionString` once via `Bundle.main` and
    /// hands the raw value to the pure `isBetaVersion(_:)` helper so
    /// the version-compare logic stays unit-testable without any
    /// Bundle mocking.
    public static var isBetaBuild: Bool {
        isBetaVersion(appVersion)
    }

    /// Pure semantic-version compare used by `isBetaBuild`. A build is
    /// a beta whenever its short version string is **strictly less
    /// than** `1.0.0` (e.g. `0.20.0`, `0.999.999`, `0.0.1` — every
    /// pre-release we ship). `1.0.0` and above flip every beta-only
    /// surface off.
    ///
    /// Malformed input (missing patch, non-numeric segments, empty
    /// string, `"—"` fallback from `appVersion`) returns `true`. The
    /// safer default for a dev / preview / test bundle that doesn't
    /// carry a real version is to **show** the beta UI: a missed
    /// "you're in the beta" badge in a production build is louder
    /// than an unexpected "beta" tag in a developer's simulator.
    public static func isBetaVersion(_ version: String) -> Bool {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—" else { return true }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 1, let major = Int(parts[0]) else { return true }
        // Major == 0 is always beta, regardless of minor / patch.
        // Major >= 1 ships when the version is exactly 1.0.0 or above —
        // anything shaped like "1.x" is a stable release.
        return major < 1
    }

    // MARK: - Beta URLs (v0.20)

    /// Universal TestFlight feedback URL. iOS intercepts this scheme
    /// inside a beta build and routes the tap into the in-app
    /// "Send feedback" flow (screenshot + device info auto-attached).
    /// Stable across versions — no need for the App Store Connect
    /// app ID, the OS resolves it from the running bundle.
    public static let testFlightFeedbackURL = URL(
        string: "https://testflight.apple.com/v3/contact-developer"
    )!

    /// Public-link join URL. The trailing path component is the
    /// public TestFlight code Mehdi fills in on App Store Connect.
    /// `MINDBETA` is a placeholder — the real code lands in the same
    /// `testflight.apple.com/join/<code>` shape so the constant stays
    /// stable when the real code is dropped in.
    public static let testFlightJoinURL = URL(
        string: "https://testflight.apple.com/join/MINDBETA"
    )!

    // MARK: - Beta UI (v0.20)

    /// Small uppercase capsule pinned at the top of the About card on
    /// beta builds. Iris-on-white tone — same gradient family the
    /// Liquid system uses for primary CTAs, so the badge reads as
    /// "official MIND tag" rather than "warning sticker".
    @ViewBuilder
    private var betaBadge: some View {
        HStack(spacing: 8) {
            Text("about.beta.badge", bundle: .main)
                .font(.system(.caption2, design: .rounded, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule(style: .continuous)
                        .fill(LiquidPalette.iris)
                }
            Spacer()
        }
    }

    /// Beta-only Settings section with two rows:
    ///   1. "Send feedback via TestFlight" — opens the universal
    ///      TestFlight feedback URL. iOS intercepts it inside a beta
    ///      build and routes the tap into the in-app feedback flow
    ///      (screenshot + device info auto-attached). On a stable
    ///      build the link 404s — but this whole section hides itself
    ///      under `isBetaBuild` so that never ships.
    ///   2. "Join the beta" — opens the public TestFlight join URL.
    ///      Useful when a tester wants to forward the link to a
    ///      colleague directly from the app.
    @ViewBuilder
    private var betaSection: some View {
        section(localized: "settings.beta.section") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    openBetaFeedback()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .foregroundStyle(LiquidPalette.iris)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings.beta.feedback.button", bundle: .main)
                                .font(.system(.body, design: .rounded, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("settings.beta.feedback.subtitle", bundle: .main)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().background(.white.opacity(0.2))

                Button {
                    openBetaJoin()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(LiquidPalette.iris)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings.beta.join.button", bundle: .main)
                                .font(.system(.body, design: .rounded, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("settings.beta.join.subtitle", bundle: .main)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func openBetaFeedback() {
        MINDTelemetry.info("beta.feedback.opened")
        LiquidHaptics.tap()
        openURL(Self.testFlightFeedbackURL)
    }

    private func openBetaJoin() {
        MINDTelemetry.info("beta.join.opened")
        LiquidHaptics.tap()
        openURL(Self.testFlightJoinURL)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("settings.header.title", bundle: .main)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text("settings.header.subtitle", bundle: .main)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var keyField: some View {
        HStack {
            Group {
                if showKey {
                    TextField("sk-ant-…", text: $apiKey)
                } else {
                    SecureField("sk-ant-…", text: $apiKey)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: apiKey) { _, _ in keySaved = false }

            Button {
                showKey.toggle()
            } label: {
                Image(systemName: showKey ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
    }

    private var openAIKeyField: some View {
        HStack {
            Group {
                if showOpenAIKey {
                    TextField("sk-…", text: $openAIKey)
                } else {
                    SecureField("sk-…", text: $openAIKey)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: openAIKey) { _, _ in openAIKeySaved = false }

            Button {
                showOpenAIKey.toggle()
            } label: {
                Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func modelRow(id: String, name: String) -> some View {
        Button {
            withAnimation(LiquidMetrics.spring) { selectedModel = id }
        } label: {
            HStack {
                Text(name)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                Spacer()
                if selectedModel == id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LiquidPalette.iris)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selectedModel == id ? LiquidPalette.lavender.opacity(0.3) : Color.clear)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func durationPill(minutes: Int) -> some View {
        let isSelected = prefs.focusDurationMinutes == minutes
        Button {
            withAnimation(LiquidMetrics.spring) {
                prefs.focusDurationMinutes = minutes
            }
        } label: {
            Text("\(minutes)m")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? .white : LiquidPalette.iris)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(isSelected
                                   ? AnyShapeStyle(LiquidGradient.primary)
                                   : AnyShapeStyle(LiquidPalette.lavender.opacity(0.35)))
                }
        }
        .buttonStyle(.plain)
    }

    /// v0.17 — Picker pill for the daily morning brief hour. Selects
    /// the wall-clock hour (0..23 local) at which `DailyBriefScheduler`
    /// fires the daily local notification. Changing the hour while
    /// the brief is enabled re-schedules immediately so the next
    /// morning fires at the new time.
    @ViewBuilder
    private func briefHourPill(hour: Int) -> some View {
        let isSelected = prefs.dailyBriefHour == hour
        Button {
            withAnimation(LiquidMetrics.spring) {
                prefs.dailyBriefHour = hour
            }
            if prefs.dailyBriefEnabled {
                Task {
                    await DailyBriefScheduler.schedule(hour: hour)
                }
            }
        } label: {
            Text("\(hour)h")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? .white : LiquidPalette.iris)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(isSelected
                                   ? AnyShapeStyle(LiquidGradient.primary)
                                   : AnyShapeStyle(LiquidPalette.lavender.opacity(0.35)))
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            LiquidCard(cornerRadius: 20) {
                content()
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Localized overload: resolves the key against the main app bundle
    /// (where Localizable.xcstrings lives) and uppercases the result for
    /// the section header style. Used by every section so all titles
    /// translate uniformly.
    @ViewBuilder
    private func section<Content: View>(localized key: String.LocalizationValue, @ViewBuilder content: () -> Content) -> some View {
        let resolved = String(localized: key, bundle: .main)
        section(title: resolved, content: content)
    }
}

/// v0.31 — UIKit bridge for the system share sheet so the
/// "Generate test invoice" CTA can hand the sample PDF to
/// Mail / Messages / AirDrop. Same pattern as `PortalActivityView`.
private struct InvoiceTestActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
