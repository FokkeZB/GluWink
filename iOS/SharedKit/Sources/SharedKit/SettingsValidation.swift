import Foundation

/// Validation helpers for user-tweakable settings that have inter-dependent
/// invariants.
///
/// Contract: these helpers run at **write time** in the Settings UI (and in
/// unit tests). They do **not** silently re-clamp persisted values at read
/// time — if an invariant is violated in storage (e.g. because the user
/// lowered `highGlucoseThreshold` after critical was set), the Settings UI
/// surfaces the validation error on the next save attempt. See AGENTS.md →
/// "Shared App Group Container" → "Settings override precedence".
public enum SettingsValidation {
    /// Error surfaced to Settings when a save would violate an invariant.
    public enum Error: Swift.Error, Equatable, Sendable {
        /// `criticalGlucoseThreshold` must be strictly greater than
        /// `highGlucoseThreshold`. Both values carried for error messages.
        case criticalNotAboveHigh(critical: Double, high: Double)
    }

    /// Validate the `critical > high` invariant.
    ///
    /// - Parameters:
    ///   - critical: proposed critical glucose threshold (mmol/L).
    ///   - high: the current (or proposed) high glucose threshold (mmol/L).
    /// - Throws: `Error.criticalNotAboveHigh` when `critical <= high`.
    public static func validateCriticalAboveHigh(critical: Double, high: Double) throws {
        if critical <= high {
            throw Error.criticalNotAboveHigh(critical: critical, high: high)
        }
    }

    /// Return the smallest critical value that is strictly greater than
    /// `high` on the given step grid — used by Settings UI to auto-bump
    /// the slider's floor when the user lowers it below high.
    ///
    /// Example: `high = 14.0`, `step = 0.5` → `14.5`.
    public static func minimumCritical(above high: Double, step: Double) -> Double {
        guard step > 0 else { return high }
        let bumped = (high / step).rounded(.down) * step + step
        return bumped
    }
}
