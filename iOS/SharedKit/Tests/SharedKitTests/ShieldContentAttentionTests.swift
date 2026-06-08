import Foundation
import XCTest
@testable import SharedKit

/// Pins the `needsAttention` contract that `SharedDataManager.refreshAttentionBadge`
/// delegates to. Before issue #4 the badge had its own attention ladder that
/// diverged from `ShieldContent` (e.g. "no carb data ever" didn't flip the
/// badge), which left the app icon silently out of sync with the shield and
/// widgets. These tests lock the ladder so the next drift fails fast.
final class ShieldContentAttentionTests: XCTestCase {
    // MARK: - Fixture

    private let strings = ShieldContent.Strings(
        positiveTitles: ["clear"],
        attentionTitles: ["attention"],
        doneButton: "Done",
        checkInButton: "I will",
        criticalCannotDismiss: "Cannot dismiss until below %@",
        openAppTo: "Open app to:",
        glucose: "%@ · %@ (%@ ago)",
        glucoseNoData: "No glucose data",
        carbsEntry: "%d g · %@ (%@ ago)",
        carbsMealOnly: "%@ · %@ (%@ ago)",
        mealLabel: "Meal",
        carbsNoData: "No carb data",
        agoMinutes: "%dm",
        agoHoursMinutes: "%dh %dm",
        scenarioChecks: [:]
    )

    /// Fixed reference date inside the morning grace window (before 09:30,
    /// the xcconfig default). Keeping it at 08:00 local time means the
    /// "no carb data" assertions aren't accidentally passing because the
    /// carb-gap rule kicked in.
    private var morning: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 25
        comps.hour = 8; comps.minute = 0
        return Calendar.current.date(from: comps)!
    }

    private func make(
        glucose: Double = 6.5,
        glucoseFetchedAt: Date?,
        lastCarbGrams: Double? = 20,
        lastCarbLabel: String? = nil,
        lastCarbEntryAt: Date?,
        carbsEnabled: Bool = true,
        now: Date
    ) -> ShieldContent {
        ShieldContent(
            glucose: glucose,
            glucoseFetchedAt: glucoseFetchedAt,
            lastCarbGrams: lastCarbGrams,
            lastCarbLabel: lastCarbLabel,
            lastCarbEntryAt: lastCarbEntryAt,
            highGlucoseThreshold: 14.0,
            lowGlucoseThreshold: 4.0,
            criticalGlucoseThreshold: 20.0,
            glucoseStaleMinutes: 30,
            carbGraceHour: 9,
            carbGraceMinute: 30,
            carbsEnabled: carbsEnabled,
            glucoseUnit: .mmolL,
            strings: strings,
            now: now
        )
    }

    // MARK: - Clear

    func testClearWhenFreshGlucoseAndRecentCarbs() {
        let now = morning
        let content = make(
            glucoseFetchedAt: now.addingTimeInterval(-5 * 60),
            lastCarbEntryAt: now.addingTimeInterval(-30 * 60),
            now: now
        )
        XCTAssertFalse(content.needsAttention)
        XCTAssertEqual(content.attentionLevel, .clear)
    }

    // MARK: - Attention (the badge must match these)

    /// A meal acknowledgment without a gram count (lastCarbEntryAt set but
    /// lastCarbGrams nil) must NOT fire `.noCarbData`. The child told the
    /// system they ate — GluWink must respect that signal.
    func testMealOnlyEntryIsNotNoCarbData() {
        let now = morning
        let content = make(
            glucoseFetchedAt: now.addingTimeInterval(-5 * 60),
            lastCarbGrams: nil,
            lastCarbLabel: "B'fast",
            lastCarbEntryAt: now.addingTimeInterval(-30 * 60),
            now: now
        )
        XCTAssertFalse(content.needsAttention, "meal-only entry within grace window must not need attention")
        XCTAssertNotNil(content.carbs, "carbs must be non-nil when a date is present, even without grams")
        XCTAssertNil(content.carbs?.grams, "carbs.grams must be nil when no gram count was recorded")
        XCTAssertEqual(content.carbs?.label, "B'fast", "label must be threaded through to ShieldContent.Carbs")
    }

    func testNoCarbDataEverIsAttention() {
        let now = morning
        let content = make(
            glucoseFetchedAt: now.addingTimeInterval(-5 * 60),
            lastCarbGrams: nil,
            lastCarbEntryAt: nil,
            now: now
        )
        XCTAssertTrue(
            content.needsAttention,
            "Missing carb history must flip the badge even during morning grace — the badge previously ignored this case."
        )
        XCTAssertEqual(content.attentionLevel, .attention)
    }

    func testStaleGlucoseCrossingThresholdIsAttention() {
        let now = morning
        let fresh = make(
            glucoseFetchedAt: now.addingTimeInterval(-29 * 60),
            lastCarbEntryAt: now.addingTimeInterval(-30 * 60),
            now: now
        )
        XCTAssertFalse(fresh.needsAttention, "29m ago is still fresh at staleMinutes=30")

        let stale = make(
            glucoseFetchedAt: now.addingTimeInterval(-31 * 60),
            lastCarbEntryAt: now.addingTimeInterval(-30 * 60),
            now: now
        )
        XCTAssertTrue(stale.needsAttention, "31m ago crosses staleMinutes=30 and must flip the badge")
        XCTAssertEqual(stale.attentionLevel, .attention)
    }

    func testCarbGapOutsideGraceIsAttention() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 25
        comps.hour = 14; comps.minute = 0
        let afternoon = Calendar.current.date(from: comps)!

        let content = make(
            glucoseFetchedAt: afternoon.addingTimeInterval(-5 * 60),
            lastCarbEntryAt: afternoon.addingTimeInterval(-5 * 3600),
            now: afternoon
        )
        XCTAssertTrue(content.needsAttention)
        XCTAssertEqual(content.attentionLevel, .attention)
    }

    func testHighGlucoseIsAttention() {
        let now = morning
        let content = make(
            glucose: 15.0,
            glucoseFetchedAt: now.addingTimeInterval(-5 * 60),
            lastCarbEntryAt: now.addingTimeInterval(-30 * 60),
            now: now
        )
        XCTAssertTrue(content.needsAttention)
        XCTAssertEqual(content.attentionLevel, .attention)
    }

    // MARK: - Critical

    func testCriticalGlucoseIsCritical() {
        let now = morning
        let content = make(
            glucose: 21.0,
            glucoseFetchedAt: now.addingTimeInterval(-5 * 60),
            lastCarbEntryAt: now.addingTimeInterval(-30 * 60),
            now: now
        )
        XCTAssertTrue(content.needsAttention)
        XCTAssertTrue(content.isCriticalGlucose)
        XCTAssertEqual(content.attentionLevel, .critical)
    }

    // MARK: - carbsEnabled = false

    func testCarbsDisabledNoCarbGap() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 25
        comps.hour = 14; comps.minute = 0
        let afternoon = Calendar.current.date(from: comps)!

        let content = make(
            glucoseFetchedAt: afternoon.addingTimeInterval(-5 * 60),
            lastCarbEntryAt: afternoon.addingTimeInterval(-5 * 3600),
            carbsEnabled: false,
            now: afternoon
        )
        XCTAssertFalse(content.needsAttention, "carbGap must not fire when carbsEnabled = false")
        XCTAssertEqual(content.attentionLevel, .clear)
    }

    func testCarbsDisabledNoNoCarbData() {
        let now = morning
        let content = make(
            glucoseFetchedAt: now.addingTimeInterval(-5 * 60),
            lastCarbGrams: nil,
            lastCarbEntryAt: nil,
            carbsEnabled: false,
            now: now
        )
        XCTAssertFalse(content.needsAttention, "noCarbData must not fire when carbsEnabled = false")
        XCTAssertEqual(content.attentionLevel, .clear)
        XCTAssertNil(content.carbs, "carbs must be nil when carbsEnabled = false")
    }

    func testCarbsDisabledCarbsAlwaysNil() {
        let now = morning
        let content = make(
            glucoseFetchedAt: now.addingTimeInterval(-5 * 60),
            lastCarbGrams: 40,
            lastCarbEntryAt: now.addingTimeInterval(-30 * 60),
            carbsEnabled: false,
            now: now
        )
        XCTAssertNil(content.carbs, "carbs must be nil regardless of input when carbsEnabled = false")
        XCTAssertFalse(content.carbsNeedsAttention)
    }

    func testCarbsDisabledGlucoseAttentionStillFires() {
        let now = morning
        let content = make(
            glucose: 15.0,
            glucoseFetchedAt: now.addingTimeInterval(-5 * 60),
            lastCarbEntryAt: nil,
            carbsEnabled: false,
            now: now
        )
        XCTAssertTrue(content.needsAttention, "glucose attention must still fire when carbsEnabled = false")
        XCTAssertEqual(content.attentionLevel, .attention)
        XCTAssertFalse(content.carbsNeedsAttention, "carbsNeedsAttention must stay false when carbsEnabled = false")
    }

    func testCarbsDisabledHasNoDataOnlyWhenNoGlucose() {
        let now = morning
        let withGlucose = make(
            glucoseFetchedAt: now.addingTimeInterval(-5 * 60),
            lastCarbEntryAt: nil,
            carbsEnabled: false,
            now: now
        )
        XCTAssertFalse(withGlucose.hasNoData, "hasNoData must be false when glucose is available, even with no carbs")

        let noGlucose = make(
            glucose: 0,
            glucoseFetchedAt: nil,
            lastCarbEntryAt: nil,
            carbsEnabled: false,
            now: now
        )
        XCTAssertTrue(noGlucose.hasNoData, "hasNoData must be true when glucose is also absent")
    }
}
