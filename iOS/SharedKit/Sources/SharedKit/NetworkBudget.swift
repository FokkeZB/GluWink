import Foundation

/// Request timeout for the current unit of work. Background tasks only get
/// about 25 seconds, so their first attempt must fail fast enough for
/// `TransientRetry` to fit a second one inside that budget.
public enum NetworkBudget {
    /// True while running inside a BGAppRefreshTask (inherited by child tasks).
    @TaskLocal public static var isBackgroundTask = false

    public static let foregroundTimeout: TimeInterval = 15
    public static let backgroundTimeout: TimeInterval = 8

    public static var requestTimeout: TimeInterval {
        isBackgroundTask ? backgroundTimeout : foregroundTimeout
    }
}
