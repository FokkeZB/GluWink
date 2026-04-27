import SwiftUI
import WidgetKit

@main
struct CompanionWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if targetEnvironment(simulator)
        // When a screenshot run launched us with `-UITest_Scene watchApp`,
        // seed the watch-local App Group first so `WatchContentView` picks
        // up deterministic numbers on first render. No-op outside a harness
        // run.
        WatchScreenshotHarness.seedAppGroupIfNeeded()
        #endif

        WatchConnectivityReceiver.shared.activate()

        #if targetEnvironment(simulator)
        // Under the harness, skip the HK observer — it could deliver a
        // newer sample and overwrite the seed via `WatchDataManager`'s
        // save-if-newer logic.
        if !WatchScreenshotHarness.isActive {
            WatchHealthKitManager.shared.startObserving()
        }
        #else
        WatchHealthKitManager.shared.startObserving()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .task {
                    #if targetEnvironment(simulator)
                    // Under the screenshot harness, skip every fetch —
                    // the App Group was seeded in `init()` and any HK /
                    // Nightscout call would either clobber it (newer
                    // timestamp) or stall the capture on a network wake.
                    if WatchScreenshotHarness.isActive { return }
                    #endif

                    await WatchHealthKitManager.shared.requestAuthorization()
                    await WatchHealthKitManager.shared.enableBackgroundDelivery()
                    await WatchHealthKitManager.shared.fetchLatestGlucose()
                    await WatchHealthKitManager.shared.fetchLatestCarbs()

                    WatchNightscoutManager.shared.startPolling()
                    await WatchNightscoutManager.shared.fetchAll()
                    WatchNightscoutManager.shared.scheduleBackgroundRefresh()
                }
                .onChange(of: scenePhase) {
                    #if targetEnvironment(simulator)
                    if WatchScreenshotHarness.isActive { return }
                    #endif
                    if scenePhase == .active {
                        Task {
                            await WatchHealthKitManager.shared.fetchLatestGlucose()
                            await WatchHealthKitManager.shared.fetchLatestCarbs()
                            await WatchNightscoutManager.shared.fetchAll()
                        }
                    } else if scenePhase == .background {
                        WatchNightscoutManager.shared.scheduleBackgroundRefresh()
                    }
                }
        }
        .backgroundTask(.appRefresh("nightscout")) {
            await WatchNightscoutManager.shared.fetchAll()
            await MainActor.run {
                WatchNightscoutManager.shared.scheduleBackgroundRefresh()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
