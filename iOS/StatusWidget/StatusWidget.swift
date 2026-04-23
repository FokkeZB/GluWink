import AppIntents
import SharedKit
import SwiftUI
import WidgetKit

// MARK: - Configuration Intent

enum MetricType: String, AppEnum {
    case glucose
    case carbs

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("widget.intent.metricType", defaultValue: "Metric"))
    static var caseDisplayRepresentations: [MetricType: DisplayRepresentation] = [
        .glucose: DisplayRepresentation(title: LocalizedStringResource("widget.intent.glucose", defaultValue: "Glucose")),
        .carbs: DisplayRepresentation(title: LocalizedStringResource("widget.intent.carbs", defaultValue: "Carbs")),
    ]
}

struct StatusWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Status"
    static var description = IntentDescription(LocalizedStringResource("widget.intent.description", defaultValue: "Shows glucose or carb status."))

    @Parameter(title: LocalizedStringResource("widget.intent.metricType", defaultValue: "Metric"), default: .glucose)
    var metric: MetricType
}

// MARK: - Shared entry builder

private enum EntryBuilder {
    static let appGroupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as! String
    /// Shared accessor so the timeline providers and the entry builder read
    /// from the exact same suite — `WidgetNightscoutRefresh` writes here too.
    static let appGroupDefaults = UserDefaults(suiteName: appGroupID)
    /// xcconfig fallbacks for when no user override has been written to the
    /// App Group yet. The resolver picks override-or-fallback per render.
    static let fallbackHighGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "HighGlucoseThreshold") as! String)!
    static let fallbackLowGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "LowGlucoseThreshold") as! String)!
    static let fallbackStaleMinutes = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
    static let fallbackCarbGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
    static let fallbackCarbGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!

    static func makeEntry(now: Date, metric: MetricType) -> StatusEntry {
        let defaults = appGroupDefaults

        let glucose = defaults?.double(forKey: "currentGlucose") ?? 0
        let glucoseDate = defaults?.string(forKey: "glucoseFetchedAt")
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        let carbGrams = defaults?.double(forKey: "lastCarbGrams") ?? 0
        let carbDate = defaults?.string(forKey: "lastCarbEntryAt")
            .flatMap { ISO8601DateFormatter().date(from: $0) }

        let unit: GlucoseUnit = defaults?.string(forKey: "glucoseUnit")
            .flatMap { GlucoseUnit(rawValue: $0) } ?? .mmolL

        let strings = ShieldContent.Strings.fromPackage()

        let content = ShieldContent(
            glucose: glucose,
            glucoseFetchedAt: glucoseDate,
            lastCarbGrams: carbGrams > 0 ? carbGrams : nil,
            lastCarbEntryAt: carbDate,
            highGlucoseThreshold: ThresholdResolver.highGlucose(defaults: defaults, fallback: fallbackHighGlucose),
            lowGlucoseThreshold: ThresholdResolver.lowGlucose(defaults: defaults, fallback: fallbackLowGlucose),
            glucoseStaleMinutes: ThresholdResolver.staleMinutes(defaults: defaults, fallback: fallbackStaleMinutes),
            carbGraceHour: ThresholdResolver.carbGraceHour(defaults: defaults, fallback: fallbackCarbGraceHour),
            carbGraceMinute: ThresholdResolver.carbGraceMinute(defaults: defaults, fallback: fallbackCarbGraceMinute),
            glucoseUnit: unit,
            strings: strings,
            now: now
        )

        return StatusEntry(
            date: now,
            content: content,
            metric: metric,
            glucoseDate: glucoseDate,
            carbDate: carbDate
        )
    }
}

// MARK: - Timeline policy

private enum TimelinePolicy {
    /// Number of entries returned per timeline. Spaced one minute apart so
    /// the relative "X min ago" labels in `WidgetTileViews` visibly age
    /// between iOS-driven reloads. iOS picks the next entry from the
    /// timeline as the wall clock crosses each entry's date — no extra
    /// process wakeups needed.
    static let entryCount = 5

    /// Spacing between successive entries.
    static let entryInterval: TimeInterval = 60

    /// Build a `[entryCount]`-long timeline starting at `now`, all sharing
    /// the same content snapshot. The shared content is correct because
    /// `ShieldContent.attentionState(now:)` re-evaluates against each entry's
    /// `date` at render time — the only thing that changes per entry is the
    /// "minutes ago" labels.
    static func entries(from now: Date, build: (Date) -> StatusEntry) -> [StatusEntry] {
        (0..<entryCount).map { index in
            build(now.addingTimeInterval(TimeInterval(index) * entryInterval))
        }
    }
}

// MARK: - Static provider (no configuration)

struct StatusTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> StatusEntry {
        EntryBuilder.makeEntry(now: Date(), metric: .glucose)
    }

    func getSnapshot(in _: Context, completion: @escaping (StatusEntry) -> Void) {
        Task {
            await WidgetNightscoutRefresh.refreshIfDue(defaults: EntryBuilder.appGroupDefaults)
            completion(EntryBuilder.makeEntry(now: Date(), metric: .glucose))
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        Task {
            await WidgetNightscoutRefresh.refreshIfDue(defaults: EntryBuilder.appGroupDefaults)
            let now = Date()
            let entries = TimelinePolicy.entries(from: now) { date in
                EntryBuilder.makeEntry(now: date, metric: .glucose)
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }
}

// MARK: - Configurable provider (metric picker)

struct StatusIntentTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> StatusEntry {
        EntryBuilder.makeEntry(now: Date(), metric: .glucose)
    }

    func snapshot(for configuration: StatusWidgetIntent, in _: Context) async -> StatusEntry {
        await WidgetNightscoutRefresh.refreshIfDue(defaults: EntryBuilder.appGroupDefaults)
        return EntryBuilder.makeEntry(now: Date(), metric: configuration.metric)
    }

    func timeline(for configuration: StatusWidgetIntent, in _: Context) async -> Timeline<StatusEntry> {
        await WidgetNightscoutRefresh.refreshIfDue(defaults: EntryBuilder.appGroupDefaults)
        let now = Date()
        let entries = TimelinePolicy.entries(from: now) { date in
            EntryBuilder.makeEntry(now: date, metric: configuration.metric)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Main widget (Home Screen + rectangular Lock Screen — shows both metrics, no config)

struct StatusWidget: Widget {
    let kind: String = "StatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusTimelineProvider()) { entry in
            StatusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "GluWink")
        .description(String(localized: "widget.description"))
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular,
        ])
    }
}

// MARK: - Metric widget (circular + inline Lock Screen — configurable glucose or carbs)

struct StatusMetricWidget: Widget {
    let kind: String = "StatusMetricWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: StatusWidgetIntent.self, provider: StatusIntentTimelineProvider()) { entry in
            StatusMetricEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.metricTitle"))
        .description(String(localized: "widget.metricDescription"))
        .supportedFamilies([
            .accessoryCircular, .accessoryInline,
        ])
    }
}

// MARK: - Entry views

struct StatusWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: StatusEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

struct StatusMetricEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: StatusEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            AccessoryInlineView(entry: entry)
        default:
            AccessoryCircularView(entry: entry)
        }
    }
}
