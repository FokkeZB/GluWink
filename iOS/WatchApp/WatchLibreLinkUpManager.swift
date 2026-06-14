import Foundation
import os
import SharedKit
import WidgetKit
#if canImport(WatchKit)
import WatchKit
#endif

/// Watch-side LibreLinkUp poller. Mirrors `WatchEasyViewManager`: keeps the
/// watch App Group glucose keys fresh so complications stay current even when
/// the paired phone is unreachable.
///
/// Config (auth token, expiry, region, userId, patientId) is synced from the
/// phone via `WatchConnectivity` and stored in the watch-local App Group by
/// `WatchDataManager.updateFromPhoneContext`. Like the iPhone widget
/// (`WidgetLibreLinkUpRefresh`), the watch has no Keychain access and therefore
/// **never re-authenticates** — on an expired or rejected token it logs and
/// serves stale cached values; the next phone foreground pass refreshes the
/// token and pushes it via WatchConnectivity.
///
/// Glucose only — LibreLinkUp provides no carb data.
@MainActor
final class WatchLibreLinkUpManager {
    static let shared = WatchLibreLinkUpManager()

    static let pollInterval: TimeInterval = 5 * 60

    /// mg/dL → mmol/L divisor (matches `LibreLinkUpManager` / `WidgetLibreLinkUpRefresh`).
    private static let mgdlPerMmol = 18.01559

    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "WatchLibreLinkUpManager")
    private var pollTimer: Timer?
    private var inFlight = false

    private init() {}

    var isConfigured: Bool {
        WatchDataManager.librelinkupEnabled && WatchDataManager.librelinkupToken != nil
    }

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
        logger.info("Watch LibreLinkUp polling started")
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

    func fetchAll() async {
        guard isConfigured, let token = WatchDataManager.librelinkupToken else { return }
        guard !WatchDataManager.isMockModeEnabled else {
            logger.info("Watch mock mode active — skipping LibreLinkUp fetch")
            return
        }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        // No Keychain access on the watch, so a token at/near expiry means
        // "serve stale and wait for the phone to push a fresh token" rather
        // than attempting a login. Matches `WidgetLibreLinkUpRefresh`.
        if let expiry = WatchDataManager.librelinkupTokenExpiry,
           expiry.timeIntervalSinceNow < 60 {
            logger.warning("Watch LibreLinkUp token expired — phone will refresh on next foreground")
            return
        }

        let region = WatchDataManager.librelinkupRegion
        let userId = WatchDataManager.librelinkupUserId
        let storedPatientId = WatchDataManager.librelinkupPatientId

        do {
            let connections = try await LibreLinkUpClient.fetchConnections(
                token: token,
                region: region,
                userId: userId
            )
            guard !connections.isEmpty else {
                logger.warning("Watch LibreLinkUp: no connections in account")
                return
            }
            let connection = connections.first(where: { $0.patientId == storedPatientId }) ?? connections[0]
            let mmol = connection.glucoseMeasurement.valueInMgPerDl / Self.mgdlPerMmol
            WatchDataManager.storeGlucose(mmol: mmol, at: connection.glucoseMeasurement.timestamp)
            logger.info("Watch LibreLinkUp glucose: \(String(format: "%.1f", mmol)) mmol/L")
        } catch LibreLinkUpClient.ClientError.tokenExpired {
            logger.warning("Watch LibreLinkUp token rejected (401) — phone will refresh on next foreground")
        } catch {
            logger.error("Watch LibreLinkUp fetch failed: \(error.localizedDescription)")
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    func scheduleBackgroundRefresh() {
        guard isConfigured else { return }
        #if canImport(WatchKit) && !os(iOS)
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: Self.pollInterval),
            userInfo: nil
        ) { [weak self] error in
            if let error {
                self?.logger.error("Watch LibreLinkUp background schedule failed: \(error.localizedDescription)")
            }
        }
        #endif
    }
}
