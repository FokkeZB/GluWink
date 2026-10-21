import AppIntents
import SharedKit
import WidgetKit

/// Backs the refresh button on the Home Screen widgets. Runs in the widget
/// extension, so it can only reach the network sources (Nightscout, EasyView,
/// LibreLinkUp) — HealthKit data still arrives via the app. The button is
/// not offered on Lock Screen families, where interactions aren't supported.
struct RefreshWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "widget.refresh"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let appGroupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
        let defaults = appGroupID.flatMap { UserDefaults(suiteName: $0) }
        await WidgetNightscoutRefresh.refreshIfDue(defaults: defaults, force: true)
        await WidgetEasyViewRefresh.refreshIfDue(defaults: defaults, force: true)
        await WidgetLibreLinkUpRefresh.refreshIfDue(defaults: defaults, force: true)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
