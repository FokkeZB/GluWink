import DeviceActivity
import Foundation
import os
import SharedKit

final class ActivityScheduler {
    static let shared = ActivityScheduler()

    static let defaultAttentionInterval = 30
    static let defaultNoAttentionInterval = 60
    static let minimumInterval = 15

    private let center = DeviceActivityCenter()
    private let logger = Logger(subsystem: Constants.bundlePrefix, category: "ActivityScheduler")

    private init() {}

    /// Schedule repeating monitors to re-apply shields.
    /// Uses the attention interval (shorter) and no-attention interval (longer)
    /// from settings, falling back to defaults.
    func startMonitoring() {
        center.stopMonitoring()

        let data = SharedDataManager.shared
        let attentionMinutes = max(Self.minimumInterval,
            data.attentionIntervalMinutes ?? Self.defaultAttentionInterval)
        let noAttentionMinutes = max(Self.minimumInterval,
            data.noAttentionIntervalMinutes ?? Self.defaultNoAttentionInterval)

        let maxSlots = 20
        let attentionSlots = maxSlots / 2
        let noAttentionSlots = maxSlots - attentionSlots

        let attentionCount = scheduleIntervals(prefix: "attention", minutes: attentionMinutes, maxSlots: attentionSlots)
        let noAttentionCount = scheduleIntervals(prefix: "noattention", minutes: noAttentionMinutes, maxSlots: noAttentionSlots)

        logger.info("Scheduled \(attentionCount)×\(attentionMinutes)m attention + \(noAttentionCount)×\(noAttentionMinutes)m no-attention intervals")
    }

    private func scheduleIntervals(prefix: String, minutes: Int, maxSlots: Int) -> Int {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let startHour = now.hour ?? 0
        let startMinute = now.minute ?? 0

        var scheduled = 0
        for i in 0..<maxSlots {
            let totalMinutes = startHour * 60 + startMinute + i * minutes
            let h = (totalMinutes / 60) % 24
            let m = totalMinutes % 60
            let endTotal = totalMinutes + minutes
            let eh = (endTotal / 60) % 24
            let em = endTotal % 60

            if endTotal >= 24 * 60 && i > 0 { break }

            let name = DeviceActivityName("\(Constants.bundlePrefix).\(prefix).\(i)")
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: h, minute: m),
                intervalEnd: DateComponents(hour: eh, minute: em),
                repeats: true
            )

            do {
                try center.startMonitoring(name, during: schedule)
                scheduled += 1
            } catch {
                logger.error("Failed to schedule \(prefix) interval \(i): \(error.localizedDescription)")
            }
        }

        return scheduled
    }

    func stopMonitoring() {
        center.stopMonitoring()
        logger.info("Stopped device activity monitoring")
    }
}
