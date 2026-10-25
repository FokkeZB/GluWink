import SharedKit
import SwiftUI

/// Recent refresh events from the app, widgets and background tasks. Lets us
/// see after the fact which triggers fired (and which didn't) — mainly for
/// debugging stale data under Low Power Mode.
struct RefreshLogView: View {
    @State private var entries: [RefreshLog.Entry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                Text("refreshLog.empty", tableName: "Localizable")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(entry.source)
                            .font(.footnote.weight(.semibold))
                        if entry.lowPowerMode {
                            Image(systemName: "battery.25percent")
                                .font(.footnote)
                                .foregroundStyle(BrandTint.orange)
                                .accessibilityLabel(String(localized: "refreshLog.lowPower"))
                        }
                    }
                    Text(entry.event)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle(String(localized: "settings.refreshLogRow"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { entries = RefreshLog.entries() }
        .refreshable { entries = RefreshLog.entries() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: RefreshLog.exportText())
                Button(role: .destructive) {
                    RefreshLog.clear()
                    entries = []
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(String(localized: "refreshLog.clear"))
            }
        }
    }
}
