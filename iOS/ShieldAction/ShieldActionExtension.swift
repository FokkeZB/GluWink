import Foundation
import ManagedSettings
import os

class ShieldActionExtension: ShieldActionDelegate {
    private static let bundlePrefix = Bundle.main.object(forInfoDictionaryKey: "BundlePrefix") as! String
    private static let appGroupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as! String

    private let logger = Logger(subsystem: "\(bundlePrefix).ShieldAction", category: "action")

    override func handle(action: ShieldAction, for _: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for _: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for _: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(action, completionHandler: completionHandler)
    }

    private func handleAction(_ action: ShieldAction, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard action == .primaryButtonPressed else {
            completionHandler(.close)
            return
        }

        let defaults = UserDefaults(suiteName: Self.appGroupID)

        let glucose = defaults?.double(forKey: "currentGlucose") ?? 0
        let glucoseDate = defaults?.string(forKey: "glucoseFetchedAt")
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        let carbDate = defaults?.string(forKey: "lastCarbEntryAt")
            .flatMap { ISO8601DateFormatter().date(from: $0) }

        let highThreshold = Double(Bundle.main.object(forInfoDictionaryKey: "HighGlucoseThreshold") as! String)!
        let lowThreshold = Double(Bundle.main.object(forInfoDictionaryKey: "LowGlucoseThreshold") as! String)!
        let staleMinutes = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
        let carbGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
        let carbGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!

        let now = Date()
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)
        let currentMin = cal.component(.minute, from: now)
        let isMorningGrace = currentHour < carbGraceHour
            || (currentHour == carbGraceHour && currentMin < carbGraceMinute)

        var needsAttention = false
        if glucose > 0, let gDate = glucoseDate {
            let minutesAgo = Int(now.timeIntervalSince(gDate) / 60)
            if glucose < lowThreshold || glucose > highThreshold { needsAttention = true }
            if minutesAgo > staleMinutes { needsAttention = true }
        } else {
            needsAttention = true
        }
        if !isMorningGrace, let cDate = carbDate, now.timeIntervalSince(cDate) / 3600 > 4 {
            needsAttention = true
        }

        if needsAttention {
            logger.notice("Attention needed — closing app (child must check in via main app)")
            completionHandler(.close)
            return
        }

        let store = ManagedSettingsStore()
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil

        logger.notice("No attention needed — shields dismissed")
        completionHandler(.defer)
    }
}
