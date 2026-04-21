import Foundation

/// Shared model that computes all shield display values.
public struct ShieldContent: Sendable {
    public let title: String
    public let subtitle: String
    public let dataText: String
    public let needsAttention: Bool
    public let glucoseNeedsAttention: Bool
    public let carbsNeedsAttention: Bool
    /// True when we have no glucose AND no carb data at all — e.g. right after
    /// initial configuration, before HealthKit has delivered anything.
    ///
    /// This is descriptive only. It is NOT the trigger for the in-app blue
    /// "welcome" icon variant — that's gated by the App-layer welcome state
    /// (no data source configured *and* no glucose history). Once a source
    /// is configured, missing data is a `needsAttention` case (red), not a
    /// neutral one. The shield UI similarly never reaches the no-data state
    /// because shielding is gated on having a data source.
    public let hasNoData: Bool
    public let buttonLabel: String
    public let glucoseValue: Double
    public let glucoseAgoMinutes: Int?
    public let carbGrams: Int?
    public let carbAgoMinutes: Int?
    public let attentionItems: [String]
    public let activeScenarios: [AttentionScenario]
    public let glucoseUnit: GlucoseUnit
    /// Glucose formatted in the display unit (e.g. "6.4" or "115"), no unit label.
    public let formattedGlucose: String
    public let glucoseUnitLabel: String

    public init(
        glucose: Double,
        glucoseFetchedAt: Date?,
        lastCarbGrams: Double?,
        lastCarbEntryAt: Date?,
        highGlucoseThreshold: Double,
        lowGlucoseThreshold: Double,
        glucoseStaleMinutes: Int,
        carbGraceHour: Int,
        carbGraceMinute: Int,
        glucoseUnit: GlucoseUnit = .mmolL,
        customChecks: [AttentionScenario: [String]] = [:],
        strings: Strings,
        now: Date = Date()
    ) {
        self.glucoseUnit = glucoseUnit
        glucoseUnitLabel = glucoseUnit.label
        glucoseValue = glucose
        let hasGlucose = glucose > 0
        var dataLines: [String] = []
        var scenarios: [AttentionScenario] = []

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        if hasGlucose, let glucoseDate = glucoseFetchedAt {
            let gMins = Int(now.timeIntervalSince(glucoseDate) / 60)
            glucoseAgoMinutes = gMins
            let formatted = glucoseUnit.formattedWithUnit(glucose)
            formattedGlucose = glucoseUnit.formatted(glucose)
            let timeStr = timeFormatter.string(from: glucoseDate)
            let agoStr = Self.shortAgo(gMins, strings: strings)
            dataLines.append(String(format: strings.glucose, formatted, timeStr, agoStr))

            if glucose < lowGlucoseThreshold {
                scenarios.append(.lowGlucose)
            } else if glucose > highGlucoseThreshold {
                scenarios.append(.highGlucose)
            }

            if gMins > glucoseStaleMinutes {
                scenarios.append(.staleSensor)
            }
        } else {
            glucoseAgoMinutes = nil
            formattedGlucose = "--"
            dataLines.append(strings.glucoseNoData)
            scenarios.append(.noGlucoseData)
        }

        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)
        let currentMinute = cal.component(.minute, from: now)
        let isMorningGrace = currentHour < carbGraceHour
            || (currentHour == carbGraceHour && currentMinute < carbGraceMinute)

        if let carbDate = lastCarbEntryAt, let grams = lastCarbGrams {
            carbGrams = Int(grams)
            let cMins = Int(now.timeIntervalSince(carbDate) / 60)
            carbAgoMinutes = cMins
            let timeStr = timeFormatter.string(from: carbDate)
            let agoStr = Self.shortAgo(cMins, strings: strings)
            dataLines.append(String(format: strings.carbsEntry, Int(grams), timeStr, agoStr))
            if !isMorningGrace && now.timeIntervalSince(carbDate) / 3600 > 4 {
                scenarios.append(.carbGap)
            }
        } else {
            carbGrams = nil
            carbAgoMinutes = nil
            dataLines.append(strings.carbsNoData)
            scenarios.append(.noCarbData)
        }

        activeScenarios = scenarios

        let glucoseScenarioSet: Set<AttentionScenario> = [.highGlucose, .lowGlucose, .staleSensor, .noGlucoseData]
        let carbScenarioSet: Set<AttentionScenario> = [.carbGap, .noCarbData]
        glucoseNeedsAttention = scenarios.contains(where: { glucoseScenarioSet.contains($0) })
        carbsNeedsAttention = scenarios.contains(where: { carbScenarioSet.contains($0) })

        var allChecks: [String] = []
        var seen = Set<String>()
        for scenario in scenarios {
            let checks = customChecks[scenario] ?? strings.scenarioChecks[scenario] ?? []
            for check in checks {
                let trimmed = check.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                if seen.insert(trimmed).inserted {
                    allChecks.append(trimmed)
                }
            }
        }
        attentionItems = allChecks
        needsAttention = !scenarios.isEmpty
        hasNoData = !hasGlucose && lastCarbEntryAt == nil

        if needsAttention {
            title = strings.attentionTitles.randomElement() ?? strings.attentionTitles[0]
        } else {
            title = strings.positiveTitles.randomElement() ?? strings.positiveTitles[0]
        }

        dataText = dataLines.joined(separator: "\n")
        var sections = [dataText]
        if !allChecks.isEmpty {
            let checksBlock = strings.openAppTo + "\n" + allChecks.joined(separator: ", ")
            sections.append(checksBlock)
        }
        let joined = sections.joined(separator: "\n\n")
        subtitle = "\n" + joined

        buttonLabel = needsAttention ? strings.checkInButton : strings.doneButton
    }

    private static func shortAgo(_ minutes: Int, strings: Strings) -> String {
        if minutes < 60 {
            return String(format: strings.agoMinutes, minutes)
        }
        return String(format: strings.agoHoursMinutes, minutes / 60, minutes % 60)
    }
}

public extension ShieldContent {
    /// All localizable strings used by shield-derived surfaces.
    struct Strings: Sendable {
        public let positiveTitles: [String]
        public let attentionTitles: [String]
        public let doneButton: String
        public let checkInButton: String
        public let openAppTo: String
        public let glucose: String
        public let glucoseNoData: String
        public let carbsEntry: String
        public let carbsNoData: String
        public let agoMinutes: String
        public let agoHoursMinutes: String
        public let scenarioChecks: [AttentionScenario: [String]]

        /// Resolve the main app's display name, even when called from an extension.
        private static func resolveAppName() -> String {
            let bundle: Bundle
            if Bundle.main.bundlePath.hasSuffix(".appex") {
                let parentURL = Bundle.main.bundleURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                bundle = Bundle(url: parentURL) ?? Bundle.main
            } else {
                bundle = Bundle.main
            }
            return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? "GluWink"
        }

        /// Load strings from a bundle's Localizable.strings.
        public static func fromBundle(_ bundle: Bundle) -> Strings {
            let appName = resolveAppName()
            let openFmt = bundle.localizedString(forKey: "shield.openAppTo %@", value: "Open %@ and:", table: nil)
            return Strings(
                positiveTitles: loadList(bundle: bundle, prefix: "shield.positiveTitle"),
                attentionTitles: loadList(bundle: bundle, prefix: "shield.attentionTitle"),
                doneButton: bundle.localizedString(forKey: "shield.doneButton", value: "Done", table: nil),
                checkInButton: bundle.localizedString(forKey: "shield.checkInButton", value: "I will", table: nil),
                openAppTo: String(format: openFmt, appName),
                glucose: bundle.localizedString(forKey: "shield.glucose %@ %@ %@", value: "%@ · %@ (%@ ago)", table: nil),
                glucoseNoData: bundle.localizedString(forKey: "shield.glucoseNoData", value: "No glucose data available.", table: nil),
                carbsEntry: bundle.localizedString(forKey: "shield.carbsEntry %d %@ %@", value: "%d g · %@ (%@ ago)", table: nil),
                carbsNoData: bundle.localizedString(forKey: "shield.carbsNoData", value: "No carb data", table: nil),
                agoMinutes: bundle.localizedString(forKey: "shield.agoMinutes %d", value: "%dm ago", table: nil),
                agoHoursMinutes: bundle.localizedString(forKey: "shield.agoHoursMinutes %d %d", value: "%dh %dm ago", table: nil),
                scenarioChecks: loadAllChecks(bundle: bundle)
            )
        }

        public static func fromPackage() -> Strings {
            fromBundle(Bundle.module)
        }

        private static func loadAllChecks(bundle: Bundle) -> [AttentionScenario: [String]] {
            var result: [AttentionScenario: [String]] = [:]
            for scenario in AttentionScenario.allCases {
                let checks = loadChecks(bundle: bundle, prefix: "shield.checks.\(scenario.rawValue)")
                if !checks.isEmpty {
                    result[scenario] = checks
                }
            }
            return result
        }

        private static func loadChecks(bundle: Bundle, prefix: String) -> [String] {
            var results: [String] = []
            for i in 0..<20 {
                let key = "\(prefix).\(i)"
                let value = bundle.localizedString(forKey: key, value: key, table: nil)
                if value == key { break }
                results.append(value)
            }
            return results
        }

        /// Load a numbered list of strings with a display-name fallback (for titles).
        private static func loadList(bundle: Bundle, prefix: String) -> [String] {
            var results: [String] = []
            for i in 0..<20 {
                let key = "\(prefix).\(i)"
                let value = bundle.localizedString(forKey: key, value: key, table: nil)
                if value == key { break }
                results.append(value)
            }
            let fallback = resolveAppName()
            return results.isEmpty ? [fallback] : results
        }
    }
}
