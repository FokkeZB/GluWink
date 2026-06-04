#if targetEnvironment(simulator)
import SharedKit
import SwiftUI

/// Mock "Home Screen + Lock Screen widgets" scene used only for the App
/// Store screenshot flow (`-UITest_Scene widgets`). Renders the real
/// `SmallWidgetTile`, `MediumWidgetTile`, `LargeWidgetTile`,
/// `AccessoryCircularTile`, and `AccessoryRectangularTile` from SharedKit,
/// so the shot can never drift from the live widget visuals.
///
/// Not a drop-in Home Screen simulator (no dock or page dots) — three
/// Home Screen tiles (small + medium + large) stack over a heavily-blurred
/// copy of the stock iOS dark wallpaper, and the slot beside the small
/// tile holds a compact "Lock Screen cluster" that mirrors how iOS
/// actually renders accessory widgets: a rectangular widget on top with
/// no background (text directly on the wallpaper) and two circular
/// widgets below on translucent-glass discs. No section headers — the
/// visual contrast between the colored Home Screen tiles and the white-
/// vibrant Lock Screen accessories reads as "Home Screen vs Lock Screen"
/// without needing an Apple-style label.
///
/// The Home Screen stack tells the green → red → orange story across
/// the three tiles (calm green small + critical red medium + attention
/// orange large hero) so a single shot covers all three brand attention
/// colors. The Lock Screen cluster intentionally does NOT carry brand
/// colour, because real iOS strips foreground tints on accessory widgets
/// (see QUIRKS.md → "Lock Screen accessory widgets cannot show custom
/// colors"). Showing fake brand red/green/orange on the Lock Screen mocks
/// would advertise behaviour the shipping app can't deliver. The
/// rectangular's `⚠` / `✓` icons + relative-time row still communicate
/// state honestly.
///
/// Mock state: the entire Lock Screen cluster renders in
/// `attentionContent` so all three accessories show consistent data, the
/// way they would on a real Lock Screen at one moment in time.
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

    // Lock Screen accessory geometry inside the 170×170pt cluster slot.
    // iOS gives accessory widgets specific point sizes (circular ~76pt
    // diameter, rectangular ~158×72pt). The circulars share the cluster's
    // bottom row side by side, so the diameter is sized down to fit two of
    // them inside 170pt with breathing room.
    private let accessoryCircularSide: CGFloat = 76
    private let accessoryRectangularHeight: CGFloat = 60

    var body: some View {
        // Pin the deck to the top of the safe area so the small + Lock
        // Screen row sits just below the camera-hole / Dynamic Island
        // chrome rather than centering vertically with empty wallpaper
        // above it. The bottom Spacer absorbs whatever slack is left,
        // which the translucent caption banner can then overlay without
        // hiding tile content above it.
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                smallTile(calmContent)
                    .frame(width: smallSide, height: smallSide)
                lockScreenCluster
                    .frame(width: smallSide, height: smallSide)
            }

            mediumTile(criticalContent)
                .frame(width: mediumSize.width, height: mediumSize.height)

            largeTile(attentionContent)
                .frame(width: largeSize.width, height: largeSize.height)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
        .background(homeScreenBackdrop)
    }

    // MARK: - Backdrop

    /// Heavily-blurred copy of the stock iOS dark wallpaper so the App Store
    /// shot reads as "widgets on your phone" rather than "widgets on a
    /// marketing card". The asset is blurred hard (`radius: 50, opaque: true`)
    /// and the backdrop is never itself shown on a shipped iOS surface —
    /// only in the simulator-only `-UITest_Scene widgets` screenshot — so
    /// no recognizable wallpaper detail ends up in the App Store listing.
    ///
    /// `opaque: true` tells SwiftUI the output is opaque, which prevents the
    /// blur kernel from bleeding transparent pixels into the image edges —
    /// without it, the left/right edges bloom into a bright cyan halo that
    /// doesn't match the wallpaper on a real device. The frame is scaled
    /// slightly beyond the viewport and `.clipped()` trims the result, so
    /// any residual edge artefacts from the kernel boundary stay outside
    /// the visible area too.
    private var homeScreenBackdrop: some View {
        GeometryReader { geo in
            Image("HomeScreenBackdrop")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width + 120, height: geo.size.height + 120)
                .offset(x: -60, y: -60)
                .blur(radius: 50, opaque: true)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()
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

    // MARK: - Lock Screen cluster

    /// Compact Lock Screen mock that fits inside a 170×170pt slot — the
    /// same footprint a second small Home Screen tile would take. Layout
    /// mirrors how iOS actually renders accessory widgets:
    ///
    /// - Rectangular widget on top, no glass background — text sits
    ///   directly on the wallpaper, the way `AccessoryWidgetBackground()`
    ///   resolves to nothing on real Lock Screens.
    /// - Two circular widgets below (glucose left, carbs right), each on
    ///   a translucent glass disc — the way iOS draws
    ///   `AccessoryWidgetBackground()` for circular accessories.
    ///
    /// The inline accessory family is intentionally omitted from the
    /// cluster mock: on a real Lock Screen the inline widget lives in
    /// its own slot above the time, separate from the configured-widget
    /// row, and rendering it next to the rectangular/circulars would
    /// misrepresent the iOS layout. The "GluWink ships an inline widget
    /// too" story is carried by the StatusWidget extension itself, which
    /// users discover when they pick a widget for that slot.
    ///
    /// All Lock Screen content uses a single mock state
    /// (`attentionContent`) — on a real Lock Screen all your widgets show
    /// the same data at the same moment. Mixing states here would look
    /// staged.
    private var lockScreenCluster: some View {
        VStack(spacing: 10) {
            accessoryRectangularCard(content: attentionContent)
            HStack(spacing: 12) {
                accessoryCircularPill(content: attentionContent, forGlucose: true)
                accessoryCircularPill(content: attentionContent, forGlucose: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `AccessoryCircularTile` on a translucent glass disc — matching
    /// how iOS draws `AccessoryWidgetBackground()` for circular
    /// accessories on the Lock Screen. The background is a flat
    /// translucent fill rather than `.ultraThinMaterial` because the
    /// Material types don't render with vibrancy outside a real Lock
    /// Screen context (they fall back to opaque grey on the captured
    /// PNG, which loses the "glass" cue). Foreground is white-ish to
    /// mimic the vibrancy treatment iOS applies when the widget renders
    /// against a wallpaper — see QUIRKS.md → "Lock Screen accessory
    /// widgets cannot show custom colors".
    private func accessoryCircularPill(content: WidgetTileContent, forGlucose: Bool) -> some View {
        AccessoryCircularTile(content: content, forGlucose: forGlucose)
            .foregroundStyle(.white.opacity(0.85))
            .padding(4)
            .frame(width: accessoryCircularSide, height: accessoryCircularSide)
            .background(lockScreenGlass)
            .clipShape(Circle())
    }

    /// `AccessoryRectangularTile` rendered with no background — on real
    /// Lock Screens, rectangular widgets sit directly on the wallpaper
    /// without a glass disc. Text uses white-ish vibrancy with `.secondary`
    /// dimming for the relative-time tail, matching the way iOS renders
    /// accessory text against a wallpaper.
    private func accessoryRectangularCard(content: WidgetTileContent) -> some View {
        AccessoryRectangularTile(content: content)
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: smallSide, height: accessoryRectangularHeight, alignment: .leading)
    }

    /// Translucent fill that stands in for the iOS Lock Screen widget
    /// container (`AccessoryWidgetBackground`) on circular accessories.
    /// Tuned to read as "glass on top of the wallpaper" against the
    /// heavily-blurred dark backdrop. Tweak the opacity here, not at
    /// each call site.
    private var lockScreenGlass: some View {
        Color.white.opacity(0.22)
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

    /// Red, critical state — mirror of `ScreenshotHarness.redShield`.
    /// Glucose 21.2 mmol/L is at/above the default critical threshold
    /// (16.7), so `ShieldContent.isCriticalGlucose` flips true and the
    /// tile background resolves to `BrandTint.red` automatically via
    /// `attentionLevel.tint`.
    private var criticalContent: WidgetTileContent {
        makeContent(
            glucose: 21.2,
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
        let now = captureNow
        let glucoseDate = now.addingTimeInterval(-glucoseMinutesAgo * 60)
        let carbDate = now.addingTimeInterval(-carbMinutesAgo * 60)
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
            strings: ShieldContent.Strings.fromPackage(),
            // Anchor the staleness / carb-grace evaluation to the same
            // 09:41 "now" the tile timestamps render against — otherwise
            // ShieldContent compares the mock dates to the real wall-clock
            // and flips every tile to orange (stale sensor + carb gap)
            // when the screenshot is captured outside the morning grace
            // window. See issue #107.
            now: now
        )
        return WidgetTileContent(
            shieldContent: shield,
            glucoseDate: glucoseDate,
            carbDate: carbDate,
            referenceDate: now
        )
    }

    /// Anchor for every "now" calculation in the screenshot showcase: today
    /// at 09:41 in the simulator's current timezone, matching the locked
    /// status-bar override (`xcrun simctl status_bar override --time 9:41`
    /// in `.claude/skills/appstore-screenshots/scripts/capture.sh`). Without
    /// this, the tiles would compute their relative ages and absolute times
    /// against the real wall-clock and produce a screenshot whose tile
    /// timestamps disagree with its own status bar — see issue #107. Falls
    /// back to `Date()` only if `Calendar.current` somehow refuses to
    /// produce 09:41 today (shouldn't happen for any real iOS calendar).
    private var captureNow: Date {
        Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()
    }
}
#endif
