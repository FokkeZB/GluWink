import SwiftUI

/// Visual-only tile bodies shared between the `StatusWidget` extension and
/// the App's screenshot showcase (`WidgetShowcaseView`). The widget extension
/// wraps each tile in `containerBackground(for: .widget)` to satisfy WidgetKit;
/// other callers apply a plain `.background` + `.clipShape`.
///
/// Keeping the visuals here — rather than duplicating into an App-only mock —
/// means the App Store screenshot can never drift from the real widget.

public struct WidgetTileContent {
    public let shieldContent: ShieldContent
    public let glucoseDate: Date?
    public let carbDate: Date?

    public init(shieldContent: ShieldContent, glucoseDate: Date?, carbDate: Date?) {
        self.shieldContent = shieldContent
        self.glucoseDate = glucoseDate
        self.carbDate = carbDate
    }
}

// MARK: - Shared helpers

private func widgetRelativeAgoText(from date: Date?, hasData: Bool) -> Text {
    guard hasData, let date else {
        return Text(String(localized: "widget.noData", bundle: .module))
    }
    return Text(date, style: .relative)
}

private func widgetGlucoseValue(_ c: ShieldContent) -> String {
    c.glucoseValue > 0 ? c.formattedGlucose : "--"
}

private func widgetGlucoseLabel(_ c: ShieldContent) -> String {
    "\(widgetGlucoseValue(c)) \(c.glucoseUnitLabel)"
}

private func widgetCarbsValue(_ c: ShieldContent) -> String {
    c.carbGrams.map { "\($0)" } ?? "--"
}

private func widgetCarbsLabel(_ c: ShieldContent) -> String {
    "\(widgetCarbsValue(c)) g"
}

// MARK: - Small tile

public struct SmallWidgetTile: View {
    public let content: WidgetTileContent

    public init(content: WidgetTileContent) {
        self.content = content
    }

    public var body: some View {
        let c = content.shieldContent
        VStack(alignment: .leading, spacing: 6) {
            Text(widgetGlucoseLabel(c))
                .font(.system(.title, design: .rounded).bold())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            widgetRelativeAgoText(from: content.glucoseDate, hasData: c.glucoseValue > 0)
                .font(.caption)
                .opacity(0.7)

            Spacer(minLength: 2)

            Text(widgetCarbsLabel(c))
                .font(.system(.title, design: .rounded).bold())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            widgetRelativeAgoText(from: content.carbDate, hasData: c.carbGrams != nil)
                .font(.caption)
                .opacity(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

// MARK: - Medium tile

public struct MediumWidgetTile: View {
    public let content: WidgetTileContent

    public init(content: WidgetTileContent) {
        self.content = content
    }

    public var body: some View {
        let c = content.shieldContent
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "widget.glucose", bundle: .module))
                    .font(.caption.bold())
                    .opacity(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(widgetGlucoseValue(c))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(c.glucoseUnit.shortLabel)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                }
                widgetRelativeAgoText(from: content.glucoseDate, hasData: c.glucoseValue > 0)
                    .font(.subheadline)
                    .opacity(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "widget.carbs", bundle: .module))
                    .font(.caption.bold())
                    .opacity(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(widgetCarbsValue(c))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("g")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                }
                widgetRelativeAgoText(from: content.carbDate, hasData: c.carbGrams != nil)
                    .font(.subheadline)
                    .opacity(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .frame(maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Large tile

public struct LargeWidgetTile: View {
    public let content: WidgetTileContent

    public init(content: WidgetTileContent) {
        self.content = content
    }

    public var body: some View {
        let c = content.shieldContent
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "widget.glucose", bundle: .module))
                    .font(.subheadline.bold())
                    .opacity(0.7)
                Text(widgetGlucoseLabel(c))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                widgetRelativeAgoText(from: content.glucoseDate, hasData: c.glucoseValue > 0)
                    .font(.subheadline)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "widget.carbs", bundle: .module))
                    .font(.subheadline.bold())
                    .opacity(0.7)
                Text(widgetCarbsLabel(c))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                widgetRelativeAgoText(from: content.carbDate, hasData: c.carbGrams != nil)
                    .font(.subheadline)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding()
    }
}
