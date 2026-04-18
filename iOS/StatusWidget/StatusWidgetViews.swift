import SharedKit
import SwiftUI
import WidgetKit

// MARK: - Shared helpers

private func relativeAgoText(from date: Date?, hasData: Bool) -> Text {
    guard hasData, let date else { return Text(String(localized: "widget.noData")) }
    return Text(date, style: .relative)
}

private func glucoseLabel(_ content: ShieldContent, compact: Bool = false) -> String {
    let value = content.glucoseValue > 0 ? content.formattedGlucose : "--"
    return compact ? value : "\(value) \(content.glucoseUnitLabel)"
}

private func glucoseValue(_ content: ShieldContent) -> String {
    content.glucoseValue > 0 ? content.formattedGlucose : "--"
}

private func carbsValue(_ content: ShieldContent) -> String {
    content.carbGrams.map { "\($0)" } ?? "--"
}

private func carbsLabel(_ content: ShieldContent, compact: Bool = false) -> String {
    let value = carbsValue(content)
    return compact ? "\(value)g" : "\(value) g"
}

// MARK: - Accessory / Lock Screen widgets

struct AccessoryCircularView: View {
    let entry: StatusEntry
    private var c: ShieldContent { entry.content }

    private var needsAttention: Bool {
        entry.metric == .glucose ? c.glucoseNeedsAttention : c.carbsNeedsAttention
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -3) {
                Text(entry.metric == .glucose ? glucoseValue(c) : carbsValue(c))
                    .font(.system(.title3, design: .rounded).bold())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(entry.metric == .glucose ? c.glucoseUnit.shortLabel : "g")
                    .font(.system(.caption2, design: .rounded))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(needsAttention ? .red : .green)
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct AccessoryRectangularView: View {
    let entry: StatusEntry
    private var c: ShieldContent { entry.content }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Glucose row
            HStack(spacing: 4) {
                Image(systemName: c.glucoseNeedsAttention ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption2.bold())
                    .widgetAccentable()
                HStack(spacing: 2) {
                    Text(glucoseValue(c))
                        .font(.system(.headline, design: .rounded).bold())
                    Text(c.glucoseUnit.shortLabel)
                        .font(.caption2)
                }
                .lineLimit(1)
                relativeAgoText(from: entry.glucoseDate, hasData: c.glucoseValue > 0)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Carbs row
            HStack(spacing: 4) {
                Image(systemName: c.carbsNeedsAttention ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption2.bold())
                    .widgetAccentable()
                HStack(spacing: 2) {
                    Text(carbsValue(c))
                        .font(.system(.headline, design: .rounded).bold())
                    Text("g")
                        .font(.caption2)
                }
                .lineLimit(1)
                relativeAgoText(from: entry.carbDate, hasData: c.carbGrams != nil)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
    }
}

struct AccessoryInlineView: View {
    let entry: StatusEntry
    private var c: ShieldContent { entry.content }

    private var needsAttention: Bool {
        entry.metric == .glucose ? c.glucoseNeedsAttention : c.carbsNeedsAttention
    }

    var body: some View {
        let icon = needsAttention ? "exclamationmark.triangle" : "checkmark.circle"
        let text = entry.metric == .glucose ? glucoseLabel(c, compact: true) : carbsLabel(c, compact: true)
        Label(text, systemImage: icon)
            .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Home Screen widgets

struct SmallWidgetView: View {
    let entry: StatusEntry
    private var c: ShieldContent { entry.content }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Glucose
            Text(glucoseLabel(c))
                .font(.system(.title, design: .rounded).bold())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            relativeAgoText(from: entry.glucoseDate, hasData: c.glucoseValue > 0)
                .font(.caption)
                .opacity(0.7)

            Spacer(minLength: 2)

            // Carbs
            Text(carbsLabel(c))
                .font(.system(.title, design: .rounded).bold())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            relativeAgoText(from: entry.carbDate, hasData: c.carbGrams != nil)
                .font(.caption)
                .opacity(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .containerBackground(for: .widget) {
            c.needsAttention ? Color.red : Color.green
        }
    }
}

struct MediumWidgetView: View {
    let entry: StatusEntry
    private var c: ShieldContent { entry.content }

    var body: some View {
        HStack(spacing: 0) {
            // Glucose column
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "widget.glucose"))
                    .font(.caption.bold())
                    .opacity(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(glucoseValue(c))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(c.glucoseUnit.shortLabel)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                }
                relativeAgoText(from: entry.glucoseDate, hasData: c.glucoseValue > 0)
                    .font(.subheadline)
                    .opacity(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Carbs column
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "widget.carbs"))
                    .font(.caption.bold())
                    .opacity(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(carbsValue(c))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("g")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                }
                relativeAgoText(from: entry.carbDate, hasData: c.carbGrams != nil)
                    .font(.subheadline)
                    .opacity(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .frame(maxHeight: .infinity)
        .padding()
        .containerBackground(for: .widget) {
            c.needsAttention ? Color.red : Color.green
        }
    }
}

struct LargeWidgetView: View {
    let entry: StatusEntry
    private var c: ShieldContent { entry.content }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Glucose section
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "widget.glucose"))
                    .font(.subheadline.bold())
                    .opacity(0.7)
                Text(glucoseLabel(c))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                relativeAgoText(from: entry.glucoseDate, hasData: c.glucoseValue > 0)
                    .font(.subheadline)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            // Carbs section
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "widget.carbs"))
                    .font(.subheadline.bold())
                    .opacity(0.7)
                Text(carbsLabel(c))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                relativeAgoText(from: entry.carbDate, hasData: c.carbGrams != nil)
                    .font(.subheadline)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding()
        .containerBackground(for: .widget) {
            c.needsAttention ? Color.red : Color.green
        }
    }
}
