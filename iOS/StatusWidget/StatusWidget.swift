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
    static let highGlucoseThreshold = Double(Bundle.main.object(forInfoDictionaryKey: "HighGlucoseThreshold") as! String)!
    static let lowGlucoseThreshold = Double(Bundle.main.object(forInfoDictionaryKey: "LowGlucoseThreshold") as! String)!
    static let glucoseStaleMinutes = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
    static let carbGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
    static let carbGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!

    static func makeEntry(now: Date, metric: MetricType) -> StatusEntry {
        let defaults = UserDefaults(suiteName: appGroupID)

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
            highGlucoseThreshold: highGlucoseThreshold,
            lowGlucoseThreshold: lowGlucoseThreshold,
            glucoseStaleMinutes: glucoseStaleMinutes,
            carbGraceHour: carbGraceHour,
            carbGraceMinute: carbGraceMinute,
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

// MARK: - Static provider (no configuration)

struct StatusTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> StatusEntry {
        EntryBuilder.makeEntry(now: Date(), metric: .glucose)
    }

    func getSnapshot(in _: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(EntryBuilder.makeEntry(now: Date(), metric: .glucose))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let now = Date()
        let entry = EntryBuilder.makeEntry(now: now, metric: .glucose)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Configurable provider (metric picker)

struct StatusIntentTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> StatusEntry {
        EntryBuilder.makeEntry(now: Date(), metric: .glucose)
    }

    func snapshot(for configuration: StatusWidgetIntent, in _: Context) async -> StatusEntry {
        EntryBuilder.makeEntry(now: Date(), metric: configuration.metric)
    }

    func timeline(for configuration: StatusWidgetIntent, in _: Context) async -> Timeline<StatusEntry> {
        let now = Date()
        let entry = EntryBuilder.makeEntry(now: now, metric: configuration.metric)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
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
