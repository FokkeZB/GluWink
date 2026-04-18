import HealthKit
import SwiftUI
import UIKit

struct HealthKitSettingsView: View {
    @State private var authorizationStatus: HKAuthorizationStatus
    @State private var isRequesting = false

    private let store = HKHealthStore()
    private let glucoseType = HKQuantityType(.bloodGlucose)

    init() {
        _authorizationStatus = State(
            initialValue: HKHealthStore().authorizationStatus(for: HKQuantityType(.bloodGlucose))
        )
    }

    /// `HKHealthStore.authorizationStatus(for:)` reports `.notDetermined`
    /// reliably (we've never prompted), but for read-only requests returns
    /// `.sharingDenied` as a privacy mask regardless of whether the user
    /// actually granted read access. We can only tell "have we asked" vs
    /// "haven't asked yet" — never "is it currently granted".
    private var hasRequested: Bool {
        authorizationStatus != .notDetermined
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label(String(localized: "healthkit.settings.statusLabel"), systemImage: "heart.text.square")
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("healthkit.settings.statusHeader", tableName: "Localizable")
            } footer: {
                Text(hasRequested
                    ? String(localized: "healthkit.settings.statusFooterRequested")
                    : String(localized: "healthkit.settings.statusFooterNotDetermined"))
            }

            Section {
                if !hasRequested {
                    Button {
                        Task { await requestAuthorization() }
                    } label: {
                        HStack {
                            Label(String(localized: "healthkit.settings.requestButton"), systemImage: "heart.fill")
                            Spacer()
                            if isRequesting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRequesting)
                }

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
        .onAppear { refreshStatus() }
    }

    private var statusText: String {
        hasRequested
            ? String(localized: "healthkit.settings.statusRequested")
            : String(localized: "healthkit.settings.statusNotConnected")
    }

    private func refreshStatus() {
        authorizationStatus = store.authorizationStatus(for: glucoseType)
    }

    @MainActor
    private func requestAuthorization() async {
        isRequesting = true
        defer { isRequesting = false }

        await HealthKitManager.shared.requestAuthorization()
        await HealthKitManager.shared.enableBackgroundDelivery()
        HealthKitManager.shared.startObserving()
        await HealthKitManager.shared.fetchLatestGlucose()
        await HealthKitManager.shared.fetchLatestCarbs()
        refreshStatus()
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
