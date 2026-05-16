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
        "\(content.glucose?.formatted ?? "--") \(content.glucoseUnitLabel)"
    }

    private func carbsValueText(for content: ShieldContent) -> String {
        "\(content.carbs.map { String($0.grams) } ?? "--") g"
    }

    private func relativeTimeText(from date: Date?) -> Text {
        guard let date else { return Text("--") }
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
        .onReceive(timer) { tick = $0 }
    }
}
