import FamilyControls
import Foundation
import ManagedSettings
import os
import SharedKit
import WidgetKit

final class ShieldManager {
    static let shared = ShieldManager()

    private let store = ManagedSettingsStore()
    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "ShieldManager")
    private let defaults = UserDefaults(suiteName: Constants.appGroupID)
    private var rearmTimer: Timer?

    private init() {}

    func applyShields() {
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            logger.error("FamilyControls not authorized — cannot apply shields")
            return
        }

        guard let selection = SharedDataManager.shared.loadSelection() else {
            logger.error("No selection found in App Group — cannot apply shields")
            return
        }

        store.shield.applicationCategories = .all(except: selection.applicationTokens)
        store.shield.webDomainCategories = .all(except: selection.webDomainTokens)

        logger.info("Shields applied — exempting \(selection.applicationTokens.count) apps")
    }

    /// Re-evaluate whether shields should be active based on attention state.
    func reevaluateShields() {
        guard SharedDataManager.shared.shieldingEnabled else {
            removeShields()
            return
        }

        if SharedDataManager.shared.onlyShieldWhenAttention && !needsAttention() {
            logger.info("No attention needed and onlyShieldWhenAttention — removing shields")
            removeShields()
            return
        }

        if isDisarmed {
            logger.info("Shields disarmed (re-arm scheduled) — skipping")
            return
        }

        applyShields()
    }

    /// Whether shields are currently disarmed with a pending re-arm.
    var isDisarmed: Bool {
        guard let isoStr = defaults?.string(forKey: "rearmShieldsAt"),
              let rearmAt = ISO8601DateFormatter().date(from: isoStr) else { return false }
        return rearmAt.timeIntervalSinceNow > 0
    }

    private func needsAttention() -> Bool {
        let data = SharedDataManager.shared
        let now = Date()

        let highThreshold = data.effectiveHighGlucoseThreshold
        let lowThreshold = data.effectiveLowGlucoseThreshold
        let staleMinutes = data.effectiveGlucoseStaleMinutes
        let graceHour = data.effectiveCarbGraceHour
        let graceMinute = data.effectiveCarbGraceMinute

        if let glucoseReading = data.currentGlucoseReading {
            let glucose = glucoseReading.mmol
            if glucose < lowThreshold || glucose > highThreshold { return true }
            if now.timeIntervalSince(glucoseReading.sampleAt) / 60 > Double(staleMinutes) { return true }
        } else {
            return true
        }

        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let isMorningGrace = hour < graceHour || (hour == graceHour && minute < graceMinute)

        if !isMorningGrace {
            if let carbsReading = data.currentCarbsReading {
                if now.timeIntervalSince(carbsReading.sampleAt) / 3600 > 4 { return true }
            } else {
                return true
            }
        }

        return false
    }

    /// Force-disable shielding when there is no data source to base
    /// attention decisions on. Called at startup and after the user disables
    /// the last data source (Nightscout, Demo, or HealthKit access revoked
    /// so no more samples arrive).
    ///
    /// This always clears `ManagedSettingsStore` and stops scheduling, even
    /// when `shieldingEnabled` is already false — that covers residual
    /// shield state left behind by a previous configuration (shielding was
    /// on, then settings got reset elsewhere without removing shields, or a
    /// beta install bequeathed an applied store to the new bundle). Without
    /// this belt-and-suspenders clear, apps stay blocked with a red
    /// "no-data" shield even after the UI thinks shielding is off.
    ///
    /// Returns true if `shieldingEnabled` actually flipped off.
    @discardableResult
    func disableIfNoDataSource() -> Bool {
        let data = SharedDataManager.shared
        guard !data.hasAnyDataSource else { return false }

        let wasEnabled = data.shieldingEnabled
        if wasEnabled {
            logger.info("No data source configured — disabling shielding")
            data.shieldingEnabled = false
            data.flush()
        } else {
            logger.info("No data source configured — clearing any residual shield state")
        }
        removeShields()
        ActivityScheduler.shared.stopMonitoring()
        WidgetCenter.shared.reloadAllTimelines()
        return wasEnabled
    }

    func removeShields() {
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        defaults?.removeObject(forKey: "rearmShieldsAt")
        rearmTimer?.invalidate()
        rearmTimer = nil
        logger.info("Shields removed")
    }

    /// Disarm shields after the child completes check-in.
    /// Shields are removed now and re-armed after the attention interval.
    ///
    /// Refuses (and returns `false`) when the current glucose reading is at
    /// or above the critical threshold — the "cannot dismiss" contract from
    /// issue #84 must hold for every disarm path, not just the Screen Time
    /// `ShieldAction` extension. Without this gate, a user could bypass the
    /// critical shield by opening GluWink directly and tapping check-in.
    @discardableResult
    func disarmShields() -> Bool {
        let data = SharedDataManager.shared
        let glucose = data.currentGlucoseReading?.mmol ?? 0
        let criticalThreshold = data.effectiveCriticalGlucoseThreshold
        if glucose > 0, glucose >= criticalThreshold {
            logger.notice("Critical glucose \(glucose) >= \(criticalThreshold) — refusing to disarm")
            return false
        }

        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil

        let intervalMinutes = data.attentionIntervalMinutes ?? ActivityScheduler.defaultAttentionInterval
        let rearmAt = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))

        defaults?.set(Date().ISO8601Format(), forKey: "shieldDismissedAt")
        defaults?.set(rearmAt.ISO8601Format(), forKey: "rearmShieldsAt")

        scheduleRearm()
        logger.info("Shields disarmed — re-arm at \(rearmAt.ISO8601Format())")
        return true
    }

    /// Check for any pending re-arm (e.g. from before the app was launched)
    /// and schedule a timer.
    func scheduleRearm() {
        rearmTimer?.invalidate()
        rearmTimer = nil

        guard let isoStr = defaults?.string(forKey: "rearmShieldsAt"),
              let rearmAt = ISO8601DateFormatter().date(from: isoStr) else {
            return
        }

        let delay = rearmAt.timeIntervalSinceNow
        if delay <= 0 {
            logger.info("Pending re-arm time already passed — re-arming now")
            defaults?.removeObject(forKey: "rearmShieldsAt")
            defaults?.removeObject(forKey: "shieldDismissedAt")
            applyShields()
            return
        }

        logger.info("Scheduling shield re-arm in \(Int(delay))s")
        rearmTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.logger.info("Re-arm timer fired — re-arming shields")
            self.defaults?.removeObject(forKey: "rearmShieldsAt")
            self.defaults?.removeObject(forKey: "shieldDismissedAt")
            self.applyShields()
        }
    }
}
