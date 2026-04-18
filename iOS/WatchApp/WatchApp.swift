import SwiftUI
import WidgetKit

@main
struct CompanionWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WatchConnectivityReceiver.shared.activate()
        WatchHealthKitManager.shared.startObserving()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .task {
                    await WatchHealthKitManager.shared.requestAuthorization()
                    await WatchHealthKitManager.shared.enableBackgroundDelivery()
                    await WatchHealthKitManager.shared.fetchLatestGlucose()
                    await WatchHealthKitManager.shared.fetchLatestCarbs()

                    WatchNightscoutManager.shared.startPolling()
                    await WatchNightscoutManager.shared.fetchAll()
                    WatchNightscoutManager.shared.scheduleBackgroundRefresh()
                }
                .onChange(of: scenePhase) {
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
