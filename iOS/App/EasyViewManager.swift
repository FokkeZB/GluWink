import BackgroundTasks
import Foundation
import os
import SharedKit
import WidgetKit

/// Coordinates EasyView polling on iOS. Mirrors `NightscoutManager` in shape:
/// a singleton that keeps the App Group keys up to date via `SharedDataManager`,
/// reloads widgets, and refreshes shields/app icon.
///
/// On session expiry (`.sessionExpired` from `EasyViewClient`) the manager
/// re-logs in using the password from Keychain, stores the new session cookie in
/// the App Group, then retries the fetch once. If re-login also fails, the error
/// is surfaced in `SharedDataManager.easyViewLastError`.
@MainActor
final class EasyViewManager {
    static let shared = EasyViewManager()

    static let backgroundTaskIdentifier = "\(Constants.bundlePrefix).easyview.refresh"
    static let pollInterval: TimeInterval = 5 * 60

    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "EasyViewManager")

    private var pollTimer: Timer?
    private var inFlight = false

    private init() {}

    // MARK: - Config

    /// Build a client from current user configuration. Returns nil when
    /// EasyView is disabled or there is no session cookie yet.
    private func currentClient() -> EasyViewClient? {
        let data = SharedDataManager.shared
        guard data.easyViewEnabled,
              let session = data.easyViewSession
        else { return nil }
        return EasyViewClient(sessionCookie: session)
    }

    var isConfigured: Bool {
        let data = SharedDataManager.shared
        guard let username = data.easyViewUsername, !username.isEmpty,
              KeychainManager.shared.easyViewPassword?.isEmpty == false
        else { return false }
        return true
    }

    // MARK: - Polling lifecycle

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
        logger.info("EasyView polling started (\(Int(Self.pollInterval))s)")
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

    // MARK: - Fetching

    func fetchAll() async {
        guard isConfigured else { return }
        guard !SharedDataManager.shared.isMockModeEnabled else {
            logger.info("Mock mode active — skipping EasyView fetch")
            return
        }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        // If we have no session yet, try to get one first.
        if SharedDataManager.shared.easyViewSession == nil {
            guard await reLogin() else { return }
        }

        await performFetch(retryOnExpiry: true)
    }

    /// Internal fetch pass. When `retryOnExpiry` is true and the session is
    /// expired, re-login once and retry. This keeps `fetchAll` readable while
    /// avoiding unbounded recursion.
    private func performFetch(retryOnExpiry: Bool) async {
        guard let client = currentClient() else { return }
        let data = SharedDataManager.shared

        guard let patientUID = data.easyViewPatientUID else {
            logger.warning("EasyView patientUID not set — skipping fetch")
            data.easyViewLastError = "Patient not selected"
            return
        }

        do {
            // Fetch glucose and carbs concurrently.
            async let glucoseTask = client.fetchLatestGlucose(patientUID: patientUID)
            async let carbsTask = client.fetchLatestCarbs(patientUID: patientUID)

            let glucose = try await glucoseTask
            let carbs = try await carbsTask

            if let glucose {
                data.saveEasyViewGlucose(mmol: glucose.mmol, at: glucose.date)
                logger.info("EasyView glucose: \(String(format: "%.1f", glucose.mmol)) mmol/L at \(glucose.date)")
            }
            if let carbs {
                data.saveEasyViewCarbs(grams: carbs.grams, at: carbs.date)
                logger.info("EasyView carbs: \(String(format: "%.0f", carbs.grams))g at \(carbs.date)")
            }
            data.easyViewLastError = nil
        } catch EasyViewClient.ClientError.sessionExpired where retryOnExpiry {
            logger.info("EasyView session expired — re-logging in")
            guard await reLogin() else { return }
            await performFetch(retryOnExpiry: false)
            return
        } catch {
            logger.error("EasyView fetch failed: \(error.localizedDescription)")
            data.easyViewLastError = error.localizedDescription
        }

        data.easyViewLastFetchedAt = Date()
        data.refreshAttentionBadge()
        ShieldManager.shared.reevaluateShields()
        WidgetCenter.shared.reloadAllTimelines()
        WatchSessionManager.shared.sendLatestContext()
        scheduleBackgroundRefresh()
    }

    /// Re-login using stored credentials. Writes the new session to the App
    /// Group on success. Returns true when the session was refreshed.
    @discardableResult
    func reLogin() async -> Bool {
        let data = SharedDataManager.shared
        guard let username = data.easyViewUsername,
              let password = KeychainManager.shared.easyViewPassword
        else {
            logger.error("EasyView re-login failed — missing credentials")
            data.easyViewLastError = "Missing credentials"
            return false
        }
        do {
            let result = try await EasyViewClient.login(
                username: username,
                password: password
            )
            data.easyViewSession = result.sessionCookie
            data.flush()
            logger.info("EasyView re-login succeeded (userType=\(result.userType))")
            return true
        } catch {
            logger.error("EasyView re-login failed: \(error.localizedDescription)")
            data.easyViewLastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Connection test (settings UI)

    struct TestResult {
        let glucose: EasyViewClient.GlucoseSample?
        let carbs: EasyViewClient.CarbEntry?
    }

    /// Login + fetch one glucose sample. Used by the Settings UI to verify credentials.
    /// On success also writes the session + patientUID to the App Group.
    func testConnection(
        username: String,
        password: String
    ) async throws -> TestResult {
        let loginResult = try await EasyViewClient.login(
            username: username,
            password: password
        )

        let client = EasyViewClient(sessionCookie: loginResult.sessionCookie)

        // Resolve the patient UID. For patient accounts use the login uid
        // directly. For monitor accounts try fetchConnections; fall back to
        // the login uid if that call fails or returns nothing (e.g. the
        // account has dual roles, or the endpoint is temporarily unreachable).
        let patientUID: Int
        if loginResult.isPatient {
            patientUID = loginResult.uid
        } else {
            let connections = (try? await client.fetchConnections()) ?? []
            patientUID = connections.first?.uid ?? loginResult.uid
            logger.info("EasyView monitor account: resolved patientUID=\(patientUID) via \(connections.isEmpty ? "login uid fallback" : "connections")")
        }

        let glucose = try await client.fetchLatestGlucose(patientUID: patientUID)

        // Persist on success.
        let data = SharedDataManager.shared
        data.easyViewSession = loginResult.sessionCookie
        data.easyViewPatientUID = patientUID
        data.flush()

        return TestResult(glucose: glucose, carbs: nil)
    }

    // MARK: - Background refresh

    func scheduleBackgroundRefresh() {
        guard isConfigured else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.pollInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Failed to schedule EasyView background refresh: \(error.localizedDescription)")
        }
    }

    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        logger.info("EasyView background refresh task started")
        scheduleBackgroundRefresh()

        let work = Task { @MainActor in
            await fetchAll()
            logger.info("EasyView background refresh task completed")
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            self.logger.warning("EasyView background refresh task expired")
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
