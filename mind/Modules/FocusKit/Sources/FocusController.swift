import Foundation
@preconcurrency import ActivityKit
import Observation

/// Owns the lifecycle of the single in-flight Deep Focus session: start,
/// pause, resume, end. Wraps ActivityKit so the rest of the app stays
/// agnostic of Live Activity machinery.
///
/// On iOS 26 push token observation has to live in a long-running
/// Task.detached or activities silently stop receiving server-side
/// updates after a few minutes in background. We don't have a backend
/// to push from yet, so the observer just keeps the token alive locally.
/// When Phase 8 adds backend-side push, the upload call goes there.
@MainActor
@Observable
public final class FocusController {
    public static let shared = FocusController()

    public private(set) var session: FocusSession?
    public private(set) var activity: Activity<FocusActivityAttributes>?

    private var pushTokenTask: Task<Void, Never>?

    public init() {}

    public var isRunning: Bool { activity != nil }

    public var areLiveActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Start a new Deep Focus session and a matching Live Activity. If a
    /// previous activity is still in flight it is ended first so we don't
    /// stack two timers in the Dynamic Island.
    @discardableResult
    public func start(
        intention: String,
        duration: TimeInterval,
        pulseColor: FocusActivityAttributes.ContentState.PulseColor = .iris
    ) -> FocusSession? {
        guard areLiveActivitiesEnabled else { return nil }
        endNow()

        let newSession = FocusSession(
            intention: intention,
            totalDuration: duration
        )
        let attributes = FocusActivityAttributes(
            sessionID: newSession.id,
            intention: newSession.intention,
            totalDuration: newSession.totalDuration
        )
        let state = FocusActivityAttributes.ContentState(
            phase: .running,
            endDate: newSession.endDate,
            pulseColor: pulseColor
        )
        let content = ActivityContent(
            state: state,
            staleDate: newSession.endDate.addingTimeInterval(60)
        )

        do {
            let started = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            self.session = newSession
            self.activity = started
            observePushTokens(for: started)
            return newSession
        } catch {
            return nil
        }
    }

    public func pause() async {
        guard let activity, let session else { return }
        let remaining = max(0, session.endDate.timeIntervalSinceNow)
        let state = FocusActivityAttributes.ContentState(
            phase: .paused,
            endDate: Date.now.addingTimeInterval(remaining)
        )
        await Self.send(
            update: activity,
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    public func resume() async {
        guard let activity, let session else { return }
        let state = FocusActivityAttributes.ContentState(
            phase: .running,
            endDate: session.endDate
        )
        await Self.send(
            update: activity,
            content: ActivityContent(
                state: state,
                staleDate: session.endDate.addingTimeInterval(60)
            )
        )
    }

    public func end() {
        Task { [weak self] in
            await self?.endActivity(phase: .completed)
        }
    }

    private func endNow() {
        guard let activity else { return }
        Task {
            await Self.sendImmediateEnd(activity: activity)
        }
        pushTokenTask?.cancel()
        pushTokenTask = nil
        self.activity = nil
        self.session = nil
    }

    private func endActivity(phase: FocusActivityAttributes.ContentState.Phase) async {
        guard let activity else { return }
        let finalState = FocusActivityAttributes.ContentState(
            phase: phase,
            endDate: .now
        )
        await Self.sendDelayedEnd(
            activity: activity,
            content: ActivityContent(state: finalState, staleDate: nil)
        )
        pushTokenTask?.cancel()
        pushTokenTask = nil
        self.activity = nil
        self.session = nil
    }

    private func observePushTokens(for activity: Activity<FocusActivityAttributes>) {
        pushTokenTask?.cancel()
        pushTokenTask = Task.detached(priority: .background) {
            for await _ in activity.pushTokenUpdates {
                // No backend to upload to yet (Phase 8). Just keep the
                // async sequence alive so iOS keeps vending tokens —
                // dropping the observer would silently stale future
                // server-side updates.
            }
        }
    }

    // Nonisolated helpers. Swift 6 strict concurrency: even though Apple
    // declares `Activity<T>` Sendable in iOS 17+, the compiler still
    // refuses to send a MainActor-bound binding across an `await`.
    // Marking the parameter `sending` tells the compiler the caller is
    // transferring ownership of its local copy to this non-isolated
    // helper, which is exactly what we mean.
    private nonisolated static func send(
        update activity: Activity<FocusActivityAttributes>,
        content: ActivityContent<FocusActivityAttributes.ContentState>
    ) async {
        await activity.update(content)
    }

    private nonisolated static func sendImmediateEnd(
        activity: Activity<FocusActivityAttributes>
    ) async {
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private nonisolated static func sendDelayedEnd(
        activity: Activity<FocusActivityAttributes>,
        content: ActivityContent<FocusActivityAttributes.ContentState>
    ) async {
        await activity.end(
            content,
            dismissalPolicy: .after(Date.now.addingTimeInterval(30))
        )
    }
}
