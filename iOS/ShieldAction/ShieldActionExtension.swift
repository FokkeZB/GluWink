import Foundation
import ManagedSettings
import os

/// Duplicate of `SharedKit.ThresholdResolver` — this extension does not link
/// SharedKit (kept lean per the extension memory cap), so the contract is
/// re-stated locally. Keep in sync with SharedKit/ThresholdResolver.swift.
private enum ThresholdResolver {
    static func highGlucose(defaults: UserDefaults?, fallback: Double) -> Double {
        (defaults?.object(forKey: "highGlucoseThreshold") as? Double) ?? fallback
    }

    static func lowGlucose(defaults: UserDefaults?, fallback: Double) -> Double {
        (defaults?.object(forKey: "lowGlucoseThreshold") as? Double) ?? fallback
    }

    static func staleMinutes(defaults: UserDefaults?, fallback: Int) -> Int {
        (defaults?.object(forKey: "glucoseStaleMinutes") as? Int) ?? fallback
    }

    static func carbGraceHour(defaults: UserDefaults?, fallback: Int) -> Int {
        (defaults?.object(forKey: "carbGraceHour") as? Int) ?? fallback
    }

    static func carbGraceMinute(defaults: UserDefaults?, fallback: Int) -> Int {
        (defaults?.object(forKey: "carbGraceMinute") as? Int) ?? fallback
    }
}

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

        let fallbackHigh = Double(Bundle.main.object(forInfoDictionaryKey: "HighGlucoseThreshold") as! String)!
        let fallbackLow = Double(Bundle.main.object(forInfoDictionaryKey: "LowGlucoseThreshold") as! String)!
        let fallbackStale = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
        let fallbackGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
        let fallbackGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!

        let highThreshold = ThresholdResolver.highGlucose(defaults: defaults, fallback: fallbackHigh)
        let lowThreshold = ThresholdResolver.lowGlucose(defaults: defaults, fallback: fallbackLow)
        let staleMinutes = ThresholdResolver.staleMinutes(defaults: defaults, fallback: fallbackStale)
        let carbGraceHour = ThresholdResolver.carbGraceHour(defaults: defaults, fallback: fallbackGraceHour)
        let carbGraceMinute = ThresholdResolver.carbGraceMinute(defaults: defaults, fallback: fallbackGraceMinute)

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
