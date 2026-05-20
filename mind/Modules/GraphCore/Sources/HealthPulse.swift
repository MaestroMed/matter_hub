import Foundation

/// v1.0-alpha.8 — Project Health Pulse value types + pure classifier.
///
/// The Cockpit needs to surface, at a glance, "is this client's site
/// up right now?". A `HealthPulse` is one HTTP HEAD probe against a
/// project's host, captured as a Sendable Codable value that round-
/// trips through `HealthPulseStore` for persistence and through the
/// SwiftUI surfaces (ProjectCard status dot + ProjectDetailSheet
/// "Site Health" row).
///
/// Everything in this file stays *pure* — no HealthKit-style actor,
/// no URLSession call. The actual `URLSession.shared.dataTask`
/// invocation lives in the UI layer (or in a future
/// `HealthPulseProbe` actor) and folds its result through
/// `HealthClassifier.classify(...)`. That separation keeps the
/// classifier deterministically testable across every status-code
/// bucket without ever booting a fake network.
public struct HealthPulse: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let host: String
    public let checkedAt: Date
    public let statusCode: Int
    public let responseTimeMs: Int
    public let status: HealthStatus

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        host: String,
        checkedAt: Date = .now,
        statusCode: Int,
        responseTimeMs: Int,
        status: HealthStatus
    ) {
        self.id = id
        self.projectID = projectID
        self.host = host
        self.checkedAt = checkedAt
        self.statusCode = statusCode
        self.responseTimeMs = responseTimeMs
        self.status = status
    }
}

/// v1.0-alpha.8 — Discrete health bucket the UI dots colour-code.
///
/// - `.online`: HTTP 200-299 AND responseTime < degradedThresholdMs
/// - `.degraded`: HTTP 200-299 AND responseTime >= degradedThresholdMs,
///                OR HTTP 300-399 (redirect — site reachable but moved)
/// - `.error`: HTTP >= 400 (4xx/5xx — site reachable but broken)
/// - `.offline`: any transport-level failure (timeout, DNS, refused)
/// - `.unknown`: never probed yet
///
/// Ordering matters for `severityRank`: more-severe-first so the
/// Cockpit can sort "show me what's broken" without a custom
/// comparator at every call site.
public enum HealthStatus: String, Sendable, Codable, CaseIterable {
    case online
    case degraded
    case error
    case offline
    case unknown

    /// Lower rank = more critical. Used by `sortByCriticalFirst` so
    /// the "what's on fire" surface lands offline + error rows at
    /// the top, then degraded, then online, then unknown last.
    public var severityRank: Int {
        switch self {
        case .offline:  return 0
        case .error:    return 1
        case .degraded: return 2
        case .online:   return 3
        case .unknown:  return 4
        }
    }

    /// User-facing label key. Resolves to FR/EN through the host
    /// app's Localizable.xcstrings. Kept here (not at the call site)
    /// so the key namespace stays single-sourced.
    public var localizationKey: String {
        switch self {
        case .online:   return "health.status.online"
        case .degraded: return "health.status.degraded"
        case .error:    return "health.status.error"
        case .offline:  return "health.status.offline"
        case .unknown:  return "health.status.unknown"
        }
    }
}

/// v1.0-alpha.8 — Pure classifier — the load-bearing contract every
/// test pins. Maps `(statusCode, responseTimeMs)` to a `HealthStatus`
/// deterministically. The `degradedThresholdMs` default of 1500 ms
/// matches the v0.4 audit "performance" probe's "slow" cutoff, so the
/// dot's red/yellow/green stays consistent with the audit report.
public enum HealthClassifier {

    /// Threshold above which a 2xx response counts as `.degraded`
    /// rather than `.online`. Exposed as a parameter so future
    /// tuning (or per-project overrides) plug in without forking
    /// the function.
    public static let defaultDegradedThresholdMs: Int = 1500

    /// Sentinel returned by the probe layer when the transport itself
    /// failed (no HTTP status to read). Stored as -1 on the
    /// persisted record so the JSON round-trip stays lossless.
    public static let transportFailureStatusCode: Int = -1

    /// Pure mapping. Caller passes the raw HTTP status (or
    /// `transportFailureStatusCode` on a transport-level failure)
    /// and the measured wall-clock response time. Returns the
    /// `HealthStatus` to surface.
    public static func classify(
        statusCode: Int,
        responseTimeMs: Int,
        degradedThresholdMs: Int = defaultDegradedThresholdMs
    ) -> HealthStatus {
        if statusCode == transportFailureStatusCode {
            return .offline
        }
        if statusCode >= 200, statusCode < 300 {
            return responseTimeMs >= degradedThresholdMs ? .degraded : .online
        }
        if statusCode >= 300, statusCode < 400 {
            // Redirects: site is reachable but the configured host
            // points elsewhere. Surface as `.degraded` so the dot
            // turns yellow — a clue Mehdi should re-check the host
            // value on the Project row.
            return .degraded
        }
        if statusCode >= 400 {
            return .error
        }
        // Any other negative code or 0-199 weirdness — surface as
        // offline rather than crashing the dot. Defensive but never
        // hit in production paths.
        return .offline
    }
}

/// v1.0-alpha.8 — Pure helpers around `[HealthPulse]` sorting and
/// filtering. Kept namespace-style so callers can `HealthPulseHelpers
/// .sortByCriticalFirst(...)` without instantiating anything.
public enum HealthPulseHelpers {

    /// Sort by `severityRank` ascending (most critical first), then
    /// by `checkedAt` descending (newest first inside a bucket).
    /// Deterministic; no platform-locale dependency.
    public static func sortByCriticalFirst(_ pulses: [HealthPulse]) -> [HealthPulse] {
        return pulses.sorted { lhs, rhs in
            if lhs.status.severityRank != rhs.status.severityRank {
                return lhs.status.severityRank < rhs.status.severityRank
            }
            return lhs.checkedAt > rhs.checkedAt
        }
    }

    /// FR-locale-aware compact human label for how long ago a pulse
    /// fired. Uses `RelativeDateTimeFormatter`'s `.short` unit style
    /// so the ProjectCard's tight dot footprint stays readable.
    /// Lives here (not in the UI) so the same label surfaces on
    /// every device + every translated locale.
    public static func formatRelativeAge(
        _ checkedAt: Date,
        relativeTo now: Date = .now,
        locale: Locale = .current
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: checkedAt, relativeTo: now)
    }
}
