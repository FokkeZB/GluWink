import Foundation

/// The three data sources that can supply glucose + carb samples to the app.
///
/// Each source writes to its own set of App Group `UserDefaults` keys
/// (`<source>Glucose`, `<source>GlucoseSampleAt`, `<source>Carbs`,
/// `<source>CarbsSampleAt`). Readers across the app — home screen, shield
/// extensions, widgets, watch — go through `UnifiedDataReader` so a single
/// resolution rule decides which source's values actually get displayed.
public enum DataSource: String, Sendable, CaseIterable {
    case healthKit
    case nightscout
    case demo
}

/// Centralised key strings for everything tied to the per-source data
/// contract. Shield extensions and the Device Activity Monitor read App
/// Group `UserDefaults` directly (no `SharedDataManager` available there),
/// so these constants are the single source of truth for keys the App
/// target writes and everyone else reads.
public enum DataSourceKeys {
    public static let healthKitGlucose = "healthKitGlucose"
    public static let healthKitGlucoseSampleAt = "healthKitGlucoseSampleAt"
    public static let healthKitCarbs = "healthKitCarbs"
    public static let healthKitCarbsSampleAt = "healthKitCarbsSampleAt"

    public static let nightscoutGlucose = "nightscoutGlucose"
    public static let nightscoutGlucoseSampleAt = "nightscoutGlucoseSampleAt"
    public static let nightscoutCarbs = "nightscoutCarbs"
    public static let nightscoutCarbsSampleAt = "nightscoutCarbsSampleAt"

    public static let demoGlucose = "demoGlucose"
    public static let demoGlucoseSampleAt = "demoGlucoseSampleAt"
    public static let demoCarbs = "demoCarbs"
    public static let demoCarbsSampleAt = "demoCarbsSampleAt"

    public static let healthKitEnabled = "healthKitEnabled"
    public static let nightscoutEnabled = "nightscoutEnabled"
    public static let mockModeEnabled = "mockModeEnabled"
}

public struct GlucoseReading: Sendable, Equatable {
    public let mmol: Double
    public let sampleAt: Date
    public let source: DataSource

    public init(mmol: Double, sampleAt: Date, source: DataSource) {
        self.mmol = mmol
        self.sampleAt = sampleAt
        self.source = source
    }
}

public struct CarbsReading: Sendable, Equatable {
    public let grams: Double
    public let sampleAt: Date
    public let source: DataSource

    public init(grams: Double, sampleAt: Date, source: DataSource) {
        self.grams = grams
        self.sampleAt = sampleAt
        self.source = source
    }
}

/// Resolves which source's glucose + carb values should be displayed
/// right now, given the enabled toggles and per-source timestamps.
///
/// Resolution rule (mirrored for glucose and carbs independently):
///
/// 1. **Demo override.** When `mockModeEnabled == true`, Demo's value
///    for that metric wins — regardless of age, and regardless of
///    whether HealthKit / Nightscout also have fresher samples. The
///    user turning Demo on is an explicit "show me the fake data"
///    signal.
/// 2. **Freshest enabled source wins.** Otherwise, among the enabled
///    sources (`healthKitEnabled` → HealthKit, `nightscoutEnabled` →
///    Nightscout), pick the one with the newest `*SampleAt`. Glucose
///    and carbs are resolved independently, so it's fine (and expected)
///    for glucose to come from HealthKit while carbs come from
///    Nightscout.
/// 3. **Nil when no enabled source has a sample.** The caller is
///    responsible for rendering an empty / welcome state.
///
/// Disabled sources are ignored entirely — a user who toggles HealthKit
/// off keeps whatever cached `healthKit*` values are in storage, but
/// this reader never returns them. This is deliberate: we can't revoke
/// iOS HealthKit authorization programmatically, so the toggle is the
/// only authoritative "use this source?" signal.
public enum UnifiedDataReader {
    /// Build a glucose reading from the active source resolution rule.
    /// Returns nil when no enabled source has a stored sample.
    public static func currentGlucoseReading(from defaults: UserDefaults?) -> GlucoseReading? {
        guard let defaults else { return nil }

        if defaults.bool(forKey: DataSourceKeys.mockModeEnabled) {
            return glucoseReading(source: .demo, from: defaults)
        }

        var candidates: [GlucoseReading] = []
        if defaults.bool(forKey: DataSourceKeys.healthKitEnabled),
           let reading = glucoseReading(source: .healthKit, from: defaults) {
            candidates.append(reading)
        }
        if defaults.bool(forKey: DataSourceKeys.nightscoutEnabled),
           let reading = glucoseReading(source: .nightscout, from: defaults) {
            candidates.append(reading)
        }
        return candidates.max(by: { $0.sampleAt < $1.sampleAt })
    }

    /// Build a carbs reading from the active source resolution rule.
    /// Returns nil when no enabled source has a stored sample.
    public static func currentCarbsReading(from defaults: UserDefaults?) -> CarbsReading? {
        guard let defaults else { return nil }

        if defaults.bool(forKey: DataSourceKeys.mockModeEnabled) {
            return carbsReading(source: .demo, from: defaults)
        }

        var candidates: [CarbsReading] = []
        if defaults.bool(forKey: DataSourceKeys.healthKitEnabled),
           let reading = carbsReading(source: .healthKit, from: defaults) {
            candidates.append(reading)
        }
        if defaults.bool(forKey: DataSourceKeys.nightscoutEnabled),
           let reading = carbsReading(source: .nightscout, from: defaults) {
            candidates.append(reading)
        }
        return candidates.max(by: { $0.sampleAt < $1.sampleAt })
    }

    /// Per-source glucose reading, regardless of whether the source is the
    /// one currently winning the resolution rule. Used by the per-source
    /// settings screens to show "latest from this source" rows.
    public static func glucoseReading(source: DataSource, from defaults: UserDefaults?) -> GlucoseReading? {
        guard let defaults else { return nil }
        let value = defaults.double(forKey: glucoseValueKey(for: source))
        guard value > 0, let date = defaults.iso8601(forKey: glucoseDateKey(for: source)) else { return nil }
        return GlucoseReading(mmol: value, sampleAt: date, source: source)
    }

    public static func carbsReading(source: DataSource, from defaults: UserDefaults?) -> CarbsReading? {
        guard let defaults else { return nil }
        let value = defaults.double(forKey: carbsValueKey(for: source))
        guard value > 0, let date = defaults.iso8601(forKey: carbsDateKey(for: source)) else { return nil }
        return CarbsReading(grams: value, sampleAt: date, source: source)
    }

    public static func glucoseValueKey(for source: DataSource) -> String {
        switch source {
        case .healthKit: return DataSourceKeys.healthKitGlucose
        case .nightscout: return DataSourceKeys.nightscoutGlucose
        case .demo: return DataSourceKeys.demoGlucose
        }
    }

    public static func glucoseDateKey(for source: DataSource) -> String {
        switch source {
        case .healthKit: return DataSourceKeys.healthKitGlucoseSampleAt
        case .nightscout: return DataSourceKeys.nightscoutGlucoseSampleAt
        case .demo: return DataSourceKeys.demoGlucoseSampleAt
        }
    }

    public static func carbsValueKey(for source: DataSource) -> String {
        switch source {
        case .healthKit: return DataSourceKeys.healthKitCarbs
        case .nightscout: return DataSourceKeys.nightscoutCarbs
        case .demo: return DataSourceKeys.demoCarbs
        }
    }

    public static func carbsDateKey(for source: DataSource) -> String {
        switch source {
        case .healthKit: return DataSourceKeys.healthKitCarbsSampleAt
        case .nightscout: return DataSourceKeys.nightscoutCarbsSampleAt
        case .demo: return DataSourceKeys.demoCarbsSampleAt
        }
    }
}

extension UserDefaults {
    /// Read an ISO8601-formatted date string and parse it. Returns nil on
    /// missing value or malformed string.
    fileprivate func iso8601(forKey key: String) -> Date? {
        guard let iso = string(forKey: key) else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }
}
