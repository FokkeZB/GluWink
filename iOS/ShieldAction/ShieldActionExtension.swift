import Foundation
import ManagedSettings
import os
import SharedKit

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

        // Per-source storage: go through `UnifiedDataReader` so the
        // shield honours Demo override + freshest-enabled-source wins,
        // same as every other reader.
        let glucoseReading = UnifiedDataReader.currentGlucoseReading(from: defaults)
        let carbsReading = UnifiedDataReader.currentCarbsReading(from: defaults)
        let glucose = glucoseReading?.mmol ?? 0
        let glucoseDate = glucoseReading?.sampleAt
        let carbDate = carbsReading?.sampleAt

        let fallbackHigh = Double(Bundle.main.object(forInfoDictionaryKey: "HighGlucoseThreshold") as! String)!
        let fallbackLow = Double(Bundle.main.object(forInfoDictionaryKey: "LowGlucoseThreshold") as! String)!
        let fallbackCritical = Double(Bundle.main.object(forInfoDictionaryKey: "CriticalGlucoseThreshold") as! String)!
        let fallbackStale = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
        let fallbackGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
        let fallbackGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!

        let highThreshold = ThresholdResolver.highGlucose(defaults: defaults, fallback: fallbackHigh)
        let lowThreshold = ThresholdResolver.lowGlucose(defaults: defaults, fallback: fallbackLow)
        let criticalThreshold = ThresholdResolver.criticalGlucose(defaults: defaults, fallback: fallbackCritical)
        let staleMinutes = ThresholdResolver.staleMinutes(defaults: defaults, fallback: fallbackStale)
        let carbGraceHour = ThresholdResolver.carbGraceHour(defaults: defaults, fallback: fallbackGraceHour)
        let carbGraceMinute = ThresholdResolver.carbGraceMinute(defaults: defaults, fallback: fallbackGraceMinute)

        let now = Date()
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)
        let currentMin = cal.component(.minute, from: now)
        let isMorningGrace = currentHour < carbGraceHour
            || (currentHour == carbGraceHour && currentMin < carbGraceMinute)

        // Critical glucose is a hard gate: the shield never dismisses at or
        // above critical, even if the rest of the check-in flow would.
        // Logged separately from the generic "attention" branch so the
        // device diagnostics can distinguish the two.
        if glucose > 0, glucose >= criticalThreshold {
            logger.notice("Critical glucose \(glucose) >= \(criticalThreshold) — refusing to dismiss")
            completionHandler(.close)
            return
        }

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
