#if targetEnvironment(simulator)
import SharedKit
import SwiftUI

/// Mock "Home Screen widgets" scene used only for the App Store screenshot
/// flow (`-UITest_Scene widgets`). Renders the real `SmallWidgetTile`,
/// `MediumWidgetTile`, and `LargeWidgetTile` from SharedKit, so the shot
/// can never drift from the live widget visuals.
///
/// Not a drop-in Home Screen simulator (no wallpaper, dock, or page dots) —
/// just three tiles stacked on a soft background with a small header, which
/// is what the App Store screenshot guide asks for: "small + medium + large
/// in a stack, mix of green and red".
struct WidgetShowcaseView: View {
    // Widget geometry for a 6.9" iPhone. Hard-coded because we only capture
    // on one device class right now; revisit when we add iPad or 6.7".
    // These match the real WidgetKit point sizes — the caption banner is
    // a translucent overlay, so the large tile is free to extend under it
    // without being clipped.
    private let smallSide: CGFloat = 170
    private let mediumSize = CGSize(width: 364, height: 170)
    private let largeSize = CGSize(width: 364, height: 382)
    private let cornerRadius: CGFloat = 22
    /// Extra inset applied outside the tile body, inside the colored background.
    /// WidgetKit's container adds ~12–16pt of default `contentMargin` that we
    /// don't get when rendering the tile directly; without this, the numbers
    /// sit closer to the tile edge than on a real Home Screen. Measured off
    /// a side-by-side with the shipping widget on an iPhone 16 Pro Max.
    private let widgetContentMargin: CGFloat = 12

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            HStack(spacing: 16) {
                smallTile(calmContent)
                smallTile(attentionContent)
            }

            mediumTile(calmContent)
                .frame(width: mediumSize.width, height: mediumSize.height)

            largeTile(calmContent)
                .frame(width: largeSize.width, height: largeSize.height)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
    }

    // MARK: - Tiles

    private func smallTile(_ content: WidgetTileContent) -> some View {
        SmallWidgetTile(content: content)
            .padding(widgetContentMargin)
            .frame(width: smallSide, height: smallSide)
            .background(content.shieldContent.attentionLevel.tint)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func mediumTile(_ content: WidgetTileContent) -> some View {
        MediumWidgetTile(content: content)
            .padding(widgetContentMargin)
            .background(content.shieldContent.attentionLevel.tint)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func largeTile(_ content: WidgetTileContent) -> some View {
        LargeWidgetTile(content: content)
            .padding(widgetContentMargin)
            .background(content.shieldContent.attentionLevel.tint)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - Mock content

    /// Green, calm state — same numbers as `ScreenshotHarness.greenShield`.
    private var calmContent: WidgetTileContent {
        makeContent(
            glucose: 6.4,
            glucoseMinutesAgo: 3,
            carbGrams: 25,
            carbMinutesAgo: 90
        )
    }

    /// Orange, needs-attention state — mirror of `ScreenshotHarness.orangeShield`.
    /// Glucose 14.8 mmol/L is above the high threshold (but below critical)
    /// so `ShieldContent` flips `needsAttention` true and picks the orange
    /// tint on its own.
    private var attentionContent: WidgetTileContent {
        makeContent(
            glucose: 14.8,
            glucoseMinutesAgo: 2,
            carbGrams: 30,
            carbMinutesAgo: 15
        )
    }

    private func makeContent(
        glucose: Double,
        glucoseMinutesAgo: Double,
        carbGrams: Double,
        carbMinutesAgo: Double
    ) -> WidgetTileContent {
        let glucoseDate = Date().addingTimeInterval(-glucoseMinutesAgo * 60)
        let carbDate = Date().addingTimeInterval(-carbMinutesAgo * 60)
        let shield = ShieldContent(
            glucose: glucose,
            glucoseFetchedAt: glucoseDate,
            lastCarbGrams: carbGrams,
            lastCarbEntryAt: carbDate,
            highGlucoseThreshold: SettingsDefaults.highGlucose,
            lowGlucoseThreshold: SettingsDefaults.lowGlucose,
            criticalGlucoseThreshold: SettingsDefaults.criticalGlucose,
            glucoseStaleMinutes: SettingsDefaults.staleMinutes,
            carbGraceHour: SettingsDefaults.carbGraceHour,
            carbGraceMinute: SettingsDefaults.carbGraceMinute,
            glucoseUnit: SharedDataManager.shared.glucoseUnit,
            strings: ShieldContent.Strings.fromPackage()
        )
        return WidgetTileContent(
            shieldContent: shield,
            glucoseDate: glucoseDate,
            carbDate: carbDate
        )
    }
}
#endif
