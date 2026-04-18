import Foundation

public enum Constants {
    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as! String
    }

    /// App Group identifier shared across all targets.
    public static var appGroupID: String { info("AppGroupID") }

    /// Bundle identifier prefix used for logging subsystems.
    public static var bundlePrefix: String { info("BundlePrefix") }

    /// User-facing app display name (from CFBundleDisplayName in xcconfig).
    public static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Status"
    }
}
