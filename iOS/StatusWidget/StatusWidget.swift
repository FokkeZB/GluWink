import SharedKit
import SwiftUI
import WidgetKit

// MARK: - Metric type

/// Which metric a Lock Screen tile renders. Shipped as a plain enum
/// (not `AppEnum`) because each metric has its own `Widget` with a
/// `StaticConfiguration` — there is no in-place picker. We deliberately
/// avoided `AppIntentConfiguration` here to mirror the watch split (see
/// `WatchMetricType` in WatchComplications.swift) and to give the user
/// a one-step gallery flow: pick "Glucose" or "Carbs" directly, no
/// two-step "pick the metric widget, then configure it" detour. Same
/// pattern that also sidesteps the `CHSError 1101` archiving bug we
/// saw on watch accessory families with `AppIntentConfiguration`.
enum MetricType {
    case glucose
    case carbs
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
    static let fallbackCriticalGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "CriticalGlucoseThreshold") as! String)!
    static let fallbackStaleMinutes = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
    static let fallbackCarbGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
    static let fallbackCarbGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!

    static func makeEntry(now: Date, metric: MetricType) -> StatusEntry {
        let defaults = appGroupDefaults

        // Per-source storage: resolve the winning glucose/carb readings
        // via `UnifiedDataReader` so widgets honour the Demo override
        // and freshest-enabled-source rule alongside the home screen
        // and shield UI.
        let glucoseReading = UnifiedDataReader.currentGlucoseReading(from: defaults)
        let carbsReading = UnifiedDataReader.currentCarbsReading(from: defaults)
        let glucoseDate = glucoseReading?.sampleAt
        let carbDate = carbsReading?.sampleAt

        let unit: GlucoseUnit = defaults?.string(forKey: "glucoseUnit")
            .flatMap { GlucoseUnit(rawValue: $0) } ?? .mmolL

        let carbsEnabled = defaults?.object(forKey: "carbsEnabled") as? Bool ?? true

        let strings = ShieldContent.Strings.fromPackage()

        let content = ShieldContent(
            glucose: glucoseReading?.mmol ?? 0,
            glucoseFetchedAt: glucoseDate,
            lastCarbGrams: carbsReading?.grams,
            lastCarbLabel: carbsReading?.label,
            lastCarbEntryAt: carbDate,
            highGlucoseThreshold: ThresholdResolver.highGlucose(defaults: defaults, fallback: fallbackHighGlucose),
            lowGlucoseThreshold: ThresholdResolver.lowGlucose(defaults: defaults, fallback: fallbackLowGlucose),
            criticalGlucoseThreshold: ThresholdResolver.criticalGlucose(defaults: defaults, fallback: fallbackCriticalGlucose),
            glucoseStaleMinutes: ThresholdResolver.staleMinutes(defaults: defaults, fallback: fallbackStaleMinutes),
            carbGraceHour: ThresholdResolver.carbGraceHour(defaults: defaults, fallback: fallbackCarbGraceHour),
            carbGraceMinute: ThresholdResolver.carbGraceMinute(defaults: defaults, fallback: fallbackCarbGraceMinute),
            carbsEnabled: carbsEnabled,
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
            await WidgetEasyViewRefresh.refreshIfDue(defaults: EntryBuilder.appGroupDefaults)
            completion(EntryBuilder.makeEntry(now: Date(), metric: .glucose))
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        Task {
            await WidgetNightscoutRefresh.refreshIfDue(defaults: EntryBuilder.appGroupDefaults)
            await WidgetEasyViewRefresh.refreshIfDue(defaults: EntryBuilder.appGroupDefaults)
            let now = Date()
            let entries = TimelinePolicy.entries(from: now) { date in
                EntryBuilder.makeEntry(now: date, metric: .glucose)
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }
}

// MARK: - Per-metric static provider

/// One provider instance per metric — the metric is fixed at the widget
/// declaration site rather than picked through an intent. Mirrors
/// `WatchMetricTimelineProvider` on the watch side.
struct StatusMetricTimelineProvider: TimelineProvider {
    let metric: MetricType

    func placeholder(in _: Context) -> StatusEntry {
        EntryBuilder.makeEntry(now: Date(), metric: metric)
    }

    func getSnapshot(in _: Context, completion: @escaping (StatusEntry) -> Void) {
        Task {
            await WidgetNightscoutRefresh.refreshIfDue(defaults: EntryBuilder.appGroupDefaults)
            await WidgetEasyViewRefresh.refreshIfDue(defaults: EntryBuilder.appGroupDefaults)
            completion(EntryBuilder.makeEntry(now: Date(), metric: metric))
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        Task {
            await WidgetNightscoutRefresh.refreshIfDue(defaults: EntryBuilder.appGroupDefaults)
            await WidgetEasyViewRefresh.refreshIfDue(defaults: EntryBuilder.appGroupDefaults)
            let now = Date()
            let entries = TimelinePolicy.entries(from: now) { date in
                EntryBuilder.makeEntry(now: date, metric: metric)
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
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

// MARK: - Metric widgets (circular + inline Lock Screen — one per metric)
//
// One `StaticConfiguration` widget per metric instead of a single
// `AppIntentConfiguration` with a picker. Same rationale as the watch
// split: cleaner gallery UX ("Glucose" / "Carbs" pickable directly,
// no two-step configure detour) and forward-only — we don't ship an
// intent we'd then have to migrate away from later.

struct StatusGlucoseWidget: Widget {
    let kind: String = "StatusGlucoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusMetricTimelineProvider(metric: .glucose)) { entry in
            StatusMetricEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.glucoseTitle"))
        .description(String(localized: "widget.glucoseDescription"))
        .supportedFamilies([
            .accessoryCircular, .accessoryInline,
        ])
    }
}

struct StatusCarbsWidget: Widget {
    let kind: String = "StatusCarbsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusMetricTimelineProvider(metric: .carbs)) { entry in
            StatusMetricEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.carbsTitle"))
        .description(String(localized: "widget.carbsDescription"))
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
