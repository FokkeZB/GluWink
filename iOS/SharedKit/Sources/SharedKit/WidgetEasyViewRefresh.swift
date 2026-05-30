import Foundation
import os

/// Fetches the latest EasyView glucose + carbs from inside a WidgetKit
/// timeline call and writes the result into the App Group `UserDefaults` that
/// the widgets already read from.
///
/// Mirrors `WidgetNightscoutRefresh` for EasyView. Key difference: if the
/// session cookie has expired, this type does **not** attempt re-login because
/// the widget extension has no access to the Keychain password. Instead it
/// logs the error and serves stale cached values. The main app re-authenticates
/// on its next foreground activation, at which point the new session propagates
/// to the App Group.
///
/// Widget extensions DO have network access (unlike Shield / Action /
/// DeviceActivityMonitor — see QUIRKS.md), so fetching here is safe.
public enum WidgetEasyViewRefresh {
    public static let throttleInterval: TimeInterval = 60
    public static let requestTimeout: TimeInterval = 5

    private static let logger = Logger(subsystem: "SharedKit", category: "WidgetEasyViewRefresh")

    /// If EasyView is enabled and the throttle window has elapsed, fetch
    /// the latest glucose + carbs and persist them to the App Group with
    /// "save if newer" semantics. Always returns; never throws.
    ///
    /// - Parameter defaults: the App Group `UserDefaults` the widget reads from.
    public static func refreshIfDue(defaults: UserDefaults?) async {
        guard let defaults else { return }
        guard defaults.bool(forKey: DataSourceKeys.easyViewEnabled) else { return }
        guard !defaults.bool(forKey: DataSourceKeys.mockModeEnabled) else { return }

        guard let sessionCookie = defaults.string(forKey: "easyViewSession"),
              !sessionCookie.isEmpty,
              let patientUID = defaults.object(forKey: "easyViewPatientUID") as? Int
        else { return }

        if let lastIso = defaults.string(forKey: "easyViewLastFetchedAt"),
           let last = ISO8601DateFormatter().date(from: lastIso),
           Date().timeIntervalSince(last) < throttleInterval {
            return
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        let client = EasyViewClient(
            sessionCookie: sessionCookie,
            urlSession: session,
            requestTimeout: requestTimeout
        )

        // One `ds` request returns both glucose and carbs.
        let glucose: EasyViewClient.GlucoseSample?
        let carbs: EasyViewClient.CarbEntry?
        do {
            let latest = try await client.fetchLatest(patientUID: patientUID)
            glucose = latest.glucose
            carbs = latest.carbs
        } catch EasyViewClient.ClientError.sessionExpired {
            logger.warning("Widget EasyView session expired — serving stale cached values")
            glucose = nil
            carbs = nil
        } catch {
            logger.error("Widget EasyView fetch failed: \(error.localizedDescription, privacy: .public)")
            glucose = nil
            carbs = nil
        }

        if let glucose {
            saveIfNewer(
                defaults: defaults,
                valueKey: UnifiedDataReader.glucoseValueKey(for: .easyView),
                dateKey: UnifiedDataReader.glucoseDateKey(for: .easyView),
                value: glucose.mmol,
                date: glucose.date
            )
        }
        if let carbs {
            saveIfNewer(
                defaults: defaults,
                valueKey: UnifiedDataReader.carbsValueKey(for: .easyView),
                dateKey: UnifiedDataReader.carbsDateKey(for: .easyView),
                value: carbs.grams,
                date: carbs.date
            )
        }

        defaults.set(Date().ISO8601Format(), forKey: "easyViewLastFetchedAt")
    }

    private static func saveIfNewer(
        defaults: UserDefaults,
        valueKey: String,
        dateKey: String,
        value: Double,
        date: Date
    ) {
        if let existingIso = defaults.string(forKey: dateKey),
           let existing = ISO8601DateFormatter().date(from: existingIso),
           date <= existing {
            return
        }
        defaults.set(value, forKey: valueKey)
        defaults.set(date.ISO8601Format(), forKey: dateKey)
    }
}
