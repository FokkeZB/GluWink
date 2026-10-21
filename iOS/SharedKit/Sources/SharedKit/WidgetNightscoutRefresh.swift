import Foundation
import os

/// Fetches the latest Nightscout glucose + carbs from inside a WidgetKit
/// timeline call and writes the result into the App Group `UserDefaults` that
/// the widgets already read from.
///
/// Why this exists: `BGAppRefreshTask` is throttled aggressively by iOS and
/// frequently doesn't fire for long stretches, so the static-timeline widgets
/// were rebuilding from stale shared data and showing old values until the
/// user opened the app. Fetching from the timeline provider closes that gap
/// without relying on the BG scheduler.
///
/// Constraints we respect:
/// - **Throttle.** Skip when `nightscoutLastFetchedAt` is within
///   `throttleInterval` of now so we never hammer the server on every paint
///   or snapshot. The iPhone foreground poller already updates the same key,
///   so they coalesce naturally.
/// - **Tight per-request timeout.** Widget timeline budgets are small
///   (~30s); a single `NightscoutClient` REST call is cheap, but we still
///   bound it explicitly via `requestTimeout` so a flaky network can't drag
///   the widget render through the floor.
/// - **Skipped entirely when Nightscout is disabled or mock mode is on** —
///   HealthKit-only users and demo users see zero overhead.
///
/// `WidgetKit` extensions DO have network access (unlike Shield/Action/
/// DeviceActivityMonitor — see `QUIRKS.md`), so this is safe to call from
/// any `TimelineProvider` / `AppIntentTimelineProvider`.
public enum WidgetNightscoutRefresh {
    /// Minimum interval between widget-initiated fetches. Coalesces snapshot,
    /// placeholder, and timeline calls that fire in quick succession during
    /// a single widget render.
    public static let throttleInterval: TimeInterval = 60

    /// Per-request timeout. Kept well under the WidgetKit timeline budget so
    /// a stalled Nightscout server never blocks the widget render.
    public static let requestTimeout: TimeInterval = 5

    private static let logger = Logger(subsystem: "SharedKit", category: "WidgetNightscoutRefresh")

    /// If Nightscout is enabled and the throttle window has elapsed, fetch
    /// the latest glucose + carbs and persist them to the App Group with
    /// "save if newer" semantics. Always returns; never throws (failures are
    /// logged and swallowed so the widget can still render from whatever is
    /// in the App Group).
    ///
    /// - Parameter defaults: the App Group `UserDefaults` the widget reads
    ///   from. Pass the same suite the widget's `EntryBuilder` uses.
    public static func refreshIfDue(defaults: UserDefaults?) async {
        guard let defaults else { return }
        guard defaults.bool(forKey: DataSourceKeys.nightscoutEnabled) else { return }
        guard !defaults.bool(forKey: DataSourceKeys.mockModeEnabled) else { return }
        guard let urlString = defaults.string(forKey: "nightscoutBaseURL"),
              !urlString.isEmpty else { return }

        if let lastIso = defaults.string(forKey: "nightscoutLastFetchedAt"),
           let last = ISO8601DateFormatter().date(from: lastIso),
           Date().timeIntervalSince(last) < throttleInterval {
            return
        }

        let token = defaults.string(forKey: "nightscoutToken")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        guard let client = NightscoutClient(
            baseURLString: urlString,
            token: token,
            session: session,
            requestTimeout: requestTimeout
        ) else { return }

        // Run the two requests concurrently — both are short and bounded by
        // requestTimeout, so worst-case wall clock is ~5s rather than ~10s.
        async let glucoseTask: NightscoutClient.GlucoseSample? = {
            do {
                return try await client.fetchLatestGlucose()
            } catch {
                logger.error("Widget Nightscout glucose fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }()
        async let carbsTask: NightscoutClient.CarbEntry? = {
            do {
                return try await client.fetchLatestCarbs()
            } catch {
                logger.error("Widget Nightscout carbs fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }()

        let glucose = await glucoseTask
        let carbs = await carbsTask

        if let glucose {
            saveIfNewer(
                defaults: defaults,
                valueKey: UnifiedDataReader.glucoseValueKey(for: .nightscout),
                dateKey: UnifiedDataReader.glucoseDateKey(for: .nightscout),
                value: glucose.mmol,
                date: glucose.date
            )
        }
        if let carbs {
            saveIfNewer(
                defaults: defaults,
                valueKey: UnifiedDataReader.carbsValueKey(for: .nightscout),
                dateKey: UnifiedDataReader.carbsDateKey(for: .nightscout),
                value: carbs.grams,
                date: carbs.date
            )
        }

        // Always bump the throttle timestamp so a flapping Nightscout server
        // can't make us retry on every paint. Matches `NightscoutManager`
        // behaviour where the timestamp tracks "when we last tried", not
        // "when we last succeeded".
        defaults.set(Date().ISO8601Format(), forKey: "nightscoutLastFetchedAt")
    }

    /// Mirror the "save if newer" semantics in `SharedDataManager.saveNightscoutGlucose`
    /// / `saveNightscoutCarbs` so an out-of-order widget-initiated fetch doesn't
    /// overwrite a Nightscout sample the main app has already cached as newer.
    /// (Writes are scoped to Nightscout's own per-source keys now, so they
    /// can't collide with HealthKit samples anyway.)
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
