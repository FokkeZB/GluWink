import Foundation
import WidgetKit
import WatchConnectivity
import os

final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityReceiver()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WatchApp", category: "WatchConnectivityReceiver")

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        if let error {
            logger.error("WC activation failed: \(error.localizedDescription)")
        } else {
            logger.info("WC activated with state \(activationState.rawValue)")
        }

        if !session.receivedApplicationContext.isEmpty {
            applyContext(session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyContext(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyContext(message)
    }

    private func applyContext(_ context: [String: Any]) {
        WatchDataManager.updateFromPhoneContext(context)
        WidgetCenter.shared.reloadAllTimelines()
        if !WatchDataManager.isMockModeEnabled {
            Task {
                await WatchHealthKitManager.shared.fetchLatestGlucose()
                await WatchHealthKitManager.shared.fetchLatestCarbs()
                await MainActor.run {
                    WatchNightscoutManager.shared.configurationDidChange()
                }
            }
        }
        logger.info("Applied phone settings context on Watch")
    }
}
