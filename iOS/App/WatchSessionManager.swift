import Foundation
import SharedKit
import WatchConnectivity
import os

final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "WatchSessionManager")

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendLatestContext() {
        let context = makeContext()
        SimulatorWatchBridge.storeContext(context)

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        do {
            try session.updateApplicationContext(context)
            logger.info("Synced latest settings to Watch")
        } catch {
            logger.error("Failed to sync settings to Watch: \(error.localizedDescription)")
        }

        guard session.isReachable else { return }
        session.sendMessage(context, replyHandler: nil) { error in
            self.logger.error("Failed to send live settings message to Watch: \(error.localizedDescription)")
        }
    }

    func session(_: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        if let error {
            logger.error("WC activation failed: \(error.localizedDescription)")
        } else {
            logger.info("WC activated with state \(activationState.rawValue)")
        }
        sendLatestContext()
    }

    func sessionDidBecomeInactive(_: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        sendLatestContext()
    }

    private func makeContext() -> [String: Any] {
        let data = SharedDataManager.shared
        let customChecks = Dictionary(uniqueKeysWithValues: data.allCustomChecks().map { scenario, checks in
            (scenario.rawValue, checks)
        })
        var context: [String: Any] = [
            "highGlucoseThreshold": data.highGlucoseThreshold ?? SettingsDefaults.highGlucose,
            "lowGlucoseThreshold": data.lowGlucoseThreshold ?? SettingsDefaults.lowGlucose,
            "glucoseStaleMinutes": data.glucoseStaleMinutes ?? SettingsDefaults.staleMinutes,
            "carbGraceHour": data.carbGraceHour ?? SettingsDefaults.carbGraceHour,
            "carbGraceMinute": data.carbGraceMinute ?? SettingsDefaults.carbGraceMinute,
            "glucoseUnit": data.glucoseUnit.rawValue,
            "customChecks": customChecks,
            "mockModeEnabled": data.isMockModeEnabled,
            "nightscoutEnabled": data.nightscoutEnabled,
            "syncToken": Date().timeIntervalSince1970,
        ]

        if let url = data.nightscoutBaseURL { context["nightscoutBaseURL"] = url }
        if let token = data.nightscoutToken { context["nightscoutToken"] = token }

        if data.isMockModeEnabled {
            if let glucose = data.currentGlucose {
                context["currentGlucose"] = glucose
            }
            if let glucoseFetchedAt = data.glucoseFetchedAt {
                context["glucoseFetchedAt"] = glucoseFetchedAt.ISO8601Format()
            }
            if let lastCarbGrams = data.lastCarbGrams {
                context["lastCarbGrams"] = lastCarbGrams
            }
            if let lastCarbEntryAt = data.lastCarbEntryAt {
                context["lastCarbEntryAt"] = lastCarbEntryAt.ISO8601Format()
            }
        }

        return context
    }
}
