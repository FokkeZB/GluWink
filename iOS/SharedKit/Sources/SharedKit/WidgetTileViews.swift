import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

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
    /// When non-nil, all relative-age and absolute-time text on the tile is
    /// computed against this anchor instead of SwiftUI's live wall-clock.
    /// Set only by the simulator-only screenshot showcase so the captured
    /// image stays consistent with the locked 9:41 status bar (issue #107).
    /// Production widget callers leave this nil to keep the live,
    /// auto-updating `Text(date, style: .relative)` / `.time` path.
    public let referenceDate: Date?

    public init(
        shieldContent: ShieldContent,
        glucoseDate: Date?,
        carbDate: Date?,
        referenceDate: Date? = nil
    ) {
        self.shieldContent = shieldContent
        self.glucoseDate = glucoseDate
        self.carbDate = carbDate
        self.referenceDate = referenceDate
    }
}

// MARK: - Shared helpers

private func widgetRelativeAgoText(
    from date: Date?,
    hasData: Bool,
    relativeTo referenceDate: Date? = nil
) -> Text {
    guard hasData, let date else {
        return Text(String(localized: "widget.noData", bundle: .module))
    }
    if let referenceDate {
        return Text(widgetRelativeAgoString(from: date, relativeTo: referenceDate))
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
private func widgetStackedTime(
    from date: Date?,
    hasData: Bool,
    relativeTo referenceDate: Date? = nil
) -> some View {
    if hasData, let date {
        VStack(alignment: .leading, spacing: 0) {
            if let referenceDate {
                Text(widgetRelativeAgoString(from: date, relativeTo: referenceDate))
                Text(date.formatted(date: .omitted, time: .shortened))
            } else {
                Text(date, style: .relative)
                Text(date, style: .time)
            }
        }
    } else {
        Text(String(localized: "widget.noData", bundle: .module))
    }
}

/// Renders a relative-ago string ("3 min ago" / "1 hr, 30 min ago" /
/// "1 u, 30 min geleden") against a fixed reference date — used by the
/// simulator-only screenshot showcase where SwiftUI's auto-updating
/// `Text(date, style: .relative)` would compute against the real
/// wall-clock and drift away from the locked 9:41 status bar (issue #107).
/// Production widgets keep the live path; this helper is `internal` so
/// SharedKit tests can pin its output.
///
/// Uses `DateComponentsFormatter` (multi-unit) rather than
/// `RelativeDateTimeFormatter` (single-unit) so a 90-minute gap reads as
/// "1 hr, 30 min ago" to match SwiftUI's live output — not rounded to
/// "1 hr ago", which would disagree with the tile's own absolute-time
/// label (e.g. "09:41" status bar + "1 hr ago" + "08:11" absolute → the
/// three numbers don't add up).
func widgetRelativeAgoString(
    from date: Date,
    relativeTo referenceDate: Date,
    locale: Locale = .current
) -> String {
    let interval = referenceDate.timeIntervalSince(date)
    // Defensive: the showcase only ever feeds dates in the past of the
    // anchor. If something flips (future date, equal dates), fall back
    // to an empty string rather than rendering "in 3 min" — the tile
    // would just hide the row, which is better than a confusing future
    // tense.
    guard interval > 0 else { return "" }

    let formatter = DateComponentsFormatter()
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    formatter.calendar = calendar
    // `.short` renders "1 hr, 30 min" / "1 u, 30 min" — two compact
    // units, matching SwiftUI's `Text(date, style: .relative)` output
    // ("2 hr, 5 min ago"). `.abbreviated` collapses to "1hr 30m" which
    // reads as a typo at marketing-screenshot scale.
    formatter.unitsStyle = .short
    formatter.allowedUnits = [.hour, .minute]
    formatter.maximumUnitCount = 2
    formatter.zeroFormattingBehavior = .dropAll

    guard let duration = formatter.string(from: interval) else { return "" }

    let template = widgetRelativeAgoTemplate(for: locale)
    return String(format: template, duration)
}

/// Resolves the "%@ ago" / "%@ geleden" template against a specific
/// locale — needed so the simulator screenshot path picks the right
/// suffix when the capture script toggles `AppleLanguages`, and so
/// SharedKit tests can pin EN and NL output deterministically.
private func widgetRelativeAgoTemplate(for locale: Locale) -> String {
    let code = locale.languageCode ?? "en"
    if
        let path = Bundle.module.path(forResource: code, ofType: "lproj"),
        let bundle = Bundle(path: path)
    {
        return bundle.localizedString(forKey: "widget.relative.ago %@", value: "%@ ago", table: nil)
    }
    return Bundle.module.localizedString(forKey: "widget.relative.ago %@", value: "%@ ago", table: nil)
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
    c.glucose?.formatted ?? "--"
}

private func widgetCarbsValue(_ c: ShieldContent) -> String {
    guard let carbs = c.carbs else { return "--" }
    if let grams = carbs.grams { return "\(grams)" }
    return carbs.label ?? "·"
}

/// Returns "g" when a gram count is available, empty string for meal-only
/// entries (labelled or unlabelled) so the unit label doesn't crowd the label.
private func widgetCarbsUnit(_ c: ShieldContent) -> String {
    c.carbs?.grams != nil ? "g" : ""
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
            widgetRelativeAgoText(
                from: content.glucoseDate,
                hasData: c.glucose != nil,
                relativeTo: content.referenceDate
            )
                .font(.caption)
                .opacity(0.7)

            Spacer(minLength: 2)

            widgetValueWithUnit(
                value: widgetCarbsValue(c),
                unit: widgetCarbsUnit(c),
                valueFont: .system(.title, design: .rounded).bold(),
                unitFont: .system(.caption, design: .rounded).weight(.semibold)
            )
            widgetRelativeAgoText(
                from: content.carbDate,
                hasData: c.carbs != nil,
                relativeTo: content.referenceDate
            )
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
                widgetStackedTime(
                    from: content.glucoseDate,
                    hasData: c.glucose != nil,
                    relativeTo: content.referenceDate
                )
                    .font(.subheadline)
                    .opacity(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                widgetValueWithUnit(
                    value: widgetCarbsValue(c),
                    unit: widgetCarbsUnit(c),
                    valueFont: .system(size: 44, weight: .bold, design: .rounded),
                    unitFont: .system(size: 18, weight: .semibold, design: .rounded)
                )
                widgetStackedTime(
                    from: content.carbDate,
                    hasData: c.carbs != nil,
                    relativeTo: content.referenceDate
                )
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

// MARK: - Accessory / Lock Screen tiles
//
// These mirror the Home Screen tile pattern: the visual body lives here in
// SharedKit so the App's screenshot showcase (`WidgetShowcaseView`) and the
// real `StatusWidget` extension render an identical picture. The widget
// wrappers in `StatusWidget/StatusWidgetViews.swift` add the WidgetKit-only
// chrome (`AccessoryWidgetBackground()` and `containerBackground(for: .widget)`).
//
// Foreground coloring is the wrapper's job, not the tile's — on a real
// Lock Screen iOS strips custom foreground colors and renders accessory
// widgets in vibrancy / desaturated white. The widget wrapper still applies
// `level.tint` (iOS strips it as appropriate), and the showcase wrapper
// applies a translucent white that mimics the vibrancy result. Either way
// the *tile* itself is a layout-only view.

public struct AccessoryCircularTile: View {
    public let content: WidgetTileContent
    public let forGlucose: Bool

    public init(content: WidgetTileContent, forGlucose: Bool) {
        self.content = content
        self.forGlucose = forGlucose
    }

    public var body: some View {
        let c = content.shieldContent
        VStack(spacing: -2) {
            Text(forGlucose ? widgetGlucoseValue(c) : widgetCarbsValue(c))
                .font(.system(.title2, design: .rounded).bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(forGlucose ? c.glucoseUnit.shortLabel : widgetCarbsUnit(c))
                .font(.system(.caption, design: .rounded))
        }
        .multilineTextAlignment(.center)
    }
}

public struct AccessoryRectangularTile: View {
    public let content: WidgetTileContent

    public init(content: WidgetTileContent) {
        self.content = content
    }

    public var body: some View {
        let c = content.shieldContent
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: c.glucoseNeedsAttention ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption2.bold())
                    .widgetAccentable()
                HStack(spacing: 2) {
                    Text(widgetGlucoseValue(c))
                        .font(.system(.headline, design: .rounded).bold())
                    Text(c.glucoseUnit.shortLabel)
                        .font(.caption2)
                }
                .lineLimit(1)
                widgetRelativeAgoText(
                    from: content.glucoseDate,
                    hasData: c.glucose != nil,
                    relativeTo: content.referenceDate
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Image(systemName: c.carbsNeedsAttention ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption2.bold())
                    .widgetAccentable()
                HStack(spacing: 2) {
                    Text(widgetCarbsValue(c))
                        .font(.system(.headline, design: .rounded).bold())
                    Text(widgetCarbsUnit(c))
                        .font(.caption2)
                }
                .lineLimit(1)
                widgetRelativeAgoText(
                    from: content.carbDate,
                    hasData: c.carbs != nil,
                    relativeTo: content.referenceDate
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

public struct AccessoryInlineTile: View {
    public let content: WidgetTileContent
    public let forGlucose: Bool

    public init(content: WidgetTileContent, forGlucose: Bool) {
        self.content = content
        self.forGlucose = forGlucose
    }

    public var body: some View {
        let c = content.shieldContent
        let needsAttention = forGlucose ? c.glucoseNeedsAttention : c.carbsNeedsAttention
        let icon = needsAttention ? "exclamationmark.triangle" : "checkmark.circle"
        // Inline is space-constrained on the Lock Screen so we drop the
        // unit suffix from glucose — the value alone (e.g. "115" or "6.4")
        // is what the user glances for. Carbs always carry the "g" suffix
        // because the bare number reads as ambiguous.
        let text: String = forGlucose
            ? (c.glucose?.formatted ?? "--")
            : "\(widgetCarbsValue(c))\(widgetCarbsUnit(c))"
        Label(text, systemImage: icon)
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
            VStack(alignment: .leading, spacing: 6) {
                widgetValueWithUnit(
                    value: widgetGlucoseValue(c),
                    unit: c.glucoseUnitLabel,
                    valueFont: .system(size: 80, weight: .bold, design: .rounded),
                    unitFont: .system(size: 32, weight: .semibold, design: .rounded)
                )
                widgetStackedTime(
                    from: content.glucoseDate,
                    hasData: c.glucose != nil,
                    relativeTo: content.referenceDate
                )
                    .font(.body)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 6) {
                widgetValueWithUnit(
                    value: widgetCarbsValue(c),
                    unit: "g",
                    valueFont: .system(size: 80, weight: .bold, design: .rounded),
                    unitFont: .system(size: 32, weight: .semibold, design: .rounded)
                )
                widgetStackedTime(
                    from: content.carbDate,
                    hasData: c.carbs != nil,
                    relativeTo: content.referenceDate
                )
                    .font(.body)
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding()
    }
}
