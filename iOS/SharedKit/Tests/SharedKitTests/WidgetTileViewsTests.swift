import XCTest
@testable import SharedKit

/// Pins the relative-ago formatter used by the simulator-only widget
/// screenshot showcase (issue #107). Production widgets keep SwiftUI's
/// auto-updating `Text(date, style: .relative)` path; this helper only
/// runs when `WidgetTileContent.referenceDate` is non-nil.
final class WidgetTileViewsTests: XCTestCase {
    private let anchor: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 4
        components.hour = 9
        components.minute = 41
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    func testRelativeAgoEnglishSingleUnit() {
        let threeMinAgo = anchor.addingTimeInterval(-3 * 60)
        let result = widgetRelativeAgoString(
            from: threeMinAgo,
            relativeTo: anchor,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(result.contains("3"), "Expected '3' in '\(result)'")
        XCTAssertTrue(result.contains("min"), "Expected 'min' in '\(result)'")
        XCTAssertTrue(result.hasSuffix("ago"), "Expected past-tense suffix 'ago' in '\(result)'")
    }

    /// The key fix for #107: a 90-minute gap must render multi-unit as
    /// "1 hr, 30 min ago" — not rounded to "1 hr ago", which would
    /// contradict the tile's own absolute-time label ("08:11" is 1 hr
    /// AND 30 min before 09:41, not 1 hr).
    func testRelativeAgoEnglishMultiUnitPreservesMinutes() {
        let ninetyMinAgo = anchor.addingTimeInterval(-90 * 60)
        let result = widgetRelativeAgoString(
            from: ninetyMinAgo,
            relativeTo: anchor,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(result.contains("1"), "Expected '1' (hour) in '\(result)'")
        XCTAssertTrue(result.contains("hr"), "Expected 'hr' (hour component) in '\(result)'")
        XCTAssertTrue(result.contains("30"), "Expected '30' (remaining minutes) in '\(result)' — multi-unit must survive, not round away")
        XCTAssertTrue(result.contains("min"), "Expected 'min' (minute component) in '\(result)'")
        XCTAssertTrue(result.hasSuffix("ago"), "Expected past-tense suffix 'ago' in '\(result)'")
    }

    func testRelativeAgoDutchMultiUnitPreservesMinutes() {
        let ninetyMinAgo = anchor.addingTimeInterval(-90 * 60)
        let result = widgetRelativeAgoString(
            from: ninetyMinAgo,
            relativeTo: anchor,
            locale: Locale(identifier: "nl_NL")
        )
        XCTAssertTrue(result.contains("30"), "Expected '30' (remaining minutes) in '\(result)' — multi-unit must survive, not round away")
        XCTAssertTrue(result.hasSuffix("geleden"), "Expected past-tense suffix 'geleden' in '\(result)'")
    }

    func testRelativeAgoDutchSingleUnit() {
        let threeMinAgo = anchor.addingTimeInterval(-3 * 60)
        let result = widgetRelativeAgoString(
            from: threeMinAgo,
            relativeTo: anchor,
            locale: Locale(identifier: "nl_NL")
        )
        XCTAssertTrue(result.contains("3"), "Expected '3' in '\(result)'")
        XCTAssertTrue(result.hasSuffix("geleden"), "Expected past-tense suffix 'geleden' in '\(result)'")
    }

    /// The mock dates are always in the past of the anchor, so the formatter
    /// should never render a future-tense ("over X" / "in X") string for the
    /// showcase. Verify the past-tense direction and that a zero/future
    /// interval collapses to empty rather than "in 0 min".
    func testRelativeAgoReturnsEmptyForFutureOrEqualDate() {
        let sameMoment = widgetRelativeAgoString(
            from: anchor,
            relativeTo: anchor,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(sameMoment, "", "Expected empty string for equal dates, got '\(sameMoment)'")

        let twoMinFuture = anchor.addingTimeInterval(2 * 60)
        let futureResult = widgetRelativeAgoString(
            from: twoMinFuture,
            relativeTo: anchor,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(futureResult, "", "Expected empty string for future date, got '\(futureResult)'")
    }
}
