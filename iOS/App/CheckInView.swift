import SwiftUI

/// Interactive check-in flow shown when attention is needed.
/// Items unlock one by one with a delay. After all are checked,
/// a Disarm button appears after a final delay.
struct CheckInView: View {
    let items: [String]
    let onDisarm: () -> Void

    @State private var checkedIndices: Set<Int>
    @State private var nextUnlockIndex: Int
    @State private var disarmReady = false

    private let itemDelay: TimeInterval = 1.5
    private let disarmDelay: TimeInterval = 2.0

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

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                checkRow(index: index, text: item)
            }

            if checkedIndices.count == items.count {
                Button {
                    onDisarm()
                } label: {
                    HStack {
                        Image(systemName: disarmReady ? "shield.slash" : "hourglass")
                        Text(disarmReady
                            ? String(localized: "checkin.disarmButton")
                            : String(localized: "checkin.disarmWait"))
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!disarmReady)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + disarmDelay) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        disarmReady = true
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isChecked
                    ? "checkmark.circle.fill"
                    : (isUnlocked ? "circle" : "circle.dashed"))
                    .font(.title2)
                    .foregroundColor(isChecked ? .green : (isUnlocked ? .primary : Color(.tertiaryLabel)))
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
                        .foregroundStyle(.green)
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
                        .foregroundStyle(.orange)
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
