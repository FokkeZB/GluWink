import Foundation
import HealthKit
import os
import SharedKit
import WidgetKit

final class HealthKitManager {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "HealthKitManager")

    private let glucoseType = HKQuantityType(.bloodGlucose)
    private let carbType = HKQuantityType(.dietaryCarbohydrates)

    /// Whether the observer queries are currently active. We can't cancel
    /// started observer queries with the modern HealthKit API without
    /// holding the `HKObserverQuery` instances, so we keep a reference
    /// here and `stop` them when the user disables HealthKit from
    /// Settings. A re-enable simply re-executes fresh queries.
    private var glucoseObserver: HKObserverQuery?
    private var carbObserver: HKObserverQuery?

    private init() {}

    // MARK: - Toggle lifecycle

    /// Turn on the HealthKit data source: prompt for read permission
    /// (iOS shows the sheet on the *first* call per type; subsequent
    /// calls are a no-op even if the user previously denied), flip the
    /// `healthKitEnabled` toggle on, enable background delivery, start
    /// observers, and kick an immediate fetch. Idempotent — safe to call
    /// from a Settings toggle binding.
    func enable() async {
        SharedDataManager.shared.healthKitEnabled = true
        await requestAuthorization()
        await enableBackgroundDelivery()
        startObserving()
        await fetchLatestGlucose()
        await fetchLatestCarbs()
        logger.info("HealthKit data source enabled")
    }

    /// Turn off the HealthKit data source. Stops observers, disables
    /// background delivery, clears cached HealthKit values, and flips
    /// the toggle off. iOS doesn't let us programmatically revoke
    /// read permission — the toggle itself is the authoritative
    /// "use this data?" gate from this point forward.
    func disable() async {
        SharedDataManager.shared.healthKitEnabled = false
        stopObserving()
        do {
            try await healthStore.disableBackgroundDelivery(for: glucoseType)
            try await healthStore.disableBackgroundDelivery(for: carbType)
        } catch {
            logger.error("Failed to disable background delivery: \(error.localizedDescription)")
        }
        SharedDataManager.shared.handleSourceDisabled(.healthKit)
        await SharedDataManager.shared.refreshAttentionBadge()
        ShieldManager.shared.reevaluateShields()
        WidgetCenter.shared.reloadAllTimelines()
        WatchSessionManager.shared.sendLatestContext()
        logger.info("HealthKit data source disabled")
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [glucoseType, carbType])
            logger.info("HealthKit authorization requested")
            await detectPreferredUnit()
        } catch {
            logger.error("HealthKit authorization failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Background Delivery

    func enableBackgroundDelivery() async {
        do {
            try await healthStore.enableBackgroundDelivery(for: glucoseType, frequency: .immediate)
            try await healthStore.enableBackgroundDelivery(for: carbType, frequency: .immediate)
            logger.info("Background delivery enabled for glucose and carbs")
        } catch {
            logger.error("Failed to enable background delivery: \(error.localizedDescription)")
        }
    }

    // MARK: - Preferred Unit Detection

    /// Auto-detect the user's preferred glucose unit from HealthKit (only on first launch).
    func detectPreferredUnit() async {
        guard !SharedDataManager.shared.hasGlucoseUnitPreference else { return }

        do {
            let preferred = try await healthStore.preferredUnits(for: [glucoseType])
            let mgdLUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
            if let unit = preferred[glucoseType], unit == mgdLUnit {
                SharedDataManager.shared.glucoseUnit = .mgdL
                logger.info("Detected preferred glucose unit: mg/dL")
            } else {
                SharedDataManager.shared.glucoseUnit = .mmolL
                logger.info("Detected preferred glucose unit: mmol/L")
            }
        } catch {
            logger.error("Failed to detect preferred glucose unit: \(error.localizedDescription)")
        }
    }

    // MARK: - Observer Queries

    func startObserving() {
        stopObserving()

        let glucose = HKObserverQuery(sampleType: glucoseType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error {
                self?.logger.error("Glucose observer error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            Task {
                await self?.fetchLatestGlucose()
                completionHandler()
            }
        }
        healthStore.execute(glucose)
        glucoseObserver = glucose

        let carbs = HKObserverQuery(sampleType: carbType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error {
                self?.logger.error("Carb observer error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            Task {
                await self?.fetchLatestCarbs()
                completionHandler()
            }
        }
        healthStore.execute(carbs)
        carbObserver = carbs

        logger.info("Started observing glucose and carb samples")
    }

    private func stopObserving() {
        if let glucoseObserver {
            healthStore.stop(glucoseObserver)
            self.glucoseObserver = nil
        }
        if let carbObserver {
            healthStore.stop(carbObserver)
            self.carbObserver = nil
        }
    }

    // MARK: - Fetch Latest Values

    /// Convenience: refresh both glucose and carbs *only* if the user has
    /// HealthKit enabled. Safe to call from anywhere — does nothing when
    /// the toggle is off, so it won't reach HealthKit at all in that case.
    func refreshIfAuthorized() async {
        guard SharedDataManager.shared.healthKitEnabled else { return }
        await fetchLatestGlucose()
        await fetchLatestCarbs()
    }

    func fetchLatestGlucose() async {
        guard SharedDataManager.shared.healthKitEnabled else {
            logger.info("HealthKit disabled — skipping glucose fetch")
            return
        }
        guard !SharedDataManager.shared.isMockModeEnabled else {
            logger.info("Mock mode active — skipping HealthKit glucose fetch")
            return
        }

        let sortDescriptor = SortDescriptor(\HKQuantitySample.startDate, order: .reverse)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: glucoseType)],
            sortDescriptors: [sortDescriptor],
            limit: 1
        )

        do {
            if let sample = try await descriptor.result(for: healthStore).first {
                let mgdl = sample.quantity.doubleValue(for: .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)))
                let mmol = mgdl / 18.018
                SharedDataManager.shared.saveHealthKitGlucose(mmol: mmol, at: sample.startDate)
                logger.info("Glucose updated: \(String(format: "%.1f", mmol)) mmol/L")
                ShieldManager.shared.reevaluateShields()
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            logger.error("Failed to fetch glucose: \(error.localizedDescription)")
        }

        // Reconcile the badge unconditionally — a sample-free observer wake
        // (no new data, denied read access) still means time has passed, so
        // stale/carb-gap transitions must be re-evaluated or the badge drifts.
        await SharedDataManager.shared.refreshAttentionBadge()

        // Piggyback: when HealthKit wakes us up (including background delivery),
        // also poll Nightscout so the two sources stay aligned. Each source
        // writes to its own keys; the resolver picks the freshest at read time.
        await NightscoutManager.shared.fetchAll()
    }

    func fetchLatestCarbs() async {
        guard SharedDataManager.shared.healthKitEnabled else {
            logger.info("HealthKit disabled — skipping carb fetch")
            return
        }
        guard !SharedDataManager.shared.isMockModeEnabled else {
            logger.info("Mock mode active — skipping HealthKit carb fetch")
            return
        }

        let sortDescriptor = SortDescriptor(\HKQuantitySample.startDate, order: .reverse)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: carbType)],
            sortDescriptors: [sortDescriptor],
            limit: 1
        )

        do {
            if let sample = try await descriptor.result(for: healthStore).first {
                let grams = sample.quantity.doubleValue(for: .gram())
                SharedDataManager.shared.saveHealthKitCarbs(grams: grams, at: sample.startDate)
                logger.info("Carbs updated: \(String(format: "%.0f", grams))g")
                ShieldManager.shared.reevaluateShields()
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            logger.error("Failed to fetch carbs: \(error.localizedDescription)")
        }

        await SharedDataManager.shared.refreshAttentionBadge()

        await NightscoutManager.shared.fetchAll()
    }
}
