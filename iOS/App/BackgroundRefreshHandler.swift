import BackgroundTasks
import SharedKit

/// Shared body of the per-source `BGAppRefreshTask` handlers: logs, runs the
/// fetch under the shorter background request timeout, and completes the task
/// exactly once — whichever of "fetch finished" or "iOS expired the task"
/// happens first.
@MainActor
enum BackgroundRefreshHandler {
    static func run(_ task: BGAppRefreshTask, source: String, fetch: @escaping @MainActor () async -> Void) {
        RefreshLog.record(source, "background task started")
        let completion = CompletionGuard()

        let work = NetworkBudget.$isBackgroundTask.withValue(true) {
            Task { @MainActor in
                await fetch()
                guard completion.claim() else { return }
                RefreshLog.record(source, "background task completed")
                task.setTaskCompleted(success: true)
            }
        }

        task.expirationHandler = {
            guard completion.claim() else { return }
            RefreshLog.record(source, "background task expired")
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

private final class CompletionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    /// True for the first caller only.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
