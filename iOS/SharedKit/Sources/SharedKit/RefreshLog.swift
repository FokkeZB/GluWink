import Foundation

/// Small persistent ring buffer of refresh events (poll fired, background
/// task ran, widget timeline requested, fetch ok / failed, …) kept in the App
/// Group so the app, widgets and Settings can all see the same history.
///
/// Exists to answer "why didn't my data update?" after the fact — in
/// particular under Low Power Mode, where iOS throttles background work and
/// there is no cable-attached console to read. Each entry records whether Low
/// Power Mode was on at the time.
///
/// Diagnostic only: writes are best-effort (read-modify-write, not atomic
/// across processes), so a rare concurrent write between the app and a widget
/// may drop an entry.
public enum RefreshLog {
    public struct Entry: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public let date: Date
        /// Which source or surface logged it, e.g. `easyview`, `widget`, `app`.
        public let source: String
        public let event: String
        public let lowPowerMode: Bool

        public init(id: UUID = UUID(), date: Date = Date(), source: String, event: String, lowPowerMode: Bool) {
            self.id = id
            self.date = date
            self.source = source
            self.event = event
            self.lowPowerMode = lowPowerMode
        }
    }

    public static let storageKey = "refreshLog"
    public static let maxEntries = 200

    private static let lock = NSLock()

    /// App Group defaults resolved from the `AppGroupID` Info.plist key every
    /// target that logs already carries.
    private static var defaults: UserDefaults? {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String)
            .flatMap { UserDefaults(suiteName: $0) }
    }

    public static func record(_ source: String, _ event: String) {
        record(source, event, defaults: defaults)
    }

    static func record(_ source: String, _ event: String, defaults: UserDefaults?) {
        guard let defaults else { return }
        lock.lock()
        defer { lock.unlock() }
        var entries = load(from: defaults)
        entries.append(Entry(
            source: source,
            event: event,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        ))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// Newest first.
    public static func entries() -> [Entry] {
        guard let defaults else { return [] }
        return load(from: defaults).reversed()
    }

    public static func clear() {
        defaults?.removeObject(forKey: storageKey)
    }

    static func load(from defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries
    }

    /// Plain-text dump for sharing, newest first.
    public static func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return entries().map { entry in
            "\(formatter.string(from: entry.date)) [\(entry.source)] \(entry.event)\(entry.lowPowerMode ? " (low power)" : "")"
        }.joined(separator: "\n")
    }
}
