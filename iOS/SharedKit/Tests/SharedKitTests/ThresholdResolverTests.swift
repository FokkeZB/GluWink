import Foundation
import XCTest
@testable import SharedKit

/// Pins the override-with-fallback contract documented in
/// `AGENTS.md` → "Settings override precedence". When the App Group
/// `UserDefaults` carries a user override, every helper returns the
/// override; when the override is absent (never written), every helper
/// returns the xcconfig default the caller supplied. Regressing this
/// contract is what shipped issue #77, so these tests exist to catch
/// the next drift.
final class ThresholdResolverTests: XCTestCase {
    private let suiteName = "ThresholdResolverTests.suite.\(UUID().uuidString)"
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

    // MARK: - Override absent → fallback wins

    func testFallbackUsedWhenNoOverride() {
        XCTAssertEqual(ThresholdResolver.highGlucose(defaults: defaults, fallback: 9.5), 9.5)
        XCTAssertEqual(ThresholdResolver.lowGlucose(defaults: defaults, fallback: 4.0), 4.0)
        XCTAssertEqual(ThresholdResolver.criticalGlucose(defaults: defaults, fallback: 20.0), 20.0)
        XCTAssertEqual(ThresholdResolver.staleMinutes(defaults: defaults, fallback: 30), 30)
        XCTAssertEqual(ThresholdResolver.carbGraceHour(defaults: defaults, fallback: 9), 9)
        XCTAssertEqual(ThresholdResolver.carbGraceMinute(defaults: defaults, fallback: 30), 30)
    }

    func testFallbackUsedWhenDefaultsIsNil() {
        XCTAssertEqual(ThresholdResolver.highGlucose(defaults: nil, fallback: 9.5), 9.5)
        XCTAssertEqual(ThresholdResolver.lowGlucose(defaults: nil, fallback: 4.0), 4.0)
        XCTAssertEqual(ThresholdResolver.criticalGlucose(defaults: nil, fallback: 20.0), 20.0)
        XCTAssertEqual(ThresholdResolver.staleMinutes(defaults: nil, fallback: 30), 30)
        XCTAssertEqual(ThresholdResolver.carbGraceHour(defaults: nil, fallback: 9), 9)
        XCTAssertEqual(ThresholdResolver.carbGraceMinute(defaults: nil, fallback: 30), 30)
    }

    // MARK: - Override present → override wins

    func testOverrideUsedWhenSet() {
        defaults.set(8.5, forKey: ThresholdResolver.highGlucoseKey)
        defaults.set(3.5, forKey: ThresholdResolver.lowGlucoseKey)
        defaults.set(18.0, forKey: ThresholdResolver.criticalGlucoseKey)
        defaults.set(45, forKey: ThresholdResolver.staleMinutesKey)
        defaults.set(7, forKey: ThresholdResolver.carbGraceHourKey)
        defaults.set(15, forKey: ThresholdResolver.carbGraceMinuteKey)

        XCTAssertEqual(ThresholdResolver.highGlucose(defaults: defaults, fallback: 9.5), 8.5)
        XCTAssertEqual(ThresholdResolver.lowGlucose(defaults: defaults, fallback: 4.0), 3.5)
        XCTAssertEqual(ThresholdResolver.criticalGlucose(defaults: defaults, fallback: 20.0), 18.0)
        XCTAssertEqual(ThresholdResolver.staleMinutes(defaults: defaults, fallback: 30), 45)
        XCTAssertEqual(ThresholdResolver.carbGraceHour(defaults: defaults, fallback: 9), 7)
        XCTAssertEqual(ThresholdResolver.carbGraceMinute(defaults: defaults, fallback: 30), 15)
    }

    /// The resolver does **not** silently re-clamp at read time, even when
    /// `critical <= high` (the invariant is enforced at write time by
    /// `SettingsValidation`). If a stale value is in storage, the resolver
    /// returns it as-is so the Settings UI can surface the validation
    /// error instead of masking it.
    func testCriticalResolverDoesNotReclampBelowHigh() {
        defaults.set(14.0, forKey: ThresholdResolver.highGlucoseKey)
        defaults.set(13.0, forKey: ThresholdResolver.criticalGlucoseKey)

        XCTAssertEqual(
            ThresholdResolver.criticalGlucose(defaults: defaults, fallback: 20.0),
            13.0,
            "Resolver must return the persisted value even when invariant is violated."
        )
    }

    /// Exact reproduction of the issue-#77 scenario: the user pulls the high
    /// threshold below the current glucose value. Before the fix, every
    /// surface except `ShieldManager` ignored the override and kept comparing
    /// against the xcconfig default — so the home icon stayed green while
    /// shields were armed. With the resolver, the same comparison the user
    /// runs in their head ("8.0 mmol/L > new high threshold 6.5") returns
    /// true via every call site.
    func testIssue77Scenario_lowerHighThresholdBelowCurrentGlucose() {
        let xcconfigHigh = 9.5
        let userOverride = 6.5
        let currentGlucose = 8.0

        XCTAssertGreaterThan(currentGlucose, userOverride)
        XCTAssertLessThan(currentGlucose, xcconfigHigh)

        defaults.set(userOverride, forKey: ThresholdResolver.highGlucoseKey)

        let resolved = ThresholdResolver.highGlucose(defaults: defaults, fallback: xcconfigHigh)
        XCTAssertEqual(resolved, userOverride)
        XCTAssertTrue(currentGlucose > resolved, "Glucose must register as 'high' against the user override.")
    }

    /// `effectiveX` accessors on `SharedDataManager` (App target only) plus
    /// the local resolver duplicates in `ShieldAction` and
    /// `DeviceActivityMonitor` all use the same key strings. If they ever
    /// diverge from `ThresholdResolver`, the App Group write/read pair
    /// silently breaks. Pin the keys.
    func testKeyStringsMatchAppGroupContract() {
        XCTAssertEqual(ThresholdResolver.highGlucoseKey, "highGlucoseThreshold")
        XCTAssertEqual(ThresholdResolver.lowGlucoseKey, "lowGlucoseThreshold")
        XCTAssertEqual(ThresholdResolver.criticalGlucoseKey, "criticalGlucoseThreshold")
        XCTAssertEqual(ThresholdResolver.staleMinutesKey, "glucoseStaleMinutes")
        XCTAssertEqual(ThresholdResolver.carbGraceHourKey, "carbGraceHour")
        XCTAssertEqual(ThresholdResolver.carbGraceMinuteKey, "carbGraceMinute")
    }
}
