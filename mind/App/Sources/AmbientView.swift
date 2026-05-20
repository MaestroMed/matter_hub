import SwiftUI
import SwiftData
import UIKit
import DesignSystem
import GraphCore
import FocusKit

/// Ambient dashboard — designed for the iPhone 14 Pro Max docked as an
/// always-on display. Big clock, calmer palette, last capture rotating
/// in the background, no chrome. Tap anywhere to exit.
///
/// V1 scaffold:
/// - Full-bleed Liquid background, brighter than the in-app one to read
///   well at arm's length.
/// - Time-of-day greeting + monumental clock (~120pt) updated each
///   minute.
/// - "Latest" card showing the most recent capture / note title.
/// - Disables the system idle timer while presented so the device
///   doesn't dim mid-display when on power.
struct AmbientView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Node.createdAt, order: .reverse) private var allNodes: [Node]
    @State private var now: Date = .now
    @State private var focus = FocusController.shared

    // Tick every 30s so the minute label stays accurate without burning
    // a per-second timer animation.
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var latest: Node? {
        allNodes.first { ["capture", "note"].contains($0.kindRaw) }
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 24) {
                Spacer()
                greeting
                clock
                if let session = focus.session {
                    focusBadge(session: session)
                }
                Spacer()
                if let latest {
                    latestCard(latest)
                }
                Spacer(minLength: 24)
                exitHint
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(tick) { value in now = value }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
    }

    // MARK: - Layout

    private var background: some View {
        LinearGradient(
            colors: [
                LiquidPalette.pearl,
                LiquidPalette.lavender.opacity(0.6),
                LiquidPalette.iris.opacity(0.35),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var greeting: some View {
        Text(timeBasedGreeting)
            .font(.system(.title, design: .rounded, weight: .light))
            .foregroundStyle(.secondary)
    }

    private var clock: some View {
        Text(now.formatted(.dateTime.hour().minute()))
            .font(.system(size: 128, weight: .ultraLight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(LiquidPalette.iris)
            .contentTransition(.numericText())
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private func focusBadge(session: FocusSession) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LiquidPalette.iris)
            Text(session.intention)
                .font(.system(.headline, design: .rounded, weight: .medium))
            Text("·")
                .foregroundStyle(.tertiary)
            Text(timerInterval: .now...session.endDate, countsDown: true)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(LiquidPalette.iris)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
    }

    private func latestCard(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DERNIÈRE PENSÉE")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Text(node.title)
                .font(.system(.title3, design: .rounded, weight: .medium))
                .lineLimit(2)
            if !node.content.isEmpty {
                Text(node.content)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(node.createdAt.formatted(.relative(presentation: .named)))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
    }

    private var exitHint: some View {
        Text("Tape pour sortir")
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.tertiary)
            .tracking(0.8)
    }

    private var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12:  return "Good morning, Mehdi"
        case 12..<18: return "Good afternoon, Mehdi"
        case 18..<23: return "Good evening, Mehdi"
        default:      return "Still up, Mehdi"
        }
    }
}
