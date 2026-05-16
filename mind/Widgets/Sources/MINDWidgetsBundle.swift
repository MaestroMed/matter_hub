import WidgetKit
import SwiftUI

@main
struct MINDWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        QuickStatsWidget()
        // FocusLiveActivityWidget is added by the next commit so it can
        // ship with its Dynamic Island UI in one self-contained change.
    }
}
