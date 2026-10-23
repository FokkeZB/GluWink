import Foundation

/// Runs one fetch at a time. A caller arriving while a fetch is in flight
/// awaits that fetch instead of returning early, so a background task stays
/// alive until the real work finishes and a manual refresh reports the real
/// result.
///
/// A fetch running longer than `staleAfter` is assumed dead (iOS suspends the
/// app mid-request and the request only times out on resume): it is cancelled
/// and replaced rather than blocking every later fetch.
@MainActor
public final class FetchCoalescer {
    private var current: (id: UUID, startedAt: Date, task: Task<Void, Never>)?
    private let staleAfter: TimeInterval

    public init(staleAfter: TimeInterval = 30) {
        self.staleAfter = staleAfter
    }

    /// - Parameters:
    ///   - joined: Called when this caller joins an in-flight fetch.
    ///   - replaced: Called when a stale in-flight fetch is abandoned.
    public func run(
        joined: () -> Void = {},
        replaced: () -> Void = {},
        _ work: @escaping @MainActor () async -> Void
    ) async {
        if let current {
            if Date().timeIntervalSince(current.startedAt) < staleAfter {
                joined()
                await current.task.value
                return
            }
            current.task.cancel()
            replaced()
        }
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await work()
            if self?.current?.id == id { self?.current = nil }
        }
        current = (id, Date(), task)
        await task.value
    }
}
