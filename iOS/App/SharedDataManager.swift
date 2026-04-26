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

    // MARK: - Unified readings (single source of truth for display)

    /// Glucose reading the app should display right now: Demo wins when
    /// mock mode is on, otherwise the freshest reading among enabled
    /// sources. Returns nil when no enabled source has a sample. See
    /// `SharedKit.UnifiedDataReader` for the full contract.
    var currentGlucoseReading: GlucoseReading? {
        UnifiedDataReader.currentGlucoseReading(from: defaults)
    }

    var currentCarbsReading: CarbsReading? {
        UnifiedDataReader.currentCarbsReading(from: defaults)
    }

    // MARK: - Per-source values (raw storage)

    /// Returns the value and timestamp this source has cached, regardless
    /// of whether it's currently the winning source in the resolver. Used
    /// by the per-source settings screens ("last seen from this source"
    /// rows) and by writers that need to compare against their own last
    /// write.
    func glucoseReading(source: DataSource) -> GlucoseReading? {
        UnifiedDataReader.glucoseReading(source: source, from: defaults)
    }

    func carbsReading(source: DataSource) -> CarbsReading? {
        UnifiedDataReader.carbsReading(source: source, from: defaults)
    }

    /// Write a glucose sample for a specific source. Default behaviour is
    /// "save if newer" against that source's own timestamp so out-of-order
    /// writes from HealthKit background deliveries can't overwrite a
    /// fresher sample. Pass `force: true` when the caller is explicitly
    /// stamping older data (Demo mode configuration).
    func saveHealthKitGlucose(mmol: Double, at date: Date, force: Bool = false) {
        saveGlucose(source: .healthKit, mmol: mmol, at: date, force: force)
    }

    func saveNightscoutGlucose(mmol: Double, at date: Date, force: Bool = false) {
        saveGlucose(source: .nightscout, mmol: mmol, at: date, force: force)
    }

    func saveDemoGlucose(mmol: Double, at date: Date, force: Bool = true) {
        saveGlucose(source: .demo, mmol: mmol, at: date, force: force)
    }

    func saveHealthKitCarbs(grams: Double, at date: Date, force: Bool = false) {
        saveCarbs(source: .healthKit, grams: grams, at: date, force: force)
    }

    func saveNightscoutCarbs(grams: Double, at date: Date, force: Bool = false) {
        saveCarbs(source: .nightscout, grams: grams, at: date, force: force)
    }

    func saveDemoCarbs(grams: Double, at date: Date, force: Bool = true) {
        saveCarbs(source: .demo, grams: grams, at: date, force: force)
    }

    /// Clear every cached value for a single source. Used when:
    ///
    /// - The user toggles HealthKit off (see `handleSourceDisabled(.healthKit)`).
    /// - The user toggles Nightscout off and wants its last reading out of
    ///   the way.
    /// - Demo mode is disabled and its synthesised values should stop
    ///   masquerading as real data.
    func clearHealthKitData() { clearSource(.healthKit) }
    func clearNightscoutData() { clearSource(.nightscout) }
    func clearDemoData() { clearSource(.demo) }

    /// Targeted per-metric clears — used by the Demo Settings panel
    /// where each metric has its own "has data?" toggle, so clearing
    /// glucose must not wipe the carbs the user is still editing.
    func clearDemoGlucose() {
        defaults?.removeObject(forKey: UnifiedDataReader.glucoseValueKey(for: .demo))
        defaults?.removeObject(forKey: UnifiedDataReader.glucoseDateKey(for: .demo))
    }

    func clearDemoCarbs() {
        defaults?.removeObject(forKey: UnifiedDataReader.carbsValueKey(for: .demo))
        defaults?.removeObject(forKey: UnifiedDataReader.carbsDateKey(for: .demo))
    }

    private func saveGlucose(source: DataSource, mmol: Double, at date: Date, force: Bool) {
        let valueKey = UnifiedDataReader.glucoseValueKey(for: source)
        let dateKey = UnifiedDataReader.glucoseDateKey(for: source)
        if !force, let existingIso = defaults?.string(forKey: dateKey),
           let existing = ISO8601DateFormatter().date(from: existingIso),
           date <= existing { return }
        defaults?.set(mmol, forKey: valueKey)
        defaults?.set(date.ISO8601Format(), forKey: dateKey)
    }

    private func saveCarbs(source: DataSource, grams: Double, at date: Date, force: Bool) {
        let valueKey = UnifiedDataReader.carbsValueKey(for: source)
        let dateKey = UnifiedDataReader.carbsDateKey(for: source)
        if !force, let existingIso = defaults?.string(forKey: dateKey),
           let existing = ISO8601DateFormatter().date(from: existingIso),
           date <= existing { return }
        defaults?.set(grams, forKey: valueKey)
        defaults?.set(date.ISO8601Format(), forKey: dateKey)
    }

    private func clearSource(_ source: DataSource) {
        defaults?.removeObject(forKey: UnifiedDataReader.glucoseValueKey(for: source))
        defaults?.removeObject(forKey: UnifiedDataReader.glucoseDateKey(for: source))
        defaults?.removeObject(forKey: UnifiedDataReader.carbsValueKey(for: source))
        defaults?.removeObject(forKey: UnifiedDataReader.carbsDateKey(for: source))
    }

    // MARK: - Attention Badge

    /// Recompute the attention state and update the app icon badge.
    ///
    /// The home-screen icon itself never changes — it always uses `AppIcon`. The
    /// green/orange/red variants (`AppIcon-Green`, `AppIcon-Orange`, `AppIcon-Red`) are only used by
    /// surfaces we can pick at render time (shield UI, in-app screens, future
    /// notification attachments).
    ///
    /// Attention is computed by delegating to `ShieldContent` so the badge,
    /// the shield extension, the widgets, and the home screen agree on the
    /// ladder. Duplicate ladders previously drifted (e.g. "no carb data ever"
    /// was attention in `ShieldContent` but not in the badge).
    @MainActor
    func refreshAttentionBadge() {
        let glucoseReading = currentGlucoseReading
        let carbsReading = currentCarbsReading
        let glucose = glucoseReading?.mmol ?? 0
        let content = ShieldContent(
            glucose: glucose,
            glucoseFetchedAt: glucoseReading?.sampleAt,
            lastCarbGrams: carbsReading?.grams,
            lastCarbEntryAt: carbsReading?.sampleAt,
            highGlucoseThreshold: effectiveHighGlucoseThreshold,
            lowGlucoseThreshold: effectiveLowGlucoseThreshold,
            criticalGlucoseThreshold: effectiveCriticalGlucoseThreshold,
            glucoseStaleMinutes: effectiveGlucoseStaleMinutes,
            carbGraceHour: effectiveCarbGraceHour,
            carbGraceMinute: effectiveCarbGraceMinute,
            glucoseUnit: glucoseUnit,
            strings: ShieldContent.Strings.fromPackage()
        )
        updateBadge(glucose: glucose, needsAttention: content.needsAttention)
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

    // MARK: - Data-source toggles

    /// Whether the user has toggled Apple Health on in Settings. This is
    /// the only authoritative "use HealthKit data?" signal — iOS privacy-
    /// masks the read auth status, so we can't tell from the system
    /// whether the user actually granted access. The toggle is the gate.
    var healthKitEnabled: Bool {
        get { defaults?.bool(forKey: DataSourceKeys.healthKitEnabled) ?? false }
        set { defaults?.set(newValue, forKey: DataSourceKeys.healthKitEnabled) }
    }

    var isMockModeEnabled: Bool {
        get { defaults?.bool(forKey: DataSourceKeys.mockModeEnabled) ?? false }
        set { defaults?.set(newValue, forKey: DataSourceKeys.mockModeEnabled) }
    }

    /// Disable mock mode. Clears Demo's cached values so the synthesised
    /// numbers can't leak into the resolver on the next launch (the
    /// resolver already ignores Demo when `mockModeEnabled == false`, but
    /// clearing prevents the next "enable" from showing stale demo data
    /// before the user reconfigures).
    func clearMockData() {
        isMockModeEnabled = false
        clearDemoData()
        logger.info("Mock mode disabled")
    }

    /// True when at least one data source is toggled on. Drives the
    /// welcome panel, the setup checklist, and the shielding gate. With
    /// per-source toggles in place this is now a simple `OR` of the
    /// three enabled flags — no recency heuristic needed.
    var hasAnyDataSource: Bool {
        healthKitEnabled || nightscoutEnabled || isMockModeEnabled
    }

    /// Call after a data-source toggle flips off. Clears the disabled
    /// source's cached values so neither the resolver nor the
    /// per-source settings screen shows stale numbers from it, and
    /// returns so callers can decide whether to kick remaining live
    /// sources.
    ///
    /// Unlike the previous "clear everything if nothing left" heuristic,
    /// this is always safe: each source owns its own keys now, so
    /// clearing HK never affects Nightscout's cache and vice versa. The
    /// resolver ignores disabled sources anyway, so clearing is only
    /// about keeping the per-source screens honest.
    func handleSourceDisabled(_ source: DataSource) {
        clearSource(source)
        flush()
        logger.info("Cleared cached values for disabled source: \(source.rawValue)")
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

    /// Raw user override for the critical glucose threshold. `nil` when the
    /// user hasn't changed the xcconfig default. The `> high` invariant is
    /// enforced at write time by `SettingsValidation`, not by this accessor.
    var criticalGlucoseThreshold: Double? {
        get { defaults?.object(forKey: "criticalGlucoseThreshold") as? Double }
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

    // MARK: - Effective thresholds (override → xcconfig fallback)

    /// Resolved `highGlucoseThreshold`: user override if set, otherwise the
    /// xcconfig default from `SettingsDefaults`. Use these from every App
    /// surface that evaluates attention so the override contract documented
    /// in `AGENTS.md` → "Settings override precedence" can't drift.
    var effectiveHighGlucoseThreshold: Double {
        ThresholdResolver.highGlucose(defaults: defaults, fallback: SettingsDefaults.highGlucose)
    }

    var effectiveLowGlucoseThreshold: Double {
        ThresholdResolver.lowGlucose(defaults: defaults, fallback: SettingsDefaults.lowGlucose)
    }

    var effectiveCriticalGlucoseThreshold: Double {
        ThresholdResolver.criticalGlucose(defaults: defaults, fallback: SettingsDefaults.criticalGlucose)
    }

    var effectiveGlucoseStaleMinutes: Int {
        ThresholdResolver.staleMinutes(defaults: defaults, fallback: SettingsDefaults.staleMinutes)
    }

    var effectiveCarbGraceHour: Int {
        ThresholdResolver.carbGraceHour(defaults: defaults, fallback: SettingsDefaults.carbGraceHour)
    }

    var effectiveCarbGraceMinute: Int {
        ThresholdResolver.carbGraceMinute(defaults: defaults, fallback: SettingsDefaults.carbGraceMinute)
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

    /// Persist all attention + shielding tunables in one call.
    ///
    /// Callers are responsible for enforcing `criticalGlucoseThreshold >
    /// highGlucoseThreshold` via `SettingsValidation.validateCriticalAboveHigh`
    /// before invoking this. If the invariant is violated, the store still
    /// accepts the values — surfacing the error is the Settings UI's job.
    func saveSettings(
        highGlucoseThreshold: Double,
        lowGlucoseThreshold: Double,
        criticalGlucoseThreshold: Double,
        glucoseStaleMinutes: Int,
        carbGraceHour: Int,
        carbGraceMinute: Int,
        attentionIntervalMinutes: Int,
        noAttentionIntervalMinutes: Int,
        cooldownSeconds: Int
    ) {
        defaults?.set(highGlucoseThreshold, forKey: "highGlucoseThreshold")
        defaults?.set(lowGlucoseThreshold, forKey: "lowGlucoseThreshold")
        defaults?.set(criticalGlucoseThreshold, forKey: "criticalGlucoseThreshold")
        defaults?.set(glucoseStaleMinutes, forKey: "glucoseStaleMinutes")
        defaults?.set(carbGraceHour, forKey: "carbGraceHour")
        defaults?.set(carbGraceMinute, forKey: "carbGraceMinute")
        defaults?.set(attentionIntervalMinutes, forKey: "attentionIntervalMinutes")
        defaults?.set(noAttentionIntervalMinutes, forKey: "noAttentionIntervalMinutes")
        defaults?.set(cooldownSeconds, forKey: "cooldownSeconds")
        logger.info("Settings saved: high=\(highGlucoseThreshold) low=\(lowGlucoseThreshold) critical=\(criticalGlucoseThreshold) stale=\(glucoseStaleMinutes)m grace=\(carbGraceHour):\(carbGraceMinute) interval=\(attentionIntervalMinutes)/\(noAttentionIntervalMinutes)m cooldown=\(cooldownSeconds)s")
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
            "highGlucoseThreshold", "lowGlucoseThreshold", "criticalGlucoseThreshold",
            "glucoseStaleMinutes", "carbGraceHour", "carbGraceMinute",
            "attentionIntervalMinutes", "noAttentionIntervalMinutes",
            "cooldownSeconds", "shieldingEnabled", "onlyShieldWhenAttention",
            "glucoseBadgeMode", "glucoseUnit", "rearmShieldsAt",
            DataSourceKeys.mockModeEnabled,
            DataSourceKeys.nightscoutEnabled,
            DataSourceKeys.healthKitEnabled,
            "nightscoutBaseURL", "nightscoutToken",
            "nightscoutLastFetchedAt", "nightscoutLastError",
            "setupTipsHidden",
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
        get { defaults?.bool(forKey: DataSourceKeys.nightscoutEnabled) ?? false }
        set { defaults?.set(newValue, forKey: DataSourceKeys.nightscoutEnabled) }
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
