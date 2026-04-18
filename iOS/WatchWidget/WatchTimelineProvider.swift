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

struct WatchRectangularTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> WatchEntry {
        WatchEntryBuilder.makeEntry(now: Date(), metric: .glucose)
    }

    func getSnapshot(in _: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(WatchEntryBuilder.makeEntry(now: Date(), metric: .glucose))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let now = Date()
        let entry = WatchEntryBuilder.makeEntry(now: now, metric: .glucose)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now) ?? now.addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
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
        let entry = WatchEntryBuilder.makeEntry(now: now, metric: configuration.metric)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now) ?? now.addingTimeInterval(300)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}
