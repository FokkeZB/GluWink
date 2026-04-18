#if targetEnvironment(simulator)
import SwiftUI

/// Marketing caption banner used only during App Store screenshot capture.
///
/// Overlays the scene's normal content with a softly translucent colored
/// banner at the bottom, carrying the localized caption from
/// `AppStore/<locale>.md`. The banner is painted in the scene's brand
/// color (green / red shield scenes inherit the shield hue, everything
/// else uses a neutral charcoal), so the bundled App Store listing reads
/// as one story.
///
/// Because it's an *overlay* instead of a `VStack` sibling, the underlying
/// scene always gets the full screen to lay itself out — important for
/// fixed-size content like `WidgetShowcaseView`'s 382pt large tile or
/// `SettingsView`'s scrolling list. A light gradient at the top edge of
/// the banner lets the underlying UI fade in gently rather than being
/// sliced flat by an opaque bar.
///
/// Rendered inside the app and captured by `simctl io screenshot`, so the
/// caption is baked into the PNG at device pixel dimensions — no external
/// compositing, no fastlane frameit dependency.
struct CaptionBanner<Content: View>: View {
    let caption: String
    let background: Color
    let content: () -> Content

    /// Fraction of the total screen height the banner occupies. 0.22 is
    /// enough for a three-line heavy-rounded caption at 30pt while keeping
    /// the top 78% of the screen fully visible underneath.
    private let bannerHeightFraction: CGFloat = 0.22
    /// Fraction of the banner used for the top-edge gradient fade-in.
    /// The remaining fraction is painted at full `bannerOpacity` so the
    /// caption sits on a calm, readable field.
    private let fadeFraction: CGFloat = 0.35
    /// Opacity of the solid portion of the banner. Leaves a hint of the
    /// underlying UI visible for depth without sacrificing caption
    /// legibility on any realistic scene background.
    private let bannerOpacity: Double = 0.92

    var body: some View {
        GeometryReader { geo in
            let bannerHeight = geo.size.height * bannerHeightFraction
            let fadeHeight = bannerHeight * fadeFraction
            content()
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [
                                background.opacity(0),
                                background.opacity(bannerOpacity),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: fadeHeight)

                        Text(caption)
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                            .lineLimit(3)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(background.opacity(bannerOpacity))
                    }
                    .frame(height: bannerHeight)
                    .ignoresSafeArea(edges: .bottom)
                }
        }
    }
}
#endif
