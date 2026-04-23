import Foundation
import SharedKit
import WidgetKit

struct WatchEntry: TimelineEntry {
    let date: Date
    let content: ShieldContent
    let metric: WatchMetricType
    let glucoseDate: Date?
    let carbDate: Date?
}

enum WatchEntryBuilder {
    static func makeEntry(now: Date, metric: WatchMetricType) -> WatchEntry {
        WatchEntry(
            date: now,
            content: WatchDataManager.content(now: now),
            metric: metric,
            glucoseDate: WatchDataManager.glucoseFetchedAt,
            carbDate: WatchDataManager.lastCarbEntryAt
        )
    }
}

private enum WatchTimelinePolicy {
    /// Mirrors the iPhone StatusWidget cadence: short entries spaced one
    /// minute apart so the relative "X min ago" label visibly ages between
    /// iOS-driven reloads, with `.atEnd` to ask WatchOS for a fresh timeline
    /// as soon as the last entry is consumed.
    static let entryCount = 5
    static let entryInterval: TimeInterval = 60

    static func entries(from now: Date, build: (Date) -> WatchEntry) -> [WatchEntry] {
        (0..<entryCount).map { index in
            build(now.addingTimeInterval(TimeInterval(index) * entryInterval))
        }
    }
}

struct WatchRectangularTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> WatchEntry {
        WatchEntryBuilder.makeEntry(now: Date(), metric: .glucose)
    }

    func getSnapshot(in _: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(WatchEntryBuilder.makeEntry(now: Date(), metric: .glucose))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let now = Date()
        let entries = WatchTimelinePolicy.entries(from: now) { date in
            WatchEntryBuilder.makeEntry(now: date, metric: .glucose)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WatchMetricTimelineProvider: AppIntentTimelineProvider {
    func recommendations() -> [AppIntentRecommendation<WatchMetricIntent>] {
        [
            AppIntentRecommendation(
                intent: {
                    let intent = WatchMetricIntent()
                    intent.metric = .glucose
                    return intent
                }(),
                description: String(localized: "watch.widget.intent.glucose")
            ),
            AppIntentRecommendation(
                intent: {
                    let intent = WatchMetricIntent()
                    intent.metric = .carbs
                    return intent
                }(),
                description: String(localized: "watch.widget.intent.carbs")
            ),
        ]
    }

    func placeholder(in _: Context) -> WatchEntry {
        WatchEntryBuilder.makeEntry(now: Date(), metric: .glucose)
    }

    func snapshot(for configuration: WatchMetricIntent, in _: Context) async -> WatchEntry {
        WatchEntryBuilder.makeEntry(now: Date(), metric: configuration.metric)
    }

    func timeline(for configuration: WatchMetricIntent, in _: Context) async -> Timeline<WatchEntry> {
        let now = Date()
        let entries = WatchTimelinePolicy.entries(from: now) { date in
            WatchEntryBuilder.makeEntry(now: date, metric: configuration.metric)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}
