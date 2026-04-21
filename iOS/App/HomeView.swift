import Combine
import HealthKit
import SharedKit
import SwiftUI

/// The app's main screen. Shown unconditionally — no more "setup vs active"
/// branching. Renders:
///
/// - A welcome panel when no data source has been configured and no glucose
///   data has ever arrived. This doubles as the first-launch experience.
/// - Otherwise, the status panel (glucose + carbs + optional check-in flow)
///   that `ShieldingActiveView` used to show.
/// - The `SetupChecklistCard` below everything, surfacing optional
///   next-step setup until the user configures or dismisses each item.
struct HomeView: View {
    @State private var showSettings = false

    #if targetEnvironment(simulator)
    @State private var glucose: Double = 6.4
    @State private var glucoseMinutesAgo: Double = 5
    @State private var carbGrams: Double = 20
    @State private var carbMinutesAgo: Double = 120
    @State private var hasGlucoseData = true
    @State private var hasCarbData = true
    @State private var overrideTime = false
    @State private var mockHour: Double = Double(Calendar.current.component(.hour, from: Date()))
    @State private var mockMinute: Double = Double(Calendar.current.component(.minute, from: Date()))
    @State private var showMockControls = false
    @State private var mockDisarmed = false
    @State private var mockShieldingEnabled = true
    #endif

    @State private var tick = Date()
    @State private var pinnedTitle: String?
    @State private var pinnedNeedsAttention: Bool?
    @State private var isDisarmed: Bool
    @State private var checklistRefreshToken = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Height reserved for the fixed icon header at the top. Content scrolls
    /// underneath it and fades out as it approaches.
    private static let headerHeight: CGFloat = 160

    /// Vertical region of the scroll view where content fades out as it
    /// scrolls up under the icon. Larger than `headerHeight` so the fade
    /// kicks in well before content reaches the icon itself.
    private static let fadeHeight: CGFloat = 200

    /// Vertical region above the bottom edge where scrollable content fades
    /// out. Without this, rows near the home indicator look sharply
    /// guillotined; with it, content visibly slides under the bottom safe
    /// area as the user scrolls.
    private static let bottomFadeHeight: CGFloat = 48

    private static let highGlucoseThreshold = Double(Bundle.main.object(forInfoDictionaryKey: "HighGlucoseThreshold") as! String)!
    private static let lowGlucoseThreshold = Double(Bundle.main.object(forInfoDictionaryKey: "LowGlucoseThreshold") as! String)!
    private static let glucoseStaleMinutes = Int(Bundle.main.object(forInfoDictionaryKey: "GlucoseStaleMinutes") as! String)!
    private static let carbGraceHour = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceHour") as! String)!
    private static let carbGraceMinute = Int(Bundle.main.object(forInfoDictionaryKey: "CarbGraceMinute") as! String)!

    init() {
        #if targetEnvironment(simulator)
        _isDisarmed = State(initialValue: false)

        if let preset = ScreenshotHarness.current?.homeViewPreset {
            _glucose = State(initialValue: preset.glucose)
            _glucoseMinutesAgo = State(initialValue: preset.glucoseMinutesAgo)
            _carbGrams = State(initialValue: preset.carbGrams)
            _carbMinutesAgo = State(initialValue: preset.carbMinutesAgo)
            _hasGlucoseData = State(initialValue: preset.hasGlucoseData)
            _hasCarbData = State(initialValue: preset.hasCarbData)
            _mockShieldingEnabled = State(initialValue: preset.shieldingEnabled)
            _mockDisarmed = State(initialValue: preset.disarmed)
        }
        #else
        _isDisarmed = State(initialValue: SharedDataManager.shared.isShieldDisarmed)
        #endif
    }

    private var content: ShieldContent {
        let _ = tick
        let strings = ShieldContent.Strings.fromPackage()

        #if targetEnvironment(simulator)
        let now = overrideTime
            ? Calendar.current.date(bySettingHour: Int(mockHour), minute: Int(mockMinute), second: 0, of: Date())!
            : Date()
        let glucoseDate: Date? = hasGlucoseData
            ? now.addingTimeInterval(-glucoseMinutesAgo * 60)
            : nil
        let carbDate: Date? = hasCarbData
            ? now.addingTimeInterval(-carbMinutesAgo * 60)
            : nil
        return ShieldContent(
            glucose: hasGlucoseData ? glucose : 0,
            glucoseFetchedAt: glucoseDate,
            lastCarbGrams: hasCarbData ? carbGrams : nil,
            lastCarbEntryAt: carbDate,
            highGlucoseThreshold: Self.highGlucoseThreshold,
            lowGlucoseThreshold: Self.lowGlucoseThreshold,
            glucoseStaleMinutes: Self.glucoseStaleMinutes,
            carbGraceHour: Self.carbGraceHour,
            carbGraceMinute: Self.carbGraceMinute,
            glucoseUnit: SharedDataManager.shared.glucoseUnit,
            strings: strings,
            now: now
        )
        #else
        let data = SharedDataManager.shared
        return ShieldContent(
            glucose: data.currentGlucose ?? 0,
            glucoseFetchedAt: data.glucoseFetchedAt,
            lastCarbGrams: data.lastCarbGrams,
            lastCarbEntryAt: data.lastCarbEntryAt,
            highGlucoseThreshold: Self.highGlucoseThreshold,
            lowGlucoseThreshold: Self.lowGlucoseThreshold,
            glucoseStaleMinutes: Self.glucoseStaleMinutes,
            carbGraceHour: Self.carbGraceHour,
            carbGraceMinute: Self.carbGraceMinute,
            glucoseUnit: data.glucoseUnit,
            customChecks: data.allCustomChecks(),
            strings: strings
        )
        #endif
    }

    /// True when the user hasn't hooked up any data source yet and has no
    /// glucose history. Drives the welcome/empty state so the first-launch
    /// screen explains what to do instead of showing "--".
    private var showsWelcome: Bool {
        #if targetEnvironment(simulator)
        if let preset = ScreenshotHarness.current?.homeViewPreset {
            return preset.forceWelcome
        }
        return false
        #else
        let data = SharedDataManager.shared
        let healthKitAsked = HKHealthStore()
            .authorizationStatus(for: HKQuantityType(.bloodGlucose)) != .notDetermined
        let hasDataSource = data.nightscoutEnabled || healthKitAsked || data.isMockModeEnabled
        let hasAnyGlucose = data.currentGlucose != nil
        return !hasDataSource && !hasAnyGlucose
        #endif
    }

    var body: some View {
        let _ = checklistRefreshToken
        let currentContent = content
        let effectiveShieldingEnabled: Bool = {
            #if targetEnvironment(simulator)
            return mockShieldingEnabled
            #else
            return SharedDataManager.shared.shieldingEnabled
            #endif
        }()
        let shieldsArmed: Bool = {
            #if targetEnvironment(simulator)
            return mockShieldingEnabled && !mockDisarmed
            #else
            if !effectiveShieldingEnabled { return false }
            if !currentContent.needsAttention { return false }
            if isDisarmed { return false }
            return true
            #endif
        }()

        ZStack(alignment: .top) {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    if showsWelcome {
                        welcomePanel
                    } else {
                        statusPanel(
                            content: currentContent,
                            shieldingEnabled: effectiveShieldingEnabled,
                            shieldsArmed: shieldsArmed
                        )
                    }

                    SetupChecklistCard(refreshToken: $checklistRefreshToken)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Self.headerHeight)
                .padding(.bottom, Self.bottomFadeHeight)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .bottom)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.0), location: 0.4),
                            .init(color: .black, location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: Self.fadeHeight)
                    Rectangle().fill(.black)
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: Self.bottomFadeHeight)
                }
                .ignoresSafeArea()
            )

            iconHeader(
                content: currentContent,
                shieldingEnabled: effectiveShieldingEnabled,
                shieldsArmed: shieldsArmed
            )
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .padding(12)
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { checklistRefreshToken &+= 1 }) {
            PassphrasePromptView()
        }
        #if targetEnvironment(simulator)
        .overlay(alignment: .bottomTrailing) {
            if !ScreenshotHarness.isActive {
                Button {
                    showMockControls = true
                } label: {
                    Image(systemName: "ladybug")
                        .font(.title2)
                        .padding(12)
                }
            }
        }
        .sheet(isPresented: $showMockControls) {
            mockControlsSheet
        }
        #endif
        .onAppear {
            pinTitleIfNeeded()
            refreshDisarmedState()
            SharedDataManager.shared.refreshAttentionBadge()
            checklistRefreshToken &+= 1
        }
        .onChange(of: currentContent.needsAttention) {
            pinnedTitle = nil
            pinTitleIfNeeded()
            SharedDataManager.shared.refreshAttentionBadge()
        }
        .onReceive(timer) {
            tick = $0
            refreshDisarmedState()
        }
    }

    // MARK: - Icon Header

    /// Fixed-position app icon pinned at the top. Sized to match
    /// `headerHeight` so the scroll view's top padding reserves space for it.
    /// Uses the same icon + shield badge the panels used to render inline.
    @ViewBuilder
    private func iconHeader(content: ShieldContent, shieldingEnabled: Bool, shieldsArmed: Bool) -> some View {
        ZStack(alignment: .bottom) {
            Image(iconName(for: content))
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22))

            if !showsWelcome && shieldingEnabled {
                Image(systemName: shieldsArmed ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(shieldsArmed ? Color.red : Color.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .offset(y: 14)
            }
        }
        .padding(.top, 24)
        .frame(height: Self.headerHeight, alignment: .top)
    }

    // MARK: - Welcome Panel

    private var welcomePanel: some View {
        VStack(spacing: 12) {
            Text("home.welcome.title \(Constants.displayName)", tableName: "Localizable")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("home.welcome.tagline \(Constants.displayName)", tableName: "Localizable")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Status Panel

    @ViewBuilder
    private func statusPanel(content: ShieldContent, shieldingEnabled: Bool, shieldsArmed: Bool) -> some View {
        VStack(spacing: 20) {
            Text(pinnedTitle ?? content.title)
                .font(.title.bold())
                .foregroundStyle(Color(.label))

            statusSummaryView(content: content)
                .padding(.horizontal, 32)

            if content.needsAttention && !content.attentionItems.isEmpty {
                if shieldsArmed {
                    CheckInView(items: content.attentionItems) {
                        handleDisarm()
                    }
                } else if shieldingEnabled && isDisarmed {
                    CheckInAcknowledgedView(items: content.attentionItems)
                } else {
                    AttentionListView(items: content.attentionItems)
                }
            }
        }
    }

    @ViewBuilder
    private func statusSummaryView(content: ShieldContent) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.secondary)
                Text(glucoseValueText(for: content))
                    .font(.subheadline.weight(.semibold))
                Text("•")
                    .foregroundStyle(.tertiary)
                relativeTimeText(from: glucoseDate, hasData: content.glucoseValue > 0, fallback: strings.glucoseNoData)
                    .font(.subheadline)
                if content.glucoseValue > 0, glucoseDate != nil {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    absoluteTimeText(from: glucoseDate, hasData: true)
                        .font(.subheadline)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "fork.knife")
                    .foregroundStyle(.secondary)
                Text(carbValueText(for: content))
                    .font(.subheadline.weight(.semibold))
                Text("•")
                    .foregroundStyle(.tertiary)
                relativeTimeText(from: carbDate, hasData: content.carbGrams != nil, fallback: strings.carbsNoData)
                    .font(.subheadline)
                if content.carbGrams != nil, carbDate != nil {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    absoluteTimeText(from: carbDate, hasData: true)
                        .font(.subheadline)
                }
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Color(.secondaryLabel))
    }

    private var strings: ShieldContent.Strings {
        ShieldContent.Strings.fromPackage()
    }

    private var glucoseDate: Date? {
        #if targetEnvironment(simulator)
        let now = overrideTime
            ? Calendar.current.date(bySettingHour: Int(mockHour), minute: Int(mockMinute), second: 0, of: Date())!
            : Date()
        return hasGlucoseData ? now.addingTimeInterval(-glucoseMinutesAgo * 60) : nil
        #else
        return SharedDataManager.shared.glucoseFetchedAt
        #endif
    }

    private var carbDate: Date? {
        #if targetEnvironment(simulator)
        let now = overrideTime
            ? Calendar.current.date(bySettingHour: Int(mockHour), minute: Int(mockMinute), second: 0, of: Date())!
            : Date()
        return hasCarbData ? now.addingTimeInterval(-carbMinutesAgo * 60) : nil
        #else
        return SharedDataManager.shared.lastCarbEntryAt
        #endif
    }

    private func glucoseValueText(for content: ShieldContent) -> String {
        "\(content.glucoseValue > 0 ? content.formattedGlucose : "--") \(content.glucoseUnitLabel)"
    }

    private func carbValueText(for content: ShieldContent) -> String {
        "\(content.carbGrams.map(String.init) ?? "--") g"
    }

    private func relativeTimeText(from date: Date?, hasData: Bool, fallback: String) -> Text {
        guard hasData, let date else { return Text(fallback) }
        return Text(date, style: .relative)
    }

    private func absoluteTimeText(from date: Date?, hasData: Bool) -> Text {
        guard hasData, let date else { return Text("") }
        return Text(date, style: .time)
    }

    private func handleDisarm() {
        #if targetEnvironment(simulator)
        withAnimation { mockDisarmed = true }
        #else
        ShieldManager.shared.disarmShields()
        withAnimation { isDisarmed = true }
        #endif
    }

    private func refreshDisarmedState() {
        #if !targetEnvironment(simulator)
        let current = SharedDataManager.shared.isShieldDisarmed
        if current != isDisarmed {
            withAnimation { isDisarmed = current }
        }
        #endif
    }

    private func iconName(for content: ShieldContent) -> String {
        if showsWelcome { return "AppIcon-Blue" }
        return content.needsAttention ? "AppIcon-Red" : "AppIcon-Green"
    }

    private func pinTitleIfNeeded() {
        let c = content
        if pinnedNeedsAttention != c.needsAttention {
            pinnedTitle = c.title
            pinnedNeedsAttention = c.needsAttention
        }
    }

    #if targetEnvironment(simulator)
    private var mockControlsSheet: some View {
        NavigationStack {
            List {
                Section("Glucose") {
                    Toggle("Has glucose data", isOn: $hasGlucoseData)
                    if hasGlucoseData {
                        HStack {
                            Text("Value")
                            Slider(value: $glucose, in: 2...25, step: 0.1)
                            Text(String(format: "%.1f", glucose)).monospacedDigit()
                        }
                        HStack {
                            Text("Minutes ago")
                            Slider(value: $glucoseMinutesAgo, in: 0...60, step: 1)
                            Text("\(Int(glucoseMinutesAgo))m").monospacedDigit()
                        }
                    }
                }

                Section("Carbs") {
                    Toggle("Has carb data", isOn: $hasCarbData)
                    if hasCarbData {
                        HStack {
                            Text("Grams")
                            Slider(value: $carbGrams, in: 1...100, step: 1)
                            Text("\(Int(carbGrams))g").monospacedDigit()
                        }
                        HStack {
                            Text("Minutes ago")
                            Slider(value: $carbMinutesAgo, in: 0...480, step: 5)
                            Text("\(Int(carbMinutesAgo))m").monospacedDigit()
                        }
                    }
                }

                Section("Time Override") {
                    Toggle("Override time", isOn: $overrideTime)
                    if overrideTime {
                        HStack {
                            Text("Hour")
                            Slider(value: $mockHour, in: 0...23, step: 1)
                            Text(String(format: "%02d", Int(mockHour))).monospacedDigit()
                        }
                        HStack {
                            Text("Minute")
                            Slider(value: $mockMinute, in: 0...59, step: 1)
                            Text(String(format: "%02d", Int(mockMinute))).monospacedDigit()
                        }
                    }
                }

                Section("Shield State") {
                    Toggle("Shielding enabled", isOn: $mockShieldingEnabled)
                    Toggle("Disarmed (checked in)", isOn: $mockDisarmed)
                }
            }
            .navigationTitle("Mock Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showMockControls = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
    #endif
}
