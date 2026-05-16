import SharedKit
import SwiftUI
import WidgetKit

/// Which metric a complication renders. Shipped as a plain enum (not
/// `AppEnum`) because each metric has its own `Widget` with a
/// `StaticConfiguration` — there is no in-place picker. We deliberately
/// avoided `AppIntentConfiguration` here after `WidgetMetricWidget` +
/// `accessoryCircular`/`accessoryCorner` reliably produced `CHSError
/// 1101 "Returned view collection was either nil or empty"` on
/// watchOS 26 (see https://github.com/FokkeZB/GluWink/pull/119 thread).
/// Splitting into one widget per metric is also clearer in the gallery:
/// the user picks "Glucose" or "Carbs" directly, no two-step "pick the
/// metric widget, then configure it" flow.
enum WatchMetricType {
    case glucose
    case carbs
}

private func metricHasData(_ entry: WatchEntry) -> Bool {
    switch entry.metric {
    case .glucose:
        return entry.content.glucoseValue > 0
    case .carbs:
        return entry.content.carbGrams != nil
    }
}

private func metricValue(_ entry: WatchEntry) -> String {
    switch entry.metric {
    case .glucose:
        return entry.content.glucoseValue > 0 ? entry.content.formattedGlucose : "--"
    case .carbs:
        return entry.content.carbGrams.map(String.init) ?? "--"
    }
}

private func metricUnit(_ entry: WatchEntry) -> String {
    switch entry.metric {
    case .glucose:
        return entry.content.glucoseUnit.shortLabel
    case .carbs:
        return "g"
    }
}

private func metricAttentionLevel(_ entry: WatchEntry) -> AttentionLevel {
    entry.content.attentionLevel(forGlucose: entry.metric == .glucose)
}

private func relativeAgoText(from date: Date?, hasData: Bool) -> Text {
    guard hasData, let date else { return Text(String(localized: "watch.widget.noData")) }
    return Text(date, style: .relative)
}

/// Doubles as a watch-face complication and as a Smart Stack tile on
/// watchOS 10+. The `.accessoryRectangular` family is what Smart Stack
/// consumes in its swipe-up panel, so a single widget covers both
/// surfaces — we stay forward-only (one source of truth) and lean on
/// `TimelineEntryRelevance` (set by `WatchEntryBuilder`) to ask Smart
/// Stack to float us up when glucose actually needs the user's
/// attention. See `WatchRelevanceScorer` for the score → level mapping.
struct WatchRectangularWidget: Widget {
    let kind = "WatchStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchRectangularTimelineProvider()) { entry in
            WatchRectangularEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "watch.widget.rectangularTitle"))
        .description(String(localized: "watch.widget.rectangularDescription"))
        .supportedFamilies([.accessoryRectangular])
    }
}

struct WatchGlucoseWidget: Widget {
    let kind = "WatchGlucoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchMetricTimelineProvider(metric: .glucose)) { entry in
            WatchMetricEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "watch.widget.glucoseTitle"))
        .description(String(localized: "watch.widget.glucoseDescription"))
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct WatchCarbsWidget: Widget {
    let kind = "WatchCarbsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchMetricTimelineProvider(metric: .carbs)) { entry in
            WatchMetricEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "watch.widget.carbsTitle"))
        .description(String(localized: "watch.widget.carbsDescription"))
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct WatchMetricEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    var body: some View {
        switch family {
        case .accessoryCorner:
            WatchAccessoryCornerView(entry: entry)
        default:
            WatchAccessoryCircularView(entry: entry)
        }
    }
}

struct WatchRectangularEntryView: View {
    let entry: WatchEntry

    var body: some View {
        let content = entry.content

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: content.glucoseNeedsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption.bold())
                Text("\(content.formattedGlucose) \(content.glucoseUnit.shortLabel)")
                    .font(.system(.headline, design: .rounded).bold())
                Spacer(minLength: 4)
                relativeAgoText(from: entry.glucoseDate, hasData: content.glucoseValue > 0)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: content.carbsNeedsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption.bold())
                Text("\(content.carbGrams.map(String.init) ?? "--") g")
                    .font(.system(.headline, design: .rounded).bold())
                Spacer(minLength: 4)
                relativeAgoText(from: entry.carbDate, hasData: content.carbGrams != nil)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) {
            content.attentionLevel.tint
        }
    }
}

struct WatchAccessoryCircularView: View {
    let entry: WatchEntry

    var body: some View {
        Group {
            if metricHasData(entry) {
                VStack(spacing: -3) {
                    Text(metricValue(entry))
                        .font(.system(.title3, design: .rounded).bold())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(metricUnit(entry))
                        .font(.system(.caption2, design: .rounded))
                        .fontWeight(.semibold)
                }
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2.bold())
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            metricAttentionLevel(entry).tint
        }
    }
}

struct WatchAccessoryCornerView: View {
    let entry: WatchEntry

    private var metricSymbol: String {
        switch entry.metric {
        case .glucose: return "drop.fill"
        case .carbs: return "fork.knife"
        }
    }

    var body: some View {
        let hasData = metricHasData(entry)
        let tint = metricAttentionLevel(entry).tint

        Image(systemName: hasData ? metricSymbol : "exclamationmark.triangle.fill")
            .foregroundStyle(tint)
            .widgetLabel {
                Text(hasData
                    ? "\(metricValue(entry)) \(metricUnit(entry))"
                    : String(localized: "watch.widget.noData"))
            }
    }
}
