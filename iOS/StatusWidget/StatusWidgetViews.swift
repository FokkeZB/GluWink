import SharedKit
import SwiftUI
import WidgetKit

// MARK: - Accessory / Lock Screen widgets
//
// The visual body of each accessory tile lives in
// `SharedKit/WidgetTileViews.swift` so the App's screenshot showcase
// can render an identical picture without duplicating layout code.
// These wrappers add the WidgetKit-only chrome (`AccessoryWidgetBackground()`
// and `containerBackground(for: .widget)`), which are no-ops outside a
// real widget context.

private func tileContent(for entry: StatusEntry) -> WidgetTileContent {
    WidgetTileContent(
        shieldContent: entry.content,
        glucoseDate: entry.glucoseDate,
        carbDate: entry.carbDate
    )
}

struct AccessoryCircularView: View {
    let entry: StatusEntry

    private var level: AttentionLevel {
        entry.content.attentionLevel(forGlucose: entry.metric == .glucose)
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            // `level.tint` is applied here even though iOS strips custom
            // foreground colors on the Lock Screen — supplying it keeps
            // the widget honest in any preview/snapshot context where the
            // vibrancy treatment isn't applied (e.g. SwiftUI previews,
            // the screenshot showcase route via SharedKit). On a real
            // Lock Screen iOS desaturates this to its vibrancy palette;
            // see QUIRKS.md → "Lock Screen accessory widgets cannot show
            // custom colors".
            AccessoryCircularTile(
                content: tileContent(for: entry),
                forGlucose: entry.metric == .glucose
            )
            .foregroundStyle(level.tint)
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct AccessoryRectangularView: View {
    let entry: StatusEntry

    var body: some View {
        AccessoryRectangularTile(content: tileContent(for: entry))
            .containerBackground(for: .widget) {
                AccessoryWidgetBackground()
            }
    }
}

struct AccessoryInlineView: View {
    let entry: StatusEntry

    var body: some View {
        AccessoryInlineTile(
            content: tileContent(for: entry),
            forGlucose: entry.metric == .glucose
        )
            .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Home Screen widgets
//
// The visual body of each tile lives in `SharedKit/WidgetTileViews.swift` so
// the App's screenshot showcase can render an identical picture without
// duplicating layout code. This file keeps only the WidgetKit-specific
// wrapping: `containerBackground(for: .widget)` which WidgetKit uses to
// colour the tile chrome beyond the padded body.

struct SmallWidgetView: View {
    let entry: StatusEntry

    var body: some View {
        SmallWidgetTile(content: tileContent(for: entry))
            .containerBackground(for: .widget) {
                entry.content.attentionLevel.tint
            }
    }
}

struct MediumWidgetView: View {
    let entry: StatusEntry

    var body: some View {
        MediumWidgetTile(content: tileContent(for: entry))
            .containerBackground(for: .widget) {
                entry.content.attentionLevel.tint
            }
    }
}

struct LargeWidgetView: View {
    let entry: StatusEntry

    var body: some View {
        LargeWidgetTile(content: tileContent(for: entry))
            .containerBackground(for: .widget) {
                entry.content.attentionLevel.tint
            }
    }
}
