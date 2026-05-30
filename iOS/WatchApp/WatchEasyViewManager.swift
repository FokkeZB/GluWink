import Foundation
import os
import SharedKit
import WidgetKit
#if canImport(WatchKit)
import WatchKit
#endif

/// Watch-side EasyView poller. Mirrors `WatchNightscoutManager`: keeps the
/// watch App Group glucose/carb keys up to date so complications stay fresh
/// even when the paired phone is unreachable.
///
/// Config (base URL, session cookie, patient UID) is synced from the phone via
/// `WatchConnectivity` and stored in the watch-local App Group by
/// `WatchDataManager.updateFromPhoneContext`. The session cookie lives in the
/// App Group (not Keychain) specifically so both the widget and the watch can
/// access it without a shared Keychain access group.
///
/// On session expiry the watch cannot re-login (no Keychain password).
/// It logs the error and serves stale cached values; the next phone
/// foreground pass will refresh the session and push it via WatchConnectivity.
@MainActor
final class WatchEasyViewManager {
    static let shared = WatchEasyViewManager()

    static let pollInterval: TimeInterval = 5 * 60

    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "WatchEasyViewManager")
    private var pollTimer: Timer?
    private var inFlight = false

    private init() {}

    private func currentClient() -> EasyViewClient? {
        guard WatchDataManager.easyViewEnabled,
              let session = WatchDataManager.easyViewSession
        else { return nil }
        return EasyViewClient(sessionCookie: session)
    }

    var isConfigured: Bool { currentClient() != nil }

    func startPolling() {
        stopPolling()
        guard isConfigured else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        logger.info("Watch EasyView polling started")
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func configurationDidChange() {
        if isConfigured {
            startPolling()
            Task { await fetchAll() }
        } else {
            stopPolling()
        }
    }

    func fetchAll() async {
        guard let client = currentClient() else { return }
        guard !WatchDataManager.isMockModeEnabled else {
            logger.info("Watch mock mode active — skipping EasyView fetch")
            return
        }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        guard let patientUID = WatchDataManager.easyViewPatientUID else {
            logger.warning("Watch EasyView patientUID not set — skipping fetch")
            return
        }

        do {
            // One `ds` request returns both glucose and carbs.
            let latest = try await client.fetchLatest(patientUID: patientUID)
            if let sample = latest.glucose {
                WatchDataManager.storeGlucose(mmol: sample.mmol, at: sample.date)
                logger.info("Watch EasyView glucose: \(String(format: "%.1f", sample.mmol)) mmol/L")
            }
            if let entry = latest.carbs {
                WatchDataManager.storeCarbs(grams: entry.grams, at: entry.date)
                logger.info("Watch EasyView carbs: \(String(format: "%.0f", entry.grams))g")
            }
        } catch EasyViewClient.ClientError.sessionExpired {
            logger.warning("Watch EasyView session expired — phone will refresh on next foreground")
        } catch {
            logger.error("Watch EasyView fetch failed: \(error.localizedDescription)")
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    func scheduleBackgroundRefresh() {
        guard isConfigured else { return }
        #if canImport(WatchKit) && !os(iOS)
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: Self.pollInterval),
            userInfo: nil
        ) { [weak self] error in
            if let error {
                self?.logger.error("Watch EasyView background schedule failed: \(error.localizedDescription)")
            }
        }
        #endif
    }
}
