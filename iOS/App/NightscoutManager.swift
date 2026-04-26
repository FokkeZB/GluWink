import BackgroundTasks
import Foundation
import os
import SharedKit
import WidgetKit

/// Coordinates Nightscout polling on iOS. Mirrors `HealthKitManager` in shape:
/// a singleton that keeps the same App Group keys up to date via
/// `SharedDataManager`, reloads widgets, and refreshes shields/app icon.
///
/// Designed to coexist with HealthKit. Each source writes to its own
/// per-source keys (see `SharedKit.DataSourceKeys`); the unified reader
/// picks the freshest sample across enabled sources independently for
/// glucose and carbs.
@MainActor
final class NightscoutManager {
    static let shared = NightscoutManager()

    /// Background task identifier for app refreshes when Nightscout is the
    /// primary data source. Must match the entry in `Info.plist` under
    /// `BGTaskSchedulerPermittedIdentifiers`.
    static let backgroundTaskIdentifier = "\(Constants.bundlePrefix).nightscout.refresh"

    /// Polling cadence matching the widget timeline refresh and Dexcom sample
    /// interval.
    static let pollInterval: TimeInterval = 5 * 60

    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "NightscoutManager")

    private var pollTimer: Timer?
    private var inFlight = false

    private init() {}

    // MARK: - Config

    /// Build a client from current user configuration. Returns nil if
    /// Nightscout is disabled or misconfigured.
    private func currentClient() -> NightscoutClient? {
        let data = SharedDataManager.shared
        guard data.nightscoutEnabled,
              let urlString = data.nightscoutBaseURL,
              let client = NightscoutClient(baseURLString: urlString, token: data.nightscoutToken)
        else {
            return nil
        }
        return client
    }

    var isConfigured: Bool {
        currentClient() != nil
    }

    // MARK: - Polling lifecycle

    /// Start (or restart) the foreground poll timer. No-op when Nightscout is
    /// disabled.
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
        logger.info("Nightscout polling started (\(Int(Self.pollInterval))s)")
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// React to config changes from the Settings UI.
    func configurationDidChange() {
        if isConfigured {
            startPolling()
            Task { await fetchAll() }
        } else {
            stopPolling()
        }
    }

    // MARK: - Fetching

    /// Fetch glucose + carbs and persist via SharedDataManager.
    func fetchAll() async {
        guard let client = currentClient() else { return }
        guard !SharedDataManager.shared.isMockModeEnabled else {
            logger.info("Mock mode active — skipping Nightscout fetch")
            return
        }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        await fetchGlucose(using: client)
        await fetchCarbs(using: client)
        SharedDataManager.shared.refreshAttentionBadge()
        ShieldManager.shared.reevaluateShields()
        WidgetCenter.shared.reloadAllTimelines()
        SharedDataManager.shared.nightscoutLastFetchedAt = Date()
        WatchSessionManager.shared.sendLatestContext()
        // Always keep a pending BG refresh queued so iOS has *something* to
        // schedule against when the app goes to sleep, regardless of who
        // triggered this fetch (foreground poll, scene activation, settings
        // change, BG handler). The system coalesces duplicate submissions.
        scheduleBackgroundRefresh()
    }

    private func fetchGlucose(using client: NightscoutClient) async {
        do {
            if let sample = try await client.fetchLatestGlucose() {
                SharedDataManager.shared.saveNightscoutGlucose(mmol: sample.mmol, at: sample.date)
                logger.info("Nightscout glucose: \(String(format: "%.1f", sample.mmol)) mmol/L at \(sample.date)")
            }
            SharedDataManager.shared.nightscoutLastError = nil
        } catch {
            logger.error("Nightscout glucose fetch failed: \(error.localizedDescription)")
            SharedDataManager.shared.nightscoutLastError = error.localizedDescription
        }
    }

    private func fetchCarbs(using client: NightscoutClient) async {
        do {
            if let entry = try await client.fetchLatestCarbs() {
                SharedDataManager.shared.saveNightscoutCarbs(grams: entry.grams, at: entry.date)
                logger.info("Nightscout carbs: \(String(format: "%.0f", entry.grams))g at \(entry.date)")
            }
        } catch {
            logger.error("Nightscout carbs fetch failed: \(error.localizedDescription)")
            SharedDataManager.shared.nightscoutLastError = error.localizedDescription
        }
    }

    /// One-shot connection test used by the Settings UI. Returns the server
    /// status when reachable, throws otherwise.
    func testConnection(baseURL: String, token: String?) async throws -> NightscoutClient.ServerStatus {
        guard let client = NightscoutClient(baseURLString: baseURL, token: token) else {
            throw NightscoutClient.ClientError.invalidBaseURL
        }
        return try await client.fetchStatus()
    }

    // MARK: - Background refresh

    /// Schedule the next background app refresh. Only relevant when Nightscout
    /// is the primary source (HealthKit doesn't provide background wakeups).
    func scheduleBackgroundRefresh() {
        guard isConfigured else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.pollInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled Nightscout background refresh")
        } catch {
            logger.error("Failed to schedule Nightscout background refresh: \(error.localizedDescription)")
        }
    }

    /// Run a Nightscout fetch as part of a `BGAppRefreshTask`.
    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        logger.info("Nightscout background refresh task started")
        scheduleBackgroundRefresh()

        let work = Task { @MainActor in
            await fetchAll()
            logger.info("Nightscout background refresh task completed")
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            self.logger.warning("Nightscout background refresh task expired")
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
