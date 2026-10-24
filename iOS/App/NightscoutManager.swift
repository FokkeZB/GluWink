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
    private let coalescer = FetchCoalescer()

    private init() {}

    // MARK: - Config

    /// Build a client from current user configuration. Returns nil if
    /// Nightscout is disabled or misconfigured.
    private func currentClient() -> NightscoutClient? {
        let data = SharedDataManager.shared
        guard data.nightscoutEnabled,
              let urlString = data.nightscoutBaseURL,
              let client = NightscoutClient(baseURLString: urlString, token: data.nightscoutToken, requestTimeout: NetworkBudget.requestTimeout)
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
                RefreshLog.record("nightscout", "poll fired")
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
        await coalescer.run(
            joined: { RefreshLog.record("nightscout", "fetch joined in-flight request") },
            replaced: { RefreshLog.record("nightscout", "abandoned stuck fetch") }
        ) { [self] in await runFetch() }
    }

    private func runFetch() async {
        guard let client = currentClient() else { return }
        guard !SharedDataManager.shared.isMockModeEnabled else {
            logger.info("Mock mode active — skipping Nightscout fetch")
            return
        }
        RefreshLog.record("nightscout", "fetch started")

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
            if let sample = try await TransientRetry.run("nightscout", "glucose fetch") { try await client.fetchLatestGlucose() } {
                SharedDataManager.shared.saveNightscoutGlucose(mmol: sample.mmol, at: sample.date)
                logger.info("Nightscout glucose: \(String(format: "%.1f", sample.mmol)) mmol/L at \(sample.date)")
                RefreshLog.record("nightscout", "fetch ok (glucose sample \(sample.date.formatted(date: .omitted, time: .shortened)))")
            }
            SharedDataManager.shared.nightscoutLastError = nil
        } catch {
            logger.error("Nightscout glucose fetch failed: \(error.localizedDescription)")
            RefreshLog.record("nightscout", "fetch failed: \(error.localizedDescription)")
            SharedDataManager.shared.nightscoutLastError = error.localizedDescription
        }
    }

    private func fetchCarbs(using client: NightscoutClient) async {
        do {
            if let entry = try await TransientRetry.run("nightscout", "carbs fetch") { try await client.fetchLatestCarbs() } {
                SharedDataManager.shared.saveNightscoutCarbs(grams: entry.grams, at: entry.date)
                logger.info("Nightscout carbs: \(String(format: "%.0f", entry.grams))g at \(entry.date)")
            }
        } catch {
            logger.error("Nightscout carbs fetch failed: \(error.localizedDescription)")
            SharedDataManager.shared.nightscoutLastError = error.localizedDescription
        }
    }

    struct TestResult {
        let glucose: NightscoutClient.GlucoseSample?
        let carbs: NightscoutClient.CarbEntry?
    }

    /// One-shot connection test used by the Settings UI. Fetches the real
    /// glucose + carbs endpoints (same ones the app polls) to verify
    /// credentials, then saves results to the App Group so "Latest data"
    /// is populated immediately. Returns a `TestResult` on success, throws
    /// on network / auth failure.
    func testConnection(baseURL: String, token: String?) async throws -> TestResult {
        guard let client = NightscoutClient(baseURLString: baseURL, token: token) else {
            throw NightscoutClient.ClientError.invalidBaseURL
        }
        let glucose = try await client.fetchLatestGlucose()
        let carbs = try await client.fetchLatestCarbs()
        let data = SharedDataManager.shared
        if let glucose {
            data.saveNightscoutGlucose(mmol: glucose.mmol, at: glucose.date)
        }
        if let carbs {
            data.saveNightscoutCarbs(grams: carbs.grams, at: carbs.date)
        }
        return TestResult(glucose: glucose, carbs: carbs)
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
        BackgroundRefreshHandler.run(task, source: "nightscout") { [self] in await fetchAll() }
    }
}
