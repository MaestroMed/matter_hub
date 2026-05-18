import SwiftUI
import DesignSystem
import Intelligence

public struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var keySaved: Bool = false
    @State private var selectedModel: String = "claude-sonnet-4-6"
    @State private var preferOnDevice: Bool = true
    @State private var showKey: Bool = false
    @State private var prefs = MINDPreferences.shared

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

                section(title: "About") {
                    VStack(alignment: .leading, spacing: 6) {
                        infoRow(label: "Version", value: "0.1.0")
                        infoRow(label: "Bundle", value: "app.mind.ios")
                        infoRow(label: "Made for", value: "Mehdi 👋")
                    }
                }
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
        }
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
