import Foundation

/// Shared HTTP client for the EasyView REST API (Medtrum cloud companion).
///
/// EasyView uses cookie-based session auth: callers must first call the static
/// `login` method to obtain a session cookie string, then pass it to the
/// instance initialiser. Every subsequent request sends the cookie in the
/// `Cookie` request header.
///
/// Platform-specific managers (`EasyViewManager` on iOS,
/// `WatchEasyViewManager` on watchOS) handle session persistence and lifecycle;
/// this type only deals with request construction and JSON parsing so the
/// logic stays identical across platforms.
///
/// ## Account modes
///
/// - **Patient** (`user_type == "P"`): the logged-in user IS the patient.
///   `patientUID` equals the `uid` returned from `login`.
/// - **Monitor** (`user_type == "M"`): the logged-in user is a caregiver.
///   Call `fetchConnections()` to list monitored patients and let the user
///   pick one. The chosen patient's `uid` becomes `patientUID`.
public struct EasyViewClient: Sendable {

    // MARK: - Error

    public enum ClientError: Error, LocalizedError, Sendable {
        case invalidBaseURL
        case invalidResponse
        case http(status: Int)
        case sessionExpired
        case decoding(String)

        public var errorDescription: String? {
            switch self {
            case .invalidBaseURL: return "Invalid EasyView URL"
            case .invalidResponse: return "Invalid response from EasyView"
            case let .http(status): return "HTTP \(status)"
            case .sessionExpired: return "Session expired (re-login required)"
            case let .decoding(message): return "Parse error: \(message)"
            }
        }
    }

    // MARK: - Output types (shared with NightscoutClient consumers)

    public struct GlucoseSample: Sendable {
        /// Blood glucose value in mmol/L.
        public let mmol: Double
        /// Timestamp the sample was recorded.
        public let date: Date
    }

    public struct CarbEntry: Sendable {
        public let grams: Double
        public let date: Date
    }

    /// A patient connection returned by `fetchConnections()`.
    public struct Connection: Sendable {
        public let uid: Int
        public let realName: String
    }

    /// Result of a successful `login` call.
    public struct LoginResult: Sendable {
        /// Cookie string to pass to the `EasyViewClient` initialiser.
        /// Format: `"userid=<N>; session=<signed-token>"`.
        public let sessionCookie: String
        /// The uid of the logged-in account.
        public let uid: Int
        /// `"P"` for patient, `"M"` for monitor/caregiver.
        public let userType: String

        /// Whether this account is a patient (owns their own data).
        public var isPatient: Bool { userType == "P" }
    }

    // MARK: - Instance state

    public let baseURL: URL
    /// Cookie string sent with every authenticated request.
    /// Format: `"userid=<N>; session=<signed-token>"`.
    public let sessionCookie: String
    private let urlSession: URLSession
    private let requestTimeout: TimeInterval

    // MARK: - Init

    public init(
        baseURL: URL,
        sessionCookie: String,
        urlSession: URLSession = .shared,
        requestTimeout: TimeInterval = 15
    ) {
        self.baseURL = baseURL
        self.sessionCookie = sessionCookie
        self.urlSession = urlSession
        self.requestTimeout = requestTimeout
    }

    public init?(
        baseURLString: String,
        sessionCookie: String,
        urlSession: URLSession = .shared,
        requestTimeout: TimeInterval = 15
    ) {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return nil }
        if components.scheme == nil { components.scheme = "https" }
        guard let url = components.url, url.host?.isEmpty == false else { return nil }
        self.init(baseURL: url, sessionCookie: sessionCookie, urlSession: urlSession, requestTimeout: requestTimeout)
    }

    // MARK: - Login (static — no session needed)

    /// Authenticate with username + password. Returns a `LoginResult` whose
    /// `sessionCookie` should be stored (App Group UserDefaults) and passed to
    /// subsequent `EasyViewClient` instances.
    ///
    /// Throws `ClientError.sessionExpired` on 401, other `ClientError` cases on
    /// network or parse failures.
    public static func login(
        baseURLString: String,
        username: String,
        password: String,
        urlSession: URLSession = .shared,
        requestTimeout: TimeInterval = 15
    ) async throws -> LoginResult {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { throw ClientError.invalidBaseURL }
        if components.scheme == nil { components.scheme = "https" }
        guard let baseURL = components.url, baseURL.host?.isEmpty == false else {
            throw ClientError.invalidBaseURL
        }

        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidBaseURL
        }
        var basePath = urlComponents.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        urlComponents.path = basePath + "/api/v2.0/login"
        guard let url = urlComponents.url else { throw ClientError.invalidBaseURL }

        let body = try JSONSerialization.data(withJSONObject: [
            "user_name": username,
            "user_type": "P",
            "password": password,
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }

        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw ClientError.sessionExpired
        default: throw ClientError.http(status: http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.decoding("login response not an object")
        }
        guard let uid = json["uid"] as? Int else {
            throw ClientError.decoding("missing uid in login response")
        }
        let userType = json["user_type"] as? String ?? "P"

        // Extract cookies from Set-Cookie headers. The session cookie
        // is a signed Flask token; the userid is the numeric account id.
        var cookieParts: [String] = []
        let headerFields = http.allHeaderFields as? [String: String] ?? [:]
        // `HTTPURLResponse.allHeaderFields` combines all headers into a dict
        // (losing duplicate Set-Cookie entries on case-insensitive keys).
        // We parse the response cookies via HTTPCookieStorage patterns:
        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: headerFields,
            for: url
        )
        for cookie in cookies where cookie.name == "session" || cookie.name == "userid" {
            cookieParts.append("\(cookie.name)=\(cookie.value)")
        }

        // Ensure userid is present even if it arrived in the body rather
        // than a Set-Cookie header (observed: some EasyView deployments
        // surface only a `session` cookie; userid comes from the JSON body).
        if !cookieParts.contains(where: { $0.hasPrefix("userid=") }) {
            cookieParts.insert("userid=\(uid)", at: 0)
        }

        if cookieParts.isEmpty {
            throw ClientError.decoding("no session cookie in login response")
        }
        let sessionCookie = cookieParts.joined(separator: "; ")
        return LoginResult(sessionCookie: sessionCookie, uid: uid, userType: userType)
    }

    // MARK: - Connections (monitor accounts only)

    /// Fetch the list of patients this monitor account can observe.
    /// Returns an empty array (rather than throwing) when the endpoint returns
    /// `error: 14` (patient account — callers should use `loginResult.uid`).
    public func fetchConnections() async throws -> [Connection] {
        let request = try makeRequest(path: "/api/v2.1/monitor/connections", query: [
            URLQueryItem(name: "per_page", value: "9999"),
        ])
        do {
            let data = try await perform(request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let items = dataObj["items"] as? [[String: Any]]
            else {
                return []
            }
            return items.compactMap { item in
                guard let uid = item["uid"] as? Int else { return nil }
                let name = item["real_name"] as? String ?? ""
                return Connection(uid: uid, realName: name)
            }
        } catch ClientError.http(let status) where status == 403 {
            // Patient accounts get 403 on this endpoint — not an error.
            return []
        }
    }

    // MARK: - Glucose

    /// Fetch the most recent BG event from the last `windowHours` hours.
    /// Returns nil when there are no events in the window.
    public func fetchLatestGlucose(patientUID: Int, windowHours: Double = 3) async throws -> GlucoseSample? {
        let items = try await fetchEvents(patientUID: patientUID, windowHours: windowHours)
        let bgEvents = items.filter { event in
            guard event.count > 2 else { return false }
            return (event[2] as? String) == "BG"
        }
        .sorted { a, b in
            (a[1] as? Double ?? 0) > (b[1] as? Double ?? 0)
        }

        guard let latest = bgEvents.first,
              let ts = latest[1] as? Double,
              let dataDict = latest[3] as? [String: Any],
              let mgdl = dataDict["value"] as? Double
        else { return nil }

        return GlucoseSample(mmol: mgdl / 18.018, date: Date(timeIntervalSince1970: ts))
    }

    // MARK: - Carbs

    /// Fetch the most recent CARB event from the last `windowHours` hours.
    /// Returns nil when there are no carb events in the window.
    public func fetchLatestCarbs(patientUID: Int, windowHours: Double = 4) async throws -> CarbEntry? {
        let items = try await fetchEvents(patientUID: patientUID, windowHours: windowHours)
        let carbEvents = items.filter { event in
            guard event.count > 2 else { return false }
            return (event[2] as? String) == "CARB"
        }
        .sorted { a, b in
            (a[1] as? Double ?? 0) > (b[1] as? Double ?? 0)
        }

        guard let latest = carbEvents.first,
              let ts = latest[1] as? Double,
              let dataDict = latest[3] as? [String: Any],
              let grams = dataDict["value"] as? Double
        else { return nil }

        return CarbEntry(grams: grams, date: Date(timeIntervalSince1970: ts))
    }

    // MARK: - Private: events

    /// Fetch raw events for `patientUID` over the last `windowHours` hours.
    /// Each event is an array: `[id, timestamp, type, data, source, record_id]`.
    private func fetchEvents(patientUID: Int, windowHours: Double) async throws -> [[Any]] {
        let now = Date().timeIntervalSince1970
        let start = now - windowHours * 3600
        let param = encodeEventsParam(start: start, end: now)

        let request = try makeRequest(path: "/api/v2.0/events/\(patientUID)", query: [
            URLQueryItem(name: "param", value: param),
            URLQueryItem(name: "per_page", value: "9999"),
            URLQueryItem(name: "page", value: "1"),
        ])
        let data = try await perform(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let items = dataObj["items"] as? [[Any]]
        else { return [] }
        return items
    }

    /// Encode the base64 JSON `param` expected by the events endpoint.
    private func encodeEventsParam(start: Double, end: Double) -> String {
        let obj: [String: Any] = [
            "order": [["time", "desc"]],
            "st": Int(start),
            "et": Int(end),
        ]
        let jsonData = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
        return jsonData.base64EncodedString()
    }

    // MARK: - Private: request plumbing

    private func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidBaseURL
        }
        var basePath = components.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + path
        components.queryItems = query.isEmpty ? nil : query

        guard let url = components.url else { throw ClientError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw ClientError.sessionExpired
        default: throw ClientError.http(status: http.statusCode)
        }
    }
}
