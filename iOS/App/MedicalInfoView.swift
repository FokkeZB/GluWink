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
            } header: {
                Text("medicalInfo.dataSourcesHeader", tableName: "Localizable")
            }

            Section {
                Text("medicalInfo.thresholds", tableName: "Localizable")
                    .font(.body)
            } header: {
                Text("medicalInfo.thresholdsHeader", tableName: "Localizable")
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
