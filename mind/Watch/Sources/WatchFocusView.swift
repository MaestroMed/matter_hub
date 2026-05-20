import SwiftUI

/// v1.0-alpha.17 — Focus pomodoro launcher tab on the Apple Watch.
/// Tap "Démarrer Focus" → dispatches a `focus.start` message to the
/// iPhone via `WatchConnectivityBridge`; while running, surfaces a
/// large elapsed counter + a Stop button that dispatches `focus.end`.
///
/// The running state lives in the shared App Group key
/// (`mind.watch.focus.running`) so the Watch survives a restart mid-
/// session.
struct WatchFocusView: View {

    @State private var isRunning: Bool = WatchSharedSnapshot.readFocusRunning()
    @State private var elapsedSeconds: Int = 0
    @State private var timerStartedAt: Date?

    private static let defaultPomodoroSeconds = 1_500   // 25 min

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                if isRunning {
                    runningBody
                } else {
                    idleBody
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .navigationTitle("Focus")
        .onAppear {
            isRunning = WatchSharedSnapshot.readFocusRunning()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass")
                .font(.headline)
            Text("watch.tab.focus.title".watchLocalized)
                .font(.headline)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var idleBody: some View {
        VStack(spacing: 6) {
            Text("Pomodoro · 25 min")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                start()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("watch.focus.start.button".watchLocalized)
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var runningBody: some View {
        VStack(spacing: 6) {
            Text(WatchKPIFormatter.elapsed(elapsedSeconds))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .padding(.vertical, 4)
            Text(String(
                format: "watch.focus.elapsed.format".watchLocalized,
                Self.defaultPomodoroSeconds / 60
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            Button(role: .destructive) {
                stop()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                    Text("watch.focus.stop.button".watchLocalized)
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }

    private func start() {
        isRunning = true
        timerStartedAt = Date()
        elapsedSeconds = 0
        WatchConnectivityBridge.shared.dispatchFocusStart(.pomodoroDefault)
    }

    private func stop() {
        isRunning = false
        timerStartedAt = nil
        elapsedSeconds = 0
        WatchConnectivityBridge.shared.dispatchFocusEnd()
    }
}
