import FamilyControls
import Foundation
import HealthKit
import os
import SharedKit
import UserNotifications

enum GlucoseBadgeMode: String, CaseIterable {
    case off
    case always
    case onlyWhenAttention
}

final class SharedDataManager {
    static let shared = SharedDataManager()

    private let defaults = UserDefaults(suiteName: Constants.appGroupID)
    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "SharedDataManager")

    private init() {
        if defaults == nil {
            logger.error("Failed to create UserDefaults for App Group")
        }
    }

    // MARK: - Glucose Data

    var currentGlucose: Double? {
        let value = defaults?.double(forKey: "currentGlucose") ?? 0
        return value > 0 ? value : nil
    }

    var glucoseFetchedAt: Date? {
        guard let iso = defaults?.string(forKey: "glucoseFetchedAt") else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    /// Persist a glucose sample. By default uses a "save if newer" strategy so
    /// HealthKit and Nightscout (which both write to the same App Group keys)
    /// never clobber a fresher reading from the other source. Pass `force: true`
    /// when the caller has an explicit reason to overwrite — e.g. mock data
    /// configuration where the user picks an older timestamp on purpose.
    func saveGlucose(mmol: Double, at date: Date, force: Bool = false) {
        if !force, let existing = glucoseFetchedAt, date <= existing { return }
        defaults?.set(mmol, forKey: "currentGlucose")
        defaults?.set(date.ISO8601Format(), forKey: "glucoseFetchedAt")
    }

    // MARK: - Carb Data

    var lastCarbGrams: Double? {
        let value = defaults?.double(forKey: "lastCarbGrams") ?? 0
        return value > 0 ? value : nil
    }

    var lastCarbEntryAt: Date? {
        guard let iso = defaults?.string(forKey: "lastCarbEntryAt") else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    /// Persist a carb entry with the same "save if newer" semantics as
    /// `saveGlucose`.
    func saveCarbs(grams: Double, at date: Date, force: Bool = false) {
        if !force, let existing = lastCarbEntryAt, date <= existing { return }
        defaults?.set(grams, forKey: "lastCarbGrams")
        defaults?.set(date.ISO8601Format(), forKey: "lastCarbEntryAt")
    }

    // MARK: - Attention Badge

    /// Recompute the attention state and update the app icon badge.
    ///
    /// The home-screen icon itself never changes — it always uses `AppIcon`. The
    /// red/green variants (`AppIcon-Red`, `AppIcon-Green`) are only used by
    /// surfaces we can pick at render time (shield UI, in-app screens, future
    /// notification attachments).
    @MainActor
    func refreshAttentionBadge() {
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

        updateBadge(glucose: glucose, needsAttention: needsAttention)
    }

    @MainActor
    private func updateBadge(glucose: Double, needsAttention: Bool) {
        let displayValue = glucoseUnit.displayValue(glucose)
        let rounded = glucose > 0 ? Int(displayValue.rounded()) : 0
        let badgeCount: Int
        switch glucoseBadgeMode {
        case .off:
            badgeCount = 0
        case .always:
            badgeCount = rounded
        case .onlyWhenAttention:
            badgeCount = needsAttention ? rounded : 0
        }
        UNUserNotificationCenter.current().setBadgeCount(badgeCount)
    }

    // MARK: - Shield Disarm State

    /// Whether shields are currently disarmed (check-in completed, pending re-arm).
    var isShieldDisarmed: Bool {
        guard let iso = defaults?.string(forKey: "rearmShieldsAt"),
              let rearmAt = ISO8601DateFormatter().date(from: iso) else { return false }
        return rearmAt.timeIntervalSinceNow > 0
    }

    // MARK: - Mock Mode (DEBUG only, writes to same keys as HealthKit)

    var isMockModeEnabled: Bool {
        get { defaults?.bool(forKey: "mockModeEnabled") ?? false }
        set { defaults?.set(newValue, forKey: "mockModeEnabled") }
    }

    func clearGlucoseData() {
        defaults?.removeObject(forKey: "currentGlucose")
        defaults?.removeObject(forKey: "glucoseFetchedAt")
    }

    func clearCarbData() {
        defaults?.removeObject(forKey: "lastCarbGrams")
        defaults?.removeObject(forKey: "lastCarbEntryAt")
    }

    /// Disable mock mode. The cached glucose / carb values share storage
    /// with HealthKit and Nightscout (see `saveGlucose` doc), so we can't
    /// safely wipe them unconditionally — Nightscout-or-HK-sourced
    /// values would disappear too. `handleInAppSourceDisabled` only
    /// clears when no in-app source remains, leaving live sources to
    /// re-publish on their own poll/observer cycle.
    func clearMockData() {
        isMockModeEnabled = false
        handleInAppSourceDisabled()
        logger.info("Mock mode disabled")
    }

    // MARK: - Data Sources

    /// Set to true the first time Apple Health actually delivers a sample
    /// (glucose or carb). Stays true afterwards — we have no reliable way
    /// to detect that the user later revoked read access in the Health
    /// app, so "has ever delivered" is the most honest "we successfully
    /// got data from HK at some point" signal.
    ///
    /// Why not just use `HKHealthStore.authorizationStatus`? For read-only
    /// requests iOS privacy-masks that status: it returns `.sharingDenied`
    /// both when the user denied *and* when we haven't asked. A user who
    /// denied HealthKit looks identical to a user who accepted it until a
    /// sample arrives, so we wait for the sample.
    ///
    /// Treat this as historical only — for the "is HK currently a source
    /// I should trust?" question, use `healthKitDeliveringRecently`. The
    /// `hasAnyDataSource` gate combines that with the user-controlled
    /// Nightscout / Demo toggles.
    var healthKitEverDelivered: Bool {
        get { defaults?.bool(forKey: "healthKitEverDelivered") ?? false }
        set { defaults?.set(newValue, forKey: "healthKitEverDelivered") }
    }

    /// Call this from `HealthKitManager` as soon as a real sample is saved.
    func markHealthKitDelivered() {
        if healthKitEverDelivered { return }
        healthKitEverDelivered = true
        flush()
        logger.info("HealthKit marked as delivering")
    }

    /// True when Apple Health both has delivered at least one sample AND
    /// the latest stored glucose timestamp is fresher than `glucoseStaleMinutes`.
    /// Used as the "HK is currently active" proxy because iOS doesn't let
    /// us read the actual read-auth status (see `healthKitEverDelivered`).
    ///
    /// `glucoseFetchedAt` is shared across HK and Nightscout — that's
    /// fine: if anyone wrote a fresh sample recently, *something* is
    /// alive. When the user disables Nightscout/Demo the disable handler
    /// clears the cached values (see `handleInAppSourceDisabled`), so a
    /// stale-but-non-nil timestamp left over from a since-disabled source
    /// can't masquerade as HK delivery.
    ///
    /// Falls back to a 30-minute window when no user override is set so
    /// we don't have to read `Info.plist` from extension bundles where
    /// the key may not be present.
    var healthKitDeliveringRecently: Bool {
        guard healthKitEverDelivered, let last = glucoseFetchedAt else { return false }
        let minutes = glucoseStaleMinutes ?? 30
        return Date().timeIntervalSince(last) < TimeInterval(minutes * 60)
    }

    /// True when at least one data source can credibly be supplying data
    /// **right now**:
    ///
    /// - Nightscout / Demo: user has toggled them on.
    /// - Apple Health: has delivered a sample within `glucoseStaleMinutes`
    ///   (see `healthKitDeliveringRecently`).
    ///
    /// Drives both UI surfaces (welcome panel, setup checklist) and the
    /// shielding gate. Shielding can't make red/green decisions without
    /// fresh input, so disabling the last live source also disables
    /// shielding (see `ShieldManager.disableIfNoDataSource()`).
    var hasAnyDataSource: Bool {
        if nightscoutEnabled || isMockModeEnabled { return true }
        return healthKitDeliveringRecently
    }

    /// Call after the user disables an in-app data-source toggle
    /// (Nightscout, Demo). When no in-app source remains enabled, wipes
    /// the cached glucose + carb values so the home screen returns to the
    /// welcome state and the setup checklist re-shows the data-source
    /// rows immediately, rather than the user staring at a stale "green
    /// with data" panel and an empty checklist.
    ///
    /// HK is intentionally not in the "anything left" check here — we
    /// can't programmatically tell whether HK read auth is still granted.
    /// Two outcomes both end up correct:
    /// - HK is still authorized and delivering → its next observer fire
    ///   re-populates the cleared values within seconds.
    /// - HK was revoked / never set up → the values stay cleared and the
    ///   welcome / setup state is honest.
    func handleInAppSourceDisabled() {
        guard !nightscoutEnabled, !isMockModeEnabled else { return }
        clearGlucoseData()
        clearCarbData()
        flush()
        logger.info("All in-app data sources disabled — cleared cached glucose/carb values")
    }

    // MARK: - Glucose Unit

    var glucoseUnit: GlucoseUnit {
        get {
            guard let raw = defaults?.string(forKey: "glucoseUnit"),
                  let unit = GlucoseUnit(rawValue: raw) else { return .mmolL }
            return unit
        }
        set {
            defaults?.set(newValue.rawValue, forKey: "glucoseUnit")
            WatchSessionManager.shared.sendLatestContext()
        }
    }

    var hasGlucoseUnitPreference: Bool {
        defaults?.string(forKey: "glucoseUnit") != nil
    }

    // MARK: - Settings (overrides for xcconfig defaults)

    var highGlucoseThreshold: Double? {
        get { defaults?.object(forKey: "highGlucoseThreshold") as? Double }
    }

    var lowGlucoseThreshold: Double? {
        get { defaults?.object(forKey: "lowGlucoseThreshold") as? Double }
    }

    var glucoseStaleMinutes: Int? {
        get { defaults?.object(forKey: "glucoseStaleMinutes") as? Int }
    }

    var carbGraceHour: Int? {
        get { defaults?.object(forKey: "carbGraceHour") as? Int }
    }

    var carbGraceMinute: Int? {
        get { defaults?.object(forKey: "carbGraceMinute") as? Int }
    }

    var attentionIntervalMinutes: Int? {
        get { defaults?.object(forKey: "attentionIntervalMinutes") as? Int }
    }

    var noAttentionIntervalMinutes: Int? {
        get { defaults?.object(forKey: "noAttentionIntervalMinutes") as? Int }
    }

    var cooldownSeconds: Int? {
        get { defaults?.object(forKey: "cooldownSeconds") as? Int }
    }

    /// Shielding is opt-in: a fresh install starts with it off so the
    /// checklist card can surface "Enable shielding" as a suggested next step.
    var shieldingEnabled: Bool {
        get { defaults?.object(forKey: "shieldingEnabled") as? Bool ?? false }
        set { defaults?.set(newValue, forKey: "shieldingEnabled") }
    }

    var onlyShieldWhenAttention: Bool {
        get { defaults?.object(forKey: "onlyShieldWhenAttention") as? Bool ?? false }
        set { defaults?.set(newValue, forKey: "onlyShieldWhenAttention") }
    }

    var glucoseBadgeMode: GlucoseBadgeMode {
        get {
            guard let raw = defaults?.string(forKey: "glucoseBadgeMode"),
                  let mode = GlucoseBadgeMode(rawValue: raw) else { return .off }
            return mode
        }
        set { defaults?.set(newValue.rawValue, forKey: "glucoseBadgeMode") }
    }

    func saveSettings(
        highGlucoseThreshold: Double,
        lowGlucoseThreshold: Double,
        glucoseStaleMinutes: Int,
        carbGraceHour: Int,
        carbGraceMinute: Int,
        attentionIntervalMinutes: Int,
        noAttentionIntervalMinutes: Int,
        cooldownSeconds: Int
    ) {
        defaults?.set(highGlucoseThreshold, forKey: "highGlucoseThreshold")
        defaults?.set(lowGlucoseThreshold, forKey: "lowGlucoseThreshold")
        defaults?.set(glucoseStaleMinutes, forKey: "glucoseStaleMinutes")
        defaults?.set(carbGraceHour, forKey: "carbGraceHour")
        defaults?.set(carbGraceMinute, forKey: "carbGraceMinute")
        defaults?.set(attentionIntervalMinutes, forKey: "attentionIntervalMinutes")
        defaults?.set(noAttentionIntervalMinutes, forKey: "noAttentionIntervalMinutes")
        defaults?.set(cooldownSeconds, forKey: "cooldownSeconds")
        logger.info("Settings saved: high=\(highGlucoseThreshold) low=\(lowGlucoseThreshold) stale=\(glucoseStaleMinutes)m grace=\(carbGraceHour):\(carbGraceMinute) interval=\(attentionIntervalMinutes)/\(noAttentionIntervalMinutes)m cooldown=\(cooldownSeconds)s")
        WatchSessionManager.shared.sendLatestContext()
    }

    // MARK: - Custom Attention Checks

    func flush() {
        defaults?.synchronize()
    }

    func customChecks(for scenario: AttentionScenario) -> [String]? {
        guard let data = defaults?.data(forKey: "checks.\(scenario.rawValue)") else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    func allCustomChecks() -> [AttentionScenario: [String]] {
        AttentionScenario.loadCustomChecks(from: defaults)
    }

    func saveCustomChecks(_ checks: [String]?, for scenario: AttentionScenario) {
        if let checks, let data = try? JSONEncoder().encode(checks) {
            defaults?.set(data, forKey: "checks.\(scenario.rawValue)")
        } else {
            defaults?.removeObject(forKey: "checks.\(scenario.rawValue)")
        }
        WatchSessionManager.shared.sendLatestContext()
    }

    func clearAllCustomChecks() {
        for scenario in AttentionScenario.allCases {
            defaults?.removeObject(forKey: "checks.\(scenario.rawValue)")
        }
        logger.info("All custom checks cleared")
        WatchSessionManager.shared.sendLatestContext()
    }

    /// Remove every key from the App Group UserDefaults suite.
    ///
    /// iOS preserves the App Group container across app deletion (the
    /// container is system-owned, not part of the app's sandbox), so a fresh
    /// install would otherwise inherit stale settings, glucose samples,
    /// data-source flags, and shielding state from the previous install.
    /// Call this from the "first launch after install" handler in
    /// `MainApp.init()` to give re-installers a clean slate.
    ///
    /// Also re-registers the watch context so the paired watch reflects the
    /// reset (in case the watch app survived).
    func wipeAllForFreshInstall() {
        guard let defaults else { return }
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        logger.info("Wiped all App Group UserDefaults for fresh install")
        WatchSessionManager.shared.sendLatestContext()
    }

    /// Reset all settings to defaults, preserving passphrase, authorization mode, allowed apps, and health data.
    func resetAllSettings() {
        let settingsKeys = [
            "highGlucoseThreshold", "lowGlucoseThreshold",
            "glucoseStaleMinutes", "carbGraceHour", "carbGraceMinute",
            "attentionIntervalMinutes", "noAttentionIntervalMinutes",
            "cooldownSeconds", "shieldingEnabled", "onlyShieldWhenAttention",
            "glucoseBadgeMode", "glucoseUnit", "rearmShieldsAt", "mockModeEnabled",
            "nightscoutEnabled", "nightscoutBaseURL", "nightscoutToken",
            "nightscoutLastFetchedAt", "nightscoutLastError",
            "setupTipsHidden",
            "healthKitEverDelivered",
        ]
        for key in settingsKeys {
            defaults?.removeObject(forKey: key)
        }
        clearAllCustomChecks()
        logger.info("All settings reset to defaults")
        WatchSessionManager.shared.sendLatestContext()
    }

    // MARK: - Nightscout

    var nightscoutEnabled: Bool {
        get { defaults?.bool(forKey: "nightscoutEnabled") ?? false }
        set { defaults?.set(newValue, forKey: "nightscoutEnabled") }
    }

    var nightscoutBaseURL: String? {
        get {
            guard let value = defaults?.string(forKey: "nightscoutBaseURL"),
                  !value.isEmpty else { return nil }
            return value
        }
        set {
            if let value = newValue, !value.isEmpty {
                defaults?.set(value, forKey: "nightscoutBaseURL")
            } else {
                defaults?.removeObject(forKey: "nightscoutBaseURL")
            }
        }
    }

    var nightscoutToken: String? {
        get {
            guard let value = defaults?.string(forKey: "nightscoutToken"),
                  !value.isEmpty else { return nil }
            return value
        }
        set {
            if let value = newValue, !value.isEmpty {
                defaults?.set(value, forKey: "nightscoutToken")
            } else {
                defaults?.removeObject(forKey: "nightscoutToken")
            }
        }
    }

    /// Timestamp of the last successful Nightscout fetch (surfaced in Settings).
    var nightscoutLastFetchedAt: Date? {
        get {
            guard let iso = defaults?.string(forKey: "nightscoutLastFetchedAt") else { return nil }
            return ISO8601DateFormatter().date(from: iso)
        }
        set {
            if let date = newValue {
                defaults?.set(date.ISO8601Format(), forKey: "nightscoutLastFetchedAt")
            } else {
                defaults?.removeObject(forKey: "nightscoutLastFetchedAt")
            }
        }
    }

    /// Last error message from Nightscout (surfaced in Settings).
    var nightscoutLastError: String? {
        get { defaults?.string(forKey: "nightscoutLastError") }
        set {
            if let error = newValue {
                defaults?.set(error, forKey: "nightscoutLastError")
            } else {
                defaults?.removeObject(forKey: "nightscoutLastError")
            }
        }
    }

    // MARK: - Authorization Mode

    /// Whether `.child` or `.individual` authorization was used during setup.
    /// Needed to re-authorize with the correct member on subsequent launches.
    var authorizationMember: FamilyControlsMember? {
        get {
            guard let raw = defaults?.string(forKey: "authorizationMember") else { return nil }
            return raw == "child" ? .child : .individual
        }
        set {
            if let member = newValue {
                defaults?.set(member == .child ? "child" : "individual", forKey: "authorizationMember")
                logger.info("Saved authorization member: \(member == .child ? "child" : "individual")")
            } else {
                defaults?.removeObject(forKey: "authorizationMember")
            }
        }
    }

    // MARK: - Setup Checklist

    /// Whether the user has dismissed the "Set up" checklist card on the home
    /// screen. When true, the card stays hidden even if optional features are
    /// still unconfigured. Everything stays reachable via Settings.
    var setupTipsHidden: Bool {
        get { defaults?.bool(forKey: "setupTipsHidden") ?? false }
        set { defaults?.set(newValue, forKey: "setupTipsHidden") }
    }

    // MARK: - Allowed Apps

    func saveSelection(_ selection: FamilyActivitySelection) throws {
        let data = try PropertyListEncoder().encode(selection)
        defaults?.set(data, forKey: "allowedAppTokens")
        logger.info("Saved selection: \(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories")
    }

    func loadSelection() -> FamilyActivitySelection? {
        guard let data = defaults?.data(forKey: "allowedAppTokens") else {
            logger.warning("No allowedAppTokens data in App Group")
            return nil
        }
        do {
            let selection = try PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
            logger.info("Loaded selection: \(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories")
            return selection
        } catch {
            logger.error("Failed to decode selection: \(error.localizedDescription)")
            return nil
        }
    }
}
