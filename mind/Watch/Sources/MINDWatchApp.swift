import SwiftUI

/// v1.0-alpha.17 — MIND Apple Watch companion app entry point.
///
/// The watchOS surface is a wrist-sized cockpit: three vertical-page
/// tabs that mirror the most-glanceable slices of the iPhone host —
/// the lead inbox (1), a Focus pomodoro launcher (2), and a portfolio
/// KPI glance (3). All three tabs read the same `mind.watch.*` keys
/// the iPhone host writes into the shared App Group
/// (`group.app.mind.ios`), so the Watch never blocks on the iPhone
/// being reachable.
///
/// Live updates ride over `WCSession` via `WatchConnectivityBridge`,
/// but the Watch always falls back to the App Group snapshot when the
/// session is inactive — same offline-first contract the iOS 26 Lock
/// Screen widgets follow (v1.0-alpha.16).
@main
struct MINDWatchApp: App {

    /// v1.0-alpha.17 — Subscribes the Watch side to incoming
    /// `WCSession.didReceiveMessage` payloads on app launch so a
    /// fresh `leads`/`portfolio` snapshot from the iPhone hydrates
    /// the local App Group cache before the user opens a tab.
    init() {
        WatchConnectivityBridge.shared.activateWatchSide()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

/// v1.0-alpha.17 — Root container. `verticalPage` is the watchOS 11+
/// idiom for a 3-tab cockpit where every tab is a self-contained
/// vertical column the user flicks through with the Digital Crown.
struct WatchRootView: View {
    var body: some View {
        TabView {
            WatchLeadInbox()
            WatchFocusView()
            WatchPortfolioGlance()
        }
        .tabViewStyle(.verticalPage)
    }
}
