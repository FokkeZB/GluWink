import Foundation

/// Scenarios that trigger attention checks on the shield.
public enum AttentionScenario: String, CaseIterable, Codable, Identifiable, Sendable {
    case highGlucose
    /// Glucose is at or above `criticalGlucoseThreshold`. The shield cannot
    /// be dismissed in this state — the child must treat the high first.
    /// Strictly mutually exclusive with `.highGlucose` (critical replaces
    /// high when both would apply).
    case criticalGlucose
    case lowGlucose
    case staleSensor
    case carbGap
    case noGlucoseData
    case noCarbData

    public var id: String { rawValue }

    /// Load any custom check overrides stored in the provided defaults domain.
    public static func loadCustomChecks(from defaults: UserDefaults?) -> [AttentionScenario: [String]] {
        var result: [AttentionScenario: [String]] = [:]
        for scenario in allCases {
            if let data = defaults?.data(forKey: "checks.\(scenario.rawValue)"),
               let checks = try? JSONDecoder().decode([String].self, from: data) {
                result[scenario] = checks
            }
        }
        return result
    }
}
