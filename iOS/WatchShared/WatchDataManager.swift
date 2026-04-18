import Foundation
import SharedKit

enum WatchDataManager {
    private static let defaults = UserDefaults(suiteName: Constants.appGroupID)

    private static let highGlucoseThreshold = Double(Bundle.main.object(forInfoDictionaryKey: "HighGlucoseThreshold") as! String)!
    private static let lowGlucoseThreshold = Double(Bundle.main.object(forInfoDictionaryKey: "LowGlucoseThreshold") as! String)!
    private static let glucoseStaleMinutes = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
    private static let carbGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
    private static let carbGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!

    static var isMockModeEnabled: Bool {
        if let bridgeContext = SimulatorWatchBridge.loadContext(),
           let isMockModeEnabled = bridgeContext["mockModeEnabled"] as? Bool {
            return isMockModeEnabled
        }
        return defaults?.bool(forKey: "mockModeEnabled") ?? false
    }

    static func content(now: Date = Date()) -> ShieldContent {
        let bridgeContext = SimulatorWatchBridge.loadContext()
        let useBridgeMockData = bridgeContext?["mockModeEnabled"] as? Bool ?? false

        let glucose = useBridgeMockData
            ? (bridgeContext?["currentGlucose"] as? Double ?? 0)
            : (defaults?.double(forKey: "currentGlucose") ?? 0)
        let glucoseFetchedAt = useBridgeMockData
            ? (bridgeContext?["glucoseFetchedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            : defaults?.string(forKey: "glucoseFetchedAt").flatMap { ISO8601DateFormatter().date(from: $0) }
        let lastCarbGrams = useBridgeMockData
            ? (bridgeContext?["lastCarbGrams"] as? Double ?? 0)
            : (defaults?.double(forKey: "lastCarbGrams") ?? 0)
        let lastCarbEntryAt = useBridgeMockData
            ? (bridgeContext?["lastCarbEntryAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            : defaults?.string(forKey: "lastCarbEntryAt").flatMap { ISO8601DateFormatter().date(from: $0) }

        let unit: GlucoseUnit = (bridgeContext?["glucoseUnit"] as? String)
            .flatMap { GlucoseUnit(rawValue: $0) }
            ?? defaults?.string(forKey: "glucoseUnit").flatMap { GlucoseUnit(rawValue: $0) }
            ?? .mmolL

        let high = (bridgeContext?["highGlucoseThreshold"] as? Double)
            ?? defaults?.object(forKey: "highGlucoseThreshold") as? Double
            ?? highGlucoseThreshold
        let low = (bridgeContext?["lowGlucoseThreshold"] as? Double)
            ?? defaults?.object(forKey: "lowGlucoseThreshold") as? Double
            ?? lowGlucoseThreshold
        let stale = (bridgeContext?["glucoseStaleMinutes"] as? Int)
            ?? defaults?.object(forKey: "glucoseStaleMinutes") as? Int
            ?? glucoseStaleMinutes
        let graceHour = (bridgeContext?["carbGraceHour"] as? Int)
            ?? defaults?.object(forKey: "carbGraceHour") as? Int
            ?? carbGraceHour
        let graceMinute = (bridgeContext?["carbGraceMinute"] as? Int)
            ?? defaults?.object(forKey: "carbGraceMinute") as? Int
            ?? carbGraceMinute
        let customChecks = customChecks(from: bridgeContext) ?? AttentionScenario.loadCustomChecks(from: defaults)

        return ShieldContent(
            glucose: glucose,
            glucoseFetchedAt: glucoseFetchedAt,
            lastCarbGrams: lastCarbGrams > 0 ? lastCarbGrams : nil,
            lastCarbEntryAt: lastCarbEntryAt,
            highGlucoseThreshold: high,
            lowGlucoseThreshold: low,
            glucoseStaleMinutes: stale,
            carbGraceHour: graceHour,
            carbGraceMinute: graceMinute,
            glucoseUnit: unit,
            customChecks: customChecks,
            strings: .fromPackage(),
            now: now
        )
    }

    static var glucoseFetchedAt: Date? {
        guard let iso = defaults?.string(forKey: "glucoseFetchedAt") else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    static var lastCarbEntryAt: Date? {
        guard let iso = defaults?.string(forKey: "lastCarbEntryAt") else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    /// Persist a glucose sample. "Save if newer" — both HealthKit and
    /// Nightscout on the watch write to these keys, so keep whichever is
    /// freshest.
    static func storeGlucose(mmol: Double, at date: Date, force: Bool = false) {
        if !force, let existing = glucoseFetchedAt, date <= existing { return }
        defaults?.set(mmol, forKey: "currentGlucose")
        defaults?.set(date.ISO8601Format(), forKey: "glucoseFetchedAt")
    }

    static func storeCarbs(grams: Double, at date: Date, force: Bool = false) {
        if !force, let existing = lastCarbEntryAt, date <= existing { return }
        defaults?.set(grams, forKey: "lastCarbGrams")
        defaults?.set(date.ISO8601Format(), forKey: "lastCarbEntryAt")
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
        } else {
            defaults?.removeObject(forKey: "currentGlucose")
            defaults?.removeObject(forKey: "glucoseFetchedAt")
            defaults?.removeObject(forKey: "lastCarbGrams")
            defaults?.removeObject(forKey: "lastCarbEntryAt")
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
