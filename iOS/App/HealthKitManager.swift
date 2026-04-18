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

    private init() {}

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
        let glucoseObserver = HKObserverQuery(sampleType: glucoseType, predicate: nil) { [weak self] _, completionHandler, error in
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
        healthStore.execute(glucoseObserver)

        let carbObserver = HKObserverQuery(sampleType: carbType, predicate: nil) { [weak self] _, completionHandler, error in
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
        healthStore.execute(carbObserver)

        logger.info("Started observing glucose and carb samples")
    }

    // MARK: - Fetch Latest Values

    func fetchLatestGlucose() async {
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
                SharedDataManager.shared.saveGlucose(mmol: mmol, at: sample.startDate)
                SharedDataManager.shared.markHealthKitDelivered()
                logger.info("Glucose updated: \(String(format: "%.1f", mmol)) mmol/L")
                SharedDataManager.shared.refreshAttentionBadge()
                ShieldManager.shared.reevaluateShields()
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            logger.error("Failed to fetch glucose: \(error.localizedDescription)")
        }

        // Piggyback: when HealthKit wakes us up (including background delivery),
        // also poll Nightscout so the two sources stay aligned. "Save if newer"
        // guarantees whichever timestamp is freshest wins.
        await NightscoutManager.shared.fetchAll()
    }

    func fetchLatestCarbs() async {
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
                SharedDataManager.shared.saveCarbs(grams: grams, at: sample.startDate)
                SharedDataManager.shared.markHealthKitDelivered()
                logger.info("Carbs updated: \(String(format: "%.0f", grams))g")
                SharedDataManager.shared.refreshAttentionBadge()
                ShieldManager.shared.reevaluateShields()
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            logger.error("Failed to fetch carbs: \(error.localizedDescription)")
        }

        await NightscoutManager.shared.fetchAll()
    }
}
