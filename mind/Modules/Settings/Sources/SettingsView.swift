import SwiftUI
import SwiftData
import CloudKit
import DesignSystem
import GraphCore
import Intelligence
import VisualKit

public struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var keySaved: Bool = false
    @State private var openAIKey: String = ""
    @State private var openAIKeySaved: Bool = false
    @State private var selectedModel: String = "claude-sonnet-4-6"
    @State private var preferOnDevice: Bool = true
    @State private var showKey: Bool = false
    @State private var showOpenAIKey: Bool = false
    @State private var prefs = MINDPreferences.shared

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

                section(title: "Anthropic API Key") {
                    VStack(spacing: 12) {
                        keyField
                        HStack(spacing: 8) {
                            LiquidButton(
                                title: keySaved ? "Saved" : "Save key",
                                systemImage: keySaved ? "checkmark" : "key.fill"
                            ) {
                                APIKeyStore.save(apiKey)
                                keySaved = true
                            }
                            .disabled(apiKey.isEmpty)

                            Button("Clear") {
                                APIKeyStore.clear()
                                apiKey = ""
                                keySaved = false
                            }
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                section(title: "OpenAI API Key (visual boards)") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Clé sk-… utilisée pour générer les boards visuels GPT Image 2 dans l'audit. Stockée dans le Keychain.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)

                        openAIKeyField

                        HStack(spacing: 8) {
                            LiquidButton(
                                title: openAIKeySaved ? "Saved" : "Save key",
                                systemImage: openAIKeySaved ? "checkmark" : "key.fill"
                            ) {
                                OpenAIAPIKeyStore.save(openAIKey)
                                openAIKeySaved = true
                            }
                            .disabled(openAIKey.isEmpty)

                            Button("Clear") {
                                OpenAIAPIKeyStore.clear()
                                openAIKey = ""
                                openAIKeySaved = false
                            }
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                section(title: "Intelligence") {
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

                section(title: "Crash reporting (Sentry)") {
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

                section(title: "Préférences") {
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

                iCloudSection

                section(title: "About") {
                    VStack(alignment: .leading, spacing: 6) {
                        infoRow(label: "Version", value: Self.appVersion)
                        infoRow(label: "Build", value: Self.appBuild)
                        infoRow(label: "Bundle", value: Self.appBundleID)
                        infoRow(label: "iOS target", value: "26.0")
                        infoRow(label: "Made for", value: "Mehdi 👋")
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
            refreshCloudKitStatus()
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
    }

    // MARK: - iCloud sync indicator

    /// Live CloudKit status row so Mehdi can verify sync actually works
    /// between his two iPhones without leaving the app. Colour-coded
    /// dot + human-readable label. The container identifier is shown
    /// in monospaced caption so it's easy to spot at a glance and
    /// matches what the iCloud settings page expects.
    private var iCloudSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iCloud Sync".uppercased())
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
            Text("Danger zone".uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.red.opacity(0.85))
                .padding(.leading, 4)

            LiquidCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    dangerRow(
                        icon: "arrow.counterclockwise.circle.fill",
                        title: "Restart onboarding",
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
                        title: "Reset Spotlight index",
                        detail: "Wipe every MIND row from iOS Spotlight. Data stays intact.",
                        action: {
                            LiquidHaptics.warning()
                            confirmResetSpotlight = true
                        }
                    )

                    Divider().background(.white.opacity(0.2))

                    dangerRow(
                        icon: "trash.circle.fill",
                        title: "Wipe all data",
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
    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private static var appBundleID: String {
        Bundle.main.bundleIdentifier ?? "app.mind.ios"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text("Configure your second brain.")
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
}
