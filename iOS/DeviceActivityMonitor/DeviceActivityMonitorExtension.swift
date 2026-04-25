import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os
import SharedKit

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private static let bundlePrefix = Bundle.main.object(forInfoDictionaryKey: "BundlePrefix") as! String
    private static let appGroupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as! String
    /// xcconfig fallbacks. The resolver picks override-or-fallback per
    /// re-arm decision so user threshold changes take effect on the next
    /// monitoring interval.
    private static let fallbackHighGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "HighGlucoseThreshold") as! String)!
    private static let fallbackLowGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "LowGlucoseThreshold") as! String)!
    private static let fallbackCriticalGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "CriticalGlucoseThreshold") as! String)!
    private static let fallbackStaleMinutes = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
    private static let fallbackCarbGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
    private static let fallbackCarbGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!

    private let logger = Logger(subsystem: "\(bundlePrefix).DeviceActivityMonitor", category: "monitor")
    private let defaults = UserDefaults(suiteName: appGroupID)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        logger.info("intervalDidStart: \(activity.rawValue)")
        rearmIfNeeded(activity: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        logger.info("intervalDidEnd: \(activity.rawValue)")
        rearmIfNeeded(activity: activity)
    }

    private func rearmIfNeeded(activity: DeviceActivityName) {
        if defaults?.object(forKey: "shieldingEnabled") as? Bool == false {
            logger.info("Shielding disabled — skipping re-arm")
            return
        }

        if let rearmISO = defaults?.string(forKey: "rearmShieldsAt"),
           let rearmAt = ISO8601DateFormatter().date(from: rearmISO),
           rearmAt.timeIntervalSinceNow > 0 {
            logger.info("Active deferral cooldown — skipping re-arm")
            return
        }

        let onlyWhenAttention = Self.readOnlyShieldWhenAttention(from: defaults)
        let attentionNeeded = needsAttention()

        if onlyWhenAttention && !attentionNeeded {
            logger.info("onlyShieldWhenAttention enabled and no attention — removing shields")
            let store = ManagedSettingsStore()
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
            return
        }

        let isShortInterval = activity.rawValue.contains(".attention.")
        if isShortInterval && !attentionNeeded {
            logger.info("Attention interval fired but no attention needed — skipping")
            return
        }

        applyShields()
    }

    private static func readOnlyShieldWhenAttention(from defaults: UserDefaults?) -> Bool {
        defaults?.bool(forKey: "onlyShieldWhenAttention") ?? false
    }

    private func needsAttention() -> Bool {
        let now = Date()

        let highThreshold = ThresholdResolver.highGlucose(defaults: defaults, fallback: Self.fallbackHighGlucose)
        let lowThreshold = ThresholdResolver.lowGlucose(defaults: defaults, fallback: Self.fallbackLowGlucose)
        let staleMinutes = ThresholdResolver.staleMinutes(defaults: defaults, fallback: Self.fallbackStaleMinutes)
        let graceHour = ThresholdResolver.carbGraceHour(defaults: defaults, fallback: Self.fallbackCarbGraceHour)
        let graceMinute = ThresholdResolver.carbGraceMinute(defaults: defaults, fallback: Self.fallbackCarbGraceMinute)

        let glucose = defaults?.double(forKey: "currentGlucose") ?? 0
        if let isoStr = defaults?.string(forKey: "glucoseFetchedAt"),
           let fetchedAt = ISO8601DateFormatter().date(from: isoStr) {
            if glucose < lowThreshold || glucose > highThreshold {
                return true
            }
            if now.timeIntervalSince(fetchedAt) / 60 > Double(staleMinutes) {
                return true
            }
        } else {
            return true
        }

        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let isMorningGrace = hour < graceHour
            || (hour == graceHour && minute < graceMinute)

        if !isMorningGrace {
            if let isoStr = defaults?.string(forKey: "lastCarbEntryAt"),
               let carbDate = ISO8601DateFormatter().date(from: isoStr) {
                if now.timeIntervalSince(carbDate) / 3600 > 4 {
                    return true
                }
            } else {
                return true
            }
        }

        return false
    }

    private func applyShields() {
        guard let data = defaults?.data(forKey: "allowedAppTokens"),
              let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) else {
            logger.error("No selection found — cannot re-arm shields")
            return
        }

        let store = ManagedSettingsStore()
        store.shield.applicationCategories = .all(except: selection.applicationTokens)
        store.shield.webDomainCategories = .all(except: selection.webDomainTokens)

        logger.info("Shields re-armed — exempting \(selection.applicationTokens.count) apps")
    }
}
