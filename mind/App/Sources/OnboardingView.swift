import SwiftUI
import UserNotifications
import DesignSystem
import Intelligence

/// First-launch onboarding shown over the app the very first time a
/// user opens MIND. Persistence is the @AppStorage flag
/// `mind.onboarding.completed` — once set, the cover never re-appears
/// (the user can still re-enter every screen via Settings).
///
/// Four pages, all skippable except the final "Start" CTA:
///   1. Welcome  — brand intro + value prop
///   2. Anthropic — paste Claude API key (Keychain) so ChatView /
///      AuditSheet / synthesis work on first try
///   3. Notifications — request UNUserNotificationCenter authorization
///      so background audits can banner when they finish
///   4. Ready   — recap + "Start"
///
/// The Anthropic key step is the highest-friction one because nothing
/// else works without it; we let the user skip it but flag it visually
/// so they know the chat / audit will be inert until they paste one.
struct OnboardingView: View {
    /// Called by the final "Start" button. The owner of this view
    /// (RootView) flips the @AppStorage flag so the cover dismisses
    /// and never re-shows.
    let onFinish: () -> Void

    @State private var stage: Stage = .welcome
    @State private var anthropicKey: String = ""
    @State private var keySaved: Bool = false
    @State private var notificationsRequested: Bool = false
    @State private var notificationsGranted: Bool = false

    enum Stage: Int, CaseIterable, Hashable {
        case welcome
        case anthropicKey
        case notifications
        case ready
    }

    var body: some View {
        ZStack {
            LiquidBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                pageIndicator
                    .padding(.top, 24)

                TabView(selection: $stage) {
                    welcomePage.tag(Stage.welcome)
                    anthropicPage.tag(Stage.anthropicKey)
                    notificationsPage.tag(Stage.notifications)
                    readyPage.tag(Stage.ready)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(LiquidMetrics.spring, value: stage)

                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            // If the user had previously saved a key in Settings (e.g.
            // re-installed without wiping the keychain), pre-fill the
            // field so they don't have to re-paste.
            if let stored = APIKeyStore.read() {
                anthropicKey = stored
                keySaved = true
            }
        }
    }

    // MARK: - Header / page indicator

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Stage.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= stage.rawValue
                          ? AnyShapeStyle(LiquidGradient.primary)
                          : AnyShapeStyle(Color.white.opacity(0.25)))
                    .frame(width: s == stage ? 28 : 8, height: 6)
                    .animation(LiquidMetrics.spring, value: stage)
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if stage != .welcome {
                Button("Back") {
                    advance(to: previousStage)
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer()

            if stage != .ready {
                Button("Skip") {
                    advance(to: nextStage)
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
            }

            LiquidButton(
                title: stage == .ready ? "Start" : "Next",
                systemImage: stage == .ready ? "sparkles" : "arrow.right"
            ) {
                if stage == .ready {
                    onFinish()
                } else {
                    advance(to: nextStage)
                }
            }
            .frame(minWidth: 120)
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        OnboardingCard {
            VStack(spacing: 24) {
                // The 42pt glyph inside the 96pt circle is intentional
                // (display-only hero icon). Kept fixed so the geometry
                // of the welcome page doesn't break at AX5.
                ZStack {
                    Circle()
                        .fill(LiquidGradient.primary)
                        .frame(width: 96, height: 96)
                        .shadow(color: LiquidPalette.iris.opacity(0.4), radius: 24, y: 12)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 10) {
                    Text("Bienvenue dans MIND")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                    Text("Ton second cerveau. Notes, focus, audits clients, captures vocales — synchronisés sur tous tes appareils via iCloud.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                bulletRow(icon: "doc.text.fill",
                          tint: LiquidPalette.iris,
                          title: "Capture",
                          detail: "Texte, voix, document — tout finit dans ton graphe.")
                bulletRow(icon: "magnifyingglass",
                          tint: .orange,
                          title: "Audit client",
                          detail: "Du domaine au pitch en quelques minutes.")
                bulletRow(icon: "drop.fill",
                          tint: LiquidPalette.iris,
                          title: "Deep Focus",
                          detail: "Sessions chronométrées, Live Activity, Dynamic Island.")
            }
        }
    }

    private var anthropicPage: some View {
        OnboardingCard {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(LiquidPalette.iris.opacity(0.18))
                        .frame(width: 80, height: 80)
                    // 32pt key glyph inside 80pt circle — display-only.
                    Image(systemName: "key.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                }

                VStack(spacing: 8) {
                    Text("Connecte Claude")
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .lineLimit(2)
                    Text("MIND s'appuie sur l'API Anthropic pour le chat, la synthèse d'audit et la génération de pitchs. Sans clé, ces fonctions restent inertes.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                    HStack(spacing: 6) {
                        Text("Obtenir une clé")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SecureField("sk-ant-…", text: $anthropicKey)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
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
                        .onChange(of: anthropicKey) { _, _ in keySaved = false }

                    LiquidButton(
                        title: keySaved ? "Saved in Keychain" : "Save key",
                        systemImage: keySaved ? "checkmark.circle.fill" : "key.fill"
                    ) {
                        APIKeyStore.save(anthropicKey)
                        keySaved = true
                    }
                    .disabled(anthropicKey.isEmpty)
                }
                .padding(.horizontal, 4)

                Text("La clé est stockée dans le Keychain iOS et ne quitte jamais l'appareil sauf pour appeler l'API Anthropic.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var notificationsPage: some View {
        OnboardingCard {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(LiquidPalette.aqua.opacity(0.20))
                        .frame(width: 80, height: 80)
                    // 32pt bell glyph inside 80pt circle — display-only.
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                }

                VStack(spacing: 8) {
                    Text("Notifications d'audit")
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .lineLimit(2)
                    Text("Lance un audit, range ton téléphone. Tu reçois un banner quand le rapport est prêt — pas avant.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if notificationsRequested {
                    HStack(spacing: 8) {
                        Image(systemName: notificationsGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(notificationsGranted ? .green : .orange)
                        Text(notificationsGranted
                             ? "Notifications activées."
                             : "Refusées — tu peux changer dans Réglages iOS.")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                } else {
                    LiquidButton(title: "Autoriser", systemImage: "bell.fill") {
                        requestNotifications()
                    }
                    .padding(.top, 4)
                }

                Text("Tu peux toujours toggle ça dans Settings → Préférences.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var readyPage: some View {
        OnboardingCard {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(LiquidGradient.primary)
                        .frame(width: 96, height: 96)
                        .shadow(color: LiquidPalette.iris.opacity(0.4), radius: 24, y: 12)
                    // 38pt sparkles glyph inside 96pt circle — display-only.
                    Image(systemName: "sparkles")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("Tu es prêt")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                    Text("MIND apprendra ta manière de penser au fil de tes captures.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    setupRow(done: keySaved, label: "Clé Anthropic configurée")
                    setupRow(done: notificationsGranted, label: "Notifications d'audit")
                    setupRow(done: true, label: "Sync iCloud activée")
                }
                .padding(.horizontal, 8)

                Text("Quelques pistes pour démarrer : capture une pensée, lance un audit, ou démarre une session focus.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Helpers

    private func bulletRow(
        icon: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.85)
                    .lineLimit(2)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer()
        }
    }

    private func setupRow(done: Bool, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Text(label)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(done ? .primary : .secondary)
                .minimumScaleFactor(0.85)
                .lineLimit(2)
            Spacer()
        }
    }

    private var previousStage: Stage {
        Stage(rawValue: max(0, stage.rawValue - 1)) ?? .welcome
    }

    private var nextStage: Stage {
        Stage(rawValue: min(Stage.allCases.count - 1, stage.rawValue + 1)) ?? .ready
    }

    private func advance(to next: Stage) {
        withAnimation(LiquidMetrics.spring) { stage = next }
    }

    /// Requests `.alert + .sound + .badge` from UNUserNotificationCenter.
    /// We don't surface the actual error to the user — if Apple's prompt
    /// fails for any reason, the UI just stays on the "Autoriser" button
    /// and the user can move on with Skip.
    private func requestNotifications() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                Task { @MainActor in
                    notificationsRequested = true
                    notificationsGranted = granted
                }
            }
    }
}

/// Reusable glass card that hosts each onboarding page's body. Keeps
/// the framing (rounded rect, soft shadow, generous padding) consistent
/// across all four pages without re-declaring it inline four times.
private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LiquidCard(cornerRadius: 28) {
                    content
                        .padding(24)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
