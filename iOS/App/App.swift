import BackgroundTasks
import FamilyControls
import HealthKit
import SwiftUI

@main
struct MainApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // First thing we do: detect a fresh install and wipe persistent
        // state that survives app deletion. App Group UserDefaults, the
        // Keychain passphrase, and ManagedSettingsStore shields all
        // outlive the app's sandbox on iOS, so a re-install would
        // otherwise inherit stale data sources, an old passphrase, and
        // even active shields from the previous install. The standard
        // `UserDefaults` *does* get wiped on delete, which is what makes
        // it usable as a "first launch after install" sentinel.
        Self.handleFirstLaunchAfterInstall()

        #if targetEnvironment(simulator)
        // When a fastlane snapshot run launched us with `-UITest_Scene`,
        // seed the App Group with the scene's glucose / carb values so the
        // widget and watch processes render the same state as the main
        // app. No-op outside of a harness run.
        ScreenshotHarness.seedAppGroupIfNeeded()
        #endif

        // Register HealthKit observers early if the user has already granted
        // HealthKit permission in a past launch. We check by looking at
        // whether we've moved past `.notDetermined` — that's the only state
        // the HealthKit API reports reliably for read-only permissions.
        WatchSessionManager.shared.activate()
        if HKHealthStore().authorizationStatus(for: HKQuantityType(.bloodGlucose)) != .notDetermined {
            HealthKitManager.shared.startObserving()
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: NightscoutManager.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                NightscoutManager.shared.handleBackgroundRefresh(refreshTask)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    let data = SharedDataManager.shared

                    #if targetEnvironment(simulator)
                    // Under the screenshot harness, skip HealthKit and
                    // Nightscout entirely — the App Group was already
                    // seeded in `init()` with deterministic values, and
                    // re-fetching would either clobber them (HK sample
                    // timestamp is newer) or wake the network and stall
                    // the capture.
                    if ScreenshotHarness.isActive {
                        WatchSessionManager.shared.sendLatestContext()
                        return
                    }
                    #endif

                    // HealthKit: re-request + enable background delivery
                    // if the user has been asked at least once, and try an
                    // immediate fetch. Fetching first matters: a successful
                    // sample flips `healthKitEverDelivered` via
                    // `markHealthKitDelivered`, which is what the
                    // `hasAnyDataSource` / shielding-gate logic below keys
                    // off. A user who denied the prompt (or revoked access
                    // in the Health app) gets no sample, the flag stays
                    // false, and `disableIfNoDataSource` below safely
                    // disarms residual shielding state.
                    if HKHealthStore().authorizationStatus(for: HKQuantityType(.bloodGlucose)) != .notDetermined {
                        await HealthKitManager.shared.requestAuthorization()
                        await HealthKitManager.shared.enableBackgroundDelivery()
                        await HealthKitManager.shared.fetchLatestGlucose()
                        await HealthKitManager.shared.fetchLatestCarbs()
                    }

                    // Nightscout: only poll when the user has wired up the
                    // integration.
                    if data.nightscoutEnabled {
                        NightscoutManager.shared.startPolling()
                        await NightscoutManager.shared.fetchAll()
                        NightscoutManager.shared.scheduleBackgroundRefresh()
                    }

                    // Shielding requires at least one live data source to
                    // make attention decisions. Run this *after* the HK /
                    // Nightscout fetches above so `hasAnyDataSource` has
                    // the latest picture — this also clears any residual
                    // shields stuck in `ManagedSettingsStore` from a past
                    // enable (e.g. shielding flipped on during a beta, then
                    // the data source went away).
                    ShieldManager.shared.disableIfNoDataSource()

                    // Shielding: only re-auth / re-arm when the user has
                    // actually enabled it (and it wasn't just auto-
                    // disabled above).
                    if data.shieldingEnabled {
                        if AuthorizationCenter.shared.authorizationStatus != .approved,
                           let member = data.authorizationMember {
                            try? await AuthorizationCenter.shared.requestAuthorization(for: member)
                        }
                        if data.loadSelection() != nil {
                            ShieldManager.shared.reevaluateShields()
                            ShieldManager.shared.scheduleRearm()
                            ActivityScheduler.shared.startMonitoring()
                        }
                    }

                    WatchSessionManager.shared.sendLatestContext()
                }
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        Task {
                            if HKHealthStore().authorizationStatus(for: HKQuantityType(.bloodGlucose)) != .notDetermined {
                                await HealthKitManager.shared.fetchLatestGlucose()
                                await HealthKitManager.shared.fetchLatestCarbs()
                            }
                            if SharedDataManager.shared.nightscoutEnabled {
                                await NightscoutManager.shared.fetchAll()
                            }
                        }
                    } else if scenePhase == .background {
                        if SharedDataManager.shared.nightscoutEnabled {
                            NightscoutManager.shared.scheduleBackgroundRefresh()
                        }
                    }
                }
        }
    }

    /// Sentinel key in `UserDefaults.standard` (the app's own container,
    /// which iOS *does* wipe on delete). Absence means this is the first
    /// launch after a fresh install and we need to clear state that lives
    /// outside the sandbox.
    private static let firstLaunchSentinelKey = "hasLaunchedSinceInstall"

    /// On the first launch after an install (or re-install), clear every
    /// piece of persistent state that survives `Delete App`:
    ///
    /// - **App Group UserDefaults** — owned by the system, not the app's
    ///   sandbox, so settings, glucose/carb samples, the data-source flags,
    ///   and the `shieldingEnabled` toggle all carry over to the new install.
    /// - **Keychain** — the passphrase has `kSecAttrAccessibleAfterFirstUnlock`
    ///   and no `kSecAttrAccessGroup`, so it survives delete and gets
    ///   inherited by the next install of the same bundle ID.
    /// - **`ManagedSettingsStore` shields** — Screen Time persists the
    ///   active configuration; without an explicit clear the new install
    ///   would inherit a (potentially red, "no data") shield from before.
    /// - **`DeviceActivityCenter` schedules** — same story; old monitoring
    ///   intervals stay armed and re-fire the extension after re-install.
    ///
    /// FamilyControls authorization and HealthKit access are left alone —
    /// both are user-managed in system Settings, and resetting them
    /// programmatically isn't possible anyway.
    private static func handleFirstLaunchAfterInstall() {
        let standard = UserDefaults.standard
        guard !standard.bool(forKey: firstLaunchSentinelKey) else { return }

        SharedDataManager.shared.wipeAllForFreshInstall()
        KeychainManager.shared.removePassphrase()
        ShieldManager.shared.removeShields()
        ActivityScheduler.shared.stopMonitoring()

        standard.set(true, forKey: firstLaunchSentinelKey)
    }
}
