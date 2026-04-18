import Foundation

public enum SimulatorWatchBridge {
    // On Simulator, "/tmp" can resolve per app sandbox.
    // Use a host-level path so iOS + watch simulator processes see the same file.
    private static let primaryBridgeURL = URL(fileURLWithPath: "/private/tmp/dev.simulator.watch-bridge.json")
    private static let legacyBridgeURL = URL(fileURLWithPath: "/tmp/dev.simulator.watch-bridge.json")

    public static func storeContext(_ context: [String: Any]) {
        #if targetEnvironment(simulator)
        guard JSONSerialization.isValidJSONObject(context),
              let data = try? JSONSerialization.data(withJSONObject: context, options: [])
        else {
            return
        }

        try? data.write(to: primaryBridgeURL, options: .atomic)
        #endif
    }

    public static func loadContext() -> [String: Any]? {
        #if targetEnvironment(simulator)
        for url in [primaryBridgeURL, legacyBridgeURL] {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data, options: []),
                  let context = object as? [String: Any]
            else {
                continue
            }

            return context
        }

        return nil
        #else
        nil
        #endif
    }
}
