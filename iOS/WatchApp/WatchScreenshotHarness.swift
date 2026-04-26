#if targetEnvironment(simulator)
import Foundation
import SharedKit

/// Deterministic state overrides for Apple Watch screenshot captures.
///
/// Sibling to `ScreenshotHarness` in the iPhone target. When the Watch
/// simulator is launched with `-UITest_Scene watchApp`, this harness seeds
/// the watch-local App Group with pinned glucose / carb values and short
/// sample ages so `WatchContentView` renders the same numbers on every
/// run — no waiting for HealthKit or Nightscout, no drift between captures.
///
/// Only compiled for simulator builds. Outside of a harness run `isActive`
/// is `false` and `CompanionWatchApp` behaves identically to a normal
/// watch launch.
///
/// See GitHub issue #85 and `AppStore/README.md` → "Apple Watch" section.
enum WatchScreenshotHarness {
    /// Scene identifiers for the Apple Watch deck. The watch face with
    /// complications is owner-supplied (Apple provides no API to render a
    /// full watch face programmatically) so there is no auto scene for it
    /// — only the WatchApp UI.
    enum Scene: String {
        /// The `WatchApp` scene: status screen with glucose value, carb
        /// value, and two relative timestamps ("Xm ago").
        case watchApp
    }

    /// Scene selected via `-UITest_Scene <rawValue>` on launch, or `nil`
    /// for normal runs. Read once at first access and cached.
    static let current: Scene? = {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-UITest_Scene"), idx + 1 < args.count else {
            return nil
        }
        return Scene(rawValue: args[idx + 1])
    }()

    /// `true` when the harness is driving the app. Used to short-circuit
    /// HealthKit observers and Nightscout polling that would otherwise
    /// overwrite the seeded values (or stall the capture on a network
    /// wake).
    static var isActive: Bool { current != nil }

    /// Display unit pinned for the active capture, derived from
    /// `-AppleLocale`. Matches the iPhone harness: English locales use
    /// mg/dL (US/UK/Canada convention), everything else defaults to
    /// mmol/L. Stored values on the App Group are always mmol/L — this
    /// only flips the display formatting.
    static let glucoseUnit: GlucoseUnit = {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-AppleLocale"), idx + 1 < args.count else {
            return .mmolL
        }
        return args[idx + 1].lowercased().hasPrefix("en") ? .mgdL : .mmolL
    }()

    /// Deterministic values for the `.watchApp` scene. Mirrors the
    /// iPhone harness's `greenShield` preset so marketing copy that
    /// describes the phone + watch pair ("glucose and carbs at a glance
    /// on both surfaces") stays truthful: the numbers agree across the
    /// two screens in the App Store deck.
    private struct Preset {
        let glucose: Double
        let glucoseMinutesAgo: Double
        let carbGrams: Double
        let carbMinutesAgo: Double
    }

    private static func preset(for scene: Scene) -> Preset {
        switch scene {
        case .watchApp:
            return Preset(
                glucose: 6.4,
                glucoseMinutesAgo: 9,
                carbGrams: 20,
                carbMinutesAgo: 20
            )
        }
    }

    /// Write the active scene's values into the watch-local App Group so
    /// `WatchContentView` picks them up on first render. No-op when the
    /// harness is inactive. Called from `CompanionWatchApp.init()` before
    /// any manager starts observing, so HealthKit / Nightscout can't race
    /// ahead of the seed.
    static func seedAppGroupIfNeeded() {
        guard let scene = current else { return }
        guard let defaults = UserDefaults(suiteName: Constants.appGroupID) else { return }
        let p = preset(for: scene)

        let glucoseDate = Date().addingTimeInterval(-p.glucoseMinutesAgo * 60)
        let carbDate = Date().addingTimeInterval(-p.carbMinutesAgo * 60)

        // Watch-local keys — `WatchDataManager` reads these directly;
        // the per-source `demoGlucose*` keys used by `UnifiedDataReader`
        // on the phone are not in play here.
        defaults.set(p.glucose, forKey: "currentGlucose")
        defaults.set(glucoseDate.ISO8601Format(), forKey: "glucoseFetchedAt")
        defaults.set(p.carbGrams, forKey: "lastCarbGrams")
        defaults.set(carbDate.ISO8601Format(), forKey: "lastCarbEntryAt")

        // Flip mock-mode on so the resolver ignores any stale Nightscout
        // config that happened to be synced from the phone in a past run,
        // and pin the display unit to match the active locale.
        defaults.set(true, forKey: "mockModeEnabled")
        defaults.set(glucoseUnit.rawValue, forKey: "glucoseUnit")
    }
}
#endif
