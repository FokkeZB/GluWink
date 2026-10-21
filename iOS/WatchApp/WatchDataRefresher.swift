import WidgetKit

/// One entry point for "fetch everything now" on the Watch. Used on
/// foreground and by the manual refresh button. Each manager guards on its
/// own enabled flag, so disabled sources cost nothing.
enum WatchDataRefresher {
    static func refreshAll() async {
        await WatchHealthKitManager.shared.fetchLatestGlucose()
        await WatchHealthKitManager.shared.fetchLatestCarbs()
        await WatchNightscoutManager.shared.fetchAll()
        await WatchEasyViewManager.shared.fetchAll()
        await WatchLibreLinkUpManager.shared.fetchAll()
        await MainActor.run { WidgetCenter.shared.reloadAllTimelines() }
    }
}
