import Foundation
import HealthKit
import os
import SharedKit
import WidgetKit

final class WatchHealthKitManager {
    static let shared = WatchHealthKitManager()

    private let healthStore = HKHealthStore()
    private let glucoseType = HKQuantityType(.bloodGlucose)
    private let carbType = HKQuantityType(.dietaryCarbohydrates)
    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "WatchHealthKitManager")

    private init() {}

    func requestAuthorization() async {
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [glucoseType, carbType])
            logger.info("Watch HealthKit authorization requested")
        } catch {
            logger.error("Watch HealthKit authorization failed: \(error.localizedDescription)")
        }
    }

    func enableBackgroundDelivery() async {
        do {
            try await healthStore.enableBackgroundDelivery(for: glucoseType, frequency: .immediate)
            try await healthStore.enableBackgroundDelivery(for: carbType, frequency: .immediate)
            logger.info("Watch background delivery enabled")
        } catch {
            logger.error("Watch background delivery failed: \(error.localizedDescription)")
        }
    }

    func startObserving() {
        let glucoseObserver = HKObserverQuery(sampleType: glucoseType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error {
                self?.logger.error("Watch glucose observer error: \(error.localizedDescription)")
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
                self?.logger.error("Watch carb observer error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            Task {
                await self?.fetchLatestCarbs()
                completionHandler()
            }
        }
        healthStore.execute(carbObserver)

        logger.info("Watch observers started")
    }

    func fetchLatestGlucose() async {
        guard !WatchDataManager.isMockModeEnabled else {
            logger.info("Watch mock mode active — skipping HealthKit glucose fetch")
            return
        }

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: glucoseType)],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .reverse)],
            limit: 1
        )

        do {
            if let sample = try await descriptor.result(for: healthStore).first {
                let mgdl = sample.quantity.doubleValue(for: .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)))
                let mmol = mgdl / 18.018
                WatchDataManager.storeGlucose(mmol: mmol, at: sample.startDate)
                WidgetCenter.shared.reloadAllTimelines()
                logger.info("Watch glucose updated")
            }
        } catch {
            logger.error("Watch glucose fetch failed: \(error.localizedDescription)")
        }
    }

    func fetchLatestCarbs() async {
        guard !WatchDataManager.isMockModeEnabled else {
            logger.info("Watch mock mode active — skipping HealthKit carb fetch")
            return
        }

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: carbType)],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .reverse)],
            limit: 1
        )

        do {
            if let sample = try await descriptor.result(for: healthStore).first {
                let grams = sample.quantity.doubleValue(for: .gram())
                WatchDataManager.storeCarbs(grams: grams, at: sample.startDate)
                WidgetCenter.shared.reloadAllTimelines()
                logger.info("Watch carbs updated")
            }
        } catch {
            logger.error("Watch carbs fetch failed: \(error.localizedDescription)")
        }
    }
}
