import Foundation

/// Shared model that computes all shield display values.
public struct ShieldContent: Sendable {
    public let title: String
    public let subtitle: String
    public let dataText: String
    public let needsAttention: Bool
    public let glucoseNeedsAttention: Bool
    public let carbsNeedsAttention: Bool
    /// True when the current glucose reading is at or above the critical
    /// threshold. In this state the shield cannot be dismissed — the
    /// shield UI must surface the explanatory subtitle and the primary
    /// button must be non-actionable (ShieldAction refuses `.defer`).
    public let isCriticalGlucose: Bool
    /// Fully-formatted "shield cannot be dismissed until glucose is below X"
    /// copy in the user's display unit, for callers that want to surface the
    /// same explanation the shield subtitle shows (e.g. the in-app home view
    /// when the interactive check-in is hidden). `nil` outside the critical
    /// state. Single source of truth for the critical-state explanation so
    /// the shield extension and the main app can't drift.
    public let criticalCannotDismissText: String?
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
    /// Latest glucose sample if any is available — value, sample timestamp,
    /// minutes-ago, and pre-formatted display string are bundled as one
    /// atomic optional. There is no way to express "value but no date" or
    /// "date but no value" at the type level. Read callers MUST treat the
    /// presence of a reading and the readability of its individual fields
    /// as inseparable: `if let g = content.glucose { ...g.formatted... }`.
    public let glucose: Glucose?
    /// Latest carb entry, atomic with its sample timestamp. Same contract
    /// as `glucose` — `nil` means "no carb data" and consumers must render
    /// the no-data state on all metric surfaces.
    public let carbs: Carbs?
    public let attentionItems: [String]
    public let activeScenarios: [AttentionScenario]
    public let glucoseUnit: GlucoseUnit
    public let glucoseUnitLabel: String
    /// Whether carb tracking is enabled. When `false`, all carb-related
    /// scenarios, data lines, and UI surfaces are suppressed. Stored here
    /// so every rendering surface (tiles, complications, home screen) can
    /// read the flag from the same model object rather than fetching it
    /// separately.
    public let carbsEnabled: Bool

    public init(
        glucose: Double,
        glucoseFetchedAt: Date?,
        lastCarbGrams: Double?,
        lastCarbLabel: String? = nil,
        lastCarbEntryAt: Date?,
        highGlucoseThreshold: Double,
        lowGlucoseThreshold: Double,
        criticalGlucoseThreshold: Double,
        glucoseStaleMinutes: Int,
        carbGraceHour: Int,
        carbGraceMinute: Int,
        carbsEnabled: Bool = true,
        glucoseUnit: GlucoseUnit = .mmolL,
        customChecks: [AttentionScenario: [String]] = [:],
        strings: Strings,
        now: Date = Date()
    ) {
        self.glucoseUnit = glucoseUnit
        glucoseUnitLabel = glucoseUnit.label
        self.carbsEnabled = carbsEnabled
        let hasGlucose = glucose > 0
        var dataLines: [String] = []
        var scenarios: [AttentionScenario] = []

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        if hasGlucose, let glucoseDate = glucoseFetchedAt {
            let gMins = Int(now.timeIntervalSince(glucoseDate) / 60)
            self.glucose = Glucose(
                mmol: glucose,
                sampleDate: glucoseDate,
                agoMinutes: gMins,
                formatted: glucoseUnit.formatted(glucose)
            )
            let formattedWithUnit = glucoseUnit.formattedWithUnit(glucose)
            let timeStr = timeFormatter.string(from: glucoseDate)
            let agoStr = Self.shortAgo(gMins, strings: strings)
            dataLines.append(String(format: strings.glucose, formattedWithUnit, timeStr, agoStr))

            if glucose < lowGlucoseThreshold {
                scenarios.append(.lowGlucose)
            } else if glucose >= criticalGlucoseThreshold {
                // Critical is additive: a critical reading also satisfies
                // the high condition, so the user sees baseline high-glucose
                // hygiene (log carbs, drink water, check pump) *plus* the
                // critical-specific escalations (calculate correction, tell
                // someone). High is appended first so the check order reads
                // as baseline → escalation. `allChecks` below dedupes by
                // string so items shared across scenarios (e.g. "Drink
                // water") appear only once.
                //
                // `isCriticalGlucose` is still the source of truth for UI
                // differentiation (cannot-dismiss copy, button label,
                // in-app swap from interactive to read-only list) — see
                // `AttentionScenario.criticalGlucose` for the contract.
                scenarios.append(.highGlucose)
                scenarios.append(.criticalGlucose)
            } else if glucose > highGlucoseThreshold {
                scenarios.append(.highGlucose)
            }

            if gMins > glucoseStaleMinutes {
                scenarios.append(.staleSensor)
            }
        } else {
            self.glucose = nil
            dataLines.append(strings.glucoseNoData)
            scenarios.append(.noGlucoseData)
        }

        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)
        let currentMinute = cal.component(.minute, from: now)
        let isMorningGrace = currentHour < carbGraceHour
            || (currentHour == carbGraceHour && currentMinute < carbGraceMinute)

        if carbsEnabled {
            if let carbDate = lastCarbEntryAt {
                let cMins = Int(now.timeIntervalSince(carbDate) / 60)
                self.carbs = Carbs(
                    grams: lastCarbGrams.map { Int($0) },
                    label: lastCarbLabel,
                    sampleDate: carbDate,
                    agoMinutes: cMins
                )
                let timeStr = timeFormatter.string(from: carbDate)
                let agoStr = Self.shortAgo(cMins, strings: strings)
                if let grams = lastCarbGrams {
                    dataLines.append(String(format: strings.carbsEntry, Int(grams), timeStr, agoStr))
                } else {
                    let displayLabel = lastCarbLabel ?? strings.mealLabel
                    dataLines.append(String(format: strings.carbsMealOnly, displayLabel, timeStr, agoStr))
                }
                if !isMorningGrace && now.timeIntervalSince(carbDate) / 3600 > 4 {
                    scenarios.append(.carbGap)
                }
            } else {
                self.carbs = nil
                dataLines.append(strings.carbsNoData)
                scenarios.append(.noCarbData)
            }
        } else {
            self.carbs = nil
        }

        activeScenarios = scenarios

        let glucoseScenarioSet: Set<AttentionScenario> = [.highGlucose, .criticalGlucose, .lowGlucose, .staleSensor, .noGlucoseData]
        let carbScenarioSet: Set<AttentionScenario> = [.carbGap, .noCarbData]
        glucoseNeedsAttention = scenarios.contains(where: { glucoseScenarioSet.contains($0) })
        carbsNeedsAttention = scenarios.contains(where: { carbScenarioSet.contains($0) })
        isCriticalGlucose = scenarios.contains(.criticalGlucose)

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
        hasNoData = !hasGlucose && (!carbsEnabled || lastCarbEntryAt == nil)

        if needsAttention {
            title = strings.attentionTitles.randomElement() ?? strings.attentionTitles[0]
        } else {
            title = strings.positiveTitles.randomElement() ?? strings.positiveTitles[0]
        }

        dataText = dataLines.joined(separator: "\n")
        if isCriticalGlucose {
            // Format the threshold in the user's display unit to match the
            // main glucose readout above. Stored as a public property so the
            // home view can reuse the same copy on its disabled check-in
            // panel without recomputing the format.
            let formattedThreshold = glucoseUnit.formatted(criticalGlucoseThreshold)
            criticalCannotDismissText = String(format: strings.criticalCannotDismiss, formattedThreshold)
        } else {
            criticalCannotDismissText = nil
        }
        var sections = [dataText]
        if let criticalCannotDismissText {
            // Surface the "cannot dismiss" explanation first in the critical
            // state so the child reads it before the regular check-in copy.
            sections.append(criticalCannotDismissText)
        }
        if !allChecks.isEmpty {
            let checksBlock = strings.openAppTo + "\n" + allChecks.joined(separator: ", ")
            sections.append(checksBlock)
        }
        let joined = sections.joined(separator: "\n\n")
        subtitle = "\n" + joined

        if needsAttention {
            // Critical glucose reuses the regular check-in button label.
            // The "cannot dismiss" affordance lives entirely in the subtitle
            // copy (see `criticalCannotDismiss` above) and the hard gate in
            // `ShieldAction.handleAction`, which rejects `.defer` in the
            // critical state regardless of which button was tapped.
            buttonLabel = strings.checkInButton
        } else {
            buttonLabel = strings.doneButton
        }
    }

    private static func shortAgo(_ minutes: Int, strings: Strings) -> String {
        if minutes < 60 {
            return String(format: strings.agoMinutes, minutes)
        }
        return String(format: strings.agoHoursMinutes, minutes / 60, minutes % 60)
    }
}

public extension ShieldContent {
    /// A glucose sample paired indivisibly with its timestamp. The whole
    /// point of this nested struct is that consumers cannot get one
    /// without the other: if `ShieldContent.glucose` is `nil`, there is
    /// no reading at all — render the no-data state on every surface
    /// (orange tint + warning triangle, never a raw value with no
    /// time-ago label). Nested under `ShieldContent` to distinguish from
    /// `UnifiedDataReader.GlucoseReading`, which is the per-source raw
    /// reading; this one is the resolved, display-formatted view.
    struct Glucose: Sendable, Equatable {
        /// Glucose value in mmol/L — always. Surfaces that show a
        /// different display unit format from `formatted` (which already
        /// respects `ShieldContent.glucoseUnit`); they should not re-do
        /// the math on `mmol` themselves.
        public let mmol: Double
        /// Time the sample was observed by the writer (HealthKit,
        /// Nightscout, or demo). What the "X min ago" label is computed
        /// against.
        public let sampleDate: Date
        /// Minutes between `sampleDate` and the `now` passed to
        /// `ShieldContent.init`. Pre-computed so widget timelines that
        /// produce multiple entries don't all recompute it at render
        /// time.
        public let agoMinutes: Int
        /// Already formatted for the active display unit (e.g. `"6.4"`
        /// for mmol/L, `"115"` for mg/dL). No unit label — surfaces tack
        /// the unit on themselves using `ShieldContent.glucoseUnitLabel`
        /// so they can position it (e.g. on the same line, on a second
        /// line, in a smaller font).
        public let formatted: String
    }

    /// A carb entry paired indivisibly with its timestamp. Mirrors
    /// `Glucose`'s atomic contract — `ShieldContent.carbs == nil` means
    /// render the no-data state, full stop.
    ///
    /// `grams` is `nil` when the source logged only that a meal occurred
    /// (e.g. EasyView `auto_mode_event`) — the grace-period and carb-gap
    /// checks are still based on `sampleDate`.
    ///
    /// When `grams` is `nil`, `label` may carry a provider-supplied display
    /// string (e.g. "B'fast"). Display surfaces should prefer `label` over a
    /// generic fallback when available. Both may be `nil` simultaneously for
    /// legacy or non-labelling sources.
    struct Carbs: Sendable, Equatable {
        public let grams: Int?
        public let label: String?
        public let sampleDate: Date
        public let agoMinutes: Int
    }
}

/// Three-way attention signal used by every surface that paints the
/// app-icon variant or a status tint. Kept in SharedKit so the shield
/// extension, main app, widgets, watch app and watch widget agree on the
/// mapping without each call site re-deriving it from `needsAttention` +
/// `isCriticalGlucose`.
public enum AttentionLevel: Sendable {
    /// All clear — green tint, `AppIcon-Green`.
    case clear
    /// Needs attention but not critical — orange tint, `AppIcon-Orange`.
    /// Covers high glucose below critical, lows, stale sensor, carb gap,
    /// no glucose data.
    case attention
    /// Critical glucose (≥ `criticalGlucoseThreshold`) — red tint,
    /// `AppIcon-Red`. Shield cannot be dismissed in this state; see
    /// `ShieldContent.isCriticalGlucose`.
    case critical

    /// Asset-catalog / bundle-resource name for this level. Matches the
    /// `AppIcon-*` imagesets in the app + watch catalogs and the raw PNG
    /// copies that extensions ship alongside their binary.
    public var iconName: String {
        switch self {
        case .clear: return "AppIcon-Green"
        case .attention: return "AppIcon-Orange"
        case .critical: return "AppIcon-Red"
        }
    }
}

public extension ShieldContent {
    /// Overall attention level for surfaces that paint one tint for the
    /// whole content (shield UI, home icon, widget background).
    var attentionLevel: AttentionLevel {
        if isCriticalGlucose { return .critical }
        if needsAttention { return .attention }
        return .clear
    }

    /// Attention level for a single metric slot (e.g. the glucose-only
    /// or carbs-only watch complication). Only glucose can be critical;
    /// carbs max out at `.attention`.
    func attentionLevel(forGlucose: Bool) -> AttentionLevel {
        if forGlucose {
            if isCriticalGlucose { return .critical }
            return glucoseNeedsAttention ? .attention : .clear
        }
        return carbsNeedsAttention ? .attention : .clear
    }
}

public extension ShieldContent {
    /// All localizable strings used by shield-derived surfaces.
    struct Strings: Sendable {
        public let positiveTitles: [String]
        public let attentionTitles: [String]
        public let doneButton: String
        public let checkInButton: String
        /// Shown near the top of the shield subtitle when glucose is critical,
        /// explaining why the shield cannot be dismissed. Format string with
        /// one `%@` placeholder for the critical threshold value in the user's
        /// display unit (no unit suffix — the shield already shows the unit
        /// on the main readout).
        public let criticalCannotDismiss: String
        public let openAppTo: String
        public let glucose: String
        public let glucoseNoData: String
        public let carbsEntry: String
        /// Displayed when a meal was acknowledged without a gram count (e.g.
        /// EasyView `auto_mode_event`). Format: label, time, ago string.
        /// The label arg receives `carbs.label` when available, or `mealLabel`
        /// as a generic fallback.
        public let carbsMealOnly: String
        /// Generic fallback label used in `carbsMealOnly` when no
        /// provider-specific label is stored (e.g. "Meal" / "Maaltijd").
        public let mealLabel: String
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
                criticalCannotDismiss: bundle.localizedString(forKey: "shield.criticalCannotDismiss %@", value: "Your glucose is critically high. The shield cannot be dismissed until your glucose is below %@.", table: nil),
                openAppTo: String(format: openFmt, appName),
                glucose: bundle.localizedString(forKey: "shield.glucose %@ %@ %@", value: "%@ · %@ (%@ ago)", table: nil),
                glucoseNoData: bundle.localizedString(forKey: "shield.glucoseNoData", value: "No glucose data available.", table: nil),
                carbsEntry: bundle.localizedString(forKey: "shield.carbsEntry %d %@ %@", value: "%d g · %@ (%@ ago)", table: nil),
                carbsMealOnly: bundle.localizedString(forKey: "shield.carbsMealOnly %@ %@ %@", value: "%@ · %@ (%@ ago)", table: nil),
                mealLabel: bundle.localizedString(forKey: "shield.mealLabel", value: "Meal", table: nil),
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
            for i in 0..<30 {
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
