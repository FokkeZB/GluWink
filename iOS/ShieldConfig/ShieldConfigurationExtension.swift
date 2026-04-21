import Foundation
import ManagedSettings
import ManagedSettingsUI
import SharedKit
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private static let appGroupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as! String
    /// xcconfig fallbacks — the resolver picks user override or these,
    /// per render, so settings changes show up in the shield UI.
    private static let fallbackHighGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "HighGlucoseThreshold") as! String)!
    private static let fallbackLowGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "LowGlucoseThreshold") as! String)!
    private static let fallbackStaleMinutes = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
    private static let fallbackCarbGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
    private static let fallbackCarbGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        let defaults = UserDefaults(suiteName: Self.appGroupID)

        let glucoseDate = defaults?.string(forKey: "glucoseFetchedAt")
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        let carbDate = defaults?.string(forKey: "lastCarbEntryAt")
            .flatMap { ISO8601DateFormatter().date(from: $0) }

        let carbGrams = defaults?.double(forKey: "lastCarbGrams") ?? 0
        let customChecks = AttentionScenario.loadCustomChecks(from: defaults)

        let unit: GlucoseUnit = defaults?.string(forKey: "glucoseUnit")
            .flatMap { GlucoseUnit(rawValue: $0) } ?? .mmolL

        let content = ShieldContent(
            glucose: defaults?.double(forKey: "currentGlucose") ?? 0,
            glucoseFetchedAt: glucoseDate,
            lastCarbGrams: carbGrams > 0 ? carbGrams : nil,
            lastCarbEntryAt: carbDate,
            highGlucoseThreshold: ThresholdResolver.highGlucose(defaults: defaults, fallback: Self.fallbackHighGlucose),
            lowGlucoseThreshold: ThresholdResolver.lowGlucose(defaults: defaults, fallback: Self.fallbackLowGlucose),
            glucoseStaleMinutes: ThresholdResolver.staleMinutes(defaults: defaults, fallback: Self.fallbackStaleMinutes),
            carbGraceHour: ThresholdResolver.carbGraceHour(defaults: defaults, fallback: Self.fallbackCarbGraceHour),
            carbGraceMinute: ThresholdResolver.carbGraceMinute(defaults: defaults, fallback: Self.fallbackCarbGraceMinute),
            glucoseUnit: unit,
            customChecks: customChecks,
            strings: .fromPackage()
        )

        // Shielding can only be enabled once a data source is configured
        // (see `ShieldManager.disableIfNoDataSource()`), so the shield is
        // always rendered against real glucose/carb input — red when
        // attention is needed (including when a configured source has
        // stopped delivering), green otherwise. There's no "blue / no data"
        // variant here; that case can't reach the shield UI.
        let iconName: String
        let tint: UIColor
        if content.needsAttention {
            iconName = "AppIcon-Red"
            tint = .systemRed
        } else {
            iconName = "AppIcon-Green"
            tint = .systemGreen
        }
        let icon = UIImage(contentsOfFile: Bundle.main.path(forResource: iconName, ofType: "png") ?? "")

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: tint,
            icon: icon,
            title: ShieldConfiguration.Label(
                text: content.title,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: content.subtitle,
                color: UIColor.white.withAlphaComponent(0.85)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: content.buttonLabel,
                color: tint
            ),
            primaryButtonBackgroundColor: .white
        )
    }
}
