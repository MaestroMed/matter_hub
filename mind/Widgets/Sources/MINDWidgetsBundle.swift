import WidgetKit
import SwiftUI

@main
struct MINDWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        QuickStatsWidget()
        // v0.27.1 — Lock Screen widgets (circular / rectangular /
        // inline accessory families). Pulls the same `Node` graph
        // count `QuickStatsWidget` reads, then surfaces it at a
        // glance inside the Lock Screen / StandBy / Always-On
        // chrome. Tapping deep-links to `mind://lock`.
        LockScreenWidget()
        // v1.0-alpha.16 — Cockpit Lock Screen widget. Reads the new
        // cockpit data spine (`Lead` + `Project` from v1.0-alpha.2)
        // and surfaces the new-lead count + most-recent contact +
        // portfolio MRR on the `.accessoryRectangular` +
        // `.accessoryInline` families. Tapping deep-links to
        // `mind://leads`, which routes back to HomeView's lead inbox.
        CockpitLockScreenWidget()
        FocusLiveActivityWidget()
        // v1.0-alpha.16 — Three fresh iOS 26 Lock Screen widgets +
        // a `.systemLarge` StandBy dashboard. All four read from
        // the App Group suite (`group.app.mind.ios`) that the host
        // App refreshes on every `.active` scene phase via
        // `SharedSnapshotWriter`. Each Lock Screen widget supports a
        // single accessory family so the picker shows them as
        // discrete tiles; the StandBy widget surfaces a two-column
        // cockpit (lead inbox left, portfolio KPI right) optimised
        // for the bedside dock at night.
        LeadInboxLockScreenWidget()
        PortfolioMRRLockScreenWidget()
        DeploymentStatusLockScreenWidget()
        StandByDashboardWidget()
    }
}
