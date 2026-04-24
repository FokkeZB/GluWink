import Foundation

/// Centralised resolver for the user-tweakable attention thresholds.
///
/// The main app writes overrides to the App Group `UserDefaults` suite when
/// the user changes them in Settings. Every surface that compares a glucose
/// or carb value against a threshold (home screen, shield UI, shield action,
/// status widget, watch app, device activity monitor) **must** go through
/// this resolver so the override-vs-fallback contract can't drift again.
///
/// See `AGENTS.md` → "Shared App Group Container" → "Settings override
/// precedence" for the documented contract.
///
/// Each helper takes:
/// - `defaults`: the App Group `UserDefaults` to read the override from. Pass
///   `nil` if the suite couldn't be opened — the helper falls back to
///   `fallback`.
/// - `fallback`: the xcconfig default the caller already parsed out of its
///   own target's `Info.plist`. Per-target plists keep the same xcconfig
///   sources of truth, so the fallback is always correct for that target.
public enum ThresholdResolver {
    public static let highGlucoseKey = "highGlucoseThreshold"
    public static let lowGlucoseKey = "lowGlucoseThreshold"
    public static let criticalGlucoseKey = "criticalGlucoseThreshold"
    public static let staleMinutesKey = "glucoseStaleMinutes"
    public static let carbGraceHourKey = "carbGraceHour"
    public static let carbGraceMinuteKey = "carbGraceMinute"

    public static func highGlucose(defaults: UserDefaults?, fallback: Double) -> Double {
        (defaults?.object(forKey: highGlucoseKey) as? Double) ?? fallback
    }

    public static func lowGlucose(defaults: UserDefaults?, fallback: Double) -> Double {
        (defaults?.object(forKey: lowGlucoseKey) as? Double) ?? fallback
    }

    /// Resolve the critical glucose threshold (shield cannot be dismissed at or above this value).
    ///
    /// Contract: `criticalGlucose(...) > highGlucose(...)` is enforced at **write time**
    /// by `SettingsValidation`. At read time the resolver does **not** silently re-clamp
    /// — callers get whatever is persisted. If the invariant is violated (e.g. the user
    /// lowered `highGlucoseThreshold` after setting critical), comparisons still work
    /// because critical is only used as an `>=` gate; the Settings UI surfaces the
    /// validation error on the next save attempt.
    public static func criticalGlucose(defaults: UserDefaults?, fallback: Double) -> Double {
        (defaults?.object(forKey: criticalGlucoseKey) as? Double) ?? fallback
    }

    public static func staleMinutes(defaults: UserDefaults?, fallback: Int) -> Int {
        (defaults?.object(forKey: staleMinutesKey) as? Int) ?? fallback
    }

    public static func carbGraceHour(defaults: UserDefaults?, fallback: Int) -> Int {
        (defaults?.object(forKey: carbGraceHourKey) as? Int) ?? fallback
    }

    public static func carbGraceMinute(defaults: UserDefaults?, fallback: Int) -> Int {
        (defaults?.object(forKey: carbGraceMinuteKey) as? Int) ?? fallback
    }
}
