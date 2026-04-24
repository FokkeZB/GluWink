import Foundation

/// Shared HTTP client for the Nightscout REST API.
/// Platform-specific wrappers (iOS / watchOS) handle storage and lifecycle;
/// this type only deals with request construction and JSON parsing so logic
/// stays identical across platforms.
public struct NightscoutClient: Sendable {
    public enum ClientError: Error, LocalizedError, Sendable {
        case invalidBaseURL
        case invalidResponse
        case http(status: Int)
        case unauthorized
        case decoding(String)

        public var errorDescription: String? {
            switch self {
            case .invalidBaseURL: return "Invalid Nightscout URL"
            case .invalidResponse: return "Invalid response from Nightscout"
            case let .http(status): return "HTTP \(status)"
            case .unauthorized: return "Unauthorized (check token)"
            case let .decoding(message): return "Parse error: \(message)"
            }
        }
    }

    public struct GlucoseSample: Sendable {
        /// Blood glucose value in mmol/L (internal storage unit).
        public let mmol: Double
        /// Timestamp the sample was recorded.
        public let date: Date
    }

    public struct CarbEntry: Sendable {
        public let grams: Double
        public let date: Date
    }

    public struct ServerStatus: Sendable {
        public let version: String?
        /// Server-reported display unit (`mg/dl` or `mmol`).
        public let units: String?
    }

    public let baseURL: URL
    public let token: String?
    private let session: URLSession
    private let requestTimeout: TimeInterval

    public init(baseURL: URL, token: String?, session: URLSession = .shared, requestTimeout: TimeInterval = 15) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.requestTimeout = requestTimeout
    }

    /// Convenience: build a client from user-provided strings. Returns nil if
    /// the URL cannot be parsed.
    public init?(baseURLString: String, token: String?, session: URLSession = .shared, requestTimeout: TimeInterval = 15) {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return nil }
        if components.scheme == nil {
            components.scheme = "https"
        }
        guard let url = components.url, url.host?.isEmpty == false else { return nil }
        self.init(baseURL: url, token: token, session: session, requestTimeout: requestTimeout)
    }

    // MARK: - Public fetches

    /// Fetch the latest glucose sample (`sgv` entry), or nil if the Nightscout
    /// instance has no data.
    public func fetchLatestGlucose() async throws -> GlucoseSample? {
        let request = try makeRequest(path: "/api/v1/entries/sgv.json", query: [
            URLQueryItem(name: "count", value: "1"),
        ])
        let data = try await perform(request)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first
        else {
            return nil
        }
        guard let sgv = first["sgv"] as? Double ?? (first["sgv"] as? Int).map(Double.init) else {
            throw ClientError.decoding("missing sgv")
        }
        let date = Self.parseDate(from: first)
        return GlucoseSample(mmol: sgv / 18.018, date: date)
    }

    /// Fetch the most recent treatment with a carb value (ignoring zero-carb
    /// entries such as pure insulin boluses).
    public func fetchLatestCarbs() async throws -> CarbEntry? {
        let request = try makeRequest(path: "/api/v1/treatments.json", query: [
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "find[carbs][$gte]", value: "1"),
        ])
        let data = try await perform(request)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first
        else {
            return nil
        }
        guard let carbs = first["carbs"] as? Double ?? (first["carbs"] as? Int).map(Double.init) else {
            return nil
        }
        let date = Self.parseDate(from: first)
        return CarbEntry(grams: carbs, date: date)
    }

    /// Fetch `/api/v1/status` as a connectivity check. Returns parsed version
    /// and unit info when available.
    public func fetchStatus() async throws -> ServerStatus {
        let request = try makeRequest(path: "/api/v1/status.json", query: [])
        let data = try await perform(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.decoding("status not an object")
        }
        let version = object["version"] as? String
        let settings = object["settings"] as? [String: Any]
        let units = settings?["units"] as? String
        return ServerStatus(version: version, units: units)
    }

    // MARK: - Request plumbing

    private func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidBaseURL
        }
        // Append path segments rather than overwriting any existing path on the base URL.
        var basePath = components.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + path

        var items = query
        if let token, !token.isEmpty {
            items.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = items.isEmpty ? nil : items

        guard let url = components.url else {
            throw ClientError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw ClientError.unauthorized
        default:
            throw ClientError.http(status: http.statusCode)
        }
    }

    private static func parseDate(from object: [String: Any]) -> Date {
        // Nightscout uses millisecond epoch in `date` (entries) or `created_at`
        // ISO8601 strings (treatments / older entries).
        if let ms = object["date"] as? Double {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        if let ms = object["date"] as? Int {
            return Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        if let iso = object["created_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: iso) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: iso) {
                return date
            }
        }
        if let dateString = object["dateString"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return Date()
    }
}
