import SwiftUI
import UIKit
import DesignSystem
import GraphCore
import AuditKit
import OutreachKit

/// v0.26 — AI Sales Email Generator UI.
///
/// Form-then-results sheet. The form captures recipient name +
/// email + voice tone + optional recent trigger. The CTA fires the
/// generator, the body swaps to 5 shimmer skeleton cards while the
/// network round-trip resolves, then renders 5 `LiquidCard` variant
/// rows once the generator returns. Each row carries three actions:
/// Copier, Ouvrir dans Mail (mailto: deep link), and Aimer (toggle
/// for the winning variant).
///
/// Entry points wired in v0.26:
/// - `NodeDetailView` client body → "Générer outreach" button
/// - `RootView.HomeView` audit card → tertiary "Outreach engine" row
/// - `ClientsView` ClientCard swipe action → "Outreach"
struct OutreachSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Pre-fill the form when the sheet is presented from a Node
    /// that already has a known prospect identity. The defaults here
    /// match the empty-form path triggered from HomeView's audit
    /// card tertiary row.
    init(
        prospect: ProspectContext = ProspectContext(clientName: "", host: ""),
        primaryContactEmail: String? = nil
    ) {
        _clientName = State(initialValue: prospect.clientName)
        _hostInput = State(initialValue: prospect.host)
        _recipientName = State(initialValue: prospect.primaryContactName ?? "")
        _recipientEmail = State(initialValue: primaryContactEmail ?? "")
        _recentTrigger = State(initialValue: prospect.recentTrigger ?? "")
        _industry = State(initialValue: prospect.industry ?? "")
        self.attachedAudit = prospect.auditReport
    }

    // MARK: - Form state

    @State private var clientName: String
    @State private var hostInput: String
    @State private var recipientName: String
    @State private var recipientEmail: String
    @State private var recentTrigger: String
    @State private var industry: String
    @State private var voice: SenderProfile.VoiceTone = .friendly

    /// Captured at init so the form's "Régénérer" CTA always uses
    /// the same audit grounding the user originally launched with —
    /// switching prospects requires dismissing + re-opening the
    /// sheet, which is the desired path.
    private let attachedAudit: AuditReport?

    // MARK: - Generation state

    @State private var phase: Phase = .form
    @State private var variants: [OutreachEmail] = []
    @State private var likedVariantIDs: Set<UUID> = []
    @State private var expandedVariantIDs: Set<UUID> = []
    @State private var errorMessage: String?

    enum Phase: Equatable {
        case form
        case generating
        case results
    }

    var body: some View {
        ZStack {
            LiquidBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    switch phase {
                    case .form:
                        formBody
                    case .generating:
                        generatingBody
                    case .results:
                        resultsBody
                    }
                }
                .padding(20)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("outreach.title")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.8)
                    .lineLimit(2)
                Text("outreach.subtitle")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Form

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            recipientCard
            voicePicker
            triggerCard
            generateButton
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var recipientCard: some View {
        LiquidCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(String(localized: "outreach.field.recipientName"), text: $recipientName)
                    .font(.system(.body, design: .rounded))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.vertical, 6)
                Divider().opacity(0.3)
                TextField(String(localized: "outreach.field.recipientEmail"), text: $recipientEmail)
                    .font(.system(.body, design: .rounded))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var voicePicker: some View {
        HStack(spacing: 8) {
            ForEach(SenderProfile.VoiceTone.allCases, id: \.self) { tone in
                LiquidPill(
                    title: voiceLabel(for: tone),
                    systemImage: voiceIcon(for: tone),
                    isActive: voice == tone
                ) {
                    LiquidHaptics.tap()
                    voice = tone
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var triggerCard: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("outreach.field.trigger")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "raised €15M Series A, hired CTO, …",
                    text: $recentTrigger,
                    axis: .vertical
                )
                .font(.system(.body, design: .rounded))
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var generateButton: some View {
        LiquidButton(
            title: String(localized: "outreach.cta.generate"),
            systemImage: "envelope.badge.shield.half.filled",
            haptic: .select
        ) {
            Task { await generate() }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Generating (shimmer skeletons)

    private var generatingBody: some View {
        VStack(spacing: 14) {
            Text("outreach.generating.label")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            ForEach(0..<5, id: \.self) { _ in
                ShimmerCard()
            }
        }
    }

    // MARK: - Results (5 variant cards)

    private var resultsBody: some View {
        VStack(spacing: 14) {
            ForEach(variants) { variant in
                variantCard(variant)
            }
            footerActions
        }
    }

    private func variantCard(_ variant: OutreachEmail) -> some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    AnglePill(angle: variant.angle)
                    Spacer()
                    Text("\(variant.estimatedReadTimeSeconds)s")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(variant.subject)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .lineLimit(2)
                Text(variant.body)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(expandedVariantIDs.contains(variant.id) ? nil : 3)
                Button {
                    LiquidHaptics.tap()
                    if expandedVariantIDs.contains(variant.id) {
                        expandedVariantIDs.remove(variant.id)
                    } else {
                        expandedVariantIDs.insert(variant.id)
                    }
                } label: {
                    Text(expandedVariantIDs.contains(variant.id)
                         ? "outreach.action.collapse"
                         : "outreach.action.expand")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
                actionRow(variant)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionRow(_ variant: OutreachEmail) -> some View {
        HStack(spacing: 10) {
            cardAction(
                labelKey: "outreach.action.copy",
                systemImage: "doc.on.doc"
            ) {
                UIPasteboard.general.string = "\(variant.subject)\n\n\(variant.body)"
                LiquidHaptics.success()
                MINDTelemetry.info(
                    "outreach.variant.copied",
                    data: ["angle": variant.angle.rawValue]
                )
            }
            cardAction(
                labelKey: "outreach.action.openInMail",
                systemImage: "envelope.fill"
            ) {
                let url = OutreachMailto.mailtoURL(
                    to: recipientEmail.isEmpty ? nil : recipientEmail,
                    subject: variant.subject,
                    body: variant.body
                )
                if let url {
                    UIApplication.shared.open(url)
                    LiquidHaptics.success()
                    MINDTelemetry.info(
                        "outreach.variant.opened.mail",
                        data: ["angle": variant.angle.rawValue]
                    )
                }
            }
            Spacer(minLength: 4)
            Button {
                LiquidHaptics.tap()
                if likedVariantIDs.contains(variant.id) {
                    likedVariantIDs.remove(variant.id)
                } else {
                    likedVariantIDs.insert(variant.id)
                    MINDTelemetry.info(
                        "outreach.variant.liked",
                        data: ["angle": variant.angle.rawValue]
                    )
                }
            } label: {
                Image(systemName: likedVariantIDs.contains(variant.id)
                      ? "heart.fill"
                      : "heart")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(likedVariantIDs.contains(variant.id)
                                     ? LiquidPalette.iris
                                     : .secondary)
                    .symbolEffect(.bounce, value: likedVariantIDs.contains(variant.id))
            }
            .accessibilityLabel(Text("outreach.action.like"))
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func cardAction(
        labelKey: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                Text(labelKey)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(LiquidPalette.iris)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            Button {
                LiquidHaptics.tap()
                Task { await generate() }
            } label: {
                Label("outreach.regenerate", systemImage: "arrow.clockwise")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background {
                        Capsule(style: .continuous).fill(.ultraThinMaterial)
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                            }
                    }
                    .foregroundStyle(LiquidPalette.iris)
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                LiquidHaptics.tap()
                phase = .form
                variants = []
                likedVariantIDs = []
                expandedVariantIDs = []
            } label: {
                Label("outreach.new", systemImage: "plus.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    // MARK: - Generation flow

    private func generate() async {
        // Light client-side guard: if the client name + host are
        // both blank we won't get a usable result. Surface a
        // localized error rather than wasting a Claude round-trip.
        let trimmedName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty && trimmedHost.isEmpty {
            errorMessage = String(localized: "outreach.error.noProspect")
            return
        }
        errorMessage = nil
        phase = .generating
        let prospect = ProspectContext(
            clientName: trimmedName.isEmpty ? trimmedHost : trimmedName,
            host: trimmedHost.isEmpty ? trimmedName : trimmedHost,
            auditReport: attachedAudit,
            recentTrigger: nilIfEmpty(recentTrigger),
            industry: nilIfEmpty(industry),
            primaryContactName: nilIfEmpty(recipientName),
            primaryContactRole: nil
        )
        let sender = SenderProfile(
            name: SenderProfile.default.name,
            title: SenderProfile.default.title,
            signature: SenderProfile.default.signature,
            voice: voice
        )
        do {
            let results = try await OutreachEmailGenerator.shared.generate(
                prospect: prospect,
                senderProfile: sender,
                variantCount: 5
            )
            await MainActor.run {
                if results.isEmpty {
                    phase = .form
                    errorMessage = String(localized: "outreach.error.emptyResponse")
                } else {
                    variants = results
                    phase = .results
                }
            }
        } catch {
            await MainActor.run {
                phase = .form
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func nilIfEmpty(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func voiceLabel(for tone: SenderProfile.VoiceTone) -> String {
        switch tone {
        case .friendly: return String(localized: "outreach.voice.friendly")
        case .direct:   return String(localized: "outreach.voice.direct")
        case .formal:   return String(localized: "outreach.voice.formal")
        }
    }

    private func voiceIcon(for tone: SenderProfile.VoiceTone) -> String {
        switch tone {
        case .friendly: return "face.smiling"
        case .direct:   return "bolt.fill"
        case .formal:   return "graduationcap.fill"
        }
    }
}

// MARK: - Angle pill

private struct AnglePill: View {
    let angle: OutreachEmail.Angle

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(.caption, design: .rounded, weight: .semibold))
            Text(labelKey)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(tint.opacity(0.18))
        }
    }

    private var labelKey: LocalizedStringKey {
        switch angle {
        case .roi:        return "outreach.variant.angle.roi"
        case .quickWin:   return "outreach.variant.angle.quickWin"
        case .competitor: return "outreach.variant.angle.competitor"
        case .funding:    return "outreach.variant.angle.funding"
        case .question:   return "outreach.variant.angle.question"
        }
    }

    private var icon: String {
        switch angle {
        case .roi:        return "eurosign.circle.fill"
        case .quickWin:   return "bolt.fill"
        case .competitor: return "person.2.fill"
        case .funding:    return "banknote.fill"
        case .question:   return "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch angle {
        case .roi:        return LiquidPalette.iris
        case .quickWin:   return LiquidPalette.aqua
        case .competitor: return LiquidPalette.blush
        case .funding:    return LiquidPalette.sky
        case .question:   return LiquidPalette.lavender
        }
    }
}

// MARK: - Shimmer skeleton

private struct ShimmerCard: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 16)
                    .frame(maxWidth: 120)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 22)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 14)
                    .frame(maxWidth: 240)
            }
            .padding(16)
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.35), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 90)
                .offset(x: phase * 320)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1.4
            }
        }
    }
}
