import Foundation
import SharedKit
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let content: ShieldContent
    let metric: MetricType
    let glucoseDate: Date?
    let carbDate: Date?
}
