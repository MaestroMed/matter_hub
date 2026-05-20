import WidgetKit
import SwiftUI
import ActivityKit
import FocusKit

/// Lock Screen + Dynamic Island UI for an in-flight Deep Focus session.
/// Driven from the app side by `FocusController` via ActivityKit; the
/// widget extension only owns the rendering.
struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.45))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading, priority: 1) {
                    expandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
            } compactLeading: {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(pulseTint(for: context.state.pulseColor))
                    .symbolEffect(.bounce, value: context.state.phase)
            } compactTrailing: {
                Text(timerInterval: pinnedNow...context.state.endDate, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .foregroundStyle(pulseTint(for: context.state.pulseColor))
            } minimal: {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(pulseTint(for: context.state.pulseColor))
            }
            .widgetURL(URL(string: "mind://focus/active"))
            .keylineTint(pulseTint(for: context.state.pulseColor))
        }
    }

    // MARK: - Dynamic Island expanded regions

    @ViewBuilder
    private func expandedLeading(context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(pulseTint(for: context.state.pulseColor).opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(pulseTint(for: context.state.pulseColor))
                    .symbolEffect(.bounce, value: context.state.phase)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(context.attributes.intention)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Text(label(for: context.state.phase))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func expandedTrailing(context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        Text(timerInterval: pinnedNow...context.state.endDate, countsDown: true)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .foregroundStyle(pulseTint(for: context.state.pulseColor))
            .contentTransition(.numericText())
    }

    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        ProgressView(
            timerInterval: startDate(for: context)...context.state.endDate,
            countsDown: false,
            label: { EmptyView() },
            currentValueLabel: { EmptyView() }
        )
        .tint(pulseTint(for: context.state.pulseColor))
        .padding(.top, 2)
    }

    // MARK: - Helpers

    private var pinnedNow: Date { .now }

    private func startDate(for context: ActivityViewContext<FocusActivityAttributes>) -> Date {
        context.state.endDate.addingTimeInterval(-context.attributes.totalDuration)
    }

    private func pulseTint(for color: FocusActivityAttributes.ContentState.PulseColor) -> Color {
        switch color {
        case .lavender: return WidgetPalette.lavender
        case .iris:     return WidgetPalette.iris
        case .aqua:     return WidgetPalette.aqua
        }
    }

    private func label(for phase: FocusActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .running:   return "In focus"
        case .paused:    return "Paused"
        case .completed: return "Done"
        }
    }
}

// MARK: - Lock Screen view

struct FocusLockScreenView: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: context.state.phase)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.intention)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                ProgressView(
                    timerInterval: startDate...context.state.endDate,
                    countsDown: false,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
                .tint(tint)
                .frame(height: 5)
            }

            Spacer(minLength: 8)

            Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(tint)
                .frame(minWidth: 90, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(16)
    }

    private var startDate: Date {
        context.state.endDate.addingTimeInterval(-context.attributes.totalDuration)
    }

    private var tint: Color {
        switch context.state.pulseColor {
        case .lavender: return WidgetPalette.lavender
        case .iris:     return WidgetPalette.iris
        case .aqua:     return WidgetPalette.aqua
        }
    }

    private var label: String {
        switch context.state.phase {
        case .running:   return "In focus"
        case .paused:    return "Paused"
        case .completed: return "Done"
        }
    }
}
