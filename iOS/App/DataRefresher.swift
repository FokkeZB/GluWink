import WidgetKit

/// One entry point for "fetch everything now". Used on foreground and by the
/// manual refresh button on the home screen. Only enabled sources are hit —
/// each manager's own guards cover the rest.
@MainActor
enum DataRefresher {
    static func refreshAll() async {
        let data = SharedDataManager.shared
        if data.healthKitEnabled {
            await HealthKitManager.shared.refreshIfAuthorized()
        }
        if data.nightscoutEnabled {
            await NightscoutManager.shared.fetchAll()
        }
        if data.easyViewEnabled {
            await EasyViewManager.shared.fetchAll()
        }
        if data.librelinkupEnabled {
            await LibreLinkUpManager.shared.fetchLatestGlucose()
        }
        // Always reconcile — staleness and carb-grace transitions cross
        // thresholds on wall-clock time alone, with no fetch event to ride.
        data.refreshAttentionBadge()
        WatchSessionManager.shared.sendLatestContext()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
