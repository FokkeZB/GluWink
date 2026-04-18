import SwiftUI
import WidgetKit

@main
struct WatchStatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchRectangularWidget()
        WatchMetricWidget()
    }
}
