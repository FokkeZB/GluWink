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

/// Two-line stack used by the medium and large home-screen tiles — relative
/// age on top, absolute time directly below, no separator. Stacking (vs. a
/// single "5 min ago · 13:42" line) lets us drop the "Glucose" / "Carbs"
/// header labels on those tiles: the big value is already self-explanatory
/// once you know the widget, and reclaiming that row gives the absolute
/// time enough vertical room to be glanceable. `.time` style lets SwiftUI
/// pick locale-appropriate 12/24h formatting for free.
@ViewBuilder
private func widgetStackedTime(from date: Date?, hasData: Bool) -> some View {
    if hasData, let date {
        VStack(alignment: .leading, spacing: 0) {
            Text(date, style: .relative)
            Text(date, style: .time)
        }
    } else {
        Text(String(localized: "widget.noData", bundle: .module))
    }
}

/// Value + unit pair (e.g. "115" "mg/dL" or "25" "g") rendered with a bold
/// value and a proportionally smaller, semibold unit at 70% opacity. All
/// three tile sizes funnel through this helper so the unit's visual weight
/// stays consistent — bold white value dominates, the unit recedes to a
/// subtle label that matches the styling of the relative/absolute time
/// below it.
private func widgetValueWithUnit(
    value: String,
    unit: String,
    valueFont: Font,
    unitFont: Font
) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(value)
            .font(valueFont)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        Text(unit)
            .font(unitFont)
            .opacity(0.7)
    }
}

private func widgetGlucoseValue(_ c: ShieldContent) -> String {
    c.glucoseValue > 0 ? c.formattedGlucose : "--"
}

private func widgetCarbsValue(_ c: ShieldContent) -> String {
    c.carbGrams.map { "\($0)" } ?? "--"
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
            widgetValueWithUnit(
                value: widgetGlucoseValue(c),
                unit: c.glucoseUnitLabel,
                valueFont: .system(.title, design: .rounded).bold(),
                unitFont: .system(.caption, design: .rounded).weight(.semibold)
            )
            widgetRelativeAgoText(from: content.glucoseDate, hasData: c.glucoseValue > 0)
                .font(.caption)
                .opacity(0.7)

            Spacer(minLength: 2)

            widgetValueWithUnit(
                value: widgetCarbsValue(c),
                unit: "g",
                valueFont: .system(.title, design: .rounded).bold(),
                unitFont: .system(.caption, design: .rounded).weight(.semibold)
            )
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
            VStack(alignment: .leading, spacing: 4) {
                widgetValueWithUnit(
                    value: widgetGlucoseValue(c),
                    unit: c.glucoseUnit.shortLabel,
                    valueFont: .system(size: 44, weight: .bold, design: .rounded),
                    unitFont: .system(size: 18, weight: .semibold, design: .rounded)
                )
                widgetStackedTime(from: content.glucoseDate, hasData: c.glucoseValue > 0)
                    .font(.subheadline)
                    .opacity(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                widgetValueWithUnit(
                    value: widgetCarbsValue(c),
                    unit: "g",
                    valueFont: .system(size: 44, weight: .bold, design: .rounded),
                    unitFont: .system(size: 18, weight: .semibold, design: .rounded)
                )
                widgetStackedTime(from: content.carbDate, hasData: c.carbGrams != nil)
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
            VStack(alignment: .leading, spacing: 4) {
                widgetValueWithUnit(
                    value: widgetGlucoseValue(c),
                    unit: c.glucoseUnitLabel,
                    valueFont: .system(size: 64, weight: .bold, design: .rounded),
                    unitFont: .system(size: 26, weight: .semibold, design: .rounded)
                )
                widgetStackedTime(from: content.glucoseDate, hasData: c.glucoseValue > 0)
                    .font(.subheadline)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 4) {
                widgetValueWithUnit(
                    value: widgetCarbsValue(c),
                    unit: "g",
                    valueFont: .system(size: 52, weight: .bold, design: .rounded),
                    unitFont: .system(size: 21, weight: .semibold, design: .rounded)
                )
                widgetStackedTime(from: content.carbDate, hasData: c.carbGrams != nil)
                    .font(.subheadline)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding()
    }
}
