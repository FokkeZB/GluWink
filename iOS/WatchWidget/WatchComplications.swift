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
        return entry.content.glucose != nil
    case .carbs:
        return entry.content.carbs != nil
    }
}

private func metricValue(_ entry: WatchEntry) -> String {
    switch entry.metric {
    case .glucose:
        return entry.content.glucose?.formatted ?? "--"
    case .carbs:
        guard let carbs = entry.content.carbs else { return "--" }
        if let grams = carbs.grams { return String(grams) }
        return carbs.label ?? "·"
    }
}

private func metricUnit(_ entry: WatchEntry) -> String {
    switch entry.metric {
    case .glucose:
        return entry.content.glucoseUnit.shortLabel
    case .carbs:
        return entry.content.carbs?.grams != nil ? "g" : ""
    }
}

private func metricAttentionLevel(_ entry: WatchEntry) -> AttentionLevel {
    entry.content.attentionLevel(forGlucose: entry.metric == .glucose)
}

/// Minutes-since-sample for the metric this widget is rendering. `nil`
/// when there is no reading (no source has delivered yet, or the source
/// is disabled). Pre-computed in `ShieldContent.init` against the entry's
/// `now`, so the timeline producing 1-minute-spaced entries gives us a
/// fresh value per render without wall-clock drift.
private func metricAgoMinutes(_ entry: WatchEntry) -> Int? {
    switch entry.metric {
    case .glucose: return entry.content.glucose?.agoMinutes
    case .carbs: return entry.content.carbs?.agoMinutes
    }
}

/// Compact "X ago" string for the corner complication slot, which has
/// room for ~3 characters max. We deliberately drop the localised "ago"
/// / "geleden" suffix used elsewhere — the corner context implies it,
/// and the suffix would push the string past what fits in a curved
/// corner. Hours collapse to whole units (`"1h"`, `"2h"`) for the same
/// reason; the more precise `"1h 30m"` form lives on the rectangular
/// tile where there's space for it.
private func shortAgoText(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h"
}

private func relativeAgoText(from date: Date?) -> Text {
    guard let date else { return Text(String(localized: "watch.widget.noData")) }
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
        let glucoseText = content.glucose?.formatted ?? "--"
        let carbsText: String = {
            guard let carbs = content.carbs else { return "--" }
            if let grams = carbs.grams { return String(grams) }
            return carbs.label ?? "·"
        }()
        let carbsUnit = content.carbs?.grams != nil ? "g" : ""

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: content.glucoseNeedsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption.bold())
                Text("\(glucoseText) \(content.glucoseUnit.shortLabel)")
                    .font(.system(.headline, design: .rounded).bold())
                Spacer(minLength: 4)
                relativeAgoText(from: content.glucose?.sampleDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: content.carbsNeedsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption.bold())
                Text(carbsUnit.isEmpty ? carbsText : "\(carbsText) \(carbsUnit)")
                    .font(.system(.headline, design: .rounded).bold())
                Spacer(minLength: 4)
                relativeAgoText(from: content.carbs?.sampleDate)
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
        ZStack {
            // Filled `Circle()` inside the widget body, not via
            // `containerBackground`, so the coloured disk is part of the
            // widget's own content. Several watch faces (Chronograph Pro
            // observed in testing — see https://github.com/FokkeZB/GluWink/pull/119
            // thread) draw their own chrome around the subdial slot and
            // don't surface the widget's container backdrop, leaving the
            // tile looking flat black. Filling a literal circle sidesteps
            // that entirely: the brand tint always shows up regardless of
            // what the face does with the slot.
            Circle().fill(metricAttentionLevel(entry).tint)

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
        }
        // WidgetKit still requires a `containerBackground` declaration on
        // every entry view. We set it `.clear` because the visible
        // colouring is owned by the `Circle()` above; without this, the
        // widget refuses to render in `accessoryCircular` on watchOS.
        .containerBackground(.clear, for: .widget)
    }
}

struct WatchAccessoryCornerView: View {
    let entry: WatchEntry

    var body: some View {
        let tint = metricAttentionLevel(entry).tint

        // Corner content is the "X ago" timestamp (or a warning triangle
        // when there is no reading at all). The metric-identifying icon
        // (drop / fork) used to live here, but the value itself is
        // already in the bezel `widgetLabel` — duplicating "this is
        // glucose" in the corner just spent the slot's tightest pixels
        // on metadata the user could already infer from the number. The
        // age of the sample is far more useful at a glance: a fresh
        // reading vs. a 45-minute-old one is information you can't get
        // anywhere else on the watch face.
        Group {
            if let mins = metricAgoMinutes(entry) {
                Text(shortAgoText(mins))
                    .font(.system(.body, design: .rounded).bold())
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
            }
        }
        .foregroundStyle(tint)
        .widgetLabel {
            Text(metricHasData(entry)
                ? "\(metricValue(entry)) \(metricUnit(entry))"
                : String(localized: "watch.widget.noData"))
        }
    }
}
