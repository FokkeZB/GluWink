import Combine
import SharedKit
import SwiftUI

/// Interactive check-in flow shown when attention is needed.
/// Items unlock one by one with a delay. After all are checked,
/// a live cooldown ticks down before the disarm button becomes ready —
/// a forced pause so the child actually does what they just acknowledged
/// instead of tapping straight through.
struct CheckInView: View {
    let items: [String]
    let onDisarm: () -> Void

    @State private var checkedIndices: Set<Int>
    @State private var nextUnlockIndex: Int
    @State private var disarmReady = false
    /// When set, the disarm button is in cooldown mode and shows
    /// `endDate.timeIntervalSinceNow` rounded up to whole seconds. `nil`
    /// means "no countdown active" (either not yet started, or finished
    /// and `disarmReady = true`, or reset by an unchecked box).
    @State private var cooldownEndDate: Date?

    private let itemDelay: TimeInterval = 1.5

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    init(items: [String], onDisarm: @escaping () -> Void) {
        self.items = items
        self.onDisarm = onDisarm

        #if targetEnvironment(simulator)
        // Under the App Store screenshot harness, start with N rows pre-
        // checked so the red-shield shot reads as "user is responding"
        // instead of a passive list. Also pre-unlocks the next row so the
        // screenshot doesn't have to wait out the 1.5s unlock timer.
        if let preset = ScreenshotHarness.current?.homeViewPreset,
           preset.checkInPreCheckedCount > 0 {
            let pre = min(preset.checkInPreCheckedCount, items.count)
            _checkedIndices = State(initialValue: Set(0..<pre))
            _nextUnlockIndex = State(initialValue: pre < items.count ? pre : items.count)
            return
        }
        #endif

        _checkedIndices = State(initialValue: [])
        _nextUnlockIndex = State(initialValue: -1)
    }

    private var cooldownRemaining: Int {
        guard let end = cooldownEndDate else { return 0 }
        return max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                checkRow(index: index, text: item)
            }

            if checkedIndices.count == items.count {
                VStack(spacing: 8) {
                    Button {
                        onDisarm()
                    } label: {
                        HStack {
                            Image(systemName: disarmReady ? "shield.slash" : "hourglass")
                            Text(disarmReady
                                ? String(localized: "checkin.disarmButton")
                                : String(localized: "checkin.disarmCountdown \(cooldownRemaining)"))
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandTint.green)
                    .disabled(!disarmReady)

                    if !disarmReady {
                        Text(String(localized: "checkin.cooldownHelper"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 32)
        .onAppear {
            #if targetEnvironment(simulator)
            // Harness already seeded `nextUnlockIndex` in init; don't let
            // the 1.5s timer stomp it back to 0.
            if ScreenshotHarness.isActive { return }
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + itemDelay) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    nextUnlockIndex = 0
                }
            }
        }
        .onReceive(timer) { _ in
            // Force a body re-evaluation every second so `cooldownRemaining`
            // refreshes the displayed count. The actual flip-to-ready is
            // scheduled via `DispatchQueue.asyncAfter` in `startCooldown`,
            // not driven from here -- a recompose around the deadline can
            // resubscribe the timer publisher and drop the final tick,
            // which is exactly the "stuck at Wacht (0s)" symptom.
        }
    }

    private func checkRow(index: Int, text: String) -> some View {
        let isChecked = checkedIndices.contains(index)
        let isUnlocked = index == nextUnlockIndex

        return Button {
            guard isUnlocked else { return }
            _ = withAnimation(.easeInOut(duration: 0.3)) {
                checkedIndices.insert(index)
            }

            if checkedIndices.count < items.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + itemDelay) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        nextUnlockIndex = nextUnlockedIndex()
                    }
                }
            } else {
                startCooldown()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isChecked
                    ? "checkmark.circle.fill"
                    : (isUnlocked ? "circle" : "circle.dashed"))
                    .font(.title2)
                    .foregroundColor(isChecked ? BrandTint.green : (isUnlocked ? .primary : Color(.tertiaryLabel)))
                    .symbolEffect(.bounce, value: isUnlocked)

                Text(text)
                    .font(.body)
                    .foregroundColor(isChecked ? .secondary : (isUnlocked ? .primary : Color(.tertiaryLabel)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .disabled(!isUnlocked)
        .buttonStyle(.plain)
    }

    private func nextUnlockedIndex() -> Int {
        for i in 0..<items.count where !checkedIndices.contains(i) {
            return i
        }
        return items.count
    }

    /// Capture the configured cooldown once at the moment the last box is
    /// checked and arm the live countdown. A non-positive value (e.g. user
    /// dialled it down to 0) skips the wait entirely and flips the button
    /// to its ready state.
    private func startCooldown() {
        let configured = SharedDataManager.shared.cooldownSeconds ?? 30
        guard configured > 0 else {
            withAnimation(.easeInOut(duration: 0.3)) {
                disarmReady = true
            }
            return
        }
        let end = Date().addingTimeInterval(TimeInterval(configured))
        cooldownEndDate = end
        // Independent one-shot for the actual flip. The per-second timer is
        // for display only; relying on it to also fire the flip is fragile
        // because a parent recompose can resubscribe the publisher and drop
        // the final tick.
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(configured)) {
            guard cooldownEndDate == end, !disarmReady else { return }
            cooldownEndDate = nil
            withAnimation(.easeInOut(duration: 0.3)) {
                disarmReady = true
            }
        }
    }
}

/// Read-only view of acknowledged check-in items (re-visit after completion).
struct CheckInAcknowledgedView: View {
    let items: [String]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(BrandTint.green)
                    Text(item)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
            }

            Text(String(localized: "checkin.acknowledgedDescription"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }
}

/// Non-interactive informational list of attention items shown when
/// shielding is disabled or shields are not armed.
struct AttentionListView: View {
    let items: [String]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(BrandTint.orange)
                    Text(item)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 32)
    }
}
