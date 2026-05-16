import Combine
import SharedKit
import SwiftUI
#if targetEnvironment(simulator)
import WidgetKit
#endif

struct WatchContentView: View {
    @State private var tick = Date()

    #if targetEnvironment(simulator)
    /// Last `syncToken` value observed in the simulator bridge file.
    /// Used to detect writes from the iPhone simulator and trigger a
    /// `WidgetCenter` reload when paired-sim WatchConnectivity delivery
    /// lags or drops the message — without this, the watch app picks up
    /// the new mock state on its next 5 s tick but the watch widgets
    /// (running in a separate extension process) don't see the change
    /// until the timeline's `.atEnd` reload fires (≤ 5 min) or some
    /// other code path happens to call `reloadAllTimelines` for a
    /// different reason.
    ///
    /// Production / device builds rely entirely on
    /// `WatchConnectivityReceiver.applyContext`, which already pairs
    /// every received context with a widget reload — this state and the
    /// polling helper below are simulator-only and gated behind
    /// `targetEnvironment(simulator)` so device behaviour is unchanged.
    @State private var lastBridgeSyncToken: Double?
    #endif

    private let valueFont = Font.system(size: 28, weight: .bold, design: .rounded)

    private static let refreshInterval: TimeInterval = {
        #if targetEnvironment(simulator)
        return 5
        #else
        return 60
        #endif
    }()

    private let timer = Timer.publish(every: refreshInterval, on: .main, in: .common).autoconnect()

    private var content: ShieldContent {
        let _ = tick
        return WatchDataManager.content(now: tick)
    }

    private func glucoseValueText(for content: ShieldContent) -> String {
        "\(content.glucose?.formatted ?? "--") \(content.glucoseUnitLabel)"
    }

    private func carbsValueText(for content: ShieldContent) -> String {
        "\(content.carbs.map { String($0.grams) } ?? "--") g"
    }

    private func relativeTimeText(from date: Date?) -> Text {
        // No-data row deliberately reads as "No data" / "Geen data" — not
        // the bare "--" placeholder we use for the metric value above. The
        // metric line ("-- mmol/L") still communicates "value missing"
        // adequately because the unit is right there; the relative-time
        // line has no such anchor, so "--" alone reads as a layout glitch.
        // Spelling it out matches the rectangular widget tile, which has
        // shown the same "No data" string on missing-sample rows since
        // PR #119's atomic-types refactor (`ShieldContent.glucose == nil`
        // → render the no-data state on every surface, full stop).
        guard let date else { return Text(String(localized: "watch.app.noData")) }
        return Text(date, style: .relative)
    }

    var body: some View {
        let current = content

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(glucoseValueText(for: current))
                    .font(valueFont)
                    .foregroundStyle(.white)
                relativeTimeText(from: current.glucose?.sampleDate)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(carbsValueText(for: current))
                    .font(valueFont)
                    .foregroundStyle(.white.opacity(0.95))
                relativeTimeText(from: current.carbs?.sampleDate)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(current.attentionLevel.tint)
        .onReceive(timer) { newTick in
            tick = newTick
            #if targetEnvironment(simulator)
            reloadWidgetsIfBridgeChanged()
            #endif
        }
    }

    #if targetEnvironment(simulator)
    /// Re-read the simulator bridge's `syncToken` and ask WidgetKit to
    /// rebuild the watch widget timelines if it has changed since the
    /// last tick. The bridge file is written by the iPhone simulator
    /// every time `WatchSessionManager.sendLatestContext` runs; the
    /// `syncToken` is a `Date().timeIntervalSince1970` taken at write
    /// time, so any toggle that flips Demo / Nightscout / settings
    /// produces a strictly newer token.
    ///
    /// The token comparison is `!=`, not `>`, on purpose: we don't care
    /// whether the bridge moved forwards or "backwards" (e.g. the
    /// iPhone simulator was reset and re-seeded), only that the state
    /// the widget extension would read has changed.
    private func reloadWidgetsIfBridgeChanged() {
        let currentToken = SimulatorWatchBridge.loadContext()?["syncToken"] as? Double
        guard currentToken != lastBridgeSyncToken else { return }
        lastBridgeSyncToken = currentToken
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif
}
