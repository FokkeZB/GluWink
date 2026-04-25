import Combine
import SharedKit
import SwiftUI

struct WatchContentView: View {
    @State private var tick = Date()
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
        "\(content.glucoseValue > 0 ? content.formattedGlucose : "--") \(content.glucoseUnitLabel)"
    }

    private func carbsValueText(for content: ShieldContent) -> String {
        "\(content.carbGrams.map(String.init) ?? "--") g"
    }

    private func relativeTimeText(from date: Date?, hasData: Bool) -> Text {
        guard hasData, let date else { return Text("--") }
        return Text(date, style: .relative)
    }

    var body: some View {
        let current = content

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(glucoseValueText(for: current))
                    .font(valueFont)
                    .foregroundStyle(.white)
                relativeTimeText(from: WatchDataManager.glucoseFetchedAt, hasData: current.glucoseValue > 0)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(carbsValueText(for: current))
                    .font(valueFont)
                    .foregroundStyle(.white.opacity(0.95))
                relativeTimeText(from: WatchDataManager.lastCarbEntryAt, hasData: current.carbGrams != nil)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(current.attentionLevel.tint)
        .onReceive(timer) { tick = $0 }
    }
}
