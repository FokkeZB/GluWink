import HealthKit
import SharedKit
import SwiftUI
import UIKit

struct HealthKitSettingsView: View {
    @State private var enabled: Bool
    @State private var isRequesting = false
    @State private var latestGlucose: GlucoseReading?
    @State private var latestCarbs: CarbsReading?

    init() {
        let data = SharedDataManager.shared
        _enabled = State(initialValue: data.healthKitEnabled)
        _latestGlucose = State(initialValue: data.glucoseReading(source: .healthKit))
        _latestCarbs = State(initialValue: data.carbsReading(source: .healthKit))
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Toggle(String(localized: "healthkit.settings.enabledToggle"), isOn: Binding(
                        get: { enabled },
                        set: { newValue in
                            if newValue {
                                Task { await enable() }
                            } else {
                                Task { await disable() }
                            }
                        }
                    ))
                    .disabled(isRequesting)
                    if isRequesting {
                        ProgressView()
                    }
                }
            } footer: {
                Text("healthkit.settings.enabledFooter", tableName: "Localizable")
            }

            Section {
                latestSampleRow(
                    label: String(localized: "healthkit.settings.latestGlucose"),
                    value: latestGlucose.map { SharedDataManager.shared.glucoseUnit.formattedWithUnit($0.mmol) },
                    at: latestGlucose?.sampleAt,
                    emptyMessage: String(localized: "healthkit.settings.noGlucoseYet")
                )
                latestSampleRow(
                    label: String(localized: "healthkit.settings.latestCarbs"),
                    value: latestCarbs.map { "\(Int($0.grams)) g" },
                    at: latestCarbs?.sampleAt,
                    emptyMessage: String(localized: "healthkit.settings.noCarbsYet")
                )
            } header: {
                Text("healthkit.settings.latestDataHeader", tableName: "Localizable")
            } footer: {
                Text("healthkit.settings.statusFooterRequested", tableName: "Localizable")
            }

            Section {
                Button {
                    openHealthApp()
                } label: {
                    Label(String(localized: "healthkit.settings.openHealthButton"), systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("healthkit.settings.sectionFooter", tableName: "Localizable")
            }
        }
        .navigationTitle(String(localized: "healthkit.settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Refresh every 5 s so a HealthKit observer fire in the
            // background shows up here without forcing the user to
            // leave and re-enter the screen. Mirrors Nightscout's
            // settings screen refresh loop.
            while !Task.isCancelled {
                refreshLatestSamples()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func refreshLatestSamples() {
        let data = SharedDataManager.shared
        enabled = data.healthKitEnabled
        latestGlucose = data.glucoseReading(source: .healthKit)
        latestCarbs = data.carbsReading(source: .healthKit)
    }

    /// Shared layout for "Latest data" rows — same shape as Nightscout's
    /// settings screen uses so the two per-source screens feel
    /// symmetrical.
    @ViewBuilder
    private func latestSampleRow(label: String, value: String?, at: Date?, emptyMessage: String) -> some View {
        if let value, let at {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .monospacedDigit()
                    Text(at, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack {
                Text(label)
                Spacer()
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func enable() async {
        isRequesting = true
        defer { isRequesting = false }
        await HealthKitManager.shared.enable()
        enabled = SharedDataManager.shared.healthKitEnabled
        refreshLatestSamples()
    }

    @MainActor
    private func disable() async {
        isRequesting = true
        defer { isRequesting = false }
        await HealthKitManager.shared.disable()
        enabled = SharedDataManager.shared.healthKitEnabled
        // After disabling, shielding may need to come down if HK was
        // the last remaining source. Mirrors Nightscout/Demo disable
        // paths.
        ShieldManager.shared.disableIfNoDataSource()
        refreshLatestSamples()
    }

    private func openHealthApp() {
        // `x-apple-health://` opens Health. There's no public API to deep-link
        // to a specific app's sources page, but the Health app is where the
        // user manages per-source read permissions.
        if let url = URL(string: "x-apple-health://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
