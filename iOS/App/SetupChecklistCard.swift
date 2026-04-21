import HealthKit
import SwiftUI
import UserNotifications

/// Card shown on `HomeView` that surfaces optional-but-encouraged setup steps.
///
/// Each row opens the same settings detail view used from Settings, so there's
/// zero UI duplication — this view is pure presentation. Rows disappear once
/// their underlying feature is configured. The whole card hides when all rows
/// are satisfied or when the user taps "Hide setup tips" (persisted).
///
/// Rows are split into two groups so the user understands the choice they're
/// making:
///
/// 1. **Data sources** — Apple Health (preferred), Nightscout (fallback /
///    remote-monitoring), Demo (try-the-app-without-a-sensor). The data-source
///    group hides as soon as any one of them is hooked up; the rest are
///    alternatives, not additional steps.
/// 2. **Recommended** — shielding, passphrase, notifications. Independent of
///    each other; each row sticks around until configured.
struct SetupChecklistCard: View {
    /// Ping this to force a state recompute (e.g. after a sheet is dismissed
    /// and the underlying feature may have changed).
    @Binding var refreshToken: Int

    @State private var presentedSheet: ChecklistSheet?
    @State private var isRequestingNotifications = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var healthKitStatus: HKAuthorizationStatus
    @State private var hasPassphrase: Bool
    @State private var shieldingEnabled: Bool
    /// Mirror of `SharedDataManager.nightscoutEnabled` so SwiftUI actually
    /// re-renders this card when Nightscout flips on/off. Without this the
    /// data-source group keeps showing all three rows after the user
    /// connects Nightscout from a sheet (no observed @State changes →
    /// no body recompute → stale layout).
    @State private var nightscoutEnabled: Bool
    /// Mirror of `SharedDataManager.isMockModeEnabled` for the same reason
    /// as `nightscoutEnabled`.
    @State private var isMockModeEnabled: Bool
    /// Mirror of `SharedDataManager.healthKitDeliveringRecently` for the
    /// same reason as `nightscoutEnabled`. Recency-based rather than the
    /// sticky `healthKitEverDelivered` so the card re-shows the
    /// data-source rows when HK access is revoked or the sensor goes
    /// offline (see issue #36 — no force-quit needed).
    @State private var healthKitDeliveringRecently: Bool
    @State private var showHideConfirmation = false

    init(refreshToken: Binding<Int>) {
        _refreshToken = refreshToken
        let data = SharedDataManager.shared
        _healthKitStatus = State(
            initialValue: HKHealthStore().authorizationStatus(for: HKQuantityType(.bloodGlucose))
        )
        _hasPassphrase = State(initialValue: KeychainManager.shared.hasPassphrase)
        _shieldingEnabled = State(initialValue: data.shieldingEnabled)
        _nightscoutEnabled = State(initialValue: data.nightscoutEnabled)
        _isMockModeEnabled = State(initialValue: data.isMockModeEnabled)
        _healthKitDeliveringRecently = State(initialValue: data.healthKitDeliveringRecently)
    }

    var body: some View {
        // Lifecycle modifiers MUST live on the outer container, not on
        // `renderedCard` — when `shouldRender` is false the card is
        // absent from the view tree, taking `.onChange(of: refreshToken)`
        // with it. That stranded the @State mirrors when the user
        // disabled the last data source from Settings: HomeView bumped
        // the token on dismiss, but no `refresh()` ran, so
        // `nightscoutEnabled` etc. stayed true, `shouldRender` stayed
        // false, and the data-source tiles only reappeared after a
        // force-quit. Keeping them up here means we always hear the
        // ping, regardless of whether we're currently rendering.
        Group {
            #if targetEnvironment(simulator)
            if let scene = ScreenshotHarness.current, scene.hidesSetupChecklist {
                EmptyView()
            } else if shouldRender {
                renderedCard
            }
            #else
            if shouldRender {
                renderedCard
            }
            #endif
        }
        .onAppear { refresh() }
        .onChange(of: refreshToken) { _, _ in refresh() }
    }

    private var renderedCard: some View {
        card
            .sheet(item: $presentedSheet, onDismiss: { refresh() }) { sheet in
                sheetContent(for: sheet)
            }
            .confirmationDialog(
                String(localized: "setup.checklist.hideConfirmTitle"),
                isPresented: $showHideConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "setup.checklist.hideConfirmAction"), role: .destructive) {
                    withAnimation { hideTips() }
                }
                Button(String(localized: "settings.cancel"), role: .cancel) {}
            } message: {
                Text("setup.checklist.hideConfirmMessage", tableName: "Localizable")
            }
    }

    // MARK: - Visibility

    /// In the welcome state (no data source configured) the data-source
    /// picker is the *only* group that shows — and it shows
    /// unconditionally, even if the user previously hid setup tips.
    /// Picking a source is the one decision that unblocks every other
    /// feature, so we never let it stay hidden.
    ///
    /// Once a source is connected, the card respects `setupTipsHidden`:
    /// the recommended group (shielding, passphrase, notifications)
    /// hides on demand. Disabling every source later brings the
    /// data-source picker back automatically.
    private var shouldRender: Bool {
        !visibleGroups.isEmpty
    }

    /// True once the user has connected at least one data source. The whole
    /// data-source group disappears in this case — Health/Nightscout/Demo are
    /// alternatives, not stacking steps.
    ///
    /// Mirrors `SharedDataManager.hasAnyDataSource` but reads from local
    /// @State so SwiftUI re-renders when any of the underlying flags
    /// (`nightscoutEnabled`, `isMockModeEnabled`, `healthKitDeliveringRecently`)
    /// changes. Reading the manager directly here would skip re-render
    /// because the body wouldn't observe those flags.
    private var hasAnyDataSource: Bool {
        nightscoutEnabled || isMockModeEnabled || healthKitDeliveringRecently
    }

    /// The shielding row stays visible until shielding is actually enabled —
    /// it's the headline recommendation, so we don't hide it just because
    /// the user hasn't connected a source yet. When no source is configured
    /// the row is rendered in a disabled style and isn't tappable (see
    /// `isRowDisabled` / `rowContent`); the user can clearly see the next
    /// step is "connect something first".
    private var recommendedRows: [ChecklistRow] {
        var rows: [ChecklistRow] = []
        if !shieldingEnabled { rows.append(.shielding) }
        if !hasPassphrase { rows.append(.passphrase) }
        if notificationStatus == .notDetermined { rows.append(.notifications) }
        return rows
    }

    /// Shielding can't be enabled without a data source, so its row is
    /// disabled (visually + non-interactive) until one is connected.
    private func isRowDisabled(_ row: ChecklistRow) -> Bool {
        switch row {
        case .shielding: return !hasAnyDataSource
        default: return false
        }
    }

    private var visibleGroups: [ChecklistGroup] {
        // Welcome state: nothing matters except picking a source. The
        // recommended group is intentionally suppressed here — shielding
        // can't enable, and burying the data-source picker under
        // passphrase / notifications dilutes the one CTA the user
        // actually needs.
        if !hasAnyDataSource {
            return [ChecklistGroup(
                kind: .dataSources,
                titleKey: "setup.checklist.dataSources",
                footerKey: "setup.checklist.dataSourcesFooter",
                rows: [.healthKit, .nightscout, .demo]
            )]
        }

        // Configured state: show the recommended group unless the user
        // explicitly dismissed it. The data-source group is always
        // empty here (we just confirmed `hasAnyDataSource`).
        guard !SharedDataManager.shared.setupTipsHidden else { return [] }
        let recommended = recommendedRows
        guard !recommended.isEmpty else { return [] }
        return [ChecklistGroup(
            kind: .recommended,
            titleKey: "setup.checklist.recommended",
            footerKey: nil,
            rows: recommended
        )]
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasAnyDataSource {
                HStack {
                    Spacer()
                    Button {
                        showHideConfirmation = true
                    } label: {
                        Text("setup.checklist.hide", tableName: "Localizable")
                            .font(.footnote)
                    }
                }
                .padding(.horizontal, 16)
            }

            ForEach(visibleGroups) { group in
                groupSection(group)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func groupSection(_ group: ChecklistGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.titleKey, tableName: "Localizable")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element) { index, row in
                    let disabled = isRowDisabled(row)
                    Button {
                        handleTap(row: row)
                    } label: {
                        rowContent(for: row, disabled: disabled)
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)

                    if index < group.rows.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)

            if let footerKey = group.footerKey {
                Text(footerKey, tableName: "Localizable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func rowContent(for row: ChecklistRow, disabled: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.icon)
                .font(.system(size: 18))
                .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.titleKey, tableName: "Localizable")
                    .font(.body)
                    .foregroundStyle(disabled ? Color.secondary : Color(.label))
                Text(disabledSubtitleKey(for: row) ?? row.subtitleKey, tableName: "Localizable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if row == .notifications, isRequestingNotifications {
                ProgressView()
            } else if disabled {
                Image(systemName: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Replacement subtitle that explains *why* a disabled row can't be
    /// actioned yet. Returning nil falls back to the row's normal subtitle.
    private func disabledSubtitleKey(for row: ChecklistRow) -> LocalizedStringKey? {
        switch row {
        case .shielding where !hasAnyDataSource:
            return "setup.checklist.enableShielding.requiresSource"
        default:
            return nil
        }
    }

    // MARK: - Actions

    private func handleTap(row: ChecklistRow) {
        switch row {
        case .healthKit: presentedSheet = .healthKit
        case .nightscout: presentedSheet = .nightscout
        case .demo: presentedSheet = .demo
        case .shielding: presentedSheet = .shielding
        case .passphrase: presentedSheet = .passphrase
        case .notifications:
            Task { await requestNotifications() }
        }
    }

    private func hideTips() {
        SharedDataManager.shared.setupTipsHidden = true
        SharedDataManager.shared.flush()
        refreshToken &+= 1
    }

    private func refresh() {
        let data = SharedDataManager.shared
        healthKitStatus = HKHealthStore().authorizationStatus(for: HKQuantityType(.bloodGlucose))
        hasPassphrase = KeychainManager.shared.hasPassphrase
        shieldingEnabled = data.shieldingEnabled
        nightscoutEnabled = data.nightscoutEnabled
        isMockModeEnabled = data.isMockModeEnabled
        healthKitDeliveringRecently = data.healthKitDeliveringRecently
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run { notificationStatus = settings.authorizationStatus }
        }
    }

    @MainActor
    private func requestNotifications() async {
        isRequestingNotifications = true
        defer { isRequestingNotifications = false }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus

        // The user just granted permission *from the setup checklist* —
        // they're explicitly opting in here, so flip on the glucose-on-
        // the-icon badge they were really asking for. Default to
        // "only when attention": least noisy and matches the app's
        // overall "quiet until something needs your eyes" stance.
        //
        // Gate on (1) the badge bit actually being granted (user can
        // deny badges while allowing alerts) and (2) the badge mode
        // still sitting at its `.off` default — they reach this row
        // only during onboarding, before they've had a chance to
        // deliberately pick `.off` in Settings, so treating `.off`
        // here as "untouched default" is safe.
        let data = SharedDataManager.shared
        if granted, settings.badgeSetting == .enabled, data.glucoseBadgeMode == .off {
            data.glucoseBadgeMode = .onlyWhenAttention
            data.flush()
            data.refreshAttentionBadge()
        }

        refreshToken &+= 1
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(for sheet: ChecklistSheet) -> some View {
        switch sheet {
        case .healthKit:
            NavigationStack {
                HealthKitSettingsView()
                    .toolbar { dismissToolbar }
            }
        case .nightscout:
            NavigationStack {
                NightscoutSettingsView()
                    .toolbar { dismissToolbar }
            }
        case .demo:
            NavigationStack {
                MockDataSettingsView()
                    .toolbar { dismissToolbar }
            }
        case .shielding:
            NavigationStack {
                ShieldingSettingsView()
                    .toolbar { dismissToolbar }
            }
        case .passphrase:
            ChangePassphraseView()
        }
    }

    @ToolbarContentBuilder
    private var dismissToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: "settings.done")) {
                presentedSheet = nil
            }
        }
    }
}

// MARK: - Rows

private enum ChecklistRow: String, Hashable {
    case healthKit
    case nightscout
    case demo
    case shielding
    case passphrase
    case notifications

    var icon: String {
        switch self {
        case .healthKit: return "heart.text.square"
        case .nightscout: return "cloud"
        case .demo: return "flask"
        case .shielding: return "shield.lefthalf.filled"
        case .passphrase: return "lock"
        case .notifications: return "bell"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .healthKit: return "setup.checklist.connectHealthKit"
        case .nightscout: return "setup.checklist.connectNightscout"
        case .demo: return "setup.checklist.tryDemo"
        case .shielding: return "setup.checklist.enableShielding"
        case .passphrase: return "setup.checklist.setPassphrase"
        case .notifications: return "setup.checklist.allowNotifications"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .healthKit: return "setup.checklist.connectHealthKit.subtitle"
        case .nightscout: return "setup.checklist.connectNightscout.subtitle"
        case .demo: return "setup.checklist.tryDemo.subtitle"
        case .shielding: return "setup.checklist.enableShielding.subtitle"
        case .passphrase: return "setup.checklist.setPassphrase.subtitle"
        case .notifications: return "setup.checklist.allowNotifications.subtitle"
        }
    }
}

// MARK: - Groups

private struct ChecklistGroup: Identifiable {
    enum Kind { case dataSources, recommended }

    let kind: Kind
    let titleKey: LocalizedStringKey
    let footerKey: LocalizedStringKey?
    let rows: [ChecklistRow]

    var id: String {
        switch kind {
        case .dataSources: return "dataSources"
        case .recommended: return "recommended"
        }
    }
}

private enum ChecklistSheet: String, Identifiable {
    case healthKit, nightscout, demo, shielding, passphrase
    var id: String { rawValue }
}
