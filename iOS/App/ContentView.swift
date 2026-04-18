import SwiftUI

struct ContentView: View {
    var body: some View {
        #if targetEnvironment(simulator)
        switch ScreenshotHarness.current {
        case .widgets:
            WidgetShowcaseView()
        case .settings:
            SettingsView()
        default:
            HomeView()
        }
        #else
        HomeView()
        #endif
    }
}
