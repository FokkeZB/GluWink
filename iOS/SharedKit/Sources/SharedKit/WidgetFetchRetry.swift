import Foundation

/// Retries a widget network call once when it times out.
///
/// Under Low Power Mode the radio is slow to wake and the first request of a
/// timeline call often times out while an immediate second one succeeds.
/// Worst case is two request timeouts back to back; widget callers keep each
/// timeout short so the total stays within the timeline budget.
enum WidgetFetchRetry {
    static func run<T>(_ label: String, _ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as URLError where error.code == .timedOut {
            RefreshLog.record("widget", "\(label) timed out — retrying once")
            return try await operation()
        }
    }
}
