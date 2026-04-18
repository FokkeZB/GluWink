import SwiftUI

struct ContentView: View {
    var body: some View {
        #if targetEnvironment(simulator)
        if let caption = ScreenshotHarness.caption, let scene = ScreenshotHarness.current {
            CaptionBanner(caption: caption, background: scene.captionBannerColor) {
                sceneContent(scene)
            }
        } else if let scene = ScreenshotHarness.current {
            sceneContent(scene)
        } else {
            HomeView()
        }
        #else
        HomeView()
        #endif
    }

    #if targetEnvironment(simulator)
    @ViewBuilder
    private func sceneContent(_ scene: ScreenshotHarness.Scene) -> some View {
        switch scene {
        case .widgets:
            WidgetShowcaseView()
        case .settings:
            SettingsView()
        default:
            HomeView()
        }
    }
    #endif
}
