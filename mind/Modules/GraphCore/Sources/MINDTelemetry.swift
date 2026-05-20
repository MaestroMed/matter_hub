import Foundation

/// Lightweight, dependency-free instrumentation facade. Lives in
/// GraphCore (which every module already depends on) so any feature
/// module can call `MINDTelemetry.breadcrumb(...)` without pulling
/// Sentry — or anything else — into its dependency graph.
///
/// Wiring contract
/// ---------------
/// At app boot (MINDApp.bootstrapSentry, after SentrySDK.start), the
/// host installs a sink:
///
///     MINDTelemetry.sink = { event in
///         let crumb = Breadcrumb(level: event.level.sentryLevel, ...)
///         SentrySDK.addBreadcrumb(crumb)
///     }
///
/// Until the sink is set the calls are silent no-ops. That keeps tests
/// and the unsigned-Simulator dev loop free of telemetry side effects
/// while production gets full Sentry breadcrumbs for context on every
/// crash.
///
/// Why a facade rather than `import Sentry` everywhere
/// ----------------------------------------------------
/// FocusKit, AuditKit, Capture, Settings, etc. should not link Sentry
/// directly — it bloats every framework binary, slows incremental
/// builds, and ties module dependency closures to a third-party SDK.
/// A 30-line facade keeps the call sites clean and the boundary
/// crossable to any other reporter (Bugsnag, Crashlytics, Posthog) by
/// swapping one line in MINDApp.
public enum MINDTelemetry {

    /// Levels mirror Sentry's `SentryLevel` so the host translator is a
    /// trivial switch. None implies "info"-ish, only `.error` and
    /// `.critical` will typically surface in dashboards.
    public enum Level: String, Sendable {
        case debug
        case info
        case warning
        case error
        case critical
    }

    /// One discrete event. Categories follow Sentry conventions ("ui",
    /// "navigation", "http", "auth", "user"…) but the field is free-form
    /// — keep the vocabulary small and consistent across call sites.
    public struct Event: Sendable {
        public let name: String
        public let category: String
        public let level: Level
        public let data: [String: String]
        public let timestamp: Date

        public init(
            name: String,
            category: String,
            level: Level = .info,
            data: [String: String] = [:],
            timestamp: Date = .now
        ) {
            self.name = name
            self.category = category
            self.level = level
            self.data = data
            self.timestamp = timestamp
        }
    }

    /// The pluggable sink. nil = no-op. Set by MINDApp once Sentry is
    /// initialised. Synchronised through MainActor isolation because
    /// SwiftUI / UIKit lifecycle callbacks already run there.
    @MainActor public static var sink: ((Event) -> Void)?

    // MARK: - Public API

    /// Record a breadcrumb. Cheap — silent when no sink is wired.
    /// Safe to call from any actor (the dispatch onto MainActor is
    /// the responsibility of the caller if needed; the typical call
    /// path is already on MainActor).
    @MainActor
    public static func breadcrumb(
        _ name: String,
        category: String = "app",
        level: Level = .info,
        data: [String: String] = [:]
    ) {
        let event = Event(name: name, category: category, level: level, data: data)
        sink?(event)
    }

    /// Convenience for the most common case — a one-liner with the
    /// default `app` category and `info` level.
    @MainActor
    public static func info(_ name: String, data: [String: String] = [:]) {
        breadcrumb(name, level: .info, data: data)
    }

    @MainActor
    public static func warning(_ name: String, data: [String: String] = [:]) {
        breadcrumb(name, level: .warning, data: data)
    }

    @MainActor
    public static func error(_ name: String, data: [String: String] = [:]) {
        breadcrumb(name, level: .error, data: data)
    }
}
