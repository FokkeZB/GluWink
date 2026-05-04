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

    func testRelativeAgoEnglishPastDate() {
        let threeMinAgo = anchor.addingTimeInterval(-3 * 60)
        let result = widgetRelativeAgoString(
            from: threeMinAgo,
            relativeTo: anchor,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(result.contains("3"), "Expected '3' in '\(result)'")
        XCTAssertTrue(result.contains("min"), "Expected 'min' in '\(result)'")
        XCTAssertTrue(result.contains("ago"), "Expected past-tense 'ago' in '\(result)'")
    }

    func testRelativeAgoDutchPastDate() {
        let ninetyMinAgo = anchor.addingTimeInterval(-90 * 60)
        let result = widgetRelativeAgoString(
            from: ninetyMinAgo,
            relativeTo: anchor,
            locale: Locale(identifier: "nl_NL")
        )
        XCTAssertTrue(result.contains("geleden"), "Expected past-tense 'geleden' in '\(result)'")
    }

    /// The mock dates are always in the past of the anchor, so the formatter
    /// should never render a future-tense ("over X" / "in X") string for the
    /// showcase. Verify the past-tense direction.
    func testRelativeAgoNeverRendersFutureForPastDate() {
        let twoMinAgo = anchor.addingTimeInterval(-2 * 60)
        let en = widgetRelativeAgoString(
            from: twoMinAgo,
            relativeTo: anchor,
            locale: Locale(identifier: "en_US")
        )
        let nl = widgetRelativeAgoString(
            from: twoMinAgo,
            relativeTo: anchor,
            locale: Locale(identifier: "nl_NL")
        )
        XCTAssertFalse(en.lowercased().hasPrefix("in "), "English unexpectedly future-tense: '\(en)'")
        XCTAssertFalse(nl.lowercased().hasPrefix("over "), "Dutch unexpectedly future-tense: '\(nl)'")
    }
}
