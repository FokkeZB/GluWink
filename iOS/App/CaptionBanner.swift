#if targetEnvironment(simulator)
import SwiftUI

/// Marketing caption banner used only during App Store screenshot capture.
///
/// Wraps the scene's normal content with a colored banner on top carrying
/// the localized caption from `AppStore/<locale>.md`. The banner is painted
/// in the scene's brand color (green / red shield scenes inherit the shield
/// hue, everything else uses a neutral charcoal) so the bundled App Store
/// listing reads as one story.
///
/// Because the banner is rendered inside the app and captured by
/// `simctl io screenshot`, it's baked into the PNG at the correct pixel
/// dimensions — no external compositing or fastlane frameit dependency.
struct CaptionBanner<Content: View>: View {
    let caption: String
    let background: Color
    let content: () -> Content

    /// Fraction of the total screen height the banner occupies. Tuned on an
    /// iPhone 17 Pro Max: 0.20 leaves room for a three-line heavy-rounded
    /// caption at 30pt while keeping enough content area for the widgets
    /// showcase scene, which has the tightest vertical budget of any
    /// captured layout.
    private let bannerHeightFraction: CGFloat = 0.20

    var body: some View {
        GeometryReader { geo in
            let bannerHeight = geo.size.height * bannerHeightFraction
            let contentHeight = geo.size.height - bannerHeight
            VStack(spacing: 0) {
                content()
                    // Hard-clamp the content area. Without this, scenes whose
                    // intrinsic height exceeds the allotted space (notably
                    // `WidgetShowcaseView` with its fixed 382pt large tile)
                    // win the layout negotiation and push the banner off
                    // the bottom of the screen.
                    .frame(width: geo.size.width, height: contentHeight)
                    .clipped()

                Text(caption)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(3)
                    .padding(.horizontal, 24)
                    // Keep the text above the home indicator; the colored
                    // background still extends down past it so the banner
                    // reads as a solid block.
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    .frame(width: geo.size.width, height: bannerHeight)
                    .background(background.ignoresSafeArea(edges: .bottom))
            }
        }
    }
}
#endif
