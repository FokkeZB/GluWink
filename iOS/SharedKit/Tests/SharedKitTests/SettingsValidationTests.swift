import XCTest
@testable import SharedKit

/// Pins the validation contract for issue #84: `criticalGlucoseThreshold`
/// must be strictly greater than `highGlucoseThreshold` at write time, and
/// when Settings lowers `high` below `critical` the slider floor auto-bumps
/// onto the same step grid.
///
/// The validation error is surfaced — not silently re-clamped — per
/// AGENTS.md → "Shared App Group Container" → validation contract.
final class SettingsValidationTests: XCTestCase {
    // MARK: - validateCriticalAboveHigh

    func testValidationPassesWhenCriticalAboveHigh() {
        XCTAssertNoThrow(
            try SettingsValidation.validateCriticalAboveHigh(critical: 20.0, high: 14.0)
        )
    }

    func testValidationFailsWhenCriticalEqualsHigh() {
        XCTAssertThrowsError(
            try SettingsValidation.validateCriticalAboveHigh(critical: 14.0, high: 14.0)
        ) { error in
            guard case SettingsValidation.Error.criticalNotAboveHigh(let critical, let high) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(critical, 14.0)
            XCTAssertEqual(high, 14.0)
        }
    }

    func testValidationFailsWhenCriticalBelowHigh() {
        XCTAssertThrowsError(
            try SettingsValidation.validateCriticalAboveHigh(critical: 12.0, high: 14.0)
        ) { error in
            guard case SettingsValidation.Error.criticalNotAboveHigh = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    // MARK: - minimumCritical(above:step:)

    func testMinimumCriticalBumpsOntoHalfUnitGrid() {
        let bumped = SettingsValidation.minimumCritical(above: 14.0, step: 0.5)
        XCTAssertEqual(bumped, 14.5, accuracy: 0.001)
    }

    func testMinimumCriticalBumpsOntoMgdlGrid() {
        let bumped = SettingsValidation.minimumCritical(above: 252.0, step: 5.0)
        XCTAssertEqual(bumped, 255.0, accuracy: 0.001)
    }

    func testMinimumCriticalAlwaysExceedsHigh() {
        // Sanity: even when high lands exactly on a step boundary, the
        // returned floor must be strictly greater — a slider clamped to
        // this value can never violate the invariant.
        for high in stride(from: 8.0, through: 24.0, by: 0.5) {
            let bumped = SettingsValidation.minimumCritical(above: high, step: 0.5)
            XCTAssertGreaterThan(bumped, high, "floor must exceed high=\(high)")
        }
    }
}
