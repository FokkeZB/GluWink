import XCTest
@testable import SharedKit

final class RefreshLogTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "RefreshLogTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testRecordsInOrder() {
        let defaults = makeDefaults()
        RefreshLog.record("a", "first", defaults: defaults)
        RefreshLog.record("b", "second", defaults: defaults)
        let entries = RefreshLog.load(from: defaults)
        XCTAssertEqual(entries.map(\.event), ["first", "second"])
        XCTAssertEqual(entries.map(\.source), ["a", "b"])
    }

    func testCapsAtMaxEntriesDroppingOldest() {
        let defaults = makeDefaults()
        for index in 0..<(RefreshLog.maxEntries + 5) {
            RefreshLog.record("s", "e\(index)", defaults: defaults)
        }
        let entries = RefreshLog.load(from: defaults)
        XCTAssertEqual(entries.count, RefreshLog.maxEntries)
        XCTAssertEqual(entries.first?.event, "e5")
        XCTAssertEqual(entries.last?.event, "e\(RefreshLog.maxEntries + 4)")
    }
}
