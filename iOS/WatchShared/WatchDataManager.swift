import Foundation
import SharedKit

enum WatchDataManager {
    private static let defaults = UserDefaults(suiteName: Constants.appGroupID)

    /// xcconfig fallbacks. Watch resolution stays a 3-tier chain
    /// (`bridgeContext > defaults > xcconfig`) — see `content(now:)` — so the
    /// extra simulator-bridge layer is preserved on top of `ThresholdResolver`'s
    /// defaults+fallback. This keeps Phase-5 / screenshot-harness flows working.
    private static let fallbackHighGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "HighGlucoseThreshold") as! String)!
    private static let fallbackLowGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "LowGlucoseThreshold") as! String)!
    private static let fallbackCriticalGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "CriticalGlucoseThreshold") as! String)!
    private static let fallbackStaleMinutes = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
    private static let fallbackCarbGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
    private static let fallbackCarbGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!

    static var isMockModeEnabled: Bool {
        if let bridgeContext = SimulatorWatchBridge.loadContext(),
           let isMockModeEnabled = bridgeContext["mockModeEnabled"] as? Bool {
            return isMockModeEnabled
        }
        return defaults?.bool(forKey: "mockModeEnabled") ?? false
    }

    static func content(now: Date = Date()) -> ShieldContent {
        let bridgeContext = SimulatorWatchBridge.loadContext()

        let glucose = bridgeMockDouble(forKey: "currentGlucose", bridge: bridgeContext)
            ?? (defaults?.double(forKey: "currentGlucose") ?? 0)
        let glucoseFetchedAt = bridgeOrDefaultsDate(forKey: "glucoseFetchedAt", bridge: bridgeContext)
        let lastCarbGrams = bridgeMockDouble(forKey: "lastCarbGrams", bridge: bridgeContext)
            ?? (defaults?.double(forKey: "lastCarbGrams") ?? 0)
        let lastCarbEntryAt = bridgeOrDefaultsDate(forKey: "lastCarbEntryAt", bridge: bridgeContext)
        let lastCarbLabel: String? = {
            if (bridgeContext?["mockModeEnabled"] as? Bool) == true {
                return bridgeContext?["lastCarbLabel"] as? String
            }
            return defaults?.string(forKey: "lastCarbLabel")
        }()

        let unit: GlucoseUnit = (bridgeContext?["glucoseUnit"] as? String)
            .flatMap { GlucoseUnit(rawValue: $0) }
            ?? defaults?.string(forKey: "glucoseUnit").flatMap { GlucoseUnit(rawValue: $0) }
            ?? .mmolL

        let high = (bridgeContext?["highGlucoseThreshold"] as? Double)
            ?? ThresholdResolver.highGlucose(defaults: defaults, fallback: fallbackHighGlucose)
        let low = (bridgeContext?["lowGlucoseThreshold"] as? Double)
            ?? ThresholdResolver.lowGlucose(defaults: defaults, fallback: fallbackLowGlucose)
        let critical = (bridgeContext?["criticalGlucoseThreshold"] as? Double)
            ?? ThresholdResolver.criticalGlucose(defaults: defaults, fallback: fallbackCriticalGlucose)
        let stale = (bridgeContext?["glucoseStaleMinutes"] as? Int)
            ?? ThresholdResolver.staleMinutes(defaults: defaults, fallback: fallbackStaleMinutes)
        let graceHour = (bridgeContext?["carbGraceHour"] as? Int)
            ?? ThresholdResolver.carbGraceHour(defaults: defaults, fallback: fallbackCarbGraceHour)
        let graceMinute = (bridgeContext?["carbGraceMinute"] as? Int)
            ?? ThresholdResolver.carbGraceMinute(defaults: defaults, fallback: fallbackCarbGraceMinute)
        let customChecks = customChecks(from: bridgeContext) ?? AttentionScenario.loadCustomChecks(from: defaults)

        let carbsEnabled = (bridgeContext?["carbsEnabled"] as? Bool)
            ?? defaults?.object(forKey: "carbsEnabled") as? Bool ?? true

        return ShieldContent(
            glucose: glucose,
            glucoseFetchedAt: glucoseFetchedAt,
            lastCarbGrams: lastCarbGrams > 0 ? lastCarbGrams : nil,
            lastCarbLabel: lastCarbGrams > 0 ? nil : lastCarbLabel,
            lastCarbEntryAt: lastCarbEntryAt,
            highGlucoseThreshold: high,
            lowGlucoseThreshold: low,
            criticalGlucoseThreshold: critical,
            glucoseStaleMinutes: stale,
            carbGraceHour: graceHour,
            carbGraceMinute: graceMinute,
            carbsEnabled: carbsEnabled,
            glucoseUnit: unit,
            customChecks: customChecks,
            strings: .fromPackage(),
            now: now
        )
    }

    static var glucoseFetchedAt: Date? {
        bridgeOrDefaultsDate(forKey: "glucoseFetchedAt", bridge: SimulatorWatchBridge.loadContext())
    }

    static var lastCarbEntryAt: Date? {
        bridgeOrDefaultsDate(forKey: "lastCarbEntryAt", bridge: SimulatorWatchBridge.loadContext())
    }

    /// Resolve an ISO-8601 date using the same precedence as `content(now:)`:
    /// when the simulator bridge has mock-mode data, the bridge fully shadows
    /// defaults (a missing key returns `nil`, not a stale defaults value);
    /// otherwise read from the watch-local App Group `defaults`. On hardware
    /// `SimulatorWatchBridge.loadContext()` returns `nil`, so this degenerates
    /// to the defaults-only path with no behaviour change.
    ///
    /// Used by both `content()` and the static `glucoseFetchedAt` /
    /// `lastCarbEntryAt` getters so widget `WatchEntry` dates and watch app
    /// "Xm ago" labels stay consistent with `ShieldContent.glucose?.agoMinutes`
    /// — without this, the static getters returned `nil` in mock-mode
    /// simulator runs because the watch sim has no provisioned App Group.
    private static func bridgeOrDefaultsDate(forKey key: String, bridge: [String: Any]?) -> Date? {
        if (bridge?["mockModeEnabled"] as? Bool) == true {
            guard let iso = bridge?[key] as? String else { return nil }
            return ISO8601DateFormatter().date(from: iso)
        }
        guard let iso = defaults?.string(forKey: key) else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    /// Sibling of `bridgeOrDefaultsDate` for numeric mock-mode values. Mock
    /// mode also shadows defaults — a missing key returns `0` (not the stale
    /// defaults value) — and a `nil` return means "bridge isn't supplying mock
    /// data, fall through to defaults" so callers stay symmetric.
    private static func bridgeMockDouble(forKey key: String, bridge: [String: Any]?) -> Double? {
        guard (bridge?["mockModeEnabled"] as? Bool) == true else { return nil }
        return (bridge?[key] as? Double) ?? 0
    }

    /// Persist a glucose sample. "Save if newer" — both HealthKit and
    /// Nightscout on the watch write to these keys, so keep whichever is
    /// freshest.
    static func storeGlucose(mmol: Double, at date: Date, force: Bool = false) {
        if !force, let existing = glucoseFetchedAt, date <= existing { return }
        defaults?.set(mmol, forKey: "currentGlucose")
        defaults?.set(date.ISO8601Format(), forKey: "glucoseFetchedAt")
    }

    /// Store a carb or meal-acknowledgment sample. Pass `nil` for `grams`
    /// when the source logged only that a meal occurred (no carb count).
    /// 0 is stored as the sentinel value so `content(now:)` maps it back to
    /// `lastCarbGrams: nil` via its existing `> 0` guard.
    static func storeCarbs(grams: Double?, label: String? = nil, at date: Date, force: Bool = false) {
        if !force, let existing = lastCarbEntryAt, date <= existing { return }
        defaults?.set(grams ?? 0.0, forKey: "lastCarbGrams")
        defaults?.set(date.ISO8601Format(), forKey: "lastCarbEntryAt")
        if let label {
            defaults?.set(label, forKey: "lastCarbLabel")
        } else {
            defaults?.removeObject(forKey: "lastCarbLabel")
        }
    }

    // MARK: - EasyView config (synced from phone)

    static var easyViewEnabled: Bool {
        defaults?.bool(forKey: "easyViewEnabled") ?? false
    }

    static var easyViewSession: String? {
        guard let value = defaults?.string(forKey: "easyViewSession"),
              !value.isEmpty else { return nil }
        return value
    }

    static var easyViewPatientUID: Int? {
        defaults?.object(forKey: "easyViewPatientUID") as? Int
    }

    // MARK: - LibreLinkUp config (synced from phone)

    static var librelinkupEnabled: Bool {
        defaults?.bool(forKey: "librelinkupEnabled") ?? false
    }

    /// Auth token mirrored from the phone. The watch has no Keychain access, so
    /// it can only read with this already-issued token — it never logs in.
    static var librelinkupToken: String? {
        guard let value = defaults?.string(forKey: "librelinkupToken"),
              !value.isEmpty else { return nil }
        return value
    }

    static var librelinkupTokenExpiry: Date? {
        guard let iso = defaults?.string(forKey: "librelinkupTokenExpiry") else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    static var librelinkupRegion: String? {
        guard let value = defaults?.string(forKey: "librelinkupRegion"),
              !value.isEmpty else { return nil }
        return value
    }

    static var librelinkupUserId: String? {
        guard let value = defaults?.string(forKey: "librelinkupUserId"),
              !value.isEmpty else { return nil }
        return value
    }

    static var librelinkupPatientId: String? {
        guard let value = defaults?.string(forKey: "librelinkupPatientId"),
              !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Nightscout config (synced from phone)

    static var nightscoutEnabled: Bool {
        defaults?.bool(forKey: "nightscoutEnabled") ?? false
    }

    static var nightscoutBaseURL: String? {
        guard let value = defaults?.string(forKey: "nightscoutBaseURL"),
              !value.isEmpty else { return nil }
        return value
    }

    static var nightscoutToken: String? {
        guard let value = defaults?.string(forKey: "nightscoutToken"),
              !value.isEmpty else { return nil }
        return value
    }

    static func updateFromPhoneContext(_ context: [String: Any]) {
        let numericKeys = [
            "highGlucoseThreshold",
            "lowGlucoseThreshold",
            "criticalGlucoseThreshold",
            "glucoseStaleMinutes",
            "carbGraceHour",
            "carbGraceMinute",
        ]

        for key in numericKeys {
            if let value = context[key] {
                defaults?.set(value, forKey: key)
            }
        }

        if let rawUnit = context["glucoseUnit"] as? String {
            defaults?.set(rawUnit, forKey: "glucoseUnit")
        }

        defaults?.set(context["carbsEnabled"] as? Bool ?? true, forKey: "carbsEnabled")

        let nightscoutEnabled = context["nightscoutEnabled"] as? Bool ?? false
        defaults?.set(nightscoutEnabled, forKey: "nightscoutEnabled")

        if let url = context["nightscoutBaseURL"] as? String, !url.isEmpty {
            defaults?.set(url, forKey: "nightscoutBaseURL")
        } else {
            defaults?.removeObject(forKey: "nightscoutBaseURL")
        }

        if let token = context["nightscoutToken"] as? String, !token.isEmpty {
            defaults?.set(token, forKey: "nightscoutToken")
        } else {
            defaults?.removeObject(forKey: "nightscoutToken")
        }

        let easyViewEnabled = context["easyViewEnabled"] as? Bool ?? false
        defaults?.set(easyViewEnabled, forKey: "easyViewEnabled")

        if let session = context["easyViewSession"] as? String, !session.isEmpty {
            defaults?.set(session, forKey: "easyViewSession")
        } else {
            defaults?.removeObject(forKey: "easyViewSession")
        }

        if let uid = context["easyViewPatientUID"] as? Int {
            defaults?.set(uid, forKey: "easyViewPatientUID")
        } else {
            defaults?.removeObject(forKey: "easyViewPatientUID")
        }

        let librelinkupEnabled = context["librelinkupEnabled"] as? Bool ?? false
        defaults?.set(librelinkupEnabled, forKey: "librelinkupEnabled")

        for key in ["librelinkupToken", "librelinkupTokenExpiry", "librelinkupRegion", "librelinkupUserId", "librelinkupPatientId"] {
            if let value = context[key] as? String, !value.isEmpty {
                defaults?.set(value, forKey: key)
            } else {
                defaults?.removeObject(forKey: key)
            }
        }

        let isMockModeEnabled = context["mockModeEnabled"] as? Bool ?? false
        defaults?.set(isMockModeEnabled, forKey: "mockModeEnabled")

        if isMockModeEnabled {
            if let currentGlucose = context["currentGlucose"] as? Double {
                defaults?.set(currentGlucose, forKey: "currentGlucose")
            } else {
                defaults?.removeObject(forKey: "currentGlucose")
            }

            if let glucoseFetchedAt = context["glucoseFetchedAt"] as? String {
                defaults?.set(glucoseFetchedAt, forKey: "glucoseFetchedAt")
            } else {
                defaults?.removeObject(forKey: "glucoseFetchedAt")
            }

            if let lastCarbGrams = context["lastCarbGrams"] as? Double {
                defaults?.set(lastCarbGrams, forKey: "lastCarbGrams")
            } else {
                defaults?.removeObject(forKey: "lastCarbGrams")
            }

            if let lastCarbEntryAt = context["lastCarbEntryAt"] as? String {
                defaults?.set(lastCarbEntryAt, forKey: "lastCarbEntryAt")
            } else {
                defaults?.removeObject(forKey: "lastCarbEntryAt")
            }

            if let lastCarbLabel = context["lastCarbLabel"] as? String {
                defaults?.set(lastCarbLabel, forKey: "lastCarbLabel")
            } else {
                defaults?.removeObject(forKey: "lastCarbLabel")
            }
        } else {
            defaults?.removeObject(forKey: "currentGlucose")
            defaults?.removeObject(forKey: "glucoseFetchedAt")
            defaults?.removeObject(forKey: "lastCarbGrams")
            defaults?.removeObject(forKey: "lastCarbEntryAt")
            defaults?.removeObject(forKey: "lastCarbLabel")
        }

        let customChecks = context["customChecks"] as? [String: [String]] ?? [:]
        for scenario in AttentionScenario.allCases {
            let key = "checks.\(scenario.rawValue)"
            if let checks = customChecks[scenario.rawValue],
               let data = try? JSONEncoder().encode(checks) {
                defaults?.set(data, forKey: key)
            } else {
                defaults?.removeObject(forKey: key)
            }
        }
    }

    private static func customChecks(from context: [String: Any]?) -> [AttentionScenario: [String]]? {
        guard let rawChecks = context?["customChecks"] as? [String: [String]] else { return nil }
        var result: [AttentionScenario: [String]] = [:]
        for (rawScenario, checks) in rawChecks {
            guard let scenario = AttentionScenario(rawValue: rawScenario) else { continue }
            result[scenario] = checks
        }
        return result
    }
}
