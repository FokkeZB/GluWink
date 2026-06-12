import Foundation
import os

/// Fetches the latest LibreLinkUp glucose from inside a WidgetKit timeline call
/// and writes the result into the App Group `UserDefaults` that the widgets
/// already read from.
///
/// Mirrors `WidgetNightscoutRefresh` / `WidgetEasyViewRefresh`. Key difference:
/// LibreLinkUp's email/password live in the Keychain, which the widget extension
/// cannot reach, so this type **never re-authenticates**. It uses the auth token
/// the main app mirrored into the App Group (`librelinkupToken`). When that
/// token is expired or rejected (401), it logs and serves stale cached values;
/// the main app re-authenticates on its next foreground activation / background
/// refresh and the fresh token propagates back to the App Group.
///
/// Widget extensions DO have network access (unlike Shield / Action /
/// DeviceActivityMonitor — see QUIRKS.md), so fetching here is safe.
///
/// Glucose only — LibreLinkUp provides no carb data.
public enum WidgetLibreLinkUpRefresh {
    /// Minimum interval between widget-initiated fetches. The iPhone foreground
    /// poller writes the same `librelinkupLastFetchedAt` key, so the two
    /// coalesce naturally.
    public static let throttleInterval: TimeInterval = 60

    /// Per-request timeout, kept well under the WidgetKit timeline budget.
    public static let requestTimeout: TimeInterval = 5

    /// mg/dL → mmol/L divisor (matches `LibreLinkUpManager`).
    private static let mgdlPerMmol = 18.01559

    private static let logger = Logger(subsystem: "SharedKit", category: "WidgetLibreLinkUpRefresh")

    /// If LibreLinkUp is enabled, a non-expired token is mirrored in the App
    /// Group, and the throttle window has elapsed, fetch the latest glucose and
    /// persist it with "save if newer" semantics. Always returns; never throws.
    ///
    /// - Parameter defaults: the App Group `UserDefaults` the widget reads from.
    public static func refreshIfDue(defaults: UserDefaults?) async {
        guard let defaults else { return }
        guard defaults.bool(forKey: DataSourceKeys.libreLinkUpEnabled) else { return }
        guard !defaults.bool(forKey: DataSourceKeys.mockModeEnabled) else { return }

        guard let token = defaults.string(forKey: "librelinkupToken"),
              !token.isEmpty else { return }

        // No Keychain access here, so a token at/near expiry means "serve stale
        // and wait for the app to re-authenticate" rather than attempting a login.
        if let expiryIso = defaults.string(forKey: "librelinkupTokenExpiry"),
           let expiry = ISO8601DateFormatter().date(from: expiryIso),
           expiry.timeIntervalSinceNow < 60 {
            logger.warning("Widget LibreLinkUp token expired — serving stale cached values")
            return
        }

        if let lastIso = defaults.string(forKey: "librelinkupLastFetchedAt"),
           let last = ISO8601DateFormatter().date(from: lastIso),
           Date().timeIntervalSince(last) < throttleInterval {
            return
        }

        let region = defaults.string(forKey: "librelinkupRegion")
        let userId = defaults.string(forKey: "librelinkupUserId")
        let storedPatientId = defaults.string(forKey: "librelinkupPatientId")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        do {
            let connections = try await LibreLinkUpClient.fetchConnections(
                token: token,
                region: region,
                userId: userId,
                session: session,
                requestTimeout: requestTimeout
            )
            guard !connections.isEmpty else {
                logger.warning("Widget LibreLinkUp: no connections in account")
                defaults.set(Date().ISO8601Format(), forKey: "librelinkupLastFetchedAt")
                return
            }

            let connection = connections.first(where: { $0.patientId == storedPatientId }) ?? connections[0]
            let mmol = connection.glucoseMeasurement.valueInMgPerDl / mgdlPerMmol
            let date = connection.glucoseMeasurement.timestamp

            saveIfNewer(
                defaults: defaults,
                valueKey: UnifiedDataReader.glucoseValueKey(for: .libreLinkUp),
                dateKey: UnifiedDataReader.glucoseDateKey(for: .libreLinkUp),
                value: mmol,
                date: date
            )
        } catch LibreLinkUpClient.ClientError.tokenExpired {
            logger.warning("Widget LibreLinkUp token rejected (401) — serving stale cached values")
        } catch {
            logger.error("Widget LibreLinkUp fetch failed: \(error.localizedDescription, privacy: .public)")
        }

        // Always bump the throttle timestamp so a flapping server can't make us
        // retry on every paint. Matches `WidgetNightscoutRefresh`.
        defaults.set(Date().ISO8601Format(), forKey: "librelinkupLastFetchedAt")
    }

    /// Mirror the "save if newer" semantics in `SharedDataManager.saveLibreLinkUpGlucose`
    /// so an out-of-order widget-initiated fetch can't overwrite a sample the
    /// main app has already cached as newer.
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
