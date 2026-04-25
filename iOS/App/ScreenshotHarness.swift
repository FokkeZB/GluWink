#if targetEnvironment(simulator)
import Foundation
import SharedKit
import SwiftUI

/// Deterministic state overrides for App Store screenshot captures.
///
/// Wired into `HomeView`'s simulator mock state and `MainApp.init()` so a
/// fastlane `snapshot` UI test can launch the app, pass `-UITest_Scene
/// <name>`, and get a pinned, reproducible render without waiting for real
/// glucose data to swing green/red.
///
/// Only compiled for simulator builds, matching the existing ladybug mock-
/// data convention in `HomeView` (see `AGENTS.md` → "Do NOT add debug menus"
/// — the simulator-only gate is what keeps this out of TestFlight and App
/// Store builds). Without `-UITest_Scene`, `current` is `nil` and the app
/// behaves identically to a normal simulator run.
///
/// See GitHub issues #28 (tracking) and #29 (this harness).
enum ScreenshotHarness {
    /// Scene identifiers correspond 1:1 with the App Store screenshot
    /// matrix documented in `AppStore/README.md` → Screenshots.
    enum Scene: String {
        /// All-clear state: friendly face, "Looking good!", glucose + carbs visible.
        case greenShield
        /// Needs-attention state (orange, non-critical): glucose just above
        /// the high threshold, check-in items visible, shield dismissible.
        case orangeShield
        /// Critical state (red): glucose at/above the critical threshold, the
        /// shield explicitly *cannot* be dismissed — subtitle surfaces the
        /// "cannot dismiss until glucose is below X" copy, button is
        /// non-actionable. Sells the "there's a separate, stricter level"
        /// half of the three-way traffic light.
        case redShield
        /// Home Screen widgets stack. `ContentView` swaps `HomeView` out for
        /// `WidgetShowcaseView` when this is active.
        case widgets
        /// Top-level Settings list — rendered via `ContentView` as the root
        /// `SettingsView` for the "The parent view: status, settings, peace
        /// of mind" caption.
        case settings
        /// Apple Watch scene (driven via App Group seed + the watch simulator).
        case watch
        /// Setup checklist front and centre, no data yet.
        case setupChecklist
    }

    /// Scene selected via `-UITest_Scene <rawValue>` on launch, or `nil` for
    /// normal runs. Read once at first access and cached.
    static let current: Scene? = {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-UITest_Scene"), idx + 1 < args.count else {
            return nil
        }
        return Scene(rawValue: args[idx + 1])
    }()

    /// `true` when the harness is driving the app. Used to short-circuit
    /// network / HealthKit work that would introduce nondeterminism into
    /// captures.
    static var isActive: Bool { current != nil }

    /// Display unit to pin for the active capture, derived from `-AppleLocale`.
    /// English locales use mg/dL (US/UK/Canada convention); everything else
    /// defaults to mmol/L (the rest of the world + our app default). Stored
    /// values on `ShieldContent` are always mmol/L, so this only flips the
    /// display formatting — no preset rewrite needed.
    static let glucoseUnit: GlucoseUnit = {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-AppleLocale"), idx + 1 < args.count else {
            return .mmolL
        }
        return args[idx + 1].lowercased().hasPrefix("en") ? .mgdL : .mmolL
    }()

    /// Marketing caption to bake into the top of the screenshot, passed via
    /// `-UITest_Caption "..."`. Sourced from `AppStore/<locale>.md` →
    /// "Screenshot captions" by `capture.sh`, so the Markdown stays the
    /// single editable home for the copy. `nil` disables the banner — handy
    /// when eyeballing a scene without the marketing overlay.
    static let caption: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-UITest_Caption"), idx + 1 < args.count else {
            return nil
        }
        let raw = args[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }()
}

// MARK: - HomeView presets

extension ScreenshotHarness.Scene {
    /// Initial values for `HomeView`'s simulator-only `@State` properties.
    /// Injected from `HomeView.init()` when a scene is active.
    struct HomeViewPreset {
        var glucose: Double
        var glucoseMinutesAgo: Double
        var carbGrams: Double
        var carbMinutesAgo: Double
        var hasGlucoseData: Bool
        var hasCarbData: Bool
        var shieldingEnabled: Bool
        var disarmed: Bool
        /// When non-nil, force `HomeView`'s welcome/empty state instead of
        /// the status panel. Used by `setupChecklist` to clear the top of
        /// the screen so the checklist card reads as the subject.
        var forceWelcome: Bool
        /// Number of check-in rows to render as already-checked in
        /// `CheckInView`. `0` leaves the view in its "nothing tapped yet"
        /// state; `1` shows the first row ticked and the second row
        /// active/tappable, which reads as "user is responding" in
        /// marketing copy. Only meaningful for scenes that reach the
        /// check-in flow (i.e. `redShield`).
        var checkInPreCheckedCount: Int
    }

    /// Background color for the marketing caption banner overlaid on this
    /// scene's screenshot. Shield scenes inherit the shield's own tint so
    /// the banner reinforces the traffic-light metaphor; everything else
    /// uses a neutral dark charcoal that reads as "marketing chrome"
    /// rather than app UI.
    ///
    /// All three shield banners pull from `BrandTint` so the banner, the
    /// shield background, the icon tint, and any widget chrome in the
    /// same shot render the exact same shade (the icons are fixed hex,
    /// so the banner has to be too — SwiftUI's `.green` / `.red` would
    /// drift visibly on some renderers).
    var captionBannerColor: Color {
        switch self {
        case .greenShield: return BrandTint.green
        case .orangeShield: return BrandTint.orange
        case .redShield: return BrandTint.red
        case .widgets, .settings, .watch, .setupChecklist:
            return Color(red: 0.11, green: 0.12, blue: 0.14)
        }
    }

    /// Whether `SetupChecklistCard` should be suppressed for this scene.
    /// True for every "showcase" scene where the checklist would just
    /// crowd out the actual subject; false only for `setupChecklist`,
    /// which exists specifically to feature the card.
    var hidesSetupChecklist: Bool {
        switch self {
        case .greenShield, .orangeShield, .redShield, .settings, .widgets, .watch: return true
        case .setupChecklist: return false
        }
    }

    var homeViewPreset: HomeViewPreset {
        switch self {
        case .greenShield, .settings, .widgets, .watch:
            return HomeViewPreset(
                glucose: 6.4,
                glucoseMinutesAgo: 3,
                carbGrams: 25,
                carbMinutesAgo: 90,
                hasGlucoseData: true,
                hasCarbData: true,
                shieldingEnabled: true,
                disarmed: false,
                forceWelcome: false,
                checkInPreCheckedCount: 0
            )
        case .orangeShield:
            // High-but-not-critical: 14.8 mmol/L sits above the default
            // `HighGlucoseThreshold` (14.0) but well below
            // `CriticalGlucoseThreshold` (20.0), so `ShieldContent` resolves
            // to the orange attention level and the check-in is dismissible.
            return HomeViewPreset(
                glucose: 14.8,
                glucoseMinutesAgo: 2,
                carbGrams: 30,
                carbMinutesAgo: 15,
                hasGlucoseData: true,
                hasCarbData: true,
                shieldingEnabled: true,
                disarmed: false,
                forceWelcome: false,
                checkInPreCheckedCount: 1
            )
        case .redShield:
            // Critical: 21.2 mmol/L is above `CriticalGlucoseThreshold`
            // (20.0 default), which flips `isCriticalGlucose` true. The
            // home view hides the interactive check-in and shows the
            // "shield cannot be dismissed until glucose is below X"
            // subtitle — the marketing-visible proof of the no-disarm
            // contract (see issue #84). `checkInPreCheckedCount = 0`
            // because there's no interactive flow to pre-tick in critical.
            return HomeViewPreset(
                glucose: 21.2,
                glucoseMinutesAgo: 2,
                carbGrams: 30,
                carbMinutesAgo: 15,
                hasGlucoseData: true,
                hasCarbData: true,
                shieldingEnabled: true,
                disarmed: false,
                forceWelcome: false,
                checkInPreCheckedCount: 0
            )
        case .setupChecklist:
            return HomeViewPreset(
                glucose: 0,
                glucoseMinutesAgo: 0,
                carbGrams: 0,
                carbMinutesAgo: 0,
                hasGlucoseData: false,
                hasCarbData: false,
                shieldingEnabled: false,
                disarmed: false,
                forceWelcome: true,
                checkInPreCheckedCount: 0
            )
        }
    }
}

// MARK: - App Group seeding (widgets / watch)

extension ScreenshotHarness {
    /// Write the active scene's glucose + carb values into the shared App
    /// Group so widget and watch processes pick up the same numbers. Called
    /// from `MainApp.init()` before any scene is rendered.
    ///
    /// No-op when the harness is inactive. The seeded values are overwritten
    /// on the next real HealthKit / Nightscout fetch, so a normal app launch
    /// after a screenshot run doesn't keep the stale sample.
    static func seedAppGroupIfNeeded() {
        guard let scene = current else { return }
        let preset = scene.homeViewPreset

        guard let defaults = UserDefaults(suiteName: Constants.appGroupID) else { return }

        if preset.hasGlucoseData {
            let glucoseDate = Date().addingTimeInterval(-preset.glucoseMinutesAgo * 60)
            defaults.set(preset.glucose, forKey: "currentGlucose")
            defaults.set(glucoseDate.ISO8601Format(), forKey: "glucoseFetchedAt")
        } else {
            defaults.removeObject(forKey: "currentGlucose")
            defaults.removeObject(forKey: "glucoseFetchedAt")
        }

        if preset.hasCarbData {
            let carbDate = Date().addingTimeInterval(-preset.carbMinutesAgo * 60)
            defaults.set(preset.carbGrams, forKey: "lastCarbGrams")
            defaults.set(carbDate.ISO8601Format(), forKey: "lastCarbEntryAt")
        } else {
            defaults.removeObject(forKey: "lastCarbGrams")
            defaults.removeObject(forKey: "lastCarbEntryAt")
        }

        // Reset "data source / shielding configured" flags on every run
        // and re-apply them only where a scene actually wants them. Without
        // this reset, running `--scene settings` then `--scene setupChecklist`
        // carries the mock/shielding flags over and the checklist scene
        // shows a half-configured state instead of the welcome layout.
        //
        // `SettingsView` renders radically differently depending on whether
        // a data source is configured — greyed rows with "connect a source
        // first" subtitles don't sell the app, so for the settings scene
        // we stamp everything as "active, configured".
        let configured = (scene == .settings)
        defaults.set(configured, forKey: "mockModeEnabled")
        defaults.set(configured, forKey: "shieldingEnabled")
        defaults.set(configured, forKey: "healthKitEverDelivered")

        // Pin the display unit per locale so en-US reads as mg/dL.
        defaults.set(glucoseUnit.rawValue, forKey: "glucoseUnit")
    }
}
#endif
