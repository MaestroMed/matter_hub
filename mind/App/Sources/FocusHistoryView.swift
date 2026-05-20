import SwiftUI
import SwiftData
import DesignSystem
import GraphCore

/// Full history of completed Deep Focus sessions, ordered most recent
/// first. Sits behind the focusWeekCard tap on HomeView.
struct FocusHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FocusSessionRecord.completedAt, order: .reverse)
    private var allSessions: [FocusSessionRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statsCard
                if allSessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background { LiquidBackground().ignoresSafeArea() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Focus history")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("\(allSessions.count) sessions enregistrées")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        LiquidCard(cornerRadius: 20) {
            HStack(spacing: 0) {
                statColumn(value: totalMinutes, label: "Minutes", unit: "min")
                divider
                statColumn(value: Int(completionRate * 100), label: "Complétion", unit: "%")
                divider
                statColumn(value: currentStreakDays, label: "Streak", unit: "j")
            }
            .padding(18)
            .frame(maxWidth: .infinity)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(width: 1, height: 36)
    }

    @ViewBuilder
    private func statColumn(value: Int, label: String, unit: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(LiquidPalette.iris)
                Text(unit)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(label.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var totalMinutes: Int {
        Int(allSessions.reduce(0.0) { $0 + $1.actualDurationSeconds } / 60)
    }

    private var completionRate: Double {
        guard !allSessions.isEmpty else { return 0 }
        let completed = allSessions.filter { $0.completedNormally }.count
        return Double(completed) / Double(allSessions.count)
    }

    /// Number of consecutive days with at least one session up to today.
    /// O(n) over the (recent-first) sessions list.
    private var currentStreakDays: Int {
        let calendar = Calendar.current
        let dayKeys = Set(allSessions.map { calendar.startOfDay(for: $0.completedAt) })
        var streak = 0
        var cursor = calendar.startOfDay(for: .now)
        while dayKeys.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    // MARK: - Empty state

    private var emptyState: some View {
        LiquidCard {
            VStack(spacing: 14) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 36))
                    .foregroundStyle(LiquidGradient.primary)
                Text("Aucune session pour le moment")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text("Lance ta première Deep Focus depuis l'écran d'accueil.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Session list

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sessions".uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, 4)

            ForEach(allSessions) { session in
                sessionRow(session)
            }
        }
    }

    private func sessionRow(_ session: FocusSessionRecord) -> some View {
        LiquidCard(cornerRadius: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((session.completedNormally ? Color.green : Color.orange).opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: session.completedNormally ? "checkmark" : "stop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(session.completedNormally ? .green : .orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.intention)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    Text(session.completedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatDuration(session.actualDurationSeconds))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(LiquidPalette.iris)
            }
            .padding(14)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return s == 0 ? "\(m) min" : String(format: "%dm%02d", m, s)
    }
}
