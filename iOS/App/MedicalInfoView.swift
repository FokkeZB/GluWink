import SwiftUI

struct MedicalInfoView: View {
    var body: some View {
        List {
            Section {
                Text("medicalInfo.notADevice", tableName: "Localizable")
                    .font(.body)
            } header: {
                Text("medicalInfo.notADeviceHeader", tableName: "Localizable")
            }

            Section {
                Text("medicalInfo.dataSources", tableName: "Localizable")
                    .font(.body)
                SourceLinks(key: "medicalInfo.dataSources.links")
            } header: {
                Text("medicalInfo.dataSourcesHeader", tableName: "Localizable")
            }

            Section {
                Text("medicalInfo.thresholds", tableName: "Localizable")
                    .font(.body)
                SourceLinks(key: "medicalInfo.thresholds.links")
            } header: {
                Text("medicalInfo.thresholdsHeader", tableName: "Localizable")
            }

            Section {
                Text("medicalInfo.glucoseUnits", tableName: "Localizable")
                    .font(.body)
                SourceLinks(key: "medicalInfo.glucoseUnits.links")
            } header: {
                Text("medicalInfo.glucoseUnitsHeader", tableName: "Localizable")
            }

            Section {
                Text("medicalInfo.checks", tableName: "Localizable")
                    .font(.body)
                SourceLinks(key: "medicalInfo.checks.links")
            } header: {
                Text("medicalInfo.checksHeader", tableName: "Localizable")
            }

            Section {
                Text("medicalInfo.careTeam", tableName: "Localizable")
                    .font(.body)
                Text("medicalInfo.emergency", tableName: "Localizable")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } header: {
                Text("medicalInfo.adviceHeader", tableName: "Localizable")
            }
        }
        .navigationTitle(String(localized: "medicalInfo.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Renders a list of `Link` rows parsed from a localized string whose value
/// is one or more `Label|URL` pairs separated by newlines.
private struct SourceLinks: View {
    let key: String

    private var items: [(label: String, url: URL)] {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, comment: "")
            .components(separatedBy: "\n")
            .compactMap { entry in
                let parts = entry.components(separatedBy: "|")
                guard parts.count == 2, let url = URL(string: parts[1]) else { return nil }
                return (label: parts[0], url: url)
            }
    }

    var body: some View {
        ForEach(items, id: \.url) { item in
            Link(item.label, destination: item.url)
        }
    }
}
