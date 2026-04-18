import Foundation
import os
import SharedKit
import WidgetKit
#if canImport(WatchKit)
import WatchKit
#endif

/// Watch-side Nightscout poller. Mirrors `WatchHealthKitManager`: keeps the
/// watch App Group glucose/carb keys up to date so complications stay fresh
/// even when the paired phone is unreachable (parent-monitoring scenario).
///
/// Uses `NightscoutClient` from `SharedKit` so HTTP/parse logic stays identical
/// to the iOS manager.
@MainActor
final class WatchNightscoutManager {
    static let shared = WatchNightscoutManager()

    static let pollInterval: TimeInterval = 5 * 60

    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "WatchNightscoutManager")
    private var pollTimer: Timer?
    private var inFlight = false

    private init() {}

    private func currentClient() -> NightscoutClient? {
        guard WatchDataManager.nightscoutEnabled,
              let urlString = WatchDataManager.nightscoutBaseURL,
              let client = NightscoutClient(baseURLString: urlString, token: WatchDataManager.nightscoutToken)
        else {
            return nil
        }
        return client
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
        logger.info("Watch Nightscout polling started")
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// React to config changes coming in from the phone via
    /// `WatchConnectivityReceiver`.
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
            logger.info("Watch mock mode active — skipping Nightscout fetch")
            return
        }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        do {
            if let sample = try await client.fetchLatestGlucose() {
                WatchDataManager.storeGlucose(mmol: sample.mmol, at: sample.date)
                logger.info("Watch Nightscout glucose: \(String(format: "%.1f", sample.mmol)) mmol/L")
            }
        } catch {
            logger.error("Watch Nightscout glucose fetch failed: \(error.localizedDescription)")
        }

        do {
            if let entry = try await client.fetchLatestCarbs() {
                WatchDataManager.storeCarbs(grams: entry.grams, at: entry.date)
                logger.info("Watch Nightscout carbs: \(String(format: "%.0f", entry.grams))g")
            }
        } catch {
            logger.error("Watch Nightscout carbs fetch failed: \(error.localizedDescription)")
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Schedule a watch background refresh so complications can update when
    /// the app isn't running. Call after each successful fetch.
    func scheduleBackgroundRefresh() {
        guard isConfigured else { return }
        #if canImport(WatchKit) && !os(iOS)
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: Self.pollInterval),
            userInfo: nil
        ) { [weak self] error in
            if let error {
                self?.logger.error("Watch Nightscout background schedule failed: \(error.localizedDescription)")
            }
        }
        #endif
    }
}
