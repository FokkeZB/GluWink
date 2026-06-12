import CryptoKit
import Foundation

/// Stateless HTTP primitives for the Abbott LibreView "LibreLinkUp" cloud API.
///
/// Holds only the request construction + JSON parsing that is identical across
/// callers, so the iOS `LibreLinkUpManager` (which also owns the Keychain-backed
/// login flow) and `WidgetLibreLinkUpRefresh` (which can only *read* with an
/// already-issued token — the widget extension has no Keychain access) share one
/// implementation.
///
/// The login / region-redirect / terms-of-use flow stays in the app's
/// `LibreLinkUpManager` because it writes credentials + token to the Keychain.
/// This type covers the authenticated read path: `fetchConnections`.
public enum LibreLinkUpClient {

    // MARK: - Output types

    public struct GlucoseMeasurement: Sendable {
        public let valueInMgPerDl: Double
        public let timestamp: Date

        public init(valueInMgPerDl: Double, timestamp: Date) {
            self.valueInMgPerDl = valueInMgPerDl
            self.timestamp = timestamp
        }
    }

    public struct Connection: Sendable {
        public let patientId: String
        public let firstName: String
        public let lastName: String
        public let glucoseMeasurement: GlucoseMeasurement

        public init(
            patientId: String,
            firstName: String,
            lastName: String,
            glucoseMeasurement: GlucoseMeasurement
        ) {
            self.patientId = patientId
            self.firstName = firstName
            self.lastName = lastName
            self.glucoseMeasurement = glucoseMeasurement
        }
    }

    // MARK: - Error

    public enum ClientError: Error, Sendable {
        case invalidURL
        case invalidResponse
        /// 401 — the auth token has expired or been revoked. The app re-logs in
        /// from the Keychain credentials; the widget serves stale values.
        case tokenExpired
        case httpError(Int)
    }

    // MARK: - Request building blocks

    /// Region-specific base URL. A `nil`/empty region uses the global endpoint,
    /// which responds with a redirect to the correct regional host on login.
    public static func baseURL(for region: String?) -> String {
        if let region, !region.isEmpty {
            return "https://api-\(region).libreview.io"
        }
        return "https://api.libreview.io"
    }

    public static let commonHeaders: [String: String] = [
        "product": "llu.ios",
        "version": "5.0.1",
        "content-type": "application/json",
        "accept-encoding": "gzip",
        "cache-control": "no-cache",
        "connection": "Keep-Alive",
    ]

    /// SHA-256 hex of the userId, sent as the `account-id` header that the
    /// LibreView API requires on authenticated requests.
    public static func accountIDHeader(for userId: String) -> String {
        let data = Data(userId.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let factoryTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy h:mm:ss a z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Authenticated reads

    /// Fetch the account's follower connections plus each one's latest glucose
    /// measurement, using an already-issued auth token.
    ///
    /// Throws `ClientError.tokenExpired` on 401 so the caller can decide whether
    /// to re-authenticate (the app, which holds the Keychain credentials) or
    /// serve stale values (the widget extension, which does not).
    public static func fetchConnections(
        token: String,
        region: String?,
        userId: String?,
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 15
    ) async throws -> [Connection] {
        guard let url = URL(string: "\(baseURL(for: region))/llu/connections") else {
            throw ClientError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        for (key, value) in commonHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        if let userId {
            request.setValue(accountIDHeader(for: userId), forHTTPHeaderField: "account-id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }

        if http.statusCode == 401 { throw ClientError.tokenExpired }
        guard http.statusCode == 200 else { throw ClientError.httpError(http.statusCode) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, status == 0,
              let dataArray = json["data"] as? [[String: Any]] else {
            throw ClientError.invalidResponse
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
