import FamilyControls
import SharedKit
import SwiftUI
import UserNotifications
import WidgetKit

// MARK: - Shared defaults

struct SettingsDefaults {
    static let highGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "HighGlucoseThreshold") as! String)!
    static let lowGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "LowGlucoseThreshold") as! String)!
    static let criticalGlucose = Double(Bundle.main.object(forInfoDictionaryKey: "CriticalGlucoseThreshold") as! String)!
    static let staleMinutes = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
    static let carbGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
    static let carbGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!
}

// MARK: - Top-level settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPassphraseChange = false
    @State private var showResetAlert = false
    @State private var showResetSuccess = false
    @State private var badgeMode: GlucoseBadgeMode
    @State private var shieldingEnabled: Bool
    @State private var demoEnabled: Bool
    @State private var glucoseUnit: GlucoseUnit
    @State private var nightscoutEnabled: Bool
    @State private var healthKitDelivering: Bool

    init() {
        let data = SharedDataManager.shared
        _badgeMode = State(initialValue: data.glucoseBadgeMode)
        _shieldingEnabled = State(initialValue: data.shieldingEnabled)
        _demoEnabled = State(initialValue: data.isMockModeEnabled)
        _glucoseUnit = State(initialValue: data.glucoseUnit)
        _nightscoutEnabled = State(initialValue: data.nightscoutEnabled)
        _healthKitDelivering = State(initialValue: data.healthKitDeliveringRecently)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AttentionRulesSettingsView()
                    } label: {
                        Label(String(localized: "settings.attentionRulesRow"), systemImage: "heart.text.clipboard")
                    }

                    NavigationLink {
                        AttentionChecksSettingsView()
                    } label: {
                        Label(String(localized: "settings.attentionChecksRow"), systemImage: "checklist")
                    }

                    NavigationLink {
                        ShieldingSettingsView()
                    } label: {
                        HStack {
                            Label(String(localized: "settings.shieldingHeader"), systemImage: "shield.lefthalf.filled")
                            Spacer()
                            Text(shieldingEnabled
                                ? String(localized: "settings.statusOn")
                                : String(localized: "settings.statusOff"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Picker(String(localized: "settings.glucoseUnit"), selection: Binding(
                        get: { glucoseUnit },
                        set: { newValue in
                            glucoseUnit = newValue
                            SharedDataManager.shared.glucoseUnit = newValue
                            SharedDataManager.shared.flush()
                            WidgetCenter.shared.reloadAllTimelines()
                            // The badge renders the glucose number in the
                            // display unit, so a unit flip must re-run the
                            // badge recompute — otherwise `.always` mode
                            // keeps showing the value in the old unit until
                            // the next fetch.
                            SharedDataManager.shared.refreshAttentionBadge()
                        }
                    )) {
                        Text("mmol/L").tag(GlucoseUnit.mmolL)
                        Text("mg/dL").tag(GlucoseUnit.mgdL)
                    }
                } footer: {
                    Text("settings.glucoseUnitFooter", tableName: "Localizable")
                }

                Section {
                    Picker(String(localized: "settings.glucoseBadge"), selection: $badgeMode) {
                        Text(String(localized: "settings.glucoseBadge.off")).tag(GlucoseBadgeMode.off)
                        Text(String(localized: "settings.glucoseBadge.always")).tag(GlucoseBadgeMode.always)
                        Text(String(localized: "settings.glucoseBadge.onlyWhenAttention")).tag(GlucoseBadgeMode.onlyWhenAttention)
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("settings.glucoseBadgeFooter", tableName: "Localizable")
                }

                Section {
                    Button {
                        showPassphraseChange = true
                    } label: {
                        Label(String(localized: KeychainManager.shared.hasPassphrase
                            ? "settings.changePassphrase"
                            : "settings.setPassphrase"), systemImage: "lock")
                    }
                }

                Section {
                    NavigationLink {
                        HealthKitSettingsView()
                    } label: {
                        HStack {
                            Label(String(localized: "settings.healthKit"), systemImage: "heart.text.square")
                            Spacer()
                            // Apple Health can't tell us whether read
                            // access is currently granted (iOS privacy-
                            // masks that for read-only requests), so we
                            // show "On" only when HK has delivered a
                            // recent sample — matching how the rest of
                            // the app classifies it as a real source
                            // (see `SharedDataManager.healthKitDeliveringRecently`).
                            // A revoked-in-Health-app source naturally
                            // flips back to "Off" once samples go stale.
                            Text(healthKitDelivering
                                ? String(localized: "settings.statusOn")
                                : String(localized: "settings.statusOff"))
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        NightscoutSettingsView()
                    } label: {
                        HStack {
                            Label(String(localized: "settings.nightscout"), systemImage: "cloud")
                            Spacer()
                            Text(nightscoutEnabled
                                ? String(localized: "settings.statusOn")
                                : String(localized: "settings.statusOff"))
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        MockDataSettingsView()
                    } label: {
                        HStack {
                            Label(String(localized: "settings.demoData"), systemImage: "flask")
                            Spacer()
                            Text(demoEnabled
                                ? String(localized: "settings.statusOn")
                                : String(localized: "settings.statusOff"))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("settings.dataSources", tableName: "Localizable")
                } footer: {
                    Text("settings.dataSourcesFooter", tableName: "Localizable")
                }

                Section {
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Label(String(localized: "settings.resetAll"), systemImage: "arrow.counterclockwise")
                            .foregroundStyle(BrandTint.red)
                    }
                }
            }
            .onAppear {
                let data = SharedDataManager.shared
                shieldingEnabled = data.shieldingEnabled
                demoEnabled = data.isMockModeEnabled
                nightscoutEnabled = data.nightscoutEnabled
                healthKitDelivering = data.healthKitDeliveringRecently
            }
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "settings.done")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPassphraseChange) {
                ChangePassphraseView()
            }
            .alert(String(localized: "settings.resetAll"), isPresented: $showResetAlert) {
                Button(String(localized: "settings.resetAll"), role: .destructive) {
                    SharedDataManager.shared.resetAllSettings()
                    badgeMode = .off
                    glucoseUnit = SharedDataManager.shared.glucoseUnit
                    shieldingEnabled = SharedDataManager.shared.shieldingEnabled
                    demoEnabled = false
                    ShieldManager.shared.reevaluateShields()
                    ActivityScheduler.shared.startMonitoring()
                    SharedDataManager.shared.refreshAttentionBadge()
                    WidgetCenter.shared.reloadAllTimelines()
                    showResetSuccess = true
                }
                Button(String(localized: "settings.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.resetAllConfirm"))
            }
            .alert(String(localized: "settings.resetAllSuccessTitle"), isPresented: $showResetSuccess) {
                Button(String(localized: "settings.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.resetAllSuccessMessage"))
            }
            .onChange(of: badgeMode) {
                SharedDataManager.shared.glucoseBadgeMode = badgeMode
                // `setBadgeCount` silently no-ops without notification auth,
                // so a user who picks a non-`.off` mode here without having
                // done the setup-checklist prompt would see no badge at all.
                // Request auth inline; iOS surfaces its own system sheet
                // and remembers prior answers, so re-prompting is cheap.
                if badgeMode != .off {
                    Task { @MainActor in
                        await Self.ensureBadgeAuthorization()
                        SharedDataManager.shared.refreshAttentionBadge()
                    }
                } else {
                    SharedDataManager.shared.refreshAttentionBadge()
                }
            }
        }
    }

    /// Request notification authorization with the badge bit if the user
    /// hasn't been prompted yet. No-op once the user has made a choice
    /// (granted or denied) — iOS no longer shows the sheet after the
    /// first response, so re-asking is harmless but also pointless.
    @MainActor
    private static func ensureBadgeAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }
}

// MARK: - Attention Rules

struct AttentionRulesSettingsView: View {
    @State private var highThreshold: Double
    @State private var lowThreshold: Double
    @State private var criticalThreshold: Double
    @State private var staleMinutes: Double
    @State private var carbGraceHour: Int
    @State private var carbGraceMinute: Int
    /// Surfaced when the user tries to drag `critical` at or below `high`,
    /// or when high is raised above critical. Cleared as soon as the values
    /// are coherent again. Drives the inline validation banner.
    @State private var criticalValidationError: String?

    private let unit: GlucoseUnit

    init() {
        let data = SharedDataManager.shared
        let u = data.glucoseUnit
        unit = u
        let highMmol = data.highGlucoseThreshold ?? SettingsDefaults.highGlucose
        let lowMmol = data.lowGlucoseThreshold ?? SettingsDefaults.lowGlucose
        let criticalMmol = data.criticalGlucoseThreshold ?? SettingsDefaults.criticalGlucose
        _highThreshold = State(initialValue: u.displayValue(highMmol))
        _lowThreshold = State(initialValue: u.displayValue(lowMmol))
        _criticalThreshold = State(initialValue: u.displayValue(criticalMmol))
        _staleMinutes = State(initialValue: Double(data.glucoseStaleMinutes ?? SettingsDefaults.staleMinutes))
        _carbGraceHour = State(initialValue: data.carbGraceHour ?? SettingsDefaults.carbGraceHour)
        _carbGraceMinute = State(initialValue: data.carbGraceMinute ?? SettingsDefaults.carbGraceMinute)
    }

    private var highRange: ClosedRange<Double> {
        switch unit {
        case .mmolL: return 8...25
        case .mgdL: return 144...450
        }
    }

    private var highStep: Double {
        unit == .mmolL ? 0.5 : 5
    }

    private var lowRange: ClosedRange<Double> {
        switch unit {
        case .mmolL: return 2...6
        case .mgdL: return 36...108
        }
    }

    private var lowStep: Double {
        unit == .mmolL ? 0.1 : 1
    }

    /// Critical range floor auto-bumps with `high` so the slider can't land
    /// at or below it. We keep the ceiling well above `highRange` so there's
    /// always somewhere to go.
    private var criticalRange: ClosedRange<Double> {
        let ceiling: Double = unit == .mmolL ? 33 : 600
        let step = highStep
        let floor = SettingsValidation.minimumCritical(above: highThreshold, step: step)
        return floor...max(ceiling, floor + step)
    }

    private var criticalStep: Double {
        highStep
    }

    private var thresholdFormat: String {
        unit == .mmolL ? "%.1f" : "%.0f"
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("settings.highThreshold", tableName: "Localizable")
                    Spacer()
                    Text(String(format: thresholdFormat, highThreshold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $highThreshold, in: highRange, step: highStep)

                HStack {
                    Text("settings.criticalThreshold", tableName: "Localizable")
                    Spacer()
                    Text(String(format: thresholdFormat, criticalThreshold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $criticalThreshold, in: criticalRange, step: criticalStep)

                if let criticalValidationError {
                    Label(criticalValidationError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(BrandTint.red)
                        .font(.caption)
                }

                HStack {
                    Text("settings.lowThreshold", tableName: "Localizable")
                    Spacer()
                    Text(String(format: thresholdFormat, lowThreshold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $lowThreshold, in: lowRange, step: lowStep)
            } header: {
                Text(String(localized: "settings.glucoseHeader \(unit.label)"))
            } footer: {
                Text("settings.criticalThresholdFooter", tableName: "Localizable")
            }

            Section {
                HStack {
                    Text("settings.staleMinutes", tableName: "Localizable")
                    Spacer()
                    Text(String(localized: "settings.minutesSuffix \(Int(staleMinutes))"))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $staleMinutes, in: 10...120, step: 5)
            } header: {
                Text("settings.dataHeader", tableName: "Localizable")
            }

            Section {
                DurationPicker(hours: $carbGraceHour, minutes: $carbGraceMinute)
                    .frame(height: 150)
            } header: {
                Text("settings.carbHeader", tableName: "Localizable")
            } footer: {
                Text("settings.carbGraceFooter", tableName: "Localizable")
            }
        }
        .navigationTitle(String(localized: "settings.attentionRulesRow"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: highThreshold) {
            // Raising `high` at or above `critical` violates the invariant;
            // auto-bump critical to the next legal step on the same grid so
            // the user never lands in an invalid state via the high slider.
            // The validation error still surfaces (and clears on save) so
            // the adjustment is not silent.
            let minCritical = SettingsValidation.minimumCritical(above: highThreshold, step: criticalStep)
            if criticalThreshold < minCritical {
                criticalThreshold = minCritical
            }
            saveAttentionRules()
        }
        .onChange(of: lowThreshold) { saveAttentionRules() }
        .onChange(of: criticalThreshold) { saveAttentionRules() }
        .onChange(of: staleMinutes) { saveAttentionRules() }
        .onChange(of: carbGraceHour) { saveAttentionRules() }
        .onChange(of: carbGraceMinute) { saveAttentionRules() }
    }

    private func saveAttentionRules() {
        let data = SharedDataManager.shared
        let highMmol = unit.toMmol(highThreshold)
        let criticalMmol = unit.toMmol(criticalThreshold)
        do {
            try SettingsValidation.validateCriticalAboveHigh(critical: criticalMmol, high: highMmol)
            criticalValidationError = nil
        } catch {
            // Per AGENTS.md → "Shared App Group Container" → validation
            // contract: surface the error, do not silently re-clamp. We
            // still persist the values so state is consistent; the Settings
            // UI keeps the banner visible until the user fixes it.
            criticalValidationError = String(localized: "settings.criticalValidationError")
        }
        data.saveSettings(
            highGlucoseThreshold: highMmol,
            lowGlucoseThreshold: unit.toMmol(lowThreshold),
            criticalGlucoseThreshold: criticalMmol,
            glucoseStaleMinutes: Int(staleMinutes),
            carbGraceHour: carbGraceHour,
            carbGraceMinute: carbGraceMinute,
            attentionIntervalMinutes: data.attentionIntervalMinutes ?? ActivityScheduler.defaultAttentionInterval,
            noAttentionIntervalMinutes: data.noAttentionIntervalMinutes ?? ActivityScheduler.defaultNoAttentionInterval,
            cooldownSeconds: data.cooldownSeconds ?? 60
        )
        // A threshold/grace tweak is an explicit user action — re-arm or
        // disarm shields immediately rather than waiting for the next
        // DeviceActivityMonitor interval. Mirrors `saveShielding()` and
        // keeps the badge in sync with the new rules.
        if data.shieldingEnabled {
            ShieldManager.shared.reevaluateShields()
        }
        data.refreshAttentionBadge()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Shielding

struct ShieldingSettingsView: View {
    @State private var selection: FamilyActivitySelection
    @State private var shieldingEnabled: Bool
    @State private var onlyWhenAttention: Bool
    @State private var attentionInterval: Double
    @State private var noAttentionInterval: Double
    @State private var isAuthorizing = false
    @State private var authError: String?
    @State private var hasAnyDataSource: Bool

    init() {
        let data = SharedDataManager.shared
        _selection = State(initialValue: data.loadSelection() ?? FamilyActivitySelection())
        _shieldingEnabled = State(initialValue: data.shieldingEnabled)
        _onlyWhenAttention = State(initialValue: data.onlyShieldWhenAttention)
        _attentionInterval = State(initialValue: Double(data.attentionIntervalMinutes ?? ActivityScheduler.defaultAttentionInterval))
        _noAttentionInterval = State(initialValue: Double(data.noAttentionIntervalMinutes ?? ActivityScheduler.defaultNoAttentionInterval))
        _hasAnyDataSource = State(initialValue: data.hasAnyDataSource)
    }

    /// FamilyControls is authorized iff we can talk to the ScreenTime API.
    /// This governs whether the app-selection picker is meaningful.
    private var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    var body: some View {
        List {
            Section {
                Toggle(String(localized: "settings.shieldingEnabled"), isOn: Binding(
                    get: { shieldingEnabled },
                    set: { newValue in
                        if newValue && !isAuthorized {
                            Task { await enableWithAuthorization() }
                        } else {
                            shieldingEnabled = newValue
                            saveShielding()
                        }
                    }
                ))
                .disabled(isAuthorizing || !hasAnyDataSource)

                if isAuthorizing {
                    HStack {
                        ProgressView()
                        Text("settings.shieldingAuthorizing", tableName: "Localizable")
                            .foregroundStyle(.secondary)
                    }
                }

                if let authError {
                    Label(authError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(BrandTint.red)
                        .font(.caption)
                }

                if shieldingEnabled {
                    Toggle(String(localized: "settings.onlyWhenAttention"), isOn: Binding(
                        get: { onlyWhenAttention },
                        set: { newValue in
                            onlyWhenAttention = newValue
                            SharedDataManager.shared.onlyShieldWhenAttention = newValue
                            SharedDataManager.shared.flush()
                            if shieldingEnabled {
                                ShieldManager.shared.reevaluateShields()
                                ActivityScheduler.shared.startMonitoring()
                            }
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    ))
                }
            } footer: {
                if !hasAnyDataSource {
                    Text("settings.shieldingRequiresDataSource", tableName: "Localizable")
                } else if !shieldingEnabled {
                    Text("settings.shieldingDisabledFooter", tableName: "Localizable")
                } else if !isAuthorized {
                    Text("settings.shieldingNotAuthorizedFooter", tableName: "Localizable")
                } else if onlyWhenAttention {
                    Text("settings.onlyWhenAttentionFooter", tableName: "Localizable")
                }
            }

            if shieldingEnabled && isAuthorized {
                Section {
                    FamilyActivityPicker(selection: $selection)
                        .frame(height: 400)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: -8, bottom: 0, trailing: -8))
                } header: {
                    Text("settings.excludedAppsHeader", tableName: "Localizable")
                } footer: {
                    Text("settings.excludedAppsFooter", tableName: "Localizable")
                }

                Section {
                    HStack {
                        Text("settings.attentionInterval", tableName: "Localizable")
                        Spacer()
                        Text(String(localized: "settings.minutesSuffix \(Int(attentionInterval))"))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $attentionInterval, in: 15...60, step: 5)

                    if !onlyWhenAttention {
                        HStack {
                            Text("settings.noAttentionInterval", tableName: "Localizable")
                            Spacer()
                            Text(String(localized: "settings.minutesSuffix \(Int(noAttentionInterval))"))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $noAttentionInterval, in: 15...120, step: 15)
                    }
                } header: {
                    Text("settings.intervalsHeader", tableName: "Localizable")
                } footer: {
                    Text("settings.intervalsFooter", tableName: "Localizable")
                }

            }
        }
        .navigationTitle(String(localized: "settings.shieldingHeader"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selection) { saveShielding() }
        .onChange(of: attentionInterval) { saveShielding() }
        .onChange(of: noAttentionInterval) { saveShielding() }
        .onAppear {
            // The user might have toggled a data source off in another
            // screen and navigated back here; pick up the latest state so
            // the toggle disables / re-enables correctly. `shieldingEnabled`
            // can also have been auto-flipped to false by
            // `ShieldManager.disableIfNoDataSource()`.
            let data = SharedDataManager.shared
            hasAnyDataSource = data.hasAnyDataSource
            shieldingEnabled = data.shieldingEnabled
        }
    }

    private func saveShielding() {
        let data = SharedDataManager.shared
        data.shieldingEnabled = shieldingEnabled
        data.onlyShieldWhenAttention = onlyWhenAttention

        try? data.saveSelection(selection)

        data.saveSettings(
            highGlucoseThreshold: data.highGlucoseThreshold ?? SettingsDefaults.highGlucose,
            lowGlucoseThreshold: data.lowGlucoseThreshold ?? SettingsDefaults.lowGlucose,
            criticalGlucoseThreshold: data.criticalGlucoseThreshold ?? SettingsDefaults.criticalGlucose,
            glucoseStaleMinutes: data.glucoseStaleMinutes ?? SettingsDefaults.staleMinutes,
            carbGraceHour: data.carbGraceHour ?? SettingsDefaults.carbGraceHour,
            carbGraceMinute: data.carbGraceMinute ?? SettingsDefaults.carbGraceMinute,
            attentionIntervalMinutes: Int(attentionInterval),
            noAttentionIntervalMinutes: Int(noAttentionInterval),
            cooldownSeconds: data.cooldownSeconds ?? 60
        )

        data.flush()

        if shieldingEnabled {
            ShieldManager.shared.reevaluateShields()
            ActivityScheduler.shared.startMonitoring()
        } else {
            ShieldManager.shared.removeShields()
            ActivityScheduler.shared.stopMonitoring()
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Ask iOS for FamilyControls authorization, trying `.child` first and
    /// falling back to `.individual` for adults without Family Sharing.
    /// Only flips `shieldingEnabled` to true if authorization succeeds.
    @MainActor
    private func enableWithAuthorization() async {
        isAuthorizing = true
        authError = nil
        defer { isAuthorizing = false }

        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .child)
            SharedDataManager.shared.authorizationMember = .child
        } catch {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                SharedDataManager.shared.authorizationMember = .individual
            } catch {
                authError = error.localizedDescription
                return
            }
        }

        shieldingEnabled = true
        saveShielding()
    }
}

// MARK: - Demo Data

struct MockDataSettingsView: View {
    @State private var mockEnabled: Bool
    @State private var hasGlucoseData: Bool
    @State private var mockGlucose: Double
    @State private var glucoseDate: Date
    @State private var hasCarbData: Bool
    @State private var mockCarbGrams: Double
    @State private var carbDate: Date

    private let unit: GlucoseUnit

    init() {
        let data = SharedDataManager.shared
        let u = data.glucoseUnit
        unit = u
        _mockEnabled = State(initialValue: data.isMockModeEnabled)
        _hasGlucoseData = State(initialValue: data.currentGlucose != nil)
        _mockGlucose = State(initialValue: u.displayValue(data.currentGlucose ?? 6.4))
        _glucoseDate = State(initialValue: data.glucoseFetchedAt ?? Date().addingTimeInterval(-5 * 60))
        _hasCarbData = State(initialValue: data.lastCarbGrams != nil)
        _mockCarbGrams = State(initialValue: data.lastCarbGrams ?? 20)
        _carbDate = State(initialValue: data.lastCarbEntryAt ?? Date().addingTimeInterval(-120 * 60))
    }

    var body: some View {
        List {
            Section {
                Toggle(String(localized: "settings.demoEnabled"), isOn: Binding(
                    get: { mockEnabled },
                    set: { newValue in
                        mockEnabled = newValue
                        if newValue && !hasGlucoseData && !hasCarbData {
                            hasGlucoseData = true
                            hasCarbData = true
                            mockGlucose = unit.displayValue(6.4)
                            glucoseDate = Date().addingTimeInterval(-5 * 60)
                            mockCarbGrams = 20
                            carbDate = Date().addingTimeInterval(-120 * 60)
                        }
                        saveMockData()
                    }
                ))
            } footer: {
                Text("settings.demoFooter", tableName: "Localizable")
            }

            if mockEnabled {
                Section {
                    Toggle(String(localized: "settings.demoHasData"), isOn: Binding(
                        get: { hasGlucoseData },
                        set: { newValue in
                            hasGlucoseData = newValue
                            saveMockData()
                        }
                    ))
                    if hasGlucoseData {
                        HStack {
                            Slider(
                                value: $mockGlucose,
                                in: unit == .mmolL ? 2...25 : 36...450,
                                step: unit == .mmolL ? 0.1 : 1
                            )
                            Text(String(format: unit == .mmolL ? "%.1f" : "%.0f", mockGlucose)).monospacedDigit()
                        }
                        DatePicker(
                            String(localized: "settings.demoAt"),
                            selection: $glucoseDate,
                            in: ...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                } header: {
                    Text(String(localized: "settings.demoGlucose"))
                }

                Section {
                    Toggle(String(localized: "settings.demoHasData"), isOn: Binding(
                        get: { hasCarbData },
                        set: { newValue in
                            hasCarbData = newValue
                            saveMockData()
                        }
                    ))
                    if hasCarbData {
                        HStack {
                            Slider(value: $mockCarbGrams, in: 0...100, step: 1)
                            Text("\(Int(mockCarbGrams))g").monospacedDigit()
                        }
                        DatePicker(
                            String(localized: "settings.demoAt"),
                            selection: $carbDate,
                            in: ...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                } header: {
                    Text(String(localized: "settings.demoCarbs"))
                }
            }
        }
        .navigationTitle(String(localized: "settings.demoData"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mockGlucose) { saveMockData() }
        .onChange(of: glucoseDate) { saveMockData() }
        .onChange(of: mockCarbGrams) { saveMockData() }
        .onChange(of: carbDate) { saveMockData() }
    }

    private func saveMockData() {
        let data = SharedDataManager.shared
        if mockEnabled {
            data.isMockModeEnabled = true

            if hasGlucoseData {
                data.saveGlucose(
                    mmol: unit.toMmol(mockGlucose),
                    at: glucoseDate,
                    force: true
                )
            } else {
                data.clearGlucoseData()
            }

            if hasCarbData {
                data.saveCarbs(
                    grams: mockCarbGrams,
                    at: carbDate,
                    force: true
                )
            } else {
                data.clearCarbData()
            }
        } else if data.isMockModeEnabled {
            // `clearMockData` only wipes the cached values when no other
            // in-app source is enabled (Nightscout/Demo share the same
            // App Group keys as live sources). In that case, kick HK
            // too — if it's still authorized and delivering, the UI
            // repopulates within seconds; otherwise the cleared state
            // is honest and HomeView returns to the welcome panel.
            data.clearMockData()
            // Disable shielding too if Demo was the last live source —
            // there's nothing left to base attention decisions on.
            ShieldManager.shared.disableIfNoDataSource()
            // Kick remaining live sources so the user sees their data
            // immediately instead of waiting for the next poll cycle.
            Task {
                if data.nightscoutEnabled {
                    await NightscoutManager.shared.fetchAll()
                }
                await HealthKitManager.shared.refreshIfAuthorized()
            }
        }
        WatchSessionManager.shared.sendLatestContext()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Nightscout

struct NightscoutSettingsView: View {
    @State private var enabled: Bool
    @State private var baseURL: String
    @State private var token: String
    @State private var lastFetchedAt: Date?
    @State private var lastError: String?
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult: Equatable {
        case success(version: String?, units: String?)
        case failure(String)
    }

    init() {
        let data = SharedDataManager.shared
        _enabled = State(initialValue: data.nightscoutEnabled)
        _baseURL = State(initialValue: data.nightscoutBaseURL ?? "")
        _token = State(initialValue: data.nightscoutToken ?? "")
        _lastFetchedAt = State(initialValue: data.nightscoutLastFetchedAt)
        _lastError = State(initialValue: data.nightscoutLastError)
    }

    /// Toggling Nightscout on is only allowed once both URL and token have
    /// been provided — the integration is unusable without them.
    private var hasCredentials: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        List {
            Section {
                TextField(
                    String(localized: "settings.nightscoutURLPlaceholder"),
                    text: $baseURL
                )
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                SecureField(
                    String(localized: "settings.nightscoutTokenPlaceholder"),
                    text: $token
                )
                .textContentType(.password)
            } header: {
                Text("settings.nightscoutConfigHeader", tableName: "Localizable")
            } footer: {
                Text("settings.nightscoutConfigFooter", tableName: "Localizable")
            }

            Section {
                HStack {
                    Toggle(String(localized: "settings.nightscoutEnabled"), isOn: Binding(
                        get: { enabled && hasCredentials },
                        set: { newValue in
                            if newValue {
                                Task { await enableWithVerification() }
                            } else {
                                disable()
                            }
                        }
                    ))
                    .disabled(!hasCredentials || isTesting)
                    if isTesting {
                        ProgressView()
                    }
                }
            } footer: {
                if !hasCredentials {
                    Text("settings.nightscoutRequiresCredentials", tableName: "Localizable")
                } else if isTesting {
                    Text("settings.nightscoutVerifying", tableName: "Localizable")
                } else {
                    Text("settings.nightscoutFooter", tableName: "Localizable")
                }
            }
            .onChange(of: hasCredentials) { _, newValue in
                // Clearing URL or token while enabled force-disables to keep
                // the manager from polling with invalid config.
                if !newValue, enabled {
                    disable()
                }
            }

            Section {
                Button {
                    Task { await runConnectionTest() }
                } label: {
                    HStack {
                        Label(String(localized: "settings.nightscoutTest"), systemImage: "network")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isTesting || !hasCredentials)

                if let testResult {
                    switch testResult {
                    case let .success(version, units):
                        VStack(alignment: .leading, spacing: 2) {
                            Label(String(localized: "settings.nightscoutTestSuccess"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(BrandTint.green)
                            if let version {
                                Text(String(localized: "settings.nightscoutVersion \(version)"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let units {
                                Text(String(localized: "settings.nightscoutUnits \(units)"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    case let .failure(message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(BrandTint.red)
                    }
                }
            }

            Section {
                if let lastFetchedAt {
                    HStack {
                        Text("settings.nightscoutLastFetch", tableName: "Localizable")
                        Spacer()
                        Text(lastFetchedAt, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                } else if enabled {
                    Text("settings.nightscoutAwaitingFirstUpdate", tableName: "Localizable")
                        .foregroundStyle(.secondary)
                } else if hasCredentials {
                    Text("settings.nightscoutDisabled", tableName: "Localizable")
                        .foregroundStyle(.secondary)
                } else {
                    Text("settings.nightscoutNotConfigured", tableName: "Localizable")
                        .foregroundStyle(.secondary)
                }
                if let lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(BrandTint.orange)
                        .font(.caption)
                }
            } header: {
                Text("settings.nightscoutStatusHeader", tableName: "Localizable")
            }
        }
        .navigationTitle(String(localized: "settings.nightscout"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Periodically refresh status fields so a fetch completed in the
            // background shows up here without forcing the user to leave and
            // re-enter the screen.
            while !Task.isCancelled {
                refreshStatusFields()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .onDisappear {
            persistFields()
        }
    }

    private func refreshStatusFields() {
        lastFetchedAt = SharedDataManager.shared.nightscoutLastFetchedAt
        lastError = SharedDataManager.shared.nightscoutLastError
    }

    private func persistFields() {
        let data = SharedDataManager.shared
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlChanged = data.nightscoutBaseURL != (trimmedURL.isEmpty ? nil : trimmedURL)
        let tokenChanged = data.nightscoutToken != (trimmedToken.isEmpty ? nil : trimmedToken)
        data.nightscoutBaseURL = trimmedURL.isEmpty ? nil : trimmedURL
        data.nightscoutToken = trimmedToken.isEmpty ? nil : trimmedToken
        data.flush()
        if urlChanged || tokenChanged {
            NightscoutManager.shared.configurationDidChange()
            WatchSessionManager.shared.sendLatestContext()
        }
    }

    private func runConnectionTest() async {
        _ = await verifyConnection()
    }

    /// Hits `/status` and updates `testResult`. Returns true on success.
    private func verifyConnection() async -> Bool {
        persistFields()
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let status = try await NightscoutManager.shared.testConnection(
                baseURL: trimmedURL,
                token: trimmedToken.isEmpty ? nil : trimmedToken
            )
            testResult = .success(version: status.version, units: status.units)

            // Auto-detect glucose unit from server when user hasn't picked one.
            if !SharedDataManager.shared.hasGlucoseUnitPreference {
                if let units = status.units?.lowercased() {
                    SharedDataManager.shared.glucoseUnit = units.contains("mg") ? .mgdL : .mmolL
                }
            }
            return true
        } catch {
            testResult = .failure(error.localizedDescription)
            return false
        }
    }

    /// Verifies the connection and only flips the toggle on if it succeeds.
    /// On failure the toggle stays off and the failure message is shown
    /// inline.
    private func enableWithVerification() async {
        guard await verifyConnection() else { return }
        enabled = true
        SharedDataManager.shared.nightscoutEnabled = true
        SharedDataManager.shared.flush()
        NightscoutManager.shared.startPolling()
        // Await the first fetch so the Status section reflects real data
        // immediately instead of "awaiting first update".
        await NightscoutManager.shared.fetchAll()
        WatchSessionManager.shared.sendLatestContext()
        refreshStatusFields()
    }

    private func disable() {
        enabled = false
        let data = SharedDataManager.shared
        data.nightscoutEnabled = false
        data.flush()
        NightscoutManager.shared.configurationDidChange()
        // Wipe Nightscout's last cached values when no other in-app
        // source remains — otherwise the home screen keeps showing the
        // disabled source's stale data with a green status. Live HK
        // (if any) will repopulate via the kick below.
        data.handleInAppSourceDisabled()
        // Disabling the last data source must also disable shielding —
        // there's nothing left to base attention decisions on.
        ShieldManager.shared.disableIfNoDataSource()
        // Kick HK so users running HK-as-fallback see their data
        // immediately instead of waiting for the next observer fire.
        Task { await HealthKitManager.shared.refreshIfAuthorized() }
        WatchSessionManager.shared.sendLatestContext()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Attention Checks

struct AttentionChecksSettingsView: View {
    @State private var checks: [AttentionScenario: [String]]
    @State private var showRestoreAlert = false

    static let defaultChecks: [AttentionScenario: [String]] = {
        ShieldContent.Strings.fromPackage().scenarioChecks
    }()

    init() {
        let data = SharedDataManager.shared
        var initial: [AttentionScenario: [String]] = [:]
        for scenario in AttentionScenario.allCases {
            initial[scenario] = data.customChecks(for: scenario) ?? Self.defaultChecks[scenario] ?? []
        }
        _checks = State(initialValue: initial)
    }

    var body: some View {
        List {
            ForEach(AttentionScenario.allCases) { scenario in
                Section {
                    checksRows(for: scenario)

                    Button {
                        checks[scenario, default: []].append("")
                    } label: {
                        Label(String(localized: "settings.addCheck"), systemImage: "plus.circle")
                    }
                } header: {
                    Text(scenarioName(scenario))
                }
            }
        }
        .navigationTitle(String(localized: "settings.attentionChecksRow"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button(String(localized: "settings.restoreDefaults"), role: .destructive) {
                    showRestoreAlert = true
                }
            }
        }
        .alert(String(localized: "settings.restoreDefaults"), isPresented: $showRestoreAlert) {
            Button(String(localized: "settings.restoreDefaults"), role: .destructive) {
                restoreDefaults()
            }
            Button(String(localized: "settings.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.restoreDefaultsConfirm"))
        }
        .onDisappear { saveAll() }
    }

    @ViewBuilder
    private func checksRows(for scenario: AttentionScenario) -> some View {
        let items = checks[scenario] ?? []
        ForEach(items.indices, id: \.self) { index in
            TextField(
                String(localized: "settings.checkPlaceholder"),
                text: Binding(
                    get: {
                        guard let items = checks[scenario], index < items.count else { return "" }
                        return items[index]
                    },
                    set: { newValue in
                        guard checks[scenario] != nil, index < (checks[scenario]?.count ?? 0) else { return }
                        checks[scenario]?[index] = newValue
                    }
                )
            )
        }
        .onDelete { offsets in
            checks[scenario]?.remove(atOffsets: offsets)
            save(scenario)
        }
    }

    private func scenarioName(_ scenario: AttentionScenario) -> String {
        switch scenario {
        case .highGlucose: return String(localized: "settings.scenario.highGlucose")
        case .criticalGlucose: return String(localized: "settings.scenario.criticalGlucose")
        case .lowGlucose: return String(localized: "settings.scenario.lowGlucose")
        case .staleSensor: return String(localized: "settings.scenario.staleSensor")
        case .carbGap: return String(localized: "settings.scenario.carbGap")
        case .noGlucoseData: return String(localized: "settings.scenario.noGlucoseData")
        case .noCarbData: return String(localized: "settings.scenario.noCarbData")
        }
    }

    private func save(_ scenario: AttentionScenario) {
        let items = (checks[scenario] ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        SharedDataManager.shared.saveCustomChecks(items.isEmpty ? nil : items, for: scenario)
    }

    private func saveAll() {
        for scenario in AttentionScenario.allCases {
            save(scenario)
        }
    }

    private func restoreDefaults() {
        SharedDataManager.shared.clearAllCustomChecks()
        var restored: [AttentionScenario: [String]] = [:]
        for scenario in AttentionScenario.allCases {
            restored[scenario] = Self.defaultChecks[scenario] ?? []
        }
        checks = restored
    }
}

// MARK: - Change Passphrase

struct ChangePassphraseView: View {
    @Environment(\.dismiss) private var dismiss

    private let hasExisting = KeychainManager.shared.hasPassphrase
    private let isChildMode = SharedDataManager.shared.authorizationMember == .child

    @State private var current = ""
    @State private var newPassphrase = ""
    @State private var confirm = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(String(localized: hasExisting
                    ? "passphrase.changeDescription"
                    : (isChildMode ? "passphrase.setDescriptionChild" : "passphrase.setDescriptionAdult")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if hasExisting {
                    SecureField(String(localized: "settings.currentPassphrase"), text: $current)
                        .textContentType(.password)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                SecureField(String(localized: hasExisting ? "settings.newPassphrase" : "setup.passphraseField"), text: $newPassphrase)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                SecureField(String(localized: "setup.passphraseConfirmField"), text: $confirm)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(BrandTint.red)
                        .font(.caption)
                }

                if hasExisting {
                    Button(String(localized: "settings.removePassphrase"), role: .destructive) {
                        removePassphrase()
                    }
                    .disabled(current.isEmpty)
                }

                Text(String(localized: "passphrase.forgotWarning"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                Spacer()
            }
            .padding(32)
            .navigationTitle(String(localized: "passphrase.title.short"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "settings.save")) { save() }
                        .disabled((hasExisting && current.isEmpty) || newPassphrase.isEmpty || newPassphrase != confirm)
                }
            }
        }
    }

    private func save() {
        if hasExisting {
            guard KeychainManager.shared.verify(current) else {
                errorMessage = String(localized: "settings.wrongPassphrase")
                return
            }
        }
        guard newPassphrase == confirm else {
            errorMessage = String(localized: "setup.passphraseMismatch")
            return
        }
        KeychainManager.shared.setPassphrase(newPassphrase)
        dismiss()
    }

    private func removePassphrase() {
        guard KeychainManager.shared.verify(current) else {
            errorMessage = String(localized: "settings.wrongPassphrase")
            return
        }
        KeychainManager.shared.removePassphrase()
        dismiss()
    }
}

// MARK: - Duration Picker (countdown timer style)

struct DurationPicker: UIViewRepresentable {
    @Binding var hours: Int
    @Binding var minutes: Int

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .countDownTimer
        picker.minuteInterval = 5
        picker.countDownDuration = TimeInterval(hours * 3600 + minutes * 60)
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        let duration = TimeInterval(hours * 3600 + minutes * 60)
        if picker.countDownDuration != duration {
            picker.countDownDuration = duration
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        let parent: DurationPicker
        init(_ parent: DurationPicker) { self.parent = parent }

        @objc func changed(_ picker: UIDatePicker) {
            let total = Int(picker.countDownDuration)
            parent.hours = total / 3600
            parent.minutes = (total % 3600) / 60
        }
    }
}
