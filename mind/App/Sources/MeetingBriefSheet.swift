import SwiftUI
import CalendarKit
import DesignSystem
import GraphCore

/// v0.28 — Discovery Call Prep Dossier sheet.
///
/// Presented when the user taps the morning-of brief notification
/// (or the "Briefs à venir" Home card). Shows the matched client +
/// recent news + audit highlights + attendee intel + 5 calibrated
/// discovery questions + a 30-second elevator opening line. Every
/// answer has a Copier button so Mehdi can paste straight into
/// Notes / Linear / a Slack message before walking in.
@MainActor
struct MeetingBriefSheet: View {

    let brief: MeetingBrief

    /// Tap-through callback for the matched client. The host App
    /// resolves the live `Node` from `DetectedClient.nodeID`,
    /// dismisses this sheet, and presents `NodeDetailView` for the
    /// matched client Node so the user can read the full audit /
    /// chat history before the call.
    var onSelectClient: ((DetectedClient) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copiedKey: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerCard
                    elevatorCard
                    if !brief.recentNews.isEmpty {
                        newsSection
                    }
                    if !brief.auditHighlights.isEmpty {
                        auditSection
                    }
                    if !brief.attendeeIntel.isEmpty {
                        attendeesSection
                    }
                    questionsSection
                }
                .padding(20)
                .padding(.bottom, 60)
            }
            .background {
                LiquidBackground()
                    .ignoresSafeArea()
            }
            .navigationTitle(Text("meetingBrief.detail.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        LiquidHaptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
        .onAppear {
            MINDTelemetry.info(
                "meetingBrief.opened",
                data: [
                    "eventID": brief.event.id,
                    "hasClient": brief.detectedClient != nil ? "1" : "0",
                    "newsBullets": "\(brief.recentNews.count)",
                    "auditBullets": "\(brief.auditHighlights.count)",
                    "attendees": "\(brief.attendeeIntel.count)",
                ]
            )
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        LiquidCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Self.formatDayHeader(brief.event.startDate))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                Text(brief.event.title)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                    Text(brief.event.formattedTime)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let location = brief.event.location, !location.isEmpty {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                        Text(location)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let client = brief.detectedClient {
                    Button {
                        LiquidHaptics.tap()
                        MINDTelemetry.info(
                            "meetingBrief.clientTapped",
                            data: ["clientID": client.nodeID.uuidString]
                        )
                        onSelectClient?(client)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "building.2.fill")
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                            Text(client.title)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                            Image(systemName: "chevron.right")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(LiquidPalette.iris.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text("meetingBrief.detail.noClient")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Elevator opening

    private var elevatorCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    key: "meetingBrief.section.opening",
                    glyph: "quote.opening",
                    tint: LiquidPalette.iris
                )
                Text(brief.elevatorOpening)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                copyButton(
                    text: brief.elevatorOpening,
                    storageKey: "opening"
                )
            }
            .padding(18)
        }
    }

    // MARK: - Recent news

    private var newsSection: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    key: "meetingBrief.section.news",
                    glyph: "newspaper.fill",
                    tint: .blue
                )
                ForEach(brief.recentNews) { bullet in
                    briefBulletRow(bullet)
                }
            }
            .padding(18)
        }
    }

    // MARK: - Audit highlights

    private var auditSection: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    key: "meetingBrief.section.audit",
                    glyph: "checkmark.shield.fill",
                    tint: .green
                )
                ForEach(brief.auditHighlights) { bullet in
                    briefBulletRow(bullet)
                }
            }
            .padding(18)
        }
    }

    // MARK: - Attendees

    private var attendeesSection: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    key: "meetingBrief.section.attendees",
                    glyph: "person.3.fill",
                    tint: LiquidPalette.iris
                )
                ForEach(brief.attendeeIntel) { intel in
                    attendeeRow(intel)
                }
            }
            .padding(18)
        }
    }

    // MARK: - Questions

    private var questionsSection: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    key: "meetingBrief.section.questions",
                    glyph: "questionmark.bubble.fill",
                    tint: .purple
                )
                ForEach(Array(brief.discoveryQuestions.enumerated()), id: \.offset) { index, question in
                    questionRow(index: index + 1, question: question)
                }
            }
            .padding(18)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func sectionHeader(key: LocalizedStringResource, glyph: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: glyph)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(key)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func briefBulletRow(_ bullet: BriefBullet) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(LiquidPalette.iris.opacity(0.7))
                .frame(width: 6, height: 6)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(bullet.text)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let source = bullet.source, source.hasPrefix("http") {
                    Button {
                        if let url = URL(string: source) {
                            openURL(url)
                            MINDTelemetry.info(
                                "meetingBrief.sourceTapped",
                                data: ["source": source]
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square.fill")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                            Text("meetingBrief.bullet.source")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else if let source = bullet.source, source == "internal:audit" {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                        Text("meetingBrief.bullet.auditSource")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func attendeeRow(_ intel: AttendeeIntel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(LiquidPalette.iris.opacity(0.18))
                    .frame(width: 32, height: 32)
                Text(initials(for: intel))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(intel.displayName.isEmpty ? intel.email : intel.displayName)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                if let role = intel.role, !role.isEmpty {
                    Text(role)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if !intel.email.isEmpty {
                    Text(intel.email)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if let urlString = intel.linkedInURL, let url = URL(string: urlString) {
                Button {
                    openURL(url)
                    MINDTelemetry.info(
                        "meetingBrief.linkedInTapped",
                        data: ["email": intel.email]
                    )
                } label: {
                    Image(systemName: "link.circle.fill")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(LiquidPalette.iris)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func questionRow(index: Int, question: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(LiquidPalette.iris.opacity(0.18))
                    .frame(width: 28, height: 28)
                Text("\(index)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(question)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                copyButton(
                    text: question,
                    storageKey: "question.\(index)"
                )
            }
        }
    }

    @ViewBuilder
    private func copyButton(text: String, storageKey: String) -> some View {
        Button {
            UIPasteboard.general.string = text
            LiquidHaptics.tap()
            withAnimation(.easeOut(duration: 0.18)) {
                copiedKey = storageKey
            }
            MINDTelemetry.info(
                "meetingBrief.questionCopied",
                data: [
                    "eventID": brief.event.id,
                    "slot": storageKey,
                ]
            )
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation(.easeOut(duration: 0.18)) {
                    if copiedKey == storageKey { copiedKey = nil }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copiedKey == storageKey ? "checkmark.circle.fill" : "doc.on.doc.fill")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                Text(copiedKey == storageKey
                     ? "meetingBrief.copy.done"
                     : "meetingBrief.copy.action")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(LiquidPalette.iris)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(LiquidPalette.iris.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func initials(for intel: AttendeeIntel) -> String {
        let source = intel.displayName.isEmpty ? intel.email : intel.displayName
        let parts = source.split { !$0.isLetter }
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.map { String($0).uppercased() }.joined()
    }

    private static func formatDayHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date).uppercased()
    }
}
