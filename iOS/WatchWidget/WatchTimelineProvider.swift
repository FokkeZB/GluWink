import Foundation
import SharedKit
import WidgetKit

struct WatchEntry: TimelineEntry {
    let date: Date
    let content: ShieldContent
    let metric: WatchMetricType
    let glucoseDate: Date?
    let carbDate: Date?
    /// Smart Stack relevance hint. WatchOS 10+ surfaces widgets with the
    /// highest valid relevance score in the swipe-up Smart Stack. Set on
    /// every entry from `WatchRelevanceScorer` so the rectangular tile
    /// (`.accessoryRectangular`, the family Smart Stack consumes) floats
    /// to the top when glucose goes critical / attention.
    let relevance: TimelineEntryRelevance?
}

/// Maps `AttentionLevel` onto the Smart Stack relevance score the system
/// uses to rank widgets in its swipe-up panel. Single source of truth so
/// the rectangular and metric providers can't drift, and so the mapping
/// is reviewable in one place if the brand-meaning of the levels ever
/// shifts.
///
/// | Level        | Score | Why                                            |
/// |--------------|-------|------------------------------------------------|
/// | `.critical`  | 100   | Glucose ≥ critical threshold — must surface.   |
/// | `.attention` | 50    | High / low / stale / carb gap / no data.       |
/// | `.clear`     | 10    | All clear — present, but easy to demote.       |
///
/// `validity` matches the timeline's covered window (5 entries × 60 s) so
/// a single attention sample stays boost-eligible across the whole
/// cycle, even if WatchOS defers the next reload past the schedule we
/// hand it. Scores overlap by design — Smart Stack picks the highest
/// valid entry at any moment.
enum WatchRelevanceScorer {
    static let validity: TimeInterval = 5 * 60

    static func score(for level: AttentionLevel) -> Float {
        switch level {
        case .critical: return 100
        case .attention: return 50
        case .clear: return 10
        }
    }

    static func relevance(for level: AttentionLevel) -> TimelineEntryRelevance {
        TimelineEntryRelevance(score: score(for: level), duration: validity)
    }
}

enum WatchEntryBuilder {
    static func makeEntry(now: Date, metric: WatchMetricType) -> WatchEntry {
        let content = WatchDataManager.content(now: now)
        return WatchEntry(
            date: now,
            content: content,
            metric: metric,
            glucoseDate: WatchDataManager.glucoseFetchedAt,
            carbDate: WatchDataManager.lastCarbEntryAt,
            relevance: WatchRelevanceScorer.relevance(for: content.attentionLevel)
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
