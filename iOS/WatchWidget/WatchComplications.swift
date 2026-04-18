import AppIntents
import SharedKit
import SwiftUI
import WidgetKit

enum WatchMetricType: String, AppEnum {
    case glucose
    case carbs

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("watch.widget.intent.metricType", defaultValue: "Metric")
    )

    static var caseDisplayRepresentations: [WatchMetricType: DisplayRepresentation] = [
        .glucose: DisplayRepresentation(title: LocalizedStringResource("watch.widget.intent.glucose", defaultValue: "Glucose")),
        .carbs: DisplayRepresentation(title: LocalizedStringResource("watch.widget.intent.carbs", defaultValue: "Carbs")),
    ]
}

struct WatchMetricIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "GluWink"
    static var description = IntentDescription(
        LocalizedStringResource("watch.widget.intent.description", defaultValue: "Choose which metric to show.")
    )

    @Parameter(
        title: LocalizedStringResource("watch.widget.intent.metricType", defaultValue: "Metric"),
        default: .glucose
    )
    var metric: WatchMetricType
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

private func metricNeedsAttention(_ entry: WatchEntry) -> Bool {
    switch entry.metric {
    case .glucose:
        return entry.content.glucoseNeedsAttention
    case .carbs:
        return entry.content.carbsNeedsAttention
    }
}

private func relativeAgoText(from date: Date?, hasData: Bool) -> Text {
    guard hasData, let date else { return Text(String(localized: "watch.widget.noData")) }
    return Text(date, style: .relative)
}

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

struct WatchMetricWidget: Widget {
    let kind = "WatchMetricWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WatchMetricIntent.self, provider: WatchMetricTimelineProvider()) { entry in
            WatchMetricEntryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "watch.widget.metricTitle"))
        .description(String(localized: "watch.widget.metricDescription"))
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
            content.needsAttention ? Color.red : Color.green
        }
    }
}

struct WatchAccessoryCircularView: View {
    let entry: WatchEntry

    var body: some View {
        ZStack {
            Circle()
                .fill(metricNeedsAttention(entry) ? Color.red : Color.green)
            VStack(spacing: -3) {
                Text(metricValue(entry))
                    .font(.system(.title3, design: .rounded).bold())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(metricUnit(entry))
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct WatchAccessoryCornerView: View {
    let entry: WatchEntry

    private var statusColor: Color {
        metricNeedsAttention(entry) ? .red : .green
    }

    var body: some View {
        EmptyView()
            .widgetLabel {
                Text("\(metricValue(entry)) \(metricUnit(entry))")
                    .foregroundStyle(statusColor)
                    .widgetCurvesContent()
            }
    }
}
