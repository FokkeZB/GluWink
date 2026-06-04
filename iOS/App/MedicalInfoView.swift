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
                Link("medicalInfo.source.appleHealth",
                     destination: URL(string: "https://www.apple.com/health/")!)
                Link("medicalInfo.source.nightscout",
                     destination: URL(string: "https://nightscout.github.io/")!)
                Link("medicalInfo.source.easyview",
                     destination: URL(string: "https://easyview.medtrum.eu/")!)
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
                Link("medicalInfo.source.adaHypoglycemia",
                     destination: URL(string: "https://diabetes.org/living-with-diabetes/hypoglycemia-low-blood-glucose")!)
                Link("medicalInfo.source.adaHyperglycemia",
                     destination: URL(string: "https://diabetes.org/living-with-diabetes/treatment-care/hyperglycemia")!)
                Link("medicalInfo.source.adaTargets",
                     destination: URL(string: "https://diabetes.org/living-with-diabetes/treatment-care/checking-your-blood-sugar")!)
                Link("medicalInfo.source.adaKetones",
                     destination: URL(string: "https://diabetes.org/living-with-diabetes/managing-ketones")!)
                Link("medicalInfo.source.ispad",
                     destination: URL(string: "https://www.ispad.org/general/custom.asp?page=ISPADGuidelines2022")!)
                Link("medicalInfo.source.diabetesFonds",
                     destination: URL(string: "https://www.diabetesfonds.nl/over-diabetes/dagelijks-leven/hypo-s-en-hypers")!)
                Link("medicalInfo.source.dvn",
                     destination: URL(string: "https://www.dvn.nl/diabetes/bloedwaarden/glucosewaarden")!)
            } header: {
                Text("medicalInfo.sourcesHeader", tableName: "Localizable")
            }

            Section {
                Text("medicalInfo.glucoseUnits", tableName: "Localizable")
                    .font(.body)
                Link("medicalInfo.source.adaTargets",
                     destination: URL(string: "https://diabetes.org/living-with-diabetes/treatment-care/checking-your-blood-sugar")!)
            } header: {
                Text("medicalInfo.glucoseUnitsHeader", tableName: "Localizable")
            }

            Section {
                Text("medicalInfo.checks", tableName: "Localizable")
                    .font(.body)
            } header: {
                Text("medicalInfo.checksHeader", tableName: "Localizable")
            }
            Section {
                Link("medicalInfo.source.adaHypoglycemia",
                     destination: URL(string: "https://diabetes.org/living-with-diabetes/hypoglycemia-low-blood-glucose")!)
                Link("medicalInfo.source.adaHyperglycemia",
                     destination: URL(string: "https://diabetes.org/living-with-diabetes/treatment-care/hyperglycemia")!)
                Link("medicalInfo.source.diabetesFonds",
                     destination: URL(string: "https://www.diabetesfonds.nl/over-diabetes/dagelijks-leven/hypo-s-en-hypers")!)
            } header: {
                Text("medicalInfo.sourcesHeader", tableName: "Localizable")
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
