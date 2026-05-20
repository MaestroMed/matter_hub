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
        FocusLiveActivityWidget()
    }
}
