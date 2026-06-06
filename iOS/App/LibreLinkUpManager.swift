import BackgroundTasks
import CryptoKit
import Foundation
import os
import SharedKit
import WidgetKit

/// Coordinates LibreLinkUp polling on iOS. Authenticates with the Abbott
/// LibreView cloud and fetches the first follower connection's latest glucose
/// reading, writing it to the per-source `librelinkup*` keys via
/// `SharedDataManager` so `UnifiedDataReader` can race it against other
/// enabled sources.
///
/// Credentials (email, password) and the cached auth token are stored in
/// Keychain. The auth region (`librelinkupRegion`) and last-seen patientId
/// (`librelinkupPatientId`) live in the App Group so they survive the manager
/// being recreated (e.g. after a fresh install wipe).
///
/// Glucose only — LibreLinkUp provides no carb data.
@MainActor
final class LibreLinkUpManager {
    static let shared = LibreLinkUpManager()

    static let backgroundTaskIdentifier = "\(Constants.bundlePrefix).librelinkup.refresh"
    static let pollInterval: TimeInterval = 5 * 60

    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "LibreLinkUpManager")

    private var pollTimer: Timer?
    private var inFlight = false

    private init() {}

    // MARK: - Config

    var isConfigured: Bool {
        KeychainManager.shared.libreLinkUpEmail?.isEmpty == false
            && KeychainManager.shared.libreLinkUpPassword?.isEmpty == false
    }

    // MARK: - Polling lifecycle

    func startPolling() {
        stopPolling()
        guard isConfigured else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchLatestGlucose()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        logger.info("LibreLinkUp polling started (\(Int(Self.pollInterval))s)")
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func configurationDidChange() {
        if isConfigured {
            startPolling()
            Task { await fetchLatestGlucose() }
        } else {
            stopPolling()
        }
    }

    // MARK: - Enable / disable

    func enable() {
        startPolling()
        Task { await fetchLatestGlucose() }
    }

    func disable() {
        stopPolling()
        SharedDataManager.shared.handleSourceDisabled(.libreLinkUp)
    }

    // MARK: - Fetching

    func fetchLatestGlucose() async {
        guard isConfigured else { return }
        guard !SharedDataManager.shared.isMockModeEnabled else {
            logger.info("Mock mode active — skipping LibreLinkUp fetch")
            return
        }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        do {
            let token = try await validToken()
            let region = SharedDataManager.shared.librelinkupRegion
            let userId = SharedDataManager.shared.librelinkupUserId
            let connections = try await Self.fetchConnections(token: token, region: region, userId: userId)

            guard !connections.isEmpty else {
                logger.warning("LibreLinkUp: no connections in account")
                SharedDataManager.shared.librelinkupLastError = String(localized: "librelinkup.error.noConnections")
                return
            }

            let storedPatientId = SharedDataManager.shared.librelinkupPatientId
            let connection = connections.first(where: { $0.patientId == storedPatientId }) ?? connections[0]

            let mmol = connection.glucoseMeasurement.valueInMgPerDl / 18.01559
            let sampleAt = connection.glucoseMeasurement.timestamp
            SharedDataManager.shared.saveLibreLinkUpGlucose(mmol: mmol, at: sampleAt)
            SharedDataManager.shared.librelinkupPatientId = connection.patientId
            SharedDataManager.shared.librelinkupLastFetchedAt = Date()
            SharedDataManager.shared.librelinkupLastError = nil

            logger.info("LibreLinkUp glucose: \(String(format: "%.1f", mmol)) mmol/L at \(sampleAt)")

            SharedDataManager.shared.refreshAttentionBadge()
            ShieldManager.shared.reevaluateShields()
            WidgetCenter.shared.reloadAllTimelines()
            WatchSessionManager.shared.sendLatestContext()
            scheduleBackgroundRefresh()
        } catch {
            logger.error("LibreLinkUp fetch failed: \(error.localizedDescription)")
            SharedDataManager.shared.librelinkupLastError = error.localizedDescription
        }
    }

    // MARK: - Connection test (settings UI)

    struct TestResult {
        let mmol: Double
        let sampleAt: Date
        let patientId: String
        let patientName: String
        let allConnections: [(patientId: String, name: String)]
    }

    /// Authenticate with the given credentials and fetch one glucose sample.
    /// On success persists credentials, token, and region to Keychain / App Group.
    func testConnection(email: String, password: String) async throws -> TestResult {
        KeychainManager.shared.libreLinkUpEmail = email
        KeychainManager.shared.libreLinkUpPassword = password
        // Clear any cached token so we re-authenticate with the new credentials.
        KeychainManager.shared.libreLinkUpToken = nil
        KeychainManager.shared.libreLinkUpTokenExpiry = nil

        let token = try await authenticate(email: email, password: password)
        let region = SharedDataManager.shared.librelinkupRegion
        let connections = try await Self.fetchConnections(token: token, region: region, userId: SharedDataManager.shared.librelinkupUserId)

        guard let first = connections.first else {
            throw LibreLinkUpError.noConnections
        }

        let storedPatientId = SharedDataManager.shared.librelinkupPatientId
        let picked = connections.first(where: { $0.patientId == storedPatientId }) ?? first

        let mmol = picked.glucoseMeasurement.valueInMgPerDl / 18.01559
        let sampleAt = picked.glucoseMeasurement.timestamp
        SharedDataManager.shared.librelinkupPatientId = picked.patientId

        return TestResult(
            mmol: mmol,
            sampleAt: sampleAt,
            patientId: picked.patientId,
            patientName: "\(picked.firstName) \(picked.lastName)",
            allConnections: connections.map { (patientId: $0.patientId, name: "\($0.firstName) \($0.lastName)") }
        )
    }

    /// Fetch available follower connections without saving glucose — used by the settings UI to populate the patient picker.
    func fetchConnectionList() async throws -> [(patientId: String, name: String)] {
        let token = try await validToken()
        let region = SharedDataManager.shared.librelinkupRegion
        let userId = SharedDataManager.shared.librelinkupUserId
        let connections = try await Self.fetchConnections(token: token, region: region, userId: userId)
        return connections.map { (patientId: $0.patientId, name: "\($0.firstName) \($0.lastName)") }
    }

    // MARK: - Background refresh

    func scheduleBackgroundRefresh() {
        guard isConfigured else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.pollInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Failed to schedule LibreLinkUp background refresh: \(error.localizedDescription)")
        }
    }

    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        logger.info("LibreLinkUp background refresh task started")
        scheduleBackgroundRefresh()

        let work = Task { @MainActor in
            await fetchLatestGlucose()
            logger.info("LibreLinkUp background refresh task completed")
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            self.logger.warning("LibreLinkUp background refresh task expired")
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Auth

    /// Return a valid token from Keychain, re-authenticating if expired or absent.
    private func validToken() async throws -> String {
        if let token = KeychainManager.shared.libreLinkUpToken,
           let expiry = KeychainManager.shared.libreLinkUpTokenExpiry,
           expiry.timeIntervalSinceNow > 60,
           SharedDataManager.shared.librelinkupUserId != nil {
            return token
        }
        guard let email = KeychainManager.shared.libreLinkUpEmail,
              let password = KeychainManager.shared.libreLinkUpPassword else {
            throw LibreLinkUpError.missingCredentials
        }
        return try await authenticate(email: email, password: password)
    }

    /// Full auth flow: login → region redirect → terms acceptance → token.
    /// Stores the resulting token + expiry + region in Keychain / App Group.
    @discardableResult
    func authenticate(email: String, password: String) async throws -> String {
        var currentRegion = SharedDataManager.shared.librelinkupRegion

        for _ in 0..<3 {
            let baseURL = Self.baseURL(for: currentRegion)
            let response = try await Self.postLogin(email: email, password: password, baseURL: baseURL)

            switch response {
            case let .redirect(region):
                currentRegion = region
                SharedDataManager.shared.librelinkupRegion = region
                SharedDataManager.shared.flush()
                logger.info("LibreLinkUp auth: redirected to region '\(region)'")
                continue

            case let .touRequired(stepType, ticketToken):
                logger.info("LibreLinkUp auth: ToU required (type=\(stepType)), accepting")
                try await Self.postContinue(type: stepType, token: ticketToken, baseURL: baseURL, userId: nil)
                // After terms acceptance, re-login to get a full auth ticket.
                continue

            case let .success(token, expiry, userId):
                KeychainManager.shared.libreLinkUpToken = token
                KeychainManager.shared.libreLinkUpTokenExpiry = expiry
                SharedDataManager.shared.librelinkupUserId = userId
                return token
            }
        }

        throw LibreLinkUpError.authLoopExceeded
    }

    // MARK: - HTTP

    private static func baseURL(for region: String?) -> String {
        if let region, !region.isEmpty {
            return "https://api-\(region).libreview.io"
        }
        return "https://api.libreview.io"
    }

    private static let commonHeaders: [String: String] = [
        "product": "llu.ios",
        "version": "5.0.1",
        "content-type": "application/json",
        "accept-encoding": "gzip",
        "cache-control": "no-cache",
        "connection": "Keep-Alive",
    ]

    private static func accountIDHeader(for userId: String) -> String {
        let data = Data(userId.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    enum LoginResponse {
        case redirect(region: String)
        case touRequired(stepType: String, ticketToken: String)
        case success(token: String, expiry: Date, userId: String)
    }

    private static func postLogin(email: String, password: String, baseURL: String) async throws -> LoginResponse {
        guard let url = URL(string: "\(baseURL)/llu/auth/login") else {
            throw LibreLinkUpError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        for (key, value) in commonHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LibreLinkUpError.invalidResponse }

        if http.statusCode == 401 {
            throw LibreLinkUpError.invalidCredentials
        }
        guard http.statusCode == 200 else {
            throw LibreLinkUpError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int,
              let dataDict = json["data"] as? [String: Any] else {
            throw LibreLinkUpError.invalidResponse
        }

        // Redirect: retry with different region.
        if status == 0,
           let redirect = dataDict["redirect"] as? Bool, redirect,
           let region = dataDict["region"] as? String {
            return .redirect(region: region)
        }

        // Terms-of-use required.
        if status == 4,
           let step = dataDict["step"] as? [String: Any],
           let stepType = step["type"] as? String,
           let ticket = dataDict["authTicket"] as? [String: Any],
           let ticketToken = ticket["token"] as? String {
            return .touRequired(stepType: stepType, ticketToken: ticketToken)
        }

        // Success.
        if status == 0,
           let user = dataDict["user"] as? [String: Any],
           let userId = user["id"] as? String,
           let ticket = dataDict["authTicket"] as? [String: Any],
           let token = ticket["token"] as? String {
            let expires = (ticket["expires"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
                ?? Date(timeIntervalSinceNow: 3600)
            return .success(token: token, expiry: expires, userId: userId)
        }

        throw LibreLinkUpError.unexpectedAuthResponse(status: status)
    }

    private static func postContinue(type: String, token: String, baseURL: String, userId: String?) async throws {
        guard let url = URL(string: "\(baseURL)/llu/auth/continue/\(type)") else {
            throw LibreLinkUpError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        for (key, value) in commonHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        if let userId {
            request.setValue(accountIDHeader(for: userId), forHTTPHeaderField: "account-id")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LibreLinkUpError.invalidResponse
        }
    }

    struct Connection {
        let patientId: String
        let firstName: String
        let lastName: String
        let glucoseMeasurement: GlucoseMeasurement
    }

    struct GlucoseMeasurement {
        let valueInMgPerDl: Double
        let timestamp: Date
    }

    private static let factoryTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy h:mm:ss a z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func fetchConnections(token: String, region: String?, userId: String?) async throws -> [Connection] {
        guard let url = URL(string: "\(baseURL(for: region))/llu/connections") else {
            throw LibreLinkUpError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        for (key, value) in commonHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        if let userId {
            request.setValue(accountIDHeader(for: userId), forHTTPHeaderField: "account-id")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LibreLinkUpError.invalidResponse }

        if http.statusCode == 401 { throw LibreLinkUpError.tokenExpired }
        guard http.statusCode == 200 else { throw LibreLinkUpError.httpError(http.statusCode) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, status == 0,
              let dataArray = json["data"] as? [[String: Any]] else {
            throw LibreLinkUpError.invalidResponse
        }

        return dataArray.compactMap { entry -> Connection? in
            guard let patientId = entry["patientId"] as? String,
                  let firstName = entry["firstName"] as? String,
                  let lastName = entry["lastName"] as? String,
                  let measurement = entry["glucoseMeasurement"] as? [String: Any],
                  let valueMgdl = measurement["ValueInMgPerDl"] as? Double,
                  let factoryTimestamp = measurement["FactoryTimestamp"] as? String else { return nil }

            let timestampString = factoryTimestamp.hasSuffix(" UTC")
                ? factoryTimestamp
                : factoryTimestamp + " UTC"

            guard let date = factoryTimestampFormatter.date(from: timestampString) else { return nil }

            return Connection(
                patientId: patientId,
                firstName: firstName,
                lastName: lastName,
                glucoseMeasurement: GlucoseMeasurement(valueInMgPerDl: valueMgdl, timestamp: date)
            )
        }
    }
}

// MARK: - Errors

enum LibreLinkUpError: LocalizedError {
    case missingCredentials
    case invalidURL
    case invalidResponse
    case invalidCredentials
    case httpError(Int)
    case tokenExpired
    case noConnections
    case authLoopExceeded
    case unexpectedAuthResponse(status: Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return String(localized: "librelinkup.error.missingCredentials")
        case .invalidURL: return String(localized: "librelinkup.error.invalidURL")
        case .invalidResponse: return String(localized: "librelinkup.error.invalidResponse")
        case .invalidCredentials: return String(localized: "librelinkup.error.invalidCredentials")
        case .httpError(let code): return String(localized: "librelinkup.error.httpError \(code)")
        case .tokenExpired: return String(localized: "librelinkup.error.tokenExpired")
        case .noConnections: return String(localized: "librelinkup.error.noConnections")
        case .authLoopExceeded: return String(localized: "librelinkup.error.authLoopExceeded")
        case .unexpectedAuthResponse(let status): return String(localized: "librelinkup.error.unexpectedAuthResponse \(status)")
        }
    }
}
