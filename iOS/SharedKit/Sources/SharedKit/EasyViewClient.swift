import Foundation

/// Shared HTTP client for the EasyView REST API.
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

    // MARK: - Constants

    /// The single known EasyView cloud endpoint.
    public static let baseURL = URL(string: "https://easyview.medtrum.eu/")!

    // MARK: - Error

    public enum ClientError: Error, LocalizedError, Sendable {
        case invalidResponse
        case http(status: Int)
        case sessionExpired
        case decoding(String)

        public var errorDescription: String? {
            switch self {
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
        /// Gram count, or `nil` when the entry is a meal acknowledgment
        /// without a carb amount (e.g. from `auto_mode_event`).
        public let grams: Double?
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

    /// Cookie string sent with every authenticated request.
    /// Format: `"userid=<N>; session=<signed-token>"`.
    public let sessionCookie: String
    private let urlSession: URLSession
    private let requestTimeout: TimeInterval

    // MARK: - Init

    public init(
        sessionCookie: String,
        urlSession: URLSession = .shared,
        requestTimeout: TimeInterval = 15
    ) {
        self.sessionCookie = sessionCookie
        self.urlSession = urlSession
        self.requestTimeout = requestTimeout
    }

    // MARK: - Login (static — no session needed)

    /// Authenticate with username + password. Returns a `LoginResult` whose
    /// `sessionCookie` should be stored (App Group UserDefaults) and passed to
    /// subsequent `EasyViewClient` instances.
    ///
    /// Throws `ClientError.sessionExpired` on 401, other `ClientError` cases on
    /// network or parse failures.
    public static func login(
        username: String,
        password: String,
        urlSession: URLSession = .shared,
        requestTimeout: TimeInterval = 15
    ) async throws -> LoginResult {
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var basePath = urlComponents.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        urlComponents.path = basePath + "/api/v2.0/login"
        let url = urlComponents.url!

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
        let request = makeRequest(path: "/api/v2.1/monitor/connections", query: [
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

    // MARK: - Combined latest reading

    /// The latest glucose + carb entry resolved from a single `ds` chart request.
    public struct LatestReading: Sendable {
        public let glucose: GlucoseSample?
        public let carbs: CarbEntry?
    }

    /// Fetch the most recent glucose and carb entry in a single round-trip.
    ///
    /// The `ds` (day summary) chart response carries both `sensor_glucose` and
    /// `carb_event`, so one request covers both metrics. Carbs come purely from
    /// `carb_event`, which already unifies bolus-wizard and manually-entered
    /// carbs. When the window holds no CGM sensor reading, glucose falls back to
    /// the most recent manually-entered BG event (one extra request).
    ///
    /// - Parameter windowHours: how far back to look for both metrics. The
    ///   default (6h) is the trade-off between payload size — the `ds` response
    ///   is dominated by 5-minute CGM `sensor_glucose` points — and capturing a
    ///   not-too-recent carb on first fetch / after a cache clear (it comfortably
    ///   covers the default 4h carb grace window). Once a carb is captured it is
    ///   persisted and survives later empty windows, so this only bounds the
    ///   initial capture, not retention.
    public func fetchLatest(patientUID: Int, windowHours: Double = 6) async throws -> LatestReading {
        let now = Date().timeIntervalSince1970
        let start = now - windowHours * 3600
        let param = encodeDsParam(start: start, end: now)

        let request = makeRequest(path: "/v3/api/v2.1/chart/\(patientUID)/data/ds", query: [
            URLQueryItem(name: "param", value: param),
        ])
        let data = try await perform(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let dataObj = json?["data"] as? [String: Any]

        let carbs = Self.parseLatestCarbOrMeal(from: dataObj)
        if let glucose = Self.parseLatestSensorGlucose(from: dataObj) {
            return LatestReading(glucose: glucose, carbs: carbs)
        }

        // No CGM sensor reading in the window — fall back to manual BG events.
        let fallback = try await fetchLatestGlucoseFromEvents(patientUID: patientUID, windowHours: windowHours)
        return LatestReading(glucose: fallback, carbs: carbs)
    }

    // MARK: - Parsing (ds chart payload)

    /// Pick the most recent sensor glucose reading from a `ds` `data` object.
    /// `sensor_glucose` is `[[ [ts, mmol, …] … ]]` — per-day buckets of readings;
    /// flatten across buckets (the window can span a day boundary) and take the latest.
    private static func parseLatestSensorGlucose(from dataObj: [String: Any]?) -> GlucoseSample? {
        guard let sensorGlucose = dataObj?["sensor_glucose"] as? [[[Any]]] else { return nil }
        let latest = sensorGlucose
            .flatMap { $0 }
            .max { ($0.first as? Double ?? 0) < ($1.first as? Double ?? 0) }
        guard let latest, latest.count >= 2,
              let ts = latest[0] as? Double,
              let mmol = latest[1] as? Double
        else { return nil }
        return GlucoseSample(mmol: mmol, date: Date(timeIntervalSince1970: ts))
    }

    /// Pick the most recent carb or meal entry from a `ds` `data` object.
    ///
    /// Two fields are checked:
    /// - `carb_event`: `[[ [ts, grams] … ]]` — bolus-wizard + manually-entered
    ///   carbs. Always has a gram amount.
    /// - `auto_mode_event`: `[[ slot0, slot1, slot2, … ]]` where each slot is
    ///   an array of `[ts, size_code]` entries for that meal type (0 = breakfast,
    ///   1 = lunch, 2 = dinner, 3 = snack, …). The `size_code` encodes meal size
    ///   (0 = Regular, 1 = Large, …), **not** grams. These are returned with
    ///   `grams: nil` to signal "meal acknowledged, amount unknown".
    ///
    /// When both sources have entries the most-recent timestamp wins; on a tie
    /// the `carb_event` entry is preferred because it carries more information.
    private static func parseLatestCarbOrMeal(from dataObj: [String: Any]?) -> CarbEntry? {
        var latestCarb: CarbEntry?
        var latestMeal: CarbEntry?

        if let carbEvent = dataObj?["carb_event"] as? [[[Any]]] {
            let best = carbEvent
                .flatMap { $0 }
                .max { ($0.first as? Double ?? 0) < ($1.first as? Double ?? 0) }
            if let best, best.count >= 2,
               let ts = best[0] as? Double,
               let grams = best[1] as? Double, grams > 0 {
                latestCarb = CarbEntry(grams: grams, date: Date(timeIntervalSince1970: ts))
            }
        }

        // auto_mode_event structure: [ dayBucket, … ]
        // dayBucket: [ slot0, slot1, slot2, … ] (0=breakfast, 1=lunch, 2=dinner, …)
        // slot: [ [ts, size_code], … ] — array of meal events for that meal type
        // We want the highest timestamp across all slots in all day buckets.
        if let autoModeEvent = dataObj?["auto_mode_event"] as? [Any] {
            var bestTs: Double = 0
            for dayBucket in autoModeEvent {
                guard let slots = dayBucket as? [Any] else { continue }
                for slot in slots {
                    guard let entries = slot as? [[Any]] else { continue }
                    for entry in entries {
                        guard let ts = entry.first as? Double, ts > bestTs else { continue }
                        bestTs = ts
                    }
                }
            }
            if bestTs > 0 {
                latestMeal = CarbEntry(grams: nil, date: Date(timeIntervalSince1970: bestTs))
            }
        }

        switch (latestCarb, latestMeal) {
        case let (carb?, meal?):
            // Prefer carb_event on a tie (it has gram information).
            return carb.date >= meal.date ? carb : meal
        case let (carb?, nil): return carb
        case let (nil, meal?): return meal
        case (nil, nil): return nil
        }
    }

    /// Fetch the most recent manually-entered BG event from the events endpoint.
    private func fetchLatestGlucoseFromEvents(patientUID: Int, windowHours: Double) async throws -> GlucoseSample? {
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

    // MARK: - Private: events

    /// Fetch raw events for `patientUID` over the last `windowHours` hours.
    /// Each event is an array: `[id, timestamp, type, data, source, record_id]`.
    private func fetchEvents(patientUID: Int, windowHours: Double) async throws -> [[Any]] {
        let now = Date().timeIntervalSince1970
        let start = now - windowHours * 3600
        let param = encodeEventsParam(start: start, end: now)

        let request = makeRequest(path: "/v3/api/v2.0/events/\(patientUID)", query: [
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

    /// Encode the base64 JSON `param` expected by the `ds` (day summary) chart endpoint.
    private func encodeDsParam(start: Double, end: Double) -> String {
        let tzHours = TimeZone.current.secondsFromGMT() / 3600
        let obj: [String: Any] = [
            "gu": "mmol/L",
            "ts": [[Int(start), Int(end)]],
            "tz": tzHours,
        ]
        let jsonData = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
        return jsonData.base64EncodedString()
    }

    // MARK: - Private: request plumbing

    private func makeRequest(path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        var basePath = components.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + path
        components.queryItems = query.isEmpty ? nil : query

        var request = URLRequest(url: components.url!)
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
