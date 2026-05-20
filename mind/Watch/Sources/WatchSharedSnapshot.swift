import Foundation

/// v1.0-alpha.17 — Watch-side reader for the cockpit snapshot the
/// iPhone host pushes into the shared App Group
/// (`group.app.mind.ios`). Mirrors the keys
/// `WatchConnectivityBridge.SnapshotKey.*` writes so the Watch can
/// fall back to the cached value when `WCSession` is inactive (no
/// paired phone, app not running, Simulator).
///
/// Pure reader — never writes. The bridge owns the write side.
enum WatchSharedSnapshot {

    static let suiteName = WatchConnectivityBridge.appGroupSuiteName

    // MARK: - Leads

    /// Reads the JSON-encoded lead list the iPhone last pushed.
    /// Returns an empty array when the suite is empty, the JSON is
    /// malformed, or the App Group container couldn't be opened —
    /// every error path collapses to "no leads", which renders the
    /// empty-state CTA on the Watch.
    static func readLeads() -> [WatchLeadDigest] {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        guard
            let data = defaults.data(forKey: WatchConnectivityBridge.SnapshotKey.leads),
            let decoded = try? JSONDecoder().decode([WatchLeadDigest].self, from: data)
        else {
            return []
        }
        return decoded
    }

    /// Reads the JSON-encoded portfolio KPI the iPhone last pushed.
    /// Returns `.empty` on any read/decode failure.
    static func readPortfolio() -> WatchPortfolioKPI {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        guard
            let data = defaults.data(forKey: WatchConnectivityBridge.SnapshotKey.portfolio),
            let decoded = try? JSONDecoder().decode(WatchPortfolioKPI.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    /// Reads the focus-running flag the iPhone host toggles on
    /// `focus.start`/`focus.end` events the Watch dispatched.
    static func readFocusRunning() -> Bool {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return defaults.bool(forKey: WatchConnectivityBridge.SnapshotKey.focusRunning)
    }
}
