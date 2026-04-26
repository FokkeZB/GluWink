import Foundation
import XCTest
@testable import SharedKit

/// Pins the resolution rule documented in `UnifiedDataReader`:
///
/// 1. When Demo mode is on, Demo wins for both metrics regardless of
///    real-source freshness.
/// 2. Otherwise the freshest enabled source wins, independently for
///    glucose and carbs.
/// 3. Disabled sources are ignored even if they have stored values.
/// 4. When nothing is stored, the reader returns nil.
final class UnifiedDataReaderTests: XCTestCase {
    private let suiteName = "UnifiedDataReaderTests.suite.\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Nothing stored

    func testReturnsNilWhenNothingStored() {
        XCTAssertNil(UnifiedDataReader.currentGlucoseReading(from: defaults))
        XCTAssertNil(UnifiedDataReader.currentCarbsReading(from: defaults))
    }

    func testReturnsNilWhenDefaultsIsNil() {
        XCTAssertNil(UnifiedDataReader.currentGlucoseReading(from: nil))
        XCTAssertNil(UnifiedDataReader.currentCarbsReading(from: nil))
    }

    // MARK: - Demo override

    func testDemoOverrideWinsForGlucoseEvenWhenOlderThanHealthKit() {
        defaults.set(true, forKey: DataSourceKeys.mockModeEnabled)
        defaults.set(true, forKey: DataSourceKeys.healthKitEnabled)

        writeGlucose(source: .demo, value: 8.0, minutesAgo: 60)
        writeGlucose(source: .healthKit, value: 6.4, minutesAgo: 5)

        let reading = UnifiedDataReader.currentGlucoseReading(from: defaults)
        XCTAssertEqual(reading?.source, .demo)
        XCTAssertEqual(reading?.mmol, 8.0)
    }

    func testDemoOverrideWinsForCarbsEvenWhenOlderThanNightscout() {
        defaults.set(true, forKey: DataSourceKeys.mockModeEnabled)
        defaults.set(true, forKey: DataSourceKeys.nightscoutEnabled)

        writeCarbs(source: .demo, value: 30, minutesAgo: 180)
        writeCarbs(source: .nightscout, value: 12, minutesAgo: 10)

        let reading = UnifiedDataReader.currentCarbsReading(from: defaults)
        XCTAssertEqual(reading?.source, .demo)
        XCTAssertEqual(reading?.grams, 30)
    }

    func testDemoModeReturnsNilWhenDemoHasNoStoredGlucose() {
        defaults.set(true, forKey: DataSourceKeys.mockModeEnabled)
        // Real sources have data but the Demo override should not fall
        // through to them.
        defaults.set(true, forKey: DataSourceKeys.healthKitEnabled)
        writeGlucose(source: .healthKit, value: 6.4, minutesAgo: 5)

        XCTAssertNil(UnifiedDataReader.currentGlucoseReading(from: defaults))
    }

    // MARK: - Freshest wins (demo off)

    func testHealthKitWinsWhenFresherThanNightscout() {
        defaults.set(true, forKey: DataSourceKeys.healthKitEnabled)
        defaults.set(true, forKey: DataSourceKeys.nightscoutEnabled)

        writeGlucose(source: .healthKit, value: 6.4, minutesAgo: 3)
        writeGlucose(source: .nightscout, value: 7.1, minutesAgo: 15)

        let reading = UnifiedDataReader.currentGlucoseReading(from: defaults)
        XCTAssertEqual(reading?.source, .healthKit)
        XCTAssertEqual(reading?.mmol, 6.4)
    }

    func testNightscoutWinsWhenFresherThanHealthKit() {
        defaults.set(true, forKey: DataSourceKeys.healthKitEnabled)
        defaults.set(true, forKey: DataSourceKeys.nightscoutEnabled)

        writeGlucose(source: .healthKit, value: 6.4, minutesAgo: 30)
        writeGlucose(source: .nightscout, value: 7.1, minutesAgo: 5)

        let reading = UnifiedDataReader.currentGlucoseReading(from: defaults)
        XCTAssertEqual(reading?.source, .nightscout)
    }

    /// Glucose and carbs resolve independently — one source can win for
    /// glucose while the other wins for carbs.
    func testGlucoseAndCarbsResolveIndependently() {
        defaults.set(true, forKey: DataSourceKeys.healthKitEnabled)
        defaults.set(true, forKey: DataSourceKeys.nightscoutEnabled)

        // HK glucose is fresher; NS carbs are fresher.
        writeGlucose(source: .healthKit, value: 6.4, minutesAgo: 3)
        writeGlucose(source: .nightscout, value: 7.1, minutesAgo: 20)
        writeCarbs(source: .healthKit, value: 25, minutesAgo: 200)
        writeCarbs(source: .nightscout, value: 40, minutesAgo: 30)

        XCTAssertEqual(UnifiedDataReader.currentGlucoseReading(from: defaults)?.source, .healthKit)
        XCTAssertEqual(UnifiedDataReader.currentCarbsReading(from: defaults)?.source, .nightscout)
    }

    // MARK: - Disabled sources ignored

    func testDisabledHealthKitIgnoredEvenWithStoredData() {
        defaults.set(false, forKey: DataSourceKeys.healthKitEnabled)
        defaults.set(true, forKey: DataSourceKeys.nightscoutEnabled)

        writeGlucose(source: .healthKit, value: 6.4, minutesAgo: 1) // fresher
        writeGlucose(source: .nightscout, value: 7.1, minutesAgo: 10)

        let reading = UnifiedDataReader.currentGlucoseReading(from: defaults)
        XCTAssertEqual(reading?.source, .nightscout)
        XCTAssertEqual(reading?.mmol, 7.1)
    }

    func testAllSourcesDisabledReturnsNil() {
        defaults.set(false, forKey: DataSourceKeys.healthKitEnabled)
        defaults.set(false, forKey: DataSourceKeys.nightscoutEnabled)
        defaults.set(false, forKey: DataSourceKeys.mockModeEnabled)

        writeGlucose(source: .healthKit, value: 6.4, minutesAgo: 1)
        writeGlucose(source: .nightscout, value: 7.1, minutesAgo: 2)
        writeGlucose(source: .demo, value: 8.0, minutesAgo: 3)

        XCTAssertNil(UnifiedDataReader.currentGlucoseReading(from: defaults))
        XCTAssertNil(UnifiedDataReader.currentCarbsReading(from: defaults))
    }

    // MARK: - Per-source accessors

    func testPerSourceReadingReturnsStoredValueIgnoringToggles() {
        // Even with HK disabled, the per-source accessor still exposes
        // whatever is stored — the settings UI uses this to show the
        // user the last value it saw, independent of the resolution rule.
        defaults.set(false, forKey: DataSourceKeys.healthKitEnabled)
        writeGlucose(source: .healthKit, value: 6.4, minutesAgo: 5)

        let reading = UnifiedDataReader.glucoseReading(source: .healthKit, from: defaults)
        XCTAssertEqual(reading?.mmol, 6.4)
    }

    // MARK: - Helpers

    private func writeGlucose(source: DataSource, value: Double, minutesAgo: Double) {
        let date = Date().addingTimeInterval(-minutesAgo * 60)
        defaults.set(value, forKey: UnifiedDataReader.glucoseValueKey(for: source))
        defaults.set(date.ISO8601Format(), forKey: UnifiedDataReader.glucoseDateKey(for: source))
    }

    private func writeCarbs(source: DataSource, value: Double, minutesAgo: Double) {
        let date = Date().addingTimeInterval(-minutesAgo * 60)
        defaults.set(value, forKey: UnifiedDataReader.carbsValueKey(for: source))
        defaults.set(date.ISO8601Format(), forKey: UnifiedDataReader.carbsDateKey(for: source))
    }
}
