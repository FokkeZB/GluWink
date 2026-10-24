import Foundation

/// Retries a network call once after a transient failure.
///
/// Right after iOS wakes the app or a widget (especially under Low Power
/// Mode) the radio and TLS state are often not ready: the first request times
/// out or fails the TLS handshake while an immediate second one succeeds.
/// Worst case is two failed attempts back to back, so callers keep each
/// request timeout short.
public enum TransientRetry {
    static let retryable: Set<URLError.Code> = [.timedOut, .secureConnectionFailed, .networkConnectionLost]

    public static func run<T>(
        _ source: String,
        _ label: String,
        pause: Duration = .seconds(1),
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as URLError where retryable.contains(error.code) {
            RefreshLog.record(source, "\(label) failed (\(error.localizedDescription)) — retrying once")
            try? await Task.sleep(for: pause)
            return try await operation()
        }
    }
}
