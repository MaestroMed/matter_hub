import Foundation

/// v1.0-alpha.19 — Telemetry bridge for the visionOS spatial cockpit.
///
/// The spatial views fire breadcrumb events (`spatial.app.launched`,
/// `spatial.tab.changed`, `spatial.audit.theater.opened`,
/// `spatial.audit.theater.exited`, `spatial.lead.tapped`,
/// `spatial.project.tapped`) so the host App's `MINDTelemetry` sink
/// (Sentry breadcrumb + console log) keeps a trace of the spatial
/// session even though `VisionSpatialKit` does not link `GraphCore`.
///
/// The bridge exposes a single closure (`sink`) the host App
/// configures at launch — keeps `MINDTelemetry` out of the module's
/// dependency graph so VisionSpatialKit remains pure-value-types +
/// SwiftUI for v1.0-alpha.19. Until the App wires `sink`, every call
/// is a silent no-op (matches the `MINDTelemetry.sink = nil` default
/// shape the rest of the codebase uses).
///
/// Compiled on every platform so the `SpatialTelemetryBridge.shared`
/// reference inside the `#if os(visionOS)` surfaces resolves at parse
/// time regardless of the build target.
public final class SpatialTelemetryBridge: @unchecked Sendable {

    /// Singleton because the visionOS surface is a single-instance
    /// SwiftUI `WindowGroup` — wiring the sink at App init and
    /// reading it from any `View` is cleaner than threading an
    /// `@Environment` value through every panel.
    public static let shared = SpatialTelemetryBridge()

    /// Event payload the host App's MINDTelemetry sink rehydrates
    /// into a Sentry breadcrumb. Plain value type so the bridge is
    /// trivially `Sendable`.
    public struct Event: Sendable, Hashable {
        public let name: String
        public let data: [String: String]
        public init(name: String, data: [String: String] = [:]) {
            self.name = name
            self.data = data
        }
    }

    /// Closure the host App configures at launch (`SpatialTelemetryBridge.shared.sink = { MINDTelemetry.info(...) }`).
    /// Default is `nil` → every event is dropped, which is the right
    /// behaviour for tests + unsigned dev builds.
    public var sink: ((Event) -> Void)?

    private init() {}

    // MARK: - Public emitters

    public func appLaunched() {
        emit("spatial.app.launched")
    }

    #if os(visionOS)
    public func tabChanged(_ tab: SpatialTab) {
        emit("spatial.tab.changed", data: ["tab": tab.rawValue])
    }
    #endif

    public func theaterOpened(auditID: UUID) {
        emit(
            "spatial.audit.theater.opened",
            data: ["auditID.prefix": String(auditID.uuidString.prefix(8))]
        )
    }

    public func theaterExited() {
        emit("spatial.audit.theater.exited")
    }

    public func leadTapped(id: UUID) {
        emit(
            "spatial.lead.tapped",
            data: ["leadID.prefix": String(id.uuidString.prefix(8))]
        )
    }

    public func projectTapped(id: UUID) {
        emit(
            "spatial.project.tapped",
            data: ["projectID.prefix": String(id.uuidString.prefix(8))]
        )
    }

    // MARK: - Private

    private func emit(_ name: String, data: [String: String] = [:]) {
        guard let sink else { return }
        sink(Event(name: name, data: data))
    }
}
