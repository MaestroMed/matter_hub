import WidgetKit
import SwiftUI

@main
struct MINDWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        QuickStatsWidget()
        FocusLiveActivityWidget()
    }
}
